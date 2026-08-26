# WhatsApp API Gateway Module Outputs

output "api_gateway_id" {
  description = "ID of the WhatsApp webhook API Gateway"
  value       = aws_api_gateway_rest_api.whatsapp.id
}

output "rest_api_id" {
  description = "REST API ID (alias for api_gateway_id)"
  value       = aws_api_gateway_rest_api.whatsapp.id
}

output "root_resource_id" {
  description = "Root resource ID of the API Gateway"
  value       = aws_api_gateway_rest_api.whatsapp.root_resource_id
}

output "stage_invoke_url" {
  description = "Base invoke URL of the API Gateway stage (without path)"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "api_gateway_url" {
  description = "Invoke URL of the WhatsApp webhook API Gateway (use for Twilio webhook configuration)"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/webhook"
}

output "api_key_id" {
  description = "ID of the Twilio webhook API key"
  value       = aws_api_gateway_api_key.twilio.id
}

output "api_key_value" {
  description = "Value of the Twilio webhook API key (sensitive)"
  value       = aws_api_gateway_api_key.twilio.value
  sensitive   = true
}

output "api_gateway_sqs_role_arn" {
  description = "ARN of the IAM role for API Gateway → SQS integration"
  value       = aws_iam_role.api_gateway_sqs.arn
}

output "stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.prod.stage_name
}

output "execution_arn" {
  description = "Execution ARN of the API Gateway (for Lambda permissions)"
  value       = aws_api_gateway_rest_api.whatsapp.execution_arn
}
