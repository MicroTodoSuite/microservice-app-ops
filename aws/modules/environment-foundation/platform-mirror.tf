# ---------------------------------------------------------------------------
# Platform image mirror (spec 009, T019).
#
# The full profile runs third-party platform images: controllers, exporters and
# dashboards. Every one of them is mirrored into a single dev-owned repository
# so a cluster never resolves an upstream registry at runtime and every
# deployable digest is reachable from one audited place.
#
# The mirror is a singleton: exactly one foundation creates it, every other
# foundation reads it. It stays off until the stage that populates it, so the
# applied dev foundation keeps exactly the repositories it has today.
# ---------------------------------------------------------------------------

locals {
  platform_mirror_repository_name = "${var.project}/platform"
  platform_mirror_role_name       = "microtodosuite-github-platform-mirror"

  create_platform_mirror = var.create_shared_resources && var.enable_platform_image_mirror

  platform_mirror_repository_arn = "arn:${data.aws_partition.current.partition}:ecr:${var.aws_region}:${var.expected_account_id}:repository/${local.platform_mirror_repository_name}"

  platform_mirror_repository_url = one(concat(
    aws_ecr_repository.platform_mirror[*].repository_url,
    data.aws_ecr_repository.platform_mirror[*].repository_url,
  ))
}

resource "aws_ecr_repository" "platform_mirror" {
  count = local.create_platform_mirror ? 1 : 0

  name                 = local.platform_mirror_repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, {
    Environment = "shared"
    Name        = local.platform_mirror_repository_name
    Content     = "third-party-platform-images"
  })
}

data "aws_ecr_repository" "platform_mirror" {
  count = var.enable_platform_image_mirror && !var.create_shared_resources ? 1 : 0

  name = local.platform_mirror_repository_name
}

# Mirrored images are pinned by digest and never expire on a timer: a cluster
# that still resolves an older digest must keep working. Only untagged layers
# left behind by an interrupted push are reclaimed.
resource "aws_ecr_lifecycle_policy" "platform_mirror" {
  count = local.create_platform_mirror ? 1 : 0

  repository = aws_ecr_repository.platform_mirror[0].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 30 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 30
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# A role of its own. The service publisher must never gain mirror access, and
# the mirror must never gain service-publishing access, so a compromise of
# either workflow cannot reach the other's artifacts.
resource "aws_iam_role" "github_platform_mirror" {
  count = local.create_platform_mirror ? 1 : 0

  name                 = local.platform_mirror_role_name
  description          = "Mirror reviewed third-party platform images into exactly ${local.platform_mirror_repository_name}"
  permissions_boundary = var.iam_permissions_boundary_arn
  max_session_duration = 3600

  # job_workflow_ref, not sub: the trust is bound to one reviewed workflow file
  # at one ref, so adding a new workflow to the same repository grants nothing.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowExactReviewedMirrorWorkflow"
      Effect = "Allow"
      Principal = {
        Federated = local.github_actions_oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud"              = "sts.amazonaws.com"
          "${local.github_oidc_host}:job_workflow_ref" = sort(tolist(var.github_platform_mirror_job_workflow_refs))
        }
      }
    }]
  })

  tags = merge(local.tags, {
    Environment = "shared"
  })
}

resource "aws_iam_role_policy" "github_platform_mirror" {
  count = local.create_platform_mirror ? 1 : 0

  name = "mirror-platform-images"
  role = aws_iam_role.github_platform_mirror[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AuthenticateToEcr"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "MirrorPlatformImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:ListImages",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = [local.platform_mirror_repository_arn]
      },
    ]
  })
}
