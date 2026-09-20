.resource_changes[]?
| select(.change.actions | index("delete"))
| select(
    (.type | test("^aws_(ecr_repository|ecr_repository_policy|ecr_lifecycle_policy|secretsmanager_secret|secretsmanager_secret_version|route53_zone|route53_zone_association|route53_key_signing_key|acm_certificate|acm_certificate_validation|kms_key|kms_alias|kms_replica_key|s3_bucket|s3_bucket_versioning|s3_bucket_policy|s3_bucket_server_side_encryption_configuration|s3_bucket_public_access_block|s3_bucket_logging|s3_bucket_lifecycle_configuration)$"))
    or (
      .type == "aws_route53_record"
      and ((.address | test("^aws_route53_record\\.ingress\\[[^]]+\\]$")) | not)
    )
    or (.address | test("(^|\\.)aws_iam_openid_connect_provider\\.github_actions(\\[[^]]+\\])?$"))
    or (.address | test("(github_ecr_publisher|github_platform_mirror|dr_secret_seed)"))
  )
| .address
