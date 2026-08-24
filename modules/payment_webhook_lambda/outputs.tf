# Payment Webhook Lambda Module Outputs

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.payment_webhook.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.payment_webhook.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway)"
  value       = aws_lambda_function.payment_webhook.invoke_arn
}

output "execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}
