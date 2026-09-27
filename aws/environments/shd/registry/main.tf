# The shd/registry root: the service image repositories every environment pulls from
# (PC-IAC-022). The images of the legacy repositories are copied in by digest, with their
# signatures and attestations, in the approved cutover (ops spec 004 FR-004).
module "service_images" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//ecr-repository?ref=ecr-repository-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client       = var.client
  project      = var.project
  environment  = var.environment
  repositories = local.service_repositories
}

# The platform image mirror (ops spec 004 T032): every locked third-party platform image, copied
# by digest by the reviewed mirror workflow under shd/security's mirror role. It is a separate
# call so the publisher role, which pushes to the service repositories, never reaches it. The
# successor of the legacy microtodosuite/platform; the module keeps the legacy protection.
module "platform_mirror" {
  source = "git::https://github.com/MicroTodoSuite/terraform-aws-modules.git//ecr-repository?ref=ecr-repository-v1.0.0"

  providers = {
    aws.project = aws.principal
  }

  client          = var.client
  project         = var.project
  environment     = var.environment
  repositories    = local.platform_mirror_repositories
  additional_tags = { Content = "third-party-platform-images" }
}
