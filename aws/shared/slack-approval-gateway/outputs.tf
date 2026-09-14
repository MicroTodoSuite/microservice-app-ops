# Configure the GitHub App's webhook URL as "{api_base_url}/github/webhook" and
# Slack's Interactivity Request URL as "{api_base_url}/slack/interactions".
output "api_base_url" {
  description = "Base invoke URL of the API Gateway HTTP API."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "github_webhook_handler_function_name" {
  description = "Lambda function name, for CloudWatch Logs lookups."
  value       = aws_lambda_function.github_webhook_handler.function_name
}

output "slack_interaction_handler_function_name" {
  description = "Lambda function name, for CloudWatch Logs lookups."
  value       = aws_lambda_function.slack_interaction_handler.function_name
}
