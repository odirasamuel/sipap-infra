# SQS Module

This module creates SQS FIFO queues for Sentinel event processing with dead letter queue configuration.

## Features

- **FIFO Queues**: Ensures message ordering and exactly-once delivery
- **Dead Letter Queue**: Handles failed message processing
- **IAM Policies**: Fine-grained access control for sender and receiver roles
- **Content-based Deduplication**: Automatic duplicate message prevention

## Resources Created

- Main FIFO queue for event processing
- Dead letter queue for failed messages
- Queue policies for IAM-based access control
- Redrive policy for dead letter queue management

## Usage

```hcl
module "sentinel_sqs" {
  source = "./modules/sqs"

  stack_name            = "sentinel"
  env                   = "deltekdev"
  sqs_role_arn          = aws_iam_role.sqs_sender.arn
  orchestrator_role_arn = aws_iam_role.orchestrator.arn
  max_receive_count     = 3
  
  additional_tags = {
    Environment = "deltekdev"
    Project     = "sentinel"
  }
}
```