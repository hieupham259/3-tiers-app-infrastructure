# Sprint S03 - Un-comment: module rds, iam_app_roles

## CAP NHAT 2026-05-15: anh huong tu refactor cost-optimization o S01

Kien truc network sau refactor cost-opt (xem README.md cua plan + S01) cung cap:
- **2 private subnet** o **2 AZ** khac nhau (us-east-1a + us-east-1b).
- Private subnet KHONG co route 0.0.0.0/0 (no NAT) - phu hop cho RDS (RDS khong can outbound internet).

→ Rang buoc **DB Subnet Group >= 2 subnet o >= 2 AZ** cua AWS RDS **da duoc thoa man** boi module network. Khong can chinh gi them o module rds ve mat subnet.

`module.rds` van dung `subnet_ids = module.network.private_subnet_ids` nhu hien tai - module.network.private_subnet_ids gio la list 2 phan tu (2 AZ), du de tao DB Subnet Group.

## Goal

Sau Sprint nay, `envs/_shared/main.tf` un-comment them 2 module: `module "rds"` va `module "iam_app_roles"`. Day la 2 module stateful/IAM can deploy truoc `ecs_service` vi `ecs_service` can `rds.secret_arn`, `rds.endpoint`, `iam_app_roles.task_exec_role_arn`, `iam_app_roles.task_role_arn`. `envs/_shared/outputs.tf` un-comment them `output "rds_endpoint"`. Deploy len `development` thanh cong.

Luu y quan trong ve cac tham chieu chua co san: module `rds` tham chieu `module.ecs_service.security_group_id` nhung `ecs_service` van comment -> can thay tam thoi bang `ingress_security_group_ids = []`. Module `iam_app_roles` tham chieu `module.frontend_cdn.bucket_arn` nhung `frontend_cdn` van comment -> can thay tam thoi bang `frontend_bucket_arn = null`. Ca hai gia tri tam thoi nay se phuc hoi o S04.

## Pham vi chinh sua

### 1. `envs/_shared/main.tf`

Un-comment `module "rds"` voi chinh sua nho o dong `ingress_security_group_ids`:
- Thay `ingress_security_group_ids = [module.ecs_service.security_group_id]`
- Bang `ingress_security_group_ids = [] # S03: temporary empty list, restored in S04`

Un-comment `module "iam_app_roles"` voi chinh sua nho o dong `frontend_bucket_arn`:
- Thay `frontend_bucket_arn = module.frontend_cdn.bucket_arn`
- Bang `frontend_bucket_arn = null # S03: temporary null, restored in S04`

Xoa comment "# PHASED-DEPLOY S01" tren cac block duoc un-comment.

Giu comment:
- `module "ecs_service"`
- `module "frontend_cdn"`
- `module "observability"`

### 2. `envs/_shared/outputs.tf`

Un-comment:
- `output "rds_endpoint"` (tham chieu `module.rds.endpoint`)

Giu comment:
- `aws_ssm_parameter.ecs_service_name` (tham chieu `module.ecs_service` - van comment)
- `aws_ssm_parameter.ecs_task_definition_family` (tham chieu `module.ecs_service` - van comment)
- `aws_ssm_parameter.frontend_bucket` (tham chieu `module.frontend_cdn` - van comment)
- `aws_ssm_parameter.cloudfront_distribution_id` (tham chieu `module.frontend_cdn` - van comment)
- `output "frontend_bucket"` (tham chieu `module.frontend_cdn` - van comment)
- `output "cloudfront_distribution_id"` (tham chieu `module.frontend_cdn` - van comment)
- `output "observability_*"` (tham chieu `module.observability` - van comment)

## Kiem tra tinh tuong thich truoc khi un-comment

Truoc khi un-comment va chinh sua, iac-builder can kiem tra:
1. `modules/iam-app-roles/variables.tf`: bien `frontend_bucket_arn` co `type = string` hay `type = any`? Co `default = null` khong? Co `nullable = true` khong? Neu khong co kha nang nhan null, can them `nullable = true` hoac `default = null` vao variables.tf cua module.
2. `modules/rds/main.tf`: resource `aws_db_instance` co `lifecycle { prevent_destroy = true }` chua? Neu chua, them vao.

## Resource stateful can luu y

`aws_db_instance` trong module `rds` la resource stateful. Sub-task S03-T02 kiem tra va them `lifecycle { prevent_destroy = true }` neu chua co.

`aws_secretsmanager_secret` trong module `rds` cung la stateful resource. Kiem tra xem module co them lifecycle cho secret khong. Neu chua, them vao.

## Definition of done

- `terraform fmt -check -recursive` pass.
- `terraform validate` trong `envs/development/` pass.
- `tflint --recursive` pass.
- `scripts/verify-envs-in-sync.sh` pass.
- `terraform-planner` xac nhan plan: chi tao resource cua `rds` va `iam_app_roles`; khong co thay doi tren networking, ECR, ALB, ECS cluster da co.
- `rds` module tao duoc: RDS instance, security group, subnet group, Secrets Manager secret.
- `iam_app_roles` tao duoc: ECS task execution role, ECS task role.
- Apply thanh cong tren branch `development`.
- RDS instance trang thai `available` trong AWS Console.

## Sub-tasks

- [ ] S03-T01 - Kiem tra `modules/iam-app-roles/variables.tf` va `modules/rds/main.tf` de xac nhan kha nang tuong thich voi gia tri tam thoi
  - Assignee: iac-builder
  - Inputs / preconditions: `modules/iam-app-roles/variables.tf`, `modules/rds/main.tf`
  - Outputs / artifacts: bao cao ngan: (1) bien `frontend_bucket_arn` co nullable/default null chua; (2) `aws_db_instance` co lifecycle prevent_destroy chua
  - Depends on: S02-T04 (giai doan truoc da deploy xong)
  - Notes: Neu `frontend_bucket_arn` khong co kha nang nhan null, them `nullable = true` hoac `default = null` vao variables.tf cua module iam-app-roles - day la chinh sua can thiet cho phased deploy va an toan

- [ ] S03-T02 - Them lifecycle { prevent_destroy = true } cho aws_db_instance (va aws_secretsmanager_secret neu chua co) trong modules/rds/main.tf
  - Assignee: iac-builder
  - Inputs / preconditions: ket qua S03-T01
  - Outputs / artifacts: `modules/rds/main.tf` co lifecycle block tren db instance va secret resource
  - Depends on: S03-T01
  - Notes: Neu da co lifecycle block thi tick luon; chi them khi chua co. Day la buoc bao ve truoc khi RDS duoc tao lan dau.

- [ ] S03-T03 - Un-comment module rds va iam_app_roles trong `envs/_shared/main.tf` voi gia tri tam thoi; un-comment output rds_endpoint trong `envs/_shared/outputs.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: S03-T01 va S03-T02 done; networking + ECR + ALB + ECS cluster da ton tai tren AWS
  - Outputs / artifacts: `envs/_shared/main.tf` voi 2 module duoc un-comment (co chinh sua tam thoi); `envs/_shared/outputs.tf` voi output rds_endpoint duoc un-comment
  - Depends on: S03-T02
  - Notes: Them comment ro rang `# S03: temporary empty list, restored in S04` va `# S03: temporary null, restored in S04` de iac-builder Sprint S04 biet chinh xac can phuc hoi gi. Xoa comment "PHASED-DEPLOY S01" tren cac block duoc un-comment.

- [ ] S03-T04 - Review diff Sprint S03
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S03-T01, S03-T02, S03-T03
  - Outputs / artifacts: tick cac sub-task; reassign neu co van de
  - Depends on: S03-T03
  - Notes: Kiem tra dac biet: (1) `ingress_security_group_ids = []` - RDS security group se khong cho ECS vao, intentional trong giai doan nay; (2) `frontend_bucket_arn = null` - module iam_app_roles co the khong tao IAM policy cho bucket neu null; (3) lifecycle prevent_destroy co mat tren db instance va secret; (4) cac module van comment (ecs_service, frontend_cdn, observability) khong lo ra output nao

- [ ] S03-T05 - Chay terraform plan xac nhan chi tao resource rds va iam_app_roles
  - Assignee: terraform-planner
  - Inputs / preconditions: code sau S03-T03 da review S03-T04 approve
  - Outputs / artifacts: bao cao plan; resource mong doi: RDS instance (1) + RDS security group (1) + RDS subnet group (1) + Secrets Manager secret (1) + IAM roles (2+) + IAM policies; output rds_endpoint
  - Depends on: S03-T04
  - Notes: Khong duoc co thay doi tren networking / ECR / ALB / ECS cluster da co tu S01-S02

- [ ] S03-T06 - Deploy giai doan 3 len branch development
  - Assignee: user
  - Inputs / preconditions: S03-T05 xac nhan plan an toan
  - Outputs / artifacts: RDS instance trang thai available, IAM roles ton tai trong AWS Console
  - Depends on: S03-T05
  - Notes: |
      Quy trinh deploy len `development`:
      1. `git checkout development && git pull && git checkout -b feature/phased-deploy-s03-rds-iam`.
      2. Push, mo PR base=`development`.
      3. Doi plan pass. Luu y: RDS tao mat khoang 10-15 phut.
      4. Merge. Approve apply.
      5. Doi apply thanh cong (co the mat 15-20 phut cho RDS).
      6. Verify: RDS instance o trang thai `available`; IAM roles ton tai.
      Replicate sang `production` (sau khi `development` verify xong):
      7. Mo PR moi base=`production`, head=`feature/phased-deploy-s03-rds-iam` (cung feature branch).
      8. Doi plan pass voi account production. Merge. Approve apply trong Environment `production`. Verify Console.

## Review checklist

Cac reviewer tick box khi verify xong.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

## Last updated

2026-05-15 by main thread - them section "CAP NHAT: anh huong tu refactor cost-optimization": xac nhan DB Subnet Group rang buoc da duoc thoa man boi 2 private subnet o 2 AZ tu module network
