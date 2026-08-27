# Account Handler Lambda Module Outputs

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.account_handler.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.account_handler.arn
}

output "invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway integration)"
  value       = aws_lambda_function.account_handler.invoke_arn
}

output "execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}
