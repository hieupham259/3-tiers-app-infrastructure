# Sprint S02 - Un-comment: module ecr_backend, alb, ecs_cluster

## Goal

Sau Sprint nay, `envs/_shared/main.tf` un-comment them 3 module: `module "ecr_backend"`, `module "alb"`, `module "ecs_cluster"`. Ba module nay doc lap hoac chi phu thuoc vao networking da co tu S01. `envs/_shared/outputs.tf` un-comment cac SSM parameter va output lien quan toi 3 module nay. Cac module `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability` van comment. `terraform plan` chi tao resource cua 3 module moi nay. Deploy len `development` thanh cong.

## Cac module duoc un-comment trong Sprint nay

| Module | Phu thuoc vao module nao | Resource chinh |
|--------|--------------------------|----------------|
| `ecr_backend` | khong co (doc lap) | `aws_ecr_repository` |
| `alb` | `module.network.vpc_id`, `module.network.public_subnet_ids` | `aws_lb`, `aws_lb_listener`, `aws_lb_target_group`, `aws_security_group` |
| `ecs_cluster` | khong co (doc lap) | `aws_ecs_cluster` |

## Pham vi un-comment

### 1. `envs/_shared/main.tf`

Un-comment (xoa comment marker truoc cac block sau):
- `module "ecr_backend"`
- `module "alb"`
- `module "ecs_cluster"`

Xoa comment "# PHASED-DEPLOY S01" tren cac block duoc un-comment.

Giu comment:
- `module "rds"`
- `module "iam_app_roles"`
- `module "ecs_service"`
- `module "frontend_cdn"`
- `module "observability"`

### 2. `envs/_shared/outputs.tf`

Un-comment cac block sau (dang bi comment tu S01):
- `resource "aws_ssm_parameter" "ecr_backend_url"` (tham chieu `module.ecr_backend.repository_url`)
- `resource "aws_ssm_parameter" "alb_dns_name"` (tham chieu `module.alb.dns_name`)
- `output "ecs_cluster_name"` (tham chieu `module.ecs_cluster.cluster_name`)
- `output "alb_dns_name"` (tham chieu `module.alb.dns_name`)
- `output "ecr_backend_url"` (tham chieu `module.ecr_backend.repository_url`)

Giu comment:
- `aws_ssm_parameter.ecs_cluster_name` - luu y block nay tham chieu `module.ecs_cluster.cluster_name`: un-comment block nay neu module `ecs_cluster` duoc un-comment (xem lai: block nay DUOC un-comment vi ecs_cluster da active)
- `aws_ssm_parameter.ecs_service_name` (tham chieu `module.ecs_service` - van comment)
- `aws_ssm_parameter.ecs_task_definition_family` (tham chieu `module.ecs_service` - van comment)
- `aws_ssm_parameter.frontend_bucket` (tham chieu `module.frontend_cdn` - van comment)
- `aws_ssm_parameter.cloudfront_distribution_id` (tham chieu `module.frontend_cdn` - van comment)
- `output "frontend_bucket"` (tham chieu `module.frontend_cdn` - van comment)
- `output "cloudfront_distribution_id"` (tham chieu `module.frontend_cdn` - van comment)
- `output "rds_endpoint"` (tham chieu `module.rds` - van comment)
- `output "observability_*"` (tham chieu `module.observability` - van comment)

Luu y chi tiet: cac block SSM parameter/output can un-comment trong Sprint nay:
1. `resource "aws_ssm_parameter" "ecs_cluster_name"` - tham chieu ecs_cluster (gio active)
2. `resource "aws_ssm_parameter" "ecr_backend_url"` - tham chieu ecr_backend (gio active)
3. `resource "aws_ssm_parameter" "alb_dns_name"` - tham chieu alb (gio active)
4. `output "ecs_cluster_name"` - tham chieu ecs_cluster (gio active)
5. `output "alb_dns_name"` - tham chieu alb (gio active)
6. `output "ecr_backend_url"` - tham chieu ecr_backend (gio active)

## Definition of done

- `terraform fmt -check -recursive` pass.
- `terraform validate` trong `envs/development/` pass.
- `tflint --recursive` pass.
- `scripts/verify-envs-in-sync.sh` pass.
- `terraform-planner` xac nhan plan: chi tao resource cua `ecr_backend`, `alb`, `ecs_cluster`; khong co thay doi tren resource networking da co tu S01.
- Apply thanh cong tren branch `development`.
- Verify: ECR repo, ALB, ECS cluster ton tai trong AWS Console.

## Sub-tasks

- [ ] S02-T01 - Un-comment module ecr_backend, alb, ecs_cluster trong `envs/_shared/main.tf` va un-comment cac SSM parameter/output tuong ung trong `envs/_shared/outputs.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: `envs/_shared/main.tf` sau S01 (8 module bi comment), `envs/_shared/outputs.tf` sau S01 (toan bo bi comment); networking da ton tai tren AWS tu S01
  - Outputs / artifacts: `envs/_shared/main.tf` voi 3 module duoc un-comment; `envs/_shared/outputs.tf` voi 6 block duoc un-comment (3 SSM parameter + 3 output)
  - Depends on: S01-T05 (networking da deploy thanh cong)
  - Notes: Can xac nhan module "alb" tham chieu dung `module.network.public_subnet_ids` - output nay co san tu `modules/network/outputs.tf`. Xoa cac comment "PHASED-DEPLOY S01" tren cac block duoc un-comment.

- [ ] S02-T02 - Review diff Sprint S02
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S02-T01
  - Outputs / artifacts: tick S02-T01; reassign neu co van de
  - Depends on: S02-T01
  - Notes: Kiem tra: (1) khong co resource networking bi thay doi; (2) cac output duoc un-comment tham chieu dung module; (3) cac module van comment (rds, iam_app_roles, ecs_service, frontend_cdn, observability) khong lo ra output nao; (4) `terraform validate` pass

- [ ] S02-T03 - Chay terraform plan xac nhan chi tao resource cua ecr_backend, alb, ecs_cluster
  - Assignee: terraform-planner
  - Inputs / preconditions: code sau S02-T01 da review S02-T02 approve
  - Outputs / artifacts: bao cao plan; so luong resource mong doi: ECR (1) + ALB stack (khoang 4-5 resource: lb, listener, target group, security group) + ECS cluster (1) + SSM parameters (3) = khoang 9-10 resource to add
  - Depends on: S02-T02
  - Notes: Khong duoc co thay doi tren networking resource da co tu S01

- [ ] S02-T04 - Deploy giai doan 2 len branch development
  - Assignee: user
  - Inputs / preconditions: S02-T03 xac nhan plan an toan
  - Outputs / artifacts: ECR, ALB, ECS cluster ton tai trong AWS Console
  - Depends on: S02-T03
  - Notes: |
      Quy trinh deploy len `development`:
      1. `git checkout development && git pull && git checkout -b feature/phased-deploy-s02-ecr-alb-ecs`.
      2. Push, mo PR base=`development`.
      3. Doi plan pass. Merge. Approve apply.
      4. Verify: ECR repo co ten `3-tiers-app-backend`, ALB co DNS name, ECS cluster `development-ecs-app` hoac ten tuong duong.
      Replicate sang `production` (sau khi `development` verify xong):
      5. Mo PR moi base=`production`, head=`feature/phased-deploy-s02-ecr-alb-ecs` (cung feature branch).
      6. Doi plan pass voi account production. Merge. Approve apply trong Environment `production`. Verify Console.
      Luu y: co the gom S02 voi cac Sprint sau roi merge sang `production` mot lan (vai module mot luc) thay vi tung Sprint.

## Review checklist

Cac reviewer tick box khi verify xong.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

## Last updated

2026-05-15 by main thread - doi marker PHASED-ROLLOUT thanh PHASED-DEPLOY; doi ten feature branch; them buoc replicate sang production
