# Terragrunt will copy the Terraform configurations specified by the source parameter, along with any files in the
# working directory, into a temporary folder, and execute your Terraform commands in that folder.
terraform {
  source = "git::https://github.com/dfds/tf-modules.git//aws-cw2cw-log-forwarder/sender"
}

# Include all settings from the root terragrunt.hcl file
include {
  path = find_in_parent_folders()
}

inputs = {
  destination_aws_account = "INSERT-DESTINATION-AWS-ACCOUNT"
  sender_aws_account = "INSERT-SOURCE-AWS-ACCOUNT"
  aws_region = "eu-west-1"
  // Map format: Key = naming for AWS resources; Value = CloudWatch Log Group name
  log_groups = {
    log_group_name = "/k8s/CLUSTER-NAME/K8S-NAMESPACE"
  }
}