resource "aws_ecr_repository" "services" {
  for_each = local.service_names

  name                 = "${var.project}/${var.environment}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, {
    Name    = "${var.project}/${var.environment}/${each.key}"
    Service = each.key
  })
}

resource "aws_ecr_lifecycle_policy" "services" {
  for_each = aws_ecr_repository.services

  repository = each.value.name
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

resource "aws_ecr_repository" "neutral_services" {
  for_each = var.create_shared_resources ? var.neutral_service_names : toset([])

  name                 = "${var.project}/${each.key}"
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
    Name        = "${var.project}/${each.key}"
    Service     = each.key
  })
}

data "aws_ecr_repository" "neutral_services" {
  for_each = var.create_shared_resources ? toset([]) : var.neutral_service_names

  name = "${var.project}/${each.key}"
}

resource "aws_ecr_lifecycle_policy" "neutral_services" {
  for_each = aws_ecr_repository.neutral_services

  repository = each.value.name
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

locals {
  neutral_ecr_repository_urls = merge(
    { for service, repository in aws_ecr_repository.neutral_services : service => repository.repository_url },
    { for service, repository in data.aws_ecr_repository.neutral_services : service => repository.repository_url }
  )
}
