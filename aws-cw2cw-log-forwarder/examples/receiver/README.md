# Example of using the *sender* module

## Files to update

Update ./terragrunt.hcl with the following:

**REPLACE-WITH-S3-BUCKET-NAME**: Replace this value with an unique unused S3 Bucket name

**REPLACE-WITH-VALID-AWS-REGION**: Replace this value with a valid AWS region

Update ./entries/capability-name-here/terragrunt.hcl with the following:
**INSERT-DESTINATION-AWS-ACCOUNT**: Replace this value with the AWS account id of the recipient AWS account

**INSERT-SOURCE-AWS-ACCOUNT**: Replace this value with the AWS account id of the origin AWS account. The account that contains the logs that should be forwarded.

**INSERT-IAM-TRUST-ARN**: Replace this value with an IAM arn. Currently used for getting access to CloudWatch metrics through Kubernetes with KIAM.
