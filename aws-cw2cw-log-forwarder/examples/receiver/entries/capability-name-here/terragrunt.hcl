# Terragrunt will copy the Terraform configurations specified by the source parameter, along with any files in the
# working directory, into a temporary folder, and execute your Terraform commands in that folder.
terraform {
  source = "git::https://github.com/dfds/tf-modules.git//aws-cw2cw-log-forwarder/receiver"
}

# Include all settings from the root terragrunt.hcl file
include {
  path = find_in_parent_folders()
}

inputs = {
  destination_aws_account = "INSERT-DESTINATION-AWS-ACCOUNT"
  sender_aws_account = "INSERT-SOURCE-AWS-ACCOUNT"
  aws_region = "eu-west-1"
  lambda_dir = "lambda"
  cloudwatch_trust_arn = "INSERT-IAM-TRUST-ARN"
}