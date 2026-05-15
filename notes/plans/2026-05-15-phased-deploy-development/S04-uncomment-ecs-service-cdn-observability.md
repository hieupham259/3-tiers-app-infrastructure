# Sprint S04 - Un-comment: module ecs_service, frontend_cdn, observability (stack day du)

## CAP NHAT 2026-05-15: anh huong tu refactor cost-optimization o S01

Sau refactor cost-opt (xem README.md cua plan + S01), kien truc ECS Fargate da thay doi:
- ECS task chay trong **public subnet** (truoc kia private subnet) voi `assign_public_ip = true`.
- Khong dung NAT Gateway nua - task pull image ECR + doc Secrets Manager qua IGW.
- Security group cua ECS task chi cho phep inbound tu ALB SG → van an toan du co public IP.

Trong block `module "ecs_service"` o `envs/_shared/main.tf` (dang comment), iac-builder da cap nhat truoc 2 dong sau de S04 un-comment ra dung kien truc moi:
- `subnet_ids = module.network.public_subnet_ids` (truoc kia: `private_subnet_ids = module.network.private_subnet_ids`).
- `assign_public_ip = true` (dong moi them).

Module `modules/ecs-service/`:
- `variables.tf`: rename `private_subnet_ids` → `subnet_ids`; them var `assign_public_ip` (default false).
- `main.tf`: `network_configuration` dung `var.subnet_ids` va `var.assign_public_ip`.
- `README.md`: cap nhat vi du usage.

S04 KHONG can sua gi them ve subnet binding cua ECS - chi cap nhat khi un-comment block.

## Goal

Sau Sprint nay, `envs/_shared/main.tf` tra ve trang thai day du voi tat ca 9 module. `envs/_shared/outputs.tf` phuc hoi toan bo. Dong thoi phuc hoi cac gia tri tam thoi da thay doi o S03: `ingress_security_group_ids` cua `module "rds"` tra ve `[module.ecs_service.security_group_id]`, `frontend_bucket_arn` cua `module "iam_app_roles"` tra ve `module.frontend_cdn.bucket_arn`. Deploy len `development` thanh cong. Day la giai doan cuoi - sau Sprint nay, stack day du.

## Pham vi un-comment va phuc hoi

### 1. `envs/_shared/main.tf`

Un-comment (xoa comment marker):
- `module "ecs_service"`
- `module "frontend_cdn"`
- `module "observability"`

Phuc hoi gia tri tam thoi tu S03:
- Trong `module "rds"`: sua `ingress_security_group_ids = [] # S03: temporary empty list, restored in S04` thanh `ingress_security_group_ids = [module.ecs_service.security_group_id]`
- Trong `module "iam_app_roles"`: sua `frontend_bucket_arn = null # S03: temporary null, restored in S04` thanh `frontend_bucket_arn = module.frontend_cdn.bucket_arn`

Xoa tat ca comment tam thoi "# S03: temporary..." con lai.

File cuoi cung phai giong het trang thai goc truoc S01.

### 2. `envs/_shared/outputs.tf`

Un-comment toan bo cac block con lai:
- `resource "aws_ssm_parameter" "ecs_service_name"` (tham chieu `module.ecs_service.service_name`)
- `resource "aws_ssm_parameter" "ecs_task_definition_family"` (tham chieu `module.ecs_service.task_definition_family`)
- `resource "aws_ssm_parameter" "frontend_bucket"` (tham chieu `module.frontend_cdn.bucket_name`)
- `resource "aws_ssm_parameter" "cloudfront_distribution_id"` (tham chieu `module.frontend_cdn.distribution_id`)
- `output "frontend_bucket"` (tham chieu `module.frontend_cdn.bucket_name`)
- `output "cloudfront_distribution_id"` (tham chieu `module.frontend_cdn.distribution_id`)
- `output "observability_ecs_cpu_alarm_arn"` (tham chieu `module.observability.ecs_cpu_alarm_arn`)
- `output "observability_rds_connections_alarm_arn"` (tham chieu `module.observability.rds_connections_alarm_arn`)
- `output "observability_alb_5xx_alarm_arn"` (tham chieu `module.observability.alb_5xx_alarm_arn`)

File cuoi cung phai giong het trang thai goc truoc S01 (khong con comment rac nao).

## Luu y ve phu thuoc vong giua rds va ecs_service

Module `rds` co `ingress_security_group_ids = [module.ecs_service.security_group_id]`. Trong khi do, `module "ecs_service"` can `module.rds.endpoint` va `module.rds.secret_arn`. Day la cross-module reference, Terraform giai quyet hop le:
- `aws_security_group` cua `ecs_service` duoc tao truoc (khong phu thuoc rds).
- `aws_db_instance` cua `rds` dung security group ID cua `ecs_service` (da co).
- `aws_ecs_task_definition` cua `ecs_service` dung endpoint/secret cua `rds` (da co sau khi rds xong).

Day la luong hop le, Terraform plan se giai quyet dung.

## Luu y ve IAM policy khi frontend_bucket_arn phuc hoi

Khi `module "iam_app_roles"` nhan duoc `frontend_bucket_arn` thuc (thay vi null tu S03), Terraform co the tao them IAM policy cho bucket hoac update policy hien tai. iac-reviewer can kiem tra plan ky xem co thay doi IAM policy nao unexpected khong.

## Definition of done

- `terraform fmt -check -recursive` pass.
- `terraform validate` trong `envs/development/` pass.
- `tflint --recursive` pass.
- `scripts/verify-envs-in-sync.sh` pass.
- `terraform-planner` xac nhan plan: chi tao resource cua `ecs_service`, `frontend_cdn`, `observability`; co the co IAM policy update (in-place) tren iam_app_roles; khong co replacement tren bat ky resource da co.
- Apply thanh cong tren branch `development`.
- Verify tren AWS Console:
  - ECS service chay trong cluster (co the PENDING neu chua co container image, nhung service va task definition da ton tai).
  - S3 bucket cho frontend ton tai.
  - CloudFront distribution o trang thai `Deployed`.
  - CloudWatch alarms cho ECS, RDS, ALB da ton tai.
  - SSM Parameter Store co day du cac key `/3-tiers-app/development/...`.
- `envs/_shared/main.tf` va `envs/_shared/outputs.tf` giong het trang thai goc truoc S01 (tat ca comment phan giai doan da bi xoa).

## Sub-tasks

- [ ] S04-T01 - Un-comment module ecs_service, frontend_cdn, observability trong `envs/_shared/main.tf`; phuc hoi ingress_security_group_ids va frontend_bucket_arn; un-comment toan bo phan con lai cua `envs/_shared/outputs.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: `envs/_shared/main.tf` sau S03 (co 2 gia tri tam thoi, 3 module van comment), `envs/_shared/outputs.tf` sau S03; RDS, IAM roles, ECR, ALB, ECS cluster, networking da ton tai tren AWS
  - Outputs / artifacts: `envs/_shared/main.tf` giong het file goc truoc S01; `envs/_shared/outputs.tf` giong het file goc truoc S01
  - Depends on: S03-T06 (RDS, IAM da deploy thanh cong)
  - Notes: Xoa het cac comment tam thoi "# S03: temporary..." truoc khi commit. File cuoi cung phai sach - khong con comment rac nao con lai tu qua trinh phased deploy.

- [ ] S04-T02 - Review diff Sprint S04
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S04-T01
  - Outputs / artifacts: tick S04-T01; reassign neu co van de
  - Depends on: S04-T01
  - Notes: Kiem tra dac biet: (1) `envs/_shared/main.tf` va `envs/_shared/outputs.tf` gio giong het file goc (so sanh voi git history truoc S01); (2) `ingress_security_group_ids` va `frontend_bucket_arn` da phuc hoi dung; (3) khong con comment rac nao; (4) IAM policy update (neu co) la in-place, khong phai replacement

- [ ] S04-T03 - Chay terraform plan xac nhan chi tao resource cua ecs_service, frontend_cdn, observability
  - Assignee: terraform-planner
  - Inputs / preconditions: code sau S04-T01 da review S04-T02 approve
  - Outputs / artifacts: bao cao plan; resource mong doi: ECS task definition, ECS service, security group ECS, S3 bucket frontend, CloudFront distribution, Route53 record (neu domain_name set), CloudWatch alarms; co the co IAM policy update (in-place)
  - Depends on: S04-T02
  - Notes: Mong doi khong co "replace" tren bat ky resource da co tu S01-S03; neu co replace, dung de proceed va reassign S04-T01

- [ ] S04-T04 - Deploy giai doan 4 (stack day du) len branch development
  - Assignee: user
  - Inputs / preconditions: S04-T03 xac nhan plan an toan
  - Outputs / artifacts: stack day du tren AWS; apply job thanh cong
  - Depends on: S04-T03
  - Notes: |
      Quy trinh deploy len `development`:
      1. `git checkout development && git pull && git checkout -b feature/phased-deploy-s04-full-stack`.
      2. Push, mo PR base=`development`.
      3. Doi plan pass. Kiem tra ky: khong co replace tren resource cu.
      4. Merge. Approve apply.
      5. Doi apply thanh cong (co the mat 10-15 phut cho CloudFront).
      6. Verify tren AWS Console (theo danh sach trong Definition of done).
      Replicate sang `production` (sau khi `development` verify xong):
      7. Mo PR moi base=`production`, head=`feature/phased-deploy-s04-full-stack` (cung feature branch).
      8. Doi plan pass voi account production. Merge. Approve apply trong Environment `production`. Verify Console.
      Sau S04 tren ca hai env, `envs/_shared/` da tro ve trang thai day du - hai branch `development` va `production` lai dong bo.

- [ ] S04-T05 - Xac nhan `envs/_shared/main.tf` va `envs/_shared/outputs.tf` giong het trang thai goc (tat ca comment rac da xoa)
  - Assignee: iac-reviewer
  - Inputs / preconditions: S04-T04 done (stack da deploy)
  - Outputs / artifacts: xac nhan cuoi cung; tick sprint done trong README.md cua plan nay; ghi nhan hoan tat phased deploy
  - Depends on: S04-T04
  - Notes: So sanh voi git history (commit truoc S01) de dam bao khong co gi con lai tu qua trinh phased deploy; neu co comment rac, reassign S04-T01 de xoa noc. Sau khi confirm, cap nhat README.md cua plan - doi tat ca Sprint sang status "done".

## Review checklist

Cac reviewer tick box khi verify xong.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

## Last updated

2026-05-15 by main thread - them section "CAP NHAT: anh huong tu refactor cost-optimization": ECS Fargate chuyen sang public subnet voi assign_public_ip=true, module ecs-service rename bien private_subnet_ids → subnet_ids
