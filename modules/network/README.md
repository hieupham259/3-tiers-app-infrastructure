# Module: network

VPC, public/private subnets, Internet Gateway, route tables. No NAT Gateway and no EIP in the current cost-optimized topology.

## BYO support

| Variable | Description |
|----------|-------------|
| `existing_vpc_id` | If set, skip VPC creation and use this VPC |
| `existing_private_subnet_ids` | Required when `existing_vpc_id != null` |
| `existing_public_subnet_ids` | Required when `existing_vpc_id != null` |

When every `existing_*` is `null`, the module creates a new VPC across 2 AZs by default (configurable via `var.az_count`). Two AZs satisfy both the ALB requirement and the RDS DB Subnet Group requirement.

## Outputs

- `vpc_id` - ID of the VPC (created or existing)
- `private_subnet_ids` - list for RDS only (no outbound internet route in the current topology)
- `public_subnet_ids` - list for ALB and Fargate task ENIs (with `assign_public_ip = true`)
- `vpc_cidr`, `azs`

## Notes

- No NAT Gateway and no EIP. Fargate tasks run in public subnets with `assign_public_ip = true` to reach ECR and Secrets Manager over the IGW. This saves the ~$32/month NAT charge in non-production. The task security group still restricts ingress to the ALB SG only.
- The private route table has only the implicit local route; private subnets host RDS, which does not need outbound internet.
- Subnet CIDR slicing uses `cidrsubnet(var.vpc_cidr, 4, ...)` - a `/16` VPC becomes `/20` subnets (4096 IPs/subnet).
