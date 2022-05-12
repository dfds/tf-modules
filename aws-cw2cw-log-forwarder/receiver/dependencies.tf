data "aws_iam_policy_document" "this" {
  statement {
    effect = "Allow"

    actions = [
      "kinesis:PutRecord",
    ]

    resources = ["arn:aws:kinesis:${var.aws_region}:${var.destination_aws_account}:stream/${var.base_name}"]
  }

  statement {
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = ["arn:aws:iam::${var.destination_aws_account}:role/${var.base_name}"]
  }
}

data "aws_iam_policy_document" "s3" {
  statement {
    effect = "Allow"

    actions = [
      "s3:*",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = ["arn:aws:iam::${var.destination_aws_account}:role/${var.base_name}"]
  }
}

data "aws_iam_policy_document" "kinesis" {
  statement {
    effect = "Allow"

    actions = [
      "kinesis:*",
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "this_trust" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "this_trust_lambda" {
	statement {
		actions = ["sts:AssumeRole"]
		effect = "Allow"
		principals {
			identifiers = ["lambda.amazonaws.com"]
			type = "Service"
		}
	}
}

data "aws_iam_policy_document" "this_lambda" {
  statement {
    effect = "Allow"

    actions = [
      "logs:*",
      "kinesis:*",
      "dynamodb:*",
    ]

    resources = ["*"]
  }
}

# todo: this only works with the symlink for ../../lambda inside the receiver module
resource "null_resource" "lambda_build" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "cd ${path.module}/lambda && go build main.go"
    environment = {
      GOOS = "linux"
      GOARCH = "amd64"
      CGO_ENABLED = "0"
    }
  }
}

data "archive_file" "lambda_zip" {
  depends_on = [null_resource.lambda_build]
  source_file = "${path.module}/lambda/main"
  type = "zip"
  output_path = "${path.module}/lambda/${local.go_file_output_name}"
}

#cloudwatch monitoring
data "aws_iam_policy_document" "this_lamba_cloudwatch_trust" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "AWS"
      identifiers = [var.cloudwatch_trust_arn]
    }
  }
}

data "aws_iam_policy_document" "this_lamba_cloudwatch" {
  statement {
    effect = "Allow"

    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetMetricData"
    ]

    resources = ["*"]
  }
}

locals {
  cloudwatch_destination_arn = "arn:aws:logs:${var.aws_region}:${var.destination_aws_account}:destination:${var.base_name}"
  go_file_output_name = "cf-logs-receiver-lambda.zip"
  lambda_envs = {
    AWS_REGION = var.aws_region
    LOG_LEVEL = "DEBUG"
    DYNAMODB_TABLE_KINESISRECORDS_NAME = "${var.base_name}-records"
    DYNAMODB_TABLE_LOGEVENTS_NAME = var.base_name
    DYNAMODB_ENTRY_TTL = 3
    CLOUDWATCH_LOGGROUP_DEFAULT_RETENTION_IN_DAYS = 30
  }

  destination_access_policy = <<POLICY
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Sid" : "",
      "Effect" : "Allow",
      "Principal" : {
        "AWS" : "${var.sender_aws_account}"
      },
      "Action" : "logs:PutSubscriptionFilter",
      "Resource" : "${local.cloudwatch_destination_arn}"
    }
  ]
}
POLICY

}