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


locals {
  cloudwatch_destination_arn = "arn:aws:logs:${var.aws_region}:${var.destination_aws_account}:destination:cf-logs-forwarder-receiver"

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
