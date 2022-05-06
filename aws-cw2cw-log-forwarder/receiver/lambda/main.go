package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs/types"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	dynamoDbTypes "github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	log "github.com/sirupsen/logrus"
	dfdsConfig "go.dfds.cloud/utils/config"
	"os"
	"strconv"
	"strings"
	"time"

	"io/ioutil"
)

func HandleRequest(ctx context.Context, payload events.KinesisEvent) error {
	lambdaConf := getConfig()
	log.SetLevel(lambdaConf.LogLevel)
	log.SetFormatter(&log.JSONFormatter{})
	log.SetOutput(os.Stdout)
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(lambdaConf.AwsRegion))
	if err != nil {
		return err
	}
	cwl := cloudwatchlogs.NewFromConfig(cfg)
	db := dynamodb.NewFromConfig(cfg)

	logStreamName := "01"
	var sequenceToken *string = nil
	var logsContainersMapByLogGroup map[string][]*LogsContainer = make(map[string][]*LogsContainer)
	var seenLogGroups map[string]int = make(map[string]int)
	totalLogEventCount := 0

	// Gather all logs from the given Kinesis event
	log.Debug("Start loop of kinesisRecord")
	for _, record := range payload.Records {
		// Check if Kinesis Record has already been seen before
		seen, err := hasEventBeenSeenBefore(ctx, db, lambdaConf.DynamoDbTableKinesisRecordsName, record.EventID, lambdaConf.DynamoDbEntryTTLInDays)
		if err != nil {
			return err
		}

		// If event has been used before, skip
		if seen {
			log.Debugf("Kinesis Record event id '%s' already used, skipping\n", record.EventID)
			continue
		}

		kinesisRecord, err := deserialiseKinesisRecordResponse(record.Kinesis.Data)
		if err != nil {
			return err
		}

		// If Kinesis event is not of type 'DATA_MESSAGE', skip
		if kinesisRecord.MessageType != "DATA_MESSAGE" {
			continue
		}

		// Make sure LogGroup is noted down so we can check if it exists later on
		seenLogGroups[kinesisRecord.LogGroup] = 1

		var logCount int = 0
		var logsContainer *LogsContainer
		log.Debug("Start loop of kinesisRecord LogEvents")
		for _, logEvent := range kinesisRecord.LogEvents {
			// Check if Event has already been seen before
			seen, err := hasEventBeenSeenBefore(ctx, db, lambdaConf.DynamoDbTableLogEventsName, logEvent.ID, lambdaConf.DynamoDbEntryTTLInDays)
			if err != nil {
				return err
			}

			// If event has been used before, skip.
			if seen {
				log.Debugf("Log event id '%s' already used, skipping\n", logEvent.ID)
				continue
			}

			// If new batch, make sure to add it to list of batches
			if logCount == 0 {
				logsContainer = &LogsContainer{Logs: []types.InputLogEvent{}}
				logsContainersMapByLogGroup[kinesisRecord.LogGroup] = append(logsContainersMapByLogGroup[kinesisRecord.LogGroup], logsContainer)
				log.Debugf("Current logContainer count: %d\n", getTotalLogContainersCount(logsContainersMapByLogGroup))
			}

			logsContainer.Logs = append(logsContainer.Logs, types.InputLogEvent{
				Message:   pString(logEvent.Message),
				Timestamp: pInt64(logEvent.Timestamp),
			})
			logCount += 1

			log.WithFields(log.Fields{
				"recordId":                    record.EventID,
				"recordName":                  record.EventName,
				"recordKinesisPartitionKey":   record.Kinesis.PartitionKey,
				"recordKinesisSequenceNumber": record.Kinesis.SequenceNumber,
				"logEventId":                  logEvent.ID,
				"logEventTimestamp":           strconv.FormatInt(logEvent.Timestamp, 10),
			}).
				Tracef("%d, %s\n", logEvent.Timestamp, logEvent.Message)
			// Create new batch (LogsContainer)
			if logCount == 15 {
				logCount = 0
			}
		}
		log.Debug("End loop of kinesisRecord LogEvents")
		totalLogEventCount += len(kinesisRecord.LogEvents)
		log.Debugf("logEvents count: %d\n", len(kinesisRecord.LogEvents))
	}
	log.Debug("End loop of kinesisRecord")

	log.Debugf("Records count: %d\n", len(payload.Records))
	log.Debugf("Total logEvents count: %d\n", totalLogEventCount)
	log.Debugf("logContainers count: %d\n", getTotalLogContainersCount(logsContainersMapByLogGroup))

	// Get all preexisting LogGroups in CloudWatch
	var logGroupsMap map[string]types.LogGroup = make(map[string]types.LogGroup)
	{
		var logGroups []types.LogGroup
		logGroupsResp, err := cwl.DescribeLogGroups(ctx, &cloudwatchlogs.DescribeLogGroupsInput{NextToken: nil})
		if err != nil {
			return err
		}

		logGroups = append(logGroups, logGroupsResp.LogGroups...)

		for logGroupsResp.NextToken != nil {
			logGroupsResp, err = cwl.DescribeLogGroups(ctx, &cloudwatchlogs.DescribeLogGroupsInput{NextToken: logGroupsResp.NextToken})
			if err != nil {
				return err
			}
			logGroups = append(logGroups, logGroupsResp.LogGroups...)
		}

		for _, lg := range logGroups {
			logGroupsMap[*lg.LogGroupName] = lg
		}
	}

	// Check if Log Groups & Log Streams mentioned in Kinesis records already exists, if not then create them
	for logGroup := range seenLogGroups {
		_, exists := logGroupsMap[logGroup]
		// Create Log Group
		if !exists {
			_, err := cwl.CreateLogGroup(ctx, &cloudwatchlogs.CreateLogGroupInput{
				LogGroupName: pString(logGroup),
			})
			if err != nil {
				return err
			}

			_, err = cwl.PutRetentionPolicy(ctx, &cloudwatchlogs.PutRetentionPolicyInput{
				LogGroupName:    pString(logGroup),
				RetentionInDays: pInt32(lambdaConf.CloudWatchLogGroupDefaultRetentionInDays),
			})
			if err != nil {
				return err
			}

		}

		// Look for existing Log Stream
		logStreams, err := cwl.DescribeLogStreams(ctx, &cloudwatchlogs.DescribeLogStreamsInput{
			LogGroupName: pString(logGroup),
		})
		if err != nil {
			return err
		}

		logStreamExists := false
		for _, stream := range logStreams.LogStreams {
			if *stream.LogStreamName == logStreamName {
				logStreamExists = true
			}
		}

		// Create Log Stream
		if !logStreamExists {
			_, err := cwl.CreateLogStream(ctx, &cloudwatchlogs.CreateLogStreamInput{
				LogGroupName:  pString(logGroup),
				LogStreamName: pString(logStreamName),
			})
			if err != nil {
				return err
			}
		}
	}

	for logGroup, containers := range logsContainersMapByLogGroup {
		// Get the initial upload sequence token
		logStreams, err := cwl.DescribeLogStreams(ctx, &cloudwatchlogs.DescribeLogStreamsInput{
			LogGroupName:        pString(logGroup),
			LogStreamNamePrefix: &logStreamName,
			Descending:          nil,
			Limit:               nil,
			NextToken:           nil,
			OrderBy:             types.OrderByLogStreamName,
		})
		if err != nil {
			return err
		}

		for _, stream := range logStreams.LogStreams {
			if *stream.LogStreamName == logStreamName {
				sequenceToken = stream.UploadSequenceToken
			}
		}

		// Uploads gathered logs to CloudWatch
		log.Debugf("Start loop of logsContainers for Log Group %s\n", logGroup)
		for i, container := range containers {
			log.Debugf("logContainer %d: Uploading logs\n", i)
			resp, err := cwl.PutLogEvents(ctx, &cloudwatchlogs.PutLogEventsInput{
				LogEvents:     container.Logs,
				LogGroupName:  pString(logGroup),
				LogStreamName: pString(logStreamName),
				SequenceToken: sequenceToken,
			})
			if err != nil {
				log.Debugf("logContainer %d: An error occurred\n", i)
				return err
			}
			log.Debugf("logContainer %d: Logs uploaded\n", i)
			sequenceTokenP := resp.NextSequenceToken
			sequenceToken = sequenceTokenP
		}
		log.Debugf("End loop of logsContainers for Log Group %s\n", logGroup)
	}

	return nil
}

func main() {
	lambda.Start(HandleRequest)
}

func pString(input string) *string {
	return &input
}

func pInt64(input int64) *int64 {
	return &input
}

func pInt32(input int32) *int32 {
	return &input
}

func hasEventBeenSeenBefore(ctx context.Context, db *dynamodb.Client, tableName string, id string, ttl int) (bool, error) {
	query := make(map[string]dynamoDbTypes.AttributeValue)
	query["EventId"] = &dynamoDbTypes.AttributeValueMemberS{Value: id}
	resp, err := db.GetItem(ctx, &dynamodb.GetItemInput{
		Key:       query,
		TableName: &tableName,
	})
	if err != nil {
		return false, err
	}

	if resp.Item != nil {
		log.Debugf("Kinesis Record event id '%s' already used, skipping\n", id)
		return true, nil
	} else {
		// Add entry to DynamoDB if not found
		ttl := time.Now().AddDate(0, 0, ttl)
		query := make(map[string]dynamoDbTypes.AttributeValue)
		query["EventId"] = &dynamoDbTypes.AttributeValueMemberS{Value: id}
		query["TTL"] = &dynamoDbTypes.AttributeValueMemberN{Value: strconv.FormatInt(ttl.Unix(), 10)}
		_, err = db.PutItem(ctx, &dynamodb.PutItemInput{
			Item:      query,
			TableName: &tableName,
		})
		if err != nil {
			return false, err
		}
		return false, nil
	}
}

func deserialiseKinesisRecordResponse(payload []byte) (KinesisRecordResponse, error) {
	g, err := gzip.NewReader(bytes.NewReader(payload))
	if err != nil {
		return KinesisRecordResponse{}, err
	}
	result, err := ioutil.ReadAll(g)
	if err != nil {
		return KinesisRecordResponse{}, err
	}

	var kinesisRecord KinesisRecordResponse
	err = json.Unmarshal(result, &kinesisRecord)
	if err != nil {
		return KinesisRecordResponse{}, err
	}

	return kinesisRecord, nil
}

func getTotalLogContainersCount(containers map[string][]*LogsContainer) int {
	count := 0
	for _, v := range containers {
		count += len(v)
	}

	return count
}

func getConfig() LambdaConfig {
	conf := LambdaConfig{
		AwsRegion:                       dfdsConfig.GetEnvValue("AWS_REGION", "eu-west-1"),
		DynamoDbTableKinesisRecordsName: dfdsConfig.GetEnvValue("DYNAMODB_TABLE_KINESISRECORDS_NAME", ""),
		DynamoDbTableLogEventsName:      dfdsConfig.GetEnvValue("DYNAMODB_TABLE_LOGEVENTS_NAME", ""),
	}

	// Set log level
	logLevel := dfdsConfig.GetEnvValue("LOG_LEVEL", "INFO")
	switch strings.ToUpper(logLevel) {
	case "INFO":
		conf.LogLevel = log.InfoLevel
	case "TRACE":
		conf.LogLevel = log.TraceLevel
	case "ERROR":
		conf.LogLevel = log.ErrorLevel
	case "WARN":
		conf.LogLevel = log.WarnLevel
	case "DEBUG":
		conf.LogLevel = log.DebugLevel
	case "FATAL":
		conf.LogLevel = log.FatalLevel
	case "PANIC":
		conf.LogLevel = log.PanicLevel
	}

	// Set DynamoDB entry TTL
	DynamoDbEntryTtl, err := dfdsConfig.GetEnvInt("DYNAMODB_ENTRY_TTL", 3)
	if err != nil {
		log.Infoln("Unable to convert value of config DYNAMODB_ENTRY_TTL into an int")
		panic(err)
	}
	conf.DynamoDbEntryTTLInDays = DynamoDbEntryTtl

	cwDefaultRetention, err := dfdsConfig.GetEnvInt32("CLOUDWATCH_LOGGROUP_DEFAULT_RETENTION_IN_DAYS", 30)
	if err != nil {
		log.Infoln("Unable to convert value of config DYNAMODB_ENTRY_TTL into an int")
		panic(err)
	}
	conf.CloudWatchLogGroupDefaultRetentionInDays = cwDefaultRetention

	return conf
}

type LambdaConfig struct {
	AwsRegion                       string    // AWS_REGION
	LogLevel                        log.Level // LOG_LEVEL
	DynamoDbTableKinesisRecordsName string    // DYNAMODB_TABLE_KINESISRECORDS_NAME
	DynamoDbTableLogEventsName      string    // DYNAMODB_TABLE_LOGEVENTS_NAME
	DynamoDbEntryTTLInDays          int       // DYNAMODB_ENTRY_TTL
	// CloudWatchLogGroupDefaultRetentionInDays Allowed values: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
	CloudWatchLogGroupDefaultRetentionInDays int32 // CLOUDWATCH_LOGGROUP_DEFAULT_RETENTION_IN_DAYS
}

type KinesisRecordResponse struct {
	MessageType         string   `json:"messageType"`
	Owner               string   `json:"owner"`
	LogGroup            string   `json:"logGroup"`
	LogStream           string   `json:"logStream"`
	SubscriptionFilters []string `json:"subscriptionFilters"`
	LogEvents           []struct {
		ID        string `json:"id"`
		Timestamp int64  `json:"timestamp"`
		Message   string `json:"message"`
	} `json:"logEvents"`
}

type LogsContainer struct {
	Logs []types.InputLogEvent
}
