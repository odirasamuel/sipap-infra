resource "aws_dynamodb_table" "tf_state_lock" {
  name             = "${var.stack_name}-${var.env}-tf-state-lock"
  hash_key         = "LockID"
  billing_mode     = "PAY_PER_REQUEST"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.tf-state-bucket-key.arn
  }
  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge({
    Name = "${var.stack_name}-${var.env}-tf-state-lock"
  }, var.additional_tags)
}