# Configure Terragrunt to automatically store tfstate files in an S3 bucket
remote_state {
  backend = "s3"

  config = {
    encrypt        = true
    bucket = get_env("terraform_state_s3bucket", "REPLACE-WITH-S3-BUCKET-NAME")
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "REPLACE-WITH-VALID-AWS-REGION"
    dynamodb_table = "terraform-locks"
  }
}