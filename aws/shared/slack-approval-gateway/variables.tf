variable "name" {
  description = "Base name for every resource this root creates."
  type        = string
  default     = "microtodosuite-slack-approval-gateway"
}

variable "expected_account_id" {
  description = "AWS account allowed to receive this shared tooling. Dev-owned, the same ownership pattern as the SonarQube admin/db secrets (specs/009-full-platform-rollout/research.md)."
  type        = string

  validation {
    condition     = var.expected_account_id == "575172595729"
    error_message = "This shared tooling belongs to the dev-owned account 575172595729. Applying it elsewhere would create an unreviewed second copy rather than fail."
  }
}

variable "aws_region" {
  description = "Region for this root. Matches every other reviewed MicroTodoSuite environment."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "Every reviewed MicroTodoSuite environment is in us-east-1."
  }
}

variable "owner" {
  description = "Owning team recorded in tags."
  type        = string
  default     = "platform"
}

variable "common_tags" {
  description = "Tags applied to every resource in this root."
  type        = map(string)
  default     = {}
}

variable "lambda_source_dir" {
  description = <<-EOT
    Path to microservice-app-slack-approval-gateway's built `dist/` directory
    (the output of that repo's `npm run build`), expected to contain
    `github-webhook-handler/index.mjs` and `slack-interaction-handler/index.mjs`.
    Defaults to the sibling-checkout layout every other cross-repo test and
    script in this project already assumes.
  EOT
  type        = string
  default     = "../../../../microservice-app-slack-approval-gateway/dist"
}

variable "lambda_runtime" {
  description = <<-EOT
    AWS Lambda managed Node.js runtime identifier. Set conservatively to a
    long-established runtime; bump to a newer nodejsNN.x once its exact
    availability is confirmed against AWS's current Lambda runtime support
    page (this project's dev tooling targets Node >=24, which is not the same
    claim as "AWS Lambda offers that runtime today").
  EOT
  type        = string
  default     = "nodejs22.x"
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for both Lambda functions. No secret value is ever logged (see the source repo's value-blind design), but request/response metadata still should not be retained indefinitely."
  type        = number
  default     = 30
}

variable "slack_channel_id" {
  description = "Slack channel both Lambdas post approval requests and notifications to."
  type        = string
}

# --- Ephemeral, write-only credentials -------------------------------------
# Every *_wo variable is never persisted to Terraform state or plan output
# (Terraform >=1.10 ephemeral values, paired with each secret version
# resource's own write-only argument). Supply the value only at apply time
# (an interactive prompt, or a short-lived TF_VAR_ environment variable that
# is unset immediately after); increment the matching *_wo_version to force a
# rotation to take effect. No PAT, no plaintext value in any committed file.

variable "github_webhook_secret_wo" {
  description = "Shared secret configured on the GitHub App's webhook; verifies X-Hub-Signature-256."
  type        = string
  ephemeral   = true
  sensitive   = true
}
variable "github_webhook_secret_wo_version" {
  description = "Increment to rotate github_webhook_secret_wo."
  type        = number
  default     = 1
}

variable "slack_signing_secret_wo" {
  description = "Slack app's signing secret; verifies X-Slack-Signature."
  type        = string
  ephemeral   = true
  sensitive   = true
}
variable "slack_signing_secret_wo_version" {
  description = "Increment to rotate slack_signing_secret_wo."
  type        = number
  default     = 1
}

variable "slack_bot_token_wo" {
  description = "Slack bot token used to post/update messages (chat:write scope)."
  type        = string
  ephemeral   = true
  sensitive   = true
}
variable "slack_bot_token_wo_version" {
  description = "Increment to rotate slack_bot_token_wo."
  type        = number
  default     = 1
}

variable "slack_approver_app_id" {
  description = "microtodosuite-slack-approver GitHub App id. Not itself sensitive, but stored in Secrets Manager alongside its private key so both Lambdas fetch App credentials the same way."
  type        = string
}

variable "github_app_private_key_wo" {
  description = "microtodosuite-slack-approver GitHub App private key (PEM). Handle per microservice-app-docs/full-platform/slack-approval-gateway.md: chmod 600 the downloaded file, apply straight from it, delete it immediately after."
  type        = string
  ephemeral   = true
  sensitive   = true
}
variable "github_app_private_key_wo_version" {
  description = "Increment to rotate github_app_private_key_wo."
  type        = number
  default     = 1
}

variable "anthropic_api_key_wo" {
  description = "Anthropic API key used to generate the non-technical summary."
  type        = string
  ephemeral   = true
  sensitive   = true
}
variable "anthropic_api_key_wo_version" {
  description = "Increment to rotate anthropic_api_key_wo."
  type        = number
  default     = 1
}
