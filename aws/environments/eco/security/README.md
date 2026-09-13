# eco/security

The economical environment's security root, second in the PC-IAC-022 order
(ops spec 004 T011, ai-agents specs/001 T025). It holds what `eco/workload`
needs before it can create the cluster.

| Resource | Module | Name |
| --- | --- | --- |
| Control-plane role: `AmazonEKSClusterPolicy`, and use of the secrets key | `iam-role-v1.0.0` | `lex-mts-eco-role-cluster` |
| Managed nodes' role: `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly` | `iam-role-v1.0.0` | `lex-mts-eco-role-node` |
| Key for Kubernetes secrets | `kms-key-v1.0.0` | `alias/lex-mts-eco-kms-eks` |
| Key for the control-plane log group | `kms-key-v1.0.0` | `alias/lex-mts-eco-kms-ekslogs` |
| Extra control-plane security group | `security-group-v1.0.0` | `lex-mts-eco-sg-cluster` |
| Node security group | `security-group-v1.0.0` | `lex-mts-eco-sg-node` |
| JWT signing secrets, one per application environment | `secret-v1.0.0` | `lex-mts-eco-sm-jwt{dev,stg,prd,dmo}` |
| Slack webhook secrets | `secret-v1.0.0` | `lex-mts-eco-sm-slackobs`, `lex-mts-eco-sm-slacksec` |

**The security groups** keep the rules the legacy upstream EKS module gave
its groups, now written out.
- **Cluster group:** the nodes may reach the API on 443.
- **Node group, ingress:**
  - from the cluster group, on 443, 4443, 6443, 8443, 9443, 10250, and 10251;
  - between nodes, CoreDNS on 53 over TCP and UDP, and TCP on the ephemeral ports 1025–65535.
- **Node group, egress:** all egress, the recorded Trivy AWS-0104 exception (`docs/iac-exceptions.md`). Its inline suppression covers only that module call.
- **Karpenter:** the node group carries Karpenter's discovery tag.

**The keys.**
- The logs key lets CloudWatch Logs in this region use it only for
  `/aws/eks/lex-mts-eco-eks-main/cluster`.
- The secrets key keeps the AWS default policy, which delegates to IAM in the
  account. The cluster role's inline policy allows the four actions the control
  plane needs on it.

**The secrets.** Terraform owns only the containers. The values are copied or
regenerated in the approved cutover (ops spec 004 T014), and the Slack
webhooks are supplied by a person.

**The VPC** is read from `eco/networking` by its standard name.

**Not here, because they come in the IRSA pass after `eco/workload`** (it
needs the cluster's OIDC issuer): the IRSA roles for the VPC CNI, the EBS CSI
driver, the load balancer controller, and the secret readers.

## Plan and apply

```bash
cp eco.tfvars.example eco.tfvars                         # fill aws_account_id
cp security.s3.tfbackend.example security.s3.tfbackend   # fill from shd/state's outputs
terraform -chdir=aws/environments/eco/security init -backend-config=security.s3.tfbackend
terraform -chdir=aws/environments/eco/security plan -input=false -var-file=eco.tfvars -out=eco-security.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107), and after `eco/networking`. The state key is new, so the apply
records a `no-prior-state` receipt.

## Outputs

- `cluster_role_arn`, `node_role_arn`
- `secrets_key_arn`, `logs_key_arn`
- `cluster_security_group_id`, `node_security_group_id`
- `jwt_secret_arns`, `webhook_secret_arns`
