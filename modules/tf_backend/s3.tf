data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tf-state-bucket" {
  bucket = "${var.stack_name}-${var.env}-tf-state-bucket"

  tags = merge({
    Name = "${var.stack_name}-${var.env}-tf-state-bucket"
  }, var.additional_tags)
}

resource "aws_s3_bucket_versioning" "tf-state-bucket-versioning" {
  bucket = aws_s3_bucket.tf-state-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_kms_key" "tf-state-bucket-key" {
  description             = "This key is used to encrypt bucket objects"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:Encrypt",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*",
        Condition = {
          StringEquals = { "kms:ViaService" = "dynamodb.${var.region}.amazonaws.com" }
        }
      }
    ]
  })

  tags = merge({
    Name = "${var.stack_name}-${var.env}-tf-state-bucket-key"
  }, var.additional_tags)
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf-state-bucket-encryption" {
  bucket = aws_s3_bucket.tf-state-bucket.bucket
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.tf-state-bucket-key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tf-state-bucket" {
  bucket                  = aws_s3_bucket.tf-state-bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "tf_state_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      "${aws_s3_bucket.tf-state-bucket.arn}",
      "${aws_s3_bucket.tf-state-bucket.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tf_state" {
  bucket = aws_s3_bucket.tf-state-bucket.id
  policy = data.aws_iam_policy_document.tf_state_bucket.json
}