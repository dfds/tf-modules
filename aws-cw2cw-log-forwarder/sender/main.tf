terraform {
  backend "s3" {}
}

provider "aws" {
  # default
  region  = var.aws_region
  version = "~> 3.75.0"
  max_retries = 3
}

data "aws_caller_identity" "this" {

}

resource "aws_cloudwatch_log_subscription_filter" "this" {
  for_each = var.log_groups
  destination_arn = local.cloudwatch_destination_arn
  filter_pattern  = ""
  log_group_name  = each.value
  name            = "${var.base_name}-${each.key}"
}