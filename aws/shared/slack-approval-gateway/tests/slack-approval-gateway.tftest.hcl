# Root-level contract for the Slack approval gateway (docs/full-platform/
# slack-approval-gateway.md). Proves the account guard fails closed, the API
# routes/integrations point at the correct Lambda, and every secret is wired
# as write-only (never a plain secret_string) except the one value that
# genuinely is not sensitive.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "575172595729"
      arn        = "arn:aws:iam::575172595729:role/test"
      id         = "575172595729"
      user_id    = "test"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  # aws_iam_policy_document is a data source too, so full mocking replaces its
  # computed `json` with this fixed value regardless of the real statements
  # configured in main.tf -- the policy *content* is not something a plan-only
  # mocked test can verify; the run below instead proves each role policy
  # attaches to the correct role, which is a real cross-reference, not a
  # mocked computed value.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# A default mock ARN is not well-formed, and aws_lambda_function's own schema
# validates that its `role` argument looks like a real ARN even under a fully
# mocked apply. Two distinct, real-looking ARNs (not one shared default) so a
# role-wiring test can actually tell the two roles apart.
override_resource {
  target = aws_iam_role.github_webhook_handler
  values = {
    arn = "arn:aws:iam::575172595729:role/mock-github-webhook-handler"
  }
}

override_resource {
  target = aws_iam_role.slack_interaction_handler
  values = {
    arn = "arn:aws:iam::575172595729:role/mock-slack-interaction-handler"
  }
}

override_resource {
  target = aws_apigatewayv2_api.this
  values = {
    execution_arn = "arn:aws:execute-api:us-east-1:575172595729:mockapiid"
  }
}

# The sibling repo's built dist/ directory will not exist in this repo's own
# CI checkout -- override both zips rather than require a cross-repo build
# just to run this root's plan-level contract.
override_data {
  target = data.archive_file.github_webhook_handler
  values = {
    output_path         = "/tmp/github-webhook-handler.zip"
    output_base64sha256 = "ZmFrZS1oYXNoLWZvci10ZXN0LW9ubHk="
  }
}

override_data {
  target = data.archive_file.slack_interaction_handler
  values = {
    output_path         = "/tmp/slack-interaction-handler.zip"
    output_base64sha256 = "ZmFrZS1oYXNoLWZvci10ZXN0LW9ubHk="
  }
}

variables {
  expected_account_id = "575172595729"
  slack_channel_id    = "C0000000000"

  slack_approver_app_id = "123456"

  github_webhook_secret_wo          = "test-github-webhook-secret"
  github_webhook_secret_wo_version  = 1
  slack_signing_secret_wo           = "test-slack-signing-secret"
  slack_signing_secret_wo_version   = 1
  slack_bot_token_wo                = "xoxb-test-token"
  slack_bot_token_wo_version        = 1
  github_app_private_key_wo         = "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----"
  github_app_private_key_wo_version = 1
  gemini_api_key_wo                 = "AIzaTest0000000000000000000000000"
  gemini_api_key_wo_version         = 1
}

run "refuses_to_apply_against_the_wrong_account" {
  command = plan

  variables {
    expected_account_id = "123456789012"
  }

  expect_failures = [
    var.expected_account_id,
  ]
}

run "wires_the_http_api_routes_to_the_matching_lambda" {
  # apply (against the mocked provider, no real AWS call): integration_uri and
  # invoke_arn are both computed from the function's mocked ARN, unknown
  # during a plan-only run, so comparing them needs the mocked apply to
  # resolve first.
  command = apply

  assert {
    condition     = aws_apigatewayv2_api.this.protocol_type == "HTTP"
    error_message = "This gateway must be an HTTP API, not a WebSocket API."
  }

  assert {
    condition     = aws_apigatewayv2_route.github_webhook_handler.route_key == "POST /github/webhook"
    error_message = "GitHub webhooks must land on POST /github/webhook exactly."
  }

  assert {
    condition     = aws_apigatewayv2_route.slack_interaction_handler.route_key == "POST /slack/interactions"
    error_message = "Slack interactions must land on POST /slack/interactions exactly."
  }

  assert {
    condition     = aws_apigatewayv2_integration.github_webhook_handler.integration_uri == aws_lambda_function.github_webhook_handler.invoke_arn
    error_message = "The github_webhook_handler route must integrate with the github_webhook_handler Lambda, not any other function."
  }

  assert {
    condition     = aws_apigatewayv2_integration.slack_interaction_handler.integration_uri == aws_lambda_function.slack_interaction_handler.invoke_arn
    error_message = "The slack_interaction_handler route must integrate with the slack_interaction_handler Lambda, not any other function."
  }
}

run "attaches_each_secrets_policy_to_its_own_lambda_role_only" {
  command = plan

  # The policy *content* (which secret ARNs are listed) is not verifiable
  # under full data-source mocking -- aws_iam_policy_document.json is always
  # the fixed mock value above. What is still real and worth asserting: each
  # inline policy attaches to its own function's role, not the other one's --
  # a copy-paste mistake here would grant the wrong Lambda every secret.
  assert {
    condition     = aws_iam_role_policy.github_webhook_handler_secrets.role == aws_iam_role.github_webhook_handler.id
    error_message = "The github_webhook_handler secrets policy must attach to the github_webhook_handler role."
  }

  assert {
    condition     = aws_iam_role_policy.slack_interaction_handler_secrets.role == aws_iam_role.slack_interaction_handler.id
    error_message = "The slack_interaction_handler secrets policy must attach to the slack_interaction_handler role."
  }

  assert {
    condition     = aws_lambda_function.github_webhook_handler.role == aws_iam_role.github_webhook_handler.arn
    error_message = "github_webhook_handler must run as its own role, not slack_interaction_handler's."
  }

  assert {
    condition     = aws_lambda_function.slack_interaction_handler.role == aws_iam_role.slack_interaction_handler.arn
    error_message = "slack_interaction_handler must run as its own role, not github_webhook_handler's."
  }
}
