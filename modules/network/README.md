# Module: network

VPC, public/private subnets, Internet Gateway, NAT Gateway, route tables.

## BYO support

| Variable | Description |
|----------|-------------|
| `existing_vpc_id` | If set, skip VPC creation and use this VPC |
| `existing_private_subnet_ids` | Required when `existing_vpc_id != null` |
| `existing_public_subnet_ids` | Required when `existing_vpc_id != null` |

When every `existing_*` is `null`, the module creates a new VPC across 3 AZs.

## Outputs

- `vpc_id` - ID of the VPC (created or existing)
- `private_subnet_ids` - list for ECS / RDS
- `public_subnet_ids` - list for ALB
- `vpc_cidr`, `azs`

## Notes

- Each AZ has its own NAT Gateway for high availability, but cost is higher. You can share a single NAT in dev if you need to save cost.
- Subnet CIDR slicing uses `cidrsubnet(var.vpc_cidr, 4, ...)` - a `/16` VPC becomes `/20` subnets (4096 IPs/subnet).
