.resource_changes[]?
| select(.change.actions | index("delete"))
| select(
    (.type | test("^aws_(ecr_repository|ecr_lifecycle_policy|secretsmanager_secret|secretsmanager_secret_version|route53_zone|route53_record)$"))
    or (.address | test("(^|\\.)aws_iam_openid_connect_provider\\.github_actions(\\[[^]]+\\])?$"))
    or (.address | test("(github_ecr_publisher|github_platform_mirror|dr_secret_seed)"))
  )
| .address
