terraform {
  backend "s3" {}
}

provider "aws" {
  # default
  region  = var.aws_region
  version = "~> 3.75.0"
  max_retries = 3
}

resource "aws_kinesis_stream" "this" {
  name = var.base_name
  shard_count = 1
}

resource "aws_iam_role" "this" {
  name = var.base_name
  path = "/"
  description = "Role for ${var.base_name}"
  assume_role_policy = data.aws_iam_policy_document.this_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "this" {
  name = var.base_name
  role = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_cloudwatch_log_destination" "this" {
  name = var.base_name
  target_arn = "arn:aws:kinesis:${var.aws_region}:${var.destination_aws_account}:stream/${var.base_name}"
  role_arn = "arn:aws:iam::${var.destination_aws_account}:role/${var.base_name}"
}

resource "aws_cloudwatch_log_destination_policy" "this" {
  destination_name = aws_cloudwatch_log_destination.this.name
  access_policy = local.destination_access_policy
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.base_name}-logs-dump"
  acl = "private"
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "firehose_role" {
  name = "${var.base_name}-firehose"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "firehose.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "firehose_role" {
  name = "${var.base_name}-s3"
  role = aws_iam_role.firehose_role.id
  policy = data.aws_iam_policy_document.s3.json
}
resource "aws_iam_role_policy" "firehose_role_kinesis" {
  name = "${var.base_name}-kinesis"
  role = aws_iam_role.firehose_role.id
  policy = data.aws_iam_policy_document.kinesis.json
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  destination = "s3"
  name = var.base_name
  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.this.arn
    role_arn           = aws_iam_role.firehose_role.arn
  }
  s3_configuration {
    bucket_arn = aws_s3_bucket.this.arn
    role_arn   = aws_iam_role.firehose_role.arn
    buffer_size = 1
    buffer_interval = 60
  }
}

resource "aws_dynamodb_table" "this" {
  name = var.base_name
  hash_key = "EventId"
  billing_mode = "PAY_PER_REQUEST"
  write_capacity = 0
  read_capacity = 0

  attribute {
    name = "EventId"
    type = "S"
  }
  #  attribute {
  #    name = "TTL"
  #    type = "N"
  #  }

  ttl {
    attribute_name = "TTL"
    enabled = true
  }
}

resource "aws_dynamodb_table" "this_records" {
  name = "${var.base_name}-records"
  hash_key = "EventId"
  billing_mode = "PAY_PER_REQUEST"
  write_capacity = 0
  read_capacity = 0

  attribute {
    name = "EventId"
    type = "S"
  }

  ttl {
    attribute_name = "TTL"
    enabled = true
  }
}

# lambda
resource "aws_iam_role" "this_lambda" {
  assume_role_policy = data.aws_iam_policy_document.this_trust_lambda.json
  description = "Role for ${var.base_name} lambda"
  name = "${var.base_name}-lambda"
  path = "/"
}

resource "aws_iam_role_policy" "this_lambda" {
  name = "${var.base_name}-lambda"
  role = aws_iam_role.this_lambda.id
  policy = data.aws_iam_policy_document.this_lambda.json
}

resource "aws_cloudwatch_log_group" "this_lambda" {
  name              = "/aws/lambda/${var.base_name}"
  retention_in_days = 14
}

resource "aws_lambda_function" "this_lambda" {
  function_name = var.base_name
  handler = "main"
  runtime = "go1.x"
  timeout = 50
  filename = "${var.lambda_dir}/${local.go_file_output_name}"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role = aws_iam_role.this_lambda.arn
  memory_size = 512
  environment {
    variables = {
      "LOG_LEVEL" = local.lambda_envs.LOG_LEVEL,
      "DYNAMODB_TABLE_KINESISRECORDS_NAME" = local.lambda_envs.DYNAMODB_TABLE_KINESISRECORDS_NAME,
      "DYNAMODB_TABLE_LOGEVENTS_NAME" = local.lambda_envs.DYNAMODB_TABLE_LOGEVENTS_NAME,
      "DYNAMODB_ENTRY_TTL" = local.lambda_envs.DYNAMODB_ENTRY_TTL,
      "CLOUDWATCH_LOGGROUP_DEFAULT_RETENTION_IN_DAYS" = local.lambda_envs.CLOUDWATCH_LOGGROUP_DEFAULT_RETENTION_IN_DAYS
    }
  }
  depends_on = [
    aws_cloudwatch_log_group.this_lambda,
  ]
}

resource "aws_lambda_event_source_mapping" "kinesis_lambda_event_mapping" {
    batch_size = 5
    event_source_arn = "arn:aws:kinesis:${var.aws_region}:${var.destination_aws_account}:stream/${var.base_name}"
    enabled = true
    function_name = "${aws_lambda_function.this_lambda.arn}"
    starting_position = "LATEST"
}

# cloudwatch monitoring role for grafana
resource "aws_iam_role" "this_lamba_cloudwatch" {
  assume_role_policy = data.aws_iam_policy_document.this_lamba_cloudwatch_trust.json
  description = "Role for ${var.base_name} lambda cloudwatch monitoring"
  name = "${var.base_name}-lambda-cloudwatch"
  path = "/"
}

resource "aws_iam_policy" "this_lamba_cloudwatch_policy" {
  name        = "${var.base_name}-lambda-cloudwatch"
  path        = "/"
  description = "Allows EKS nodes to reach cloudwatch API for use with grafana pods"
  policy = data.aws_iam_policy_document.this_lamba_cloudwatch.json
}

resource "aws_iam_role_policy_attachment" "this_lamba_cloudwatch_attach" {
  role = aws_iam_role.this_lamba_cloudwatch.id
  policy_arn = aws_iam_policy.this_lamba_cloudwatch_policy.arn
}