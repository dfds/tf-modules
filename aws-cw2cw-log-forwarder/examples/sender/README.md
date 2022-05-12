# Example of using the *sender* module

## Files to update

Update ./terragrunt.hcl with the following:

**REPLACE-WITH-S3-BUCKET-NAME**: Replace this value with an unique unused S3 Bucket name
**REPLACE-WITH-VALID-AWS-REGION**: Replace this value with a valid AWS region

Update ./entries/primary-sender/terragrunt.hcl with the following:
**INSERT-DESTINATION-AWS-ACCOUNT**: Replace this value with the AWS account id of the recipient AWS account
**INSERT-SOURCE-AWS-ACCOUNT**: Replace this value with the AWS account id of the origin AWS account. The account that contains the logs that should be forwarded.

Within the _log_groups_ map, there resides a single entry. One entry = one log group being forwarded. If we look at that entry, it looks like this:

```yaml
log_group_name = "/k8s/CLUSTER-NAME/K8S-NAMESPACE"
```

_log_group_name_ is the **key**, and is used in the naming of a CloudWatch subscription filter. Therefore, a key should be unique. _"/k8s/CLUSTER-NAME/K8S-NAMESPACE"_ is the **value**, and is the name of the Log Group that is going to be forwarded.