variable "aws_region" {
  type = string
}

variable "base_name" {
  type = string
  default = "aws-cw2cw-log-forwarder"
}

variable "destination_aws_account" {
  type = string
}

variable "sender_aws_account" {
  type = string
}

variable "log_groups" {
  type = map
}

variable "kinesis_stream_arn" {
  type = string
}

variable "lambda_dir" {
  type = string
}

variable "cloudwatch_trust_arn" {
  type = string
}