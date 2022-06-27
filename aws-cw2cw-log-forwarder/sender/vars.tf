variable "aws_region" {
  type = string
}

variable "base_name" {
  type = string
  default = "cf-logs-sender"
}

variable "destination_aws_account" {
  type = string
}

variable "sender_aws_account" {
  type = string
}

variable "sender_aws_role" {
  type = string
  default = "ewica-cloudwatch-testing"
}

variable "log_groups" {
  type = map
}

variable "cloudwatch_destination_arn" {
  type = string
  default = ""
}