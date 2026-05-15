# Phased Deploy for Development Environment

## Context

Day la trien khai ha tang LAN DAU (chua co resource nao duoc tao tru cac stack trong `bootstrap/`). Day KHONG phai rollout/cap nhat ha tang dang chay.

Nguoi dung muon deploy ha tang theo tung module mot (phased deploy) cho moi truong `development` thay vi deploy toan bo stack cung luc, voi muc dich hieu cau truc va cach hoat dong cua Terraform. Cach thuc hien: comment phan code chua can thiet de moi lan `terraform apply` chi tao dung cac resource cua giai doan hien tai. Sau moi giai doan, un-comment them module cua giai doan ke tiep va deploy lai.

Sau khi moi giai doan chay tot tren `development`, nguoi dung se merge cung thay doi do sang `production` (tung module hoac vai module mot lan).

Sprint 1 deploy full networking module (cost-optimized topology). Chi comment/uncomment cac module call trong `envs/_shared/main.tf` va cac block tuong ung trong `envs/_shared/outputs.tf`.

## Quyet dinh kien truc cost-optimization (2026-05-15)

Trong qua trinh thuc hien S01, user yeu cau refactor de toi uu chi phi truoc khi deploy lan dau. Tom tat kien truc mang moi:

- **VPC 2 AZ** (us-east-1a + us-east-1b) - thoa man ALB (>=2 AZ) va RDS DB Subnet Group (>=2 AZ).
- **2 public subnet** (1 moi AZ, /20) - phuc vu ALB + ECS Fargate task.
- **2 private subnet** (1 moi AZ, /20) - chi phuc vu RDS (de thoa man Subnet Group, khong co outbound internet).
- **KHONG CO NAT Gateway, KHONG CO Elastic IP** - tiet kiem ~$32/thang (NAT Gateway: ~$32/cai/thang).
- **1 public route table** (shared cho 2 public subnet) → IGW.
- **1 private route table** (shared cho 2 private subnet) - chi co local route, khong co 0.0.0.0/0.
- **ECS Fargate** chay trong public subnet voi `assign_public_ip = true` de pull image ECR + Secrets Manager qua IGW thay vi NAT. Security group ECS chi cho phep inbound tu ALB SG → van an toan du co public IP.

Tong: **12 resource networking** (1 VPC + 2 public subnet + 2 private subnet + 1 IGW + 1 public RT + 1 private RT + 4 RTA).

### File da sua trong refactor nay

- `modules/network/variables.tf` - `az_count` default 1 → 2.
- `modules/network/main.tf` - xoa `aws_eip.nat` va `aws_nat_gateway.this`; `aws_route_table.private` thanh shared (count=1) khong co route NAT; `aws_route_table_association.private` map ve RT[0].
- `modules/network/README.md` - cap nhat mo ta (2 AZs, no NAT/EIP).
- `modules/ecs-service/variables.tf` - rename `private_subnet_ids` → `subnet_ids`; them var `assign_public_ip` (default false).
- `modules/ecs-service/main.tf` - dung `var.subnet_ids` va `var.assign_public_ip` trong network_configuration.
- `modules/ecs-service/README.md` - cap nhat vi du usage.
- `envs/_shared/main.tf` - sua noi dung block `module "ecs_service"` van con comment: `subnet_ids = module.network.public_subnet_ids` + `assign_public_ip = true`. Khi un-comment o S04 se dung kien truc moi.

### Anh huong toi cac Sprint

- **S01**: resource mong doi tu 21 (kien truc cu 3 AZ + 3 NAT/EIP) → **12** (kien truc moi 2 AZ + 0 NAT/EIP). Sub-task S01-T01 (them lifecycle prevent_destroy cho aws_eip.nat) khong con relevant vi aws_eip da bi xoa khoi module.
- **S03**: RDS DB Subnet Group rang buoc >=2 subnet o >=2 AZ → da duoc thoa man boi 2 private subnet o 2 AZ trong kien truc moi.
- **S04**: ECS service un-comment se dung public subnet + assign_public_ip=true thay vi private subnet.

### Open question

Code `envs/_shared/` dung chung cho ca `production`. Khi merge sang production, production cung mat NAT. Neu sau nay production can NAT (HA + tach traffic), can them variable gate (vi du `enable_nat_gateway` o module network) de production override. Hien tai user chap nhan, ghi nhan de revisit.

## Cap nhat

Plan nay da duoc sua lai vao 2026-05-15 (ban dau tao cung ngay). Thay doi chinh: S01 cu (comment ben trong modules/network) va S02 cu (uncomment full networking) da duoc gop/loai bo. Thay vao do la 4 Sprint moi, khong dong cham vao `modules/network/`.

## Deployment model

Apply KHONG chay tu local. Theo CLAUDE.md, apply chi xay ra qua GitHub Actions pipeline khi push. Luong deploy cho moi giai doan:

1. Tao feature branch tu `development`.
2. Commit va push code (da comment/uncomment dung giai doan).
3. Mo PR vao `development` -> `terraform-plan.yaml` chay, kiem tra plan.
4. Merge PR vao `development` -> `terraform-apply.yaml` chay, duyet va apply.

## Sprints

| ID | Title | Status | Owner of last update |
|----|-------|--------|----------------------|
| S01 | deploy-full-networking | planned | task-planner |
| S02 | uncomment-ecr-alb-ecs-cluster | planned | task-planner |
| S03 | uncomment-rds-iam | planned | task-planner |
| S04 | uncomment-ecs-service-cdn-observability | planned | task-planner |

## Chuoi phu thuoc giua Sprint

S01 -> S02 -> S03 -> S04. Moi Sprint mo khoa giai doan truoc khi bat dau giai doan tiep theo.

## Open questions

- Khong co open question. Tat ca quyet dinh co the dat ra da duoc nguoi dung trinh bay ro trong yeu cau.

## Out-of-scope

- Thay doi `envs/development/` va `envs/production/` ngoai viec deploy.
- Thay doi cac workflow `.github/workflows/`.
- Luat "byte-identical" cua `scripts/verify-envs-in-sync.sh` khong bi vi pham vi script chi kiem tra `envs/development/main.tf` va `envs/development/variables.tf` - khong kiem tra `envs/_shared/`.

## Production

Code comment/uncomment nam o `envs/_shared/` (dung chung cho ca hai env). Vi chua co resource nao duoc tao tren ca `development` lan `production`, viec deploy sang `production` la AN TOAN - moi giai doan chi THEM resource (0 destroy).

Luong lam viec:
- Moi Sprint = mot feature branch chua dung mot diff. Merge vao `development` truoc -> deploy + verify tren account development.
- Sau khi `development` chay tot, merge cung feature branch do sang `production` -> deploy + verify tren account production.
- Co the gom vai Sprint roi merge sang `production` mot lan (vai module mot luc) thay vi tung Sprint mot.
- Khong co rang buoc thu tu cung-nhip giua hai env; `development` co the di truoc `production` bao nhieu giai doan tuy y.

## Last updated

2026-05-15 by main thread - them section "Quyet dinh kien truc cost-optimization": bo NAT/EIP, 2 AZ public + 2 AZ private, ECS Fargate trong public subnet voi assign_public_ip=true; cap nhat anh huong toi S01/S03/S04; ghi nhan open question ve production NAT gating
