# ---------------------------------------------------------------------------
# Opt-in AWS Load Balancer Controller prerequisites (spec 009, T018).
#
# Terraform owns the IRSA role and publishes the VPC/cluster discovery inputs
# the controller needs. GitOps owns the controller release itself, and the
# controller's permission set comes from reviewed policy ARNs rather than a
# policy document reproduced here.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "aws_load_balancer_controller" {
  count = local.full_profile_prerequisite_count

  name                 = "${local.cluster_name}-aws-load-balancer-controller"
  description          = "IRSA role bound exactly to ${var.aws_load_balancer_controller_service_account_subject} on ${local.cluster_name}"
  permissions_boundary = var.iam_permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowLoadBalancerControllerWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          "${module.eks.oidc_provider}:sub" = var.aws_load_balancer_controller_service_account_subject
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  for_each = var.enable_full_profile_cluster_prerequisites ? var.aws_load_balancer_controller_policy_arns : toset([])

  role       = aws_iam_role.aws_load_balancer_controller[0].name
  policy_arn = each.value
}
