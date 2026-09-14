locals {
  tags = merge(var.common_tags, {
    Project     = "MicroTodoSuite"
    Owner       = var.owner
    ManagedBy   = "terraform"
    Root        = "aws/shared/slack-approval-gateway"
    Environment = "shared"
  })
}

# --- Built Lambda bundles ----------------------------------------------------
# microservice-app-slack-approval-gateway's esbuild step already inlines every
# dependency (including config/authorized-approvers.json) into one file per
# handler, so each zip here is exactly that one file -- no node_modules to
# package, well under Lambda's direct-upload size limit.
data "archive_file" "github_webhook_handler" {
  type        = "zip"
  source_dir  = "${var.lambda_source_dir}/github-webhook-handler"
  output_path = "${path.module}/.build/github-webhook-handler.zip"
}

data "archive_file" "slack_interaction_handler" {
  type        = "zip"
  source_dir  = "${var.lambda_source_dir}/slack-interaction-handler"
  output_path = "${path.module}/.build/slack-interaction-handler.zip"
}

# --- Secrets Manager (value-blind: every value is write-only, never in state)
resource "aws_secretsmanager_secret" "github_webhook_secret" {
  name = "${var.name}/github-webhook-secret"
}
resource "aws_secretsmanager_secret_version" "github_webhook_secret" {
  secret_id                = aws_secretsmanager_secret.github_webhook_secret.id
  secret_string_wo         = var.github_webhook_secret_wo
  secret_string_wo_version = var.github_webhook_secret_wo_version
}

resource "aws_secretsmanager_secret" "slack_signing_secret" {
  name = "${var.name}/slack-signing-secret"
}
resource "aws_secretsmanager_secret_version" "slack_signing_secret" {
  secret_id                = aws_secretsmanager_secret.slack_signing_secret.id
  secret_string_wo         = var.slack_signing_secret_wo
  secret_string_wo_version = var.slack_signing_secret_wo_version
}

resource "aws_secretsmanager_secret" "slack_bot_token" {
  name = "${var.name}/slack-bot-token"
}
resource "aws_secretsmanager_secret_version" "slack_bot_token" {
  secret_id                = aws_secretsmanager_secret.slack_bot_token.id
  secret_string_wo         = var.slack_bot_token_wo
  secret_string_wo_version = var.slack_bot_token_wo_version
}

resource "aws_secretsmanager_secret" "github_app_private_key" {
  name = "${var.name}/github-app-private-key"
}
resource "aws_secretsmanager_secret_version" "github_app_private_key" {
  secret_id                = aws_secretsmanager_secret.github_app_private_key.id
  secret_string_wo         = var.github_app_private_key_wo
  secret_string_wo_version = var.github_app_private_key_wo_version
}

resource "aws_secretsmanager_secret" "gemini_api_key" {
  name = "${var.name}/gemini-api-key"
}
resource "aws_secretsmanager_secret_version" "gemini_api_key" {
  secret_id                = aws_secretsmanager_secret.gemini_api_key.id
  secret_string_wo         = var.gemini_api_key_wo
  secret_string_wo_version = var.gemini_api_key_wo_version
}

# --- IAM: one execution role per Lambda, each reading only the secrets it uses
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_webhook_handler" {
  name               = "${var.name}-github-webhook-handler"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "github_webhook_handler_logs" {
  role       = aws_iam_role.github_webhook_handler.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "github_webhook_handler_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.github_webhook_secret.arn,
      aws_secretsmanager_secret.slack_bot_token.arn,
      aws_secretsmanager_secret.gemini_api_key.arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_webhook_handler_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.github_webhook_handler.id
  policy = data.aws_iam_policy_document.github_webhook_handler_secrets.json
}

resource "aws_iam_role" "slack_interaction_handler" {
  name               = "${var.name}-slack-interaction-handler"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "slack_interaction_handler_logs" {
  role       = aws_iam_role.slack_interaction_handler.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "slack_interaction_handler_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.slack_signing_secret.arn,
      aws_secretsmanager_secret.slack_bot_token.arn,
      aws_secretsmanager_secret.github_app_private_key.arn,
    ]
  }
}

resource "aws_iam_role_policy" "slack_interaction_handler_secrets" {
  name   = "read-secrets"
  role   = aws_iam_role.slack_interaction_handler.id
  policy = data.aws_iam_policy_document.slack_interaction_handler_secrets.json
}

# --- CloudWatch Logs (explicit, bounded retention -- never the account default
# of "keep forever") --------------------------------------------------------
resource "aws_cloudwatch_log_group" "github_webhook_handler" {
  name              = "/aws/lambda/${var.name}-github-webhook-handler"
  retention_in_days = var.log_retention_in_days
}

resource "aws_cloudwatch_log_group" "slack_interaction_handler" {
  name              = "/aws/lambda/${var.name}-slack-interaction-handler"
  retention_in_days = var.log_retention_in_days
}

# --- Lambda functions --------------------------------------------------------
resource "aws_lambda_function" "github_webhook_handler" {
  function_name    = "${var.name}-github-webhook-handler"
  role             = aws_iam_role.github_webhook_handler.arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.github_webhook_handler.output_path
  source_code_hash = data.archive_file.github_webhook_handler.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      GITHUB_WEBHOOK_SECRET_ARN  = aws_secretsmanager_secret.github_webhook_secret.arn
      SLACK_BOT_TOKEN_SECRET_ARN = aws_secretsmanager_secret.slack_bot_token.arn
      GEMINI_API_KEY_SECRET_ARN  = aws_secretsmanager_secret.gemini_api_key.arn
      SLACK_CHANNEL_ID           = var.slack_channel_id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.github_webhook_handler,
    aws_iam_role_policy.github_webhook_handler_secrets,
    aws_iam_role_policy_attachment.github_webhook_handler_logs,
  ]
}

resource "aws_lambda_function" "slack_interaction_handler" {
  function_name    = "${var.name}-slack-interaction-handler"
  role             = aws_iam_role.slack_interaction_handler.arn
  handler          = "index.handler"
  runtime          = var.lambda_runtime
  filename         = data.archive_file.slack_interaction_handler.output_path
  source_code_hash = data.archive_file.slack_interaction_handler.output_base64sha256
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      SLACK_SIGNING_SECRET_ARN          = aws_secretsmanager_secret.slack_signing_secret.arn
      SLACK_BOT_TOKEN_SECRET_ARN        = aws_secretsmanager_secret.slack_bot_token.arn
      SLACK_APPROVER_APP_ID             = var.slack_approver_app_id # not sensitive; a public GitHub App id, so a plain env var, not a Secrets Manager entry
      SLACK_APPROVER_APP_KEY_SECRET_ARN = aws_secretsmanager_secret.github_app_private_key.arn
      SLACK_CHANNEL_ID                  = var.slack_channel_id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.slack_interaction_handler,
    aws_iam_role_policy.slack_interaction_handler_secrets,
    aws_iam_role_policy_attachment.slack_interaction_handler_logs,
  ]
}

# --- API Gateway (HTTP API): one route per Lambda ---------------------------
resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "github_webhook_handler" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.github_webhook_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "github_webhook_handler" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /github/webhook"
  target    = "integrations/${aws_apigatewayv2_integration.github_webhook_handler.id}"
}

resource "aws_lambda_permission" "github_webhook_handler_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.github_webhook_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "slack_interaction_handler" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.slack_interaction_handler.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "slack_interaction_handler" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /slack/interactions"
  target    = "integrations/${aws_apigatewayv2_integration.slack_interaction_handler.id}"
}

resource "aws_lambda_permission" "slack_interaction_handler_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_interaction_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
