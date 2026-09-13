# Infrastructure-as-Code Exceptions

Findings of the rule contracts, tflint, Trivy, or SonarCloud that the team has
decided to accept. A row waives a contract finding only when it carries a
reason and an expiry; the format is defined in
`microservice-app-ai-agents/rules/iac/README.md`. Rows for tflint, Trivy, and
SonarCloud record the decision behind a suppression made in that tool or in
the code (`NOSONAR`, `.trivyignore`), which must cite the row. Each row is added
in its own reviewed pull request.

| Rule | Path | Resource | Reason | Expiry |
| --- | --- | --- | --- | --- |
| Trivy `AWS-0104` | aws/environments/{dev,demo-full,full-dev,full-prod}/foundation | The node security group's egress rule to `0.0.0.0/0`, created by the upstream `terraform-aws-modules/eks/aws` module | Nodes pull images from ECR and reach STS, S3, and CloudWatch Logs through this egress. The Amazon EKS security group requirements allow all outbound traffic from nodes, and narrowing it needs VPC endpoints, which are billed by the hour in every environment. Egress leaves only through NAT gateways or the transit hub, and VPC flow logs record it. Decision delegated by the maintainer, 2026-09-13 (ai-agents specs/001 T041). | Re-decided at the full-profile capacity review (ai-agents specs/001 T028), which budgets VPC endpoints for ECR, S3, STS, and CloudWatch Logs |
