.resource_changes[]?
| select(.change.actions | index("delete"))
| select(
    (.type | test("^aws_(ecr_repository|ecr_lifecycle_policy|secretsmanager_secret|secretsmanager_secret_version|route53_zone)$"))
    or (
      .type == "aws_route53_record"
      and ((.address | test("^aws_route53_record\\.ingress\\[[^]]+\\]$")) | not)
    )
    or (.address | test("(^|\\.)aws_iam_openid_connect_provider\\.github_actions(\\[[^]]+\\])?$"))
    or (.address | test("(github_ecr_publisher|github_platform_mirror|dr_secret_seed)"))
  )
| .address
