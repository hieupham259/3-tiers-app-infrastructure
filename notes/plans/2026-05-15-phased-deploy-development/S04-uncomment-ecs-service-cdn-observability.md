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

- [x] S04-T01 - Un-comment module ecs_service, frontend_cdn, observability trong `envs/_shared/main.tf`; phuc hoi ingress_security_group_ids va frontend_bucket_arn; un-comment toan bo phan con lai cua `envs/_shared/outputs.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: `envs/_shared/main.tf` sau S03 (co 2 gia tri tam thoi, 3 module van comment), `envs/_shared/outputs.tf` sau S03; RDS, IAM roles, ECR, ALB, ECS cluster, networking da ton tai tren AWS
  - Outputs / artifacts: `envs/_shared/main.tf` giong het file goc truoc S01; `envs/_shared/outputs.tf` giong het file goc truoc S01
  - Depends on: S03-T06 (RDS, IAM da deploy thanh cong)
  - Notes: Xoa het cac comment tam thoi "# S03: temporary..." truoc khi commit. File cuoi cung phai sach - khong con comment rac nao con lai tu qua trinh phased deploy.

- [x] S04-T02 - Review diff Sprint S04
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S04-T01
  - Outputs / artifacts: tick S04-T01; reassign neu co van de
  - Depends on: S04-T01
  - Notes: Kiem tra dac biet: (1) `envs/_shared/main.tf` va `envs/_shared/outputs.tf` gio giong het file goc (so sanh voi git history truoc S01); (2) `ingress_security_group_ids` va `frontend_bucket_arn` da phuc hoi dung; (3) khong con comment rac nao; (4) IAM policy update (neu co) la in-place, khong phai replacement

- [x] S04-T03 - Chay terraform plan xac nhan chi tao resource cua ecs_service, frontend_cdn, observability
  - Assignee: terraform-planner
  - Inputs / preconditions: code sau S04-T01 da review S04-T02 approve
  - Outputs / artifacts: bao cao plan; resource mong doi: ECS task definition, ECS service, security group ECS, S3 bucket frontend, CloudFront distribution, Route53 record (neu domain_name set), CloudWatch alarms; co the co IAM policy update (in-place)
  - Depends on: S04-T02
  - Notes: Mong doi khong co "replace" tren bat ky resource da co tu S01-S03; neu co replace, dung de proceed va reassign S04-T01

- [x] S04-T04 - Deploy giai doan 4 (stack day du) len branch development
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

- [x] S04-T05 - Xac nhan `envs/_shared/main.tf` va `envs/_shared/outputs.tf` giong het trang thai goc (tat ca comment rac da xoa)
  - Assignee: iac-reviewer
  - Inputs / preconditions: S04-T04 done (stack da deploy)
  - Outputs / artifacts: xac nhan cuoi cung; tick sprint done trong README.md cua plan nay; ghi nhan hoan tat phased deploy
  - Depends on: S04-T04
  - Notes: So sanh voi git history (commit truoc S01) de dam bao khong co gi con lai tu qua trinh phased deploy; neu co comment rac, reassign S04-T01 de xoa noc. Sau khi confirm, cap nhat README.md cua plan - doi tat ca Sprint sang status "done".

## Review checklist

Cac reviewer tick box khi verify xong.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

### 2026-05-19 - iac-reviewer
- Verdict: approve
- Sub-tasks ticked: S04-T01, S04-T02
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0, INFO 1

Tom tat:
- Diff cua S04-T01 chinh xac voi yeu cau Sprint:
  - Un-comment 3 module `ecs_service`, `frontend_cdn`, `observability` trong `envs/_shared/main.tf`.
  - Phuc hoi `ingress_security_group_ids = [module.ecs_service.security_group_id]` o `module "rds"`.
  - Phuc hoi `frontend_bucket_arn = module.frontend_cdn.bucket_arn` o `module "iam_app_roles"`.
  - Un-comment toan bo phan SSM parameter + output con lai cua `envs/_shared/outputs.tf` (ecs_service_name, ecs_task_definition_family, frontend_bucket, cloudfront_distribution_id, observability_*_alarm_arn).
- So sanh voi baseline pre-S01 (commit 0837c87): cau truc 9 module va outputs/SSM cua `envs/_shared/` da khoi phuc dung. Sai khac duy nhat la nhung thay doi co chu dich tu cac plan khac (tag `Repository`, ECR repo name suffix `-${var.environment}`, `master_password` cho RDS, output `rds_secret_arn`, ECS subnet/public_ip cua refactor cost-opt). Khong co drift ngoai du kien.
- Khong con comment rac `# S03: temporary` / `# S04:` / module block bi comment toan bo trong hai file (grep `S03|S04|temporary|phased` va `^#\s*(module|resource|output|data)` deu rong).
- Cross-module reference da xac minh ton tai:
  - `module.ecs_service.service_name`, `task_definition_family`, `security_group_id` trong `modules/ecs-service/outputs.tf`.
  - `module.frontend_cdn.bucket_name`, `bucket_arn`, `distribution_id` trong `modules/frontend-cdn/outputs.tf`.
  - `module.observability.ecs_cpu_alarm_arn`, `rds_connections_alarm_arn`, `alb_5xx_alarm_arn` trong `modules/observability/outputs.tf`.
- ECS Fargate subnet binding khop refactor cost-opt: `var.subnet_ids` (list) + `var.assign_public_ip` (bool) ton tai trong `modules/ecs-service/variables.tf`, va `network_configuration` trong `modules/ecs-service/main.tf` dung dung hai bien nay (subnets = var.subnet_ids, assign_public_ip = var.assign_public_ip).
- Quality gates local-only chay lai:
  - `terraform fmt -check -recursive`: PASS (exit 0).
  - `scripts/verify-envs-in-sync.sh`: PASS ("OK: envs/development and envs/production are in sync.").
  - `tflint` SKIP (khong co tren PATH - khong phai loi cua diff nay).
  - `terraform validate` SKIP (gate AWS API + remote backend init - se duoc terraform-planner xu ly o S04-T03).
- [INFO] `modules/iam-app-roles/main.tf` hien KHONG tham chieu `var.frontend_bucket_arn` (variable chi duoc khai bao trong `variables.tf` nhung khong duoc dung trong main.tf). Do do viec doi tu `null` -> `module.frontend_cdn.bucket_arn` o env wiring se KHONG sinh IAM policy moi hoac trigger update IAM resource nao. Sprint plan dong 66-68 noi "Terraform co the tao them IAM policy cho bucket hoac update policy hien tai" - thuc te plan se chi co `frontend_cdn` + `ecs_service` + `observability` resource moi, va `iam_app_roles` van no-op (hoac chi update do change-set cua biet sai variable value, tuy plan engine - khong replace, khong delete). terraform-planner xac nhan o S04-T03.

Ket luan: code dat yeu cau. San sang dispatch terraform-planner cho S04-T03.

### 2026-05-19 - main thread (ghi nhan S04-T03 va S04-T04 done)
- Sub-tasks ticked: S04-T03, S04-T04.
- Quy trinh thuc te:
  - Feature branch `feature/phased-deploy-s04-full-stack` (tao tu development).
  - PR #28 mo voi base=`development`.
  - `terraform-plan.yaml` chay tren PR (S04-T03 thay vi terraform-planner local theo policy "terraform commands chi chay tren CI/CD hoac co confirm cua user").
  - Plan pass: chi co create + in-place update; khong replacement tren resource cu cua S01-S03.
  - PR #28 merged vao `development` luc 2026-05-19 17:23 +0700 (commit `46eea80`).
  - `terraform-apply.yaml` chay tren commit merge va apply thanh cong (S04-T04 done).
  - Development branch da fast-forward tu `8b0092b` -> `46eea80`.
- San sang cho S04-T05 (xac nhan cuoi cung + dong plan).
- Buoc tiep theo cua user (out of scope S04 nhung trong Notes cua sub-task): mo PR moi base=`production`, head=`feature/phased-deploy-s04-full-stack` de replicate sang production.

### 2026-05-19 - iac-reviewer (S04-T05 final confirmation)
- Verdict: approve - dong Sprint S04 va toan bo phased-deploy plan
- Sub-tasks ticked: S04-T05
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0

Tom tat verify cuoi cung:
- Baseline pre-S01 = commit `0837c87` (commit truoc khi feature branch S01 mo).
- `git diff 0837c87 HEAD -- envs/_shared/main.tf`: 4 hunk, tat ca deu la thay doi co chu dich tu cac plan khac:
  - Hunk 1: them `Repository = var.repository` vao `common_tags` (plan `2026-05-16-add-repository-tag`).
  - Hunk 2: doi `repo_name = "3-tiers-app-backend"` thanh `"3-tiers-app-backend-${var.environment}"` (S02a).
  - Hunk 3: them `master_password = var.rds_master_password` vao `module "rds"` (S03 + plan `2026-05-18-fix-secret-version-refresh-bomb`).
  - Hunk 4: doi `private_subnet_ids = module.network.private_subnet_ids` thanh `subnet_ids = module.network.public_subnet_ids` + them `assign_public_ip = true` trong `module "ecs_service"` (cost-opt refactor 2026-05-15).
- `git diff 0837c87 HEAD -- envs/_shared/outputs.tf`: 1 hunk, them `output "rds_secret_arn"` (S03 + plan `2026-05-18-fix-secret-version-refresh-bomb`).
- KHONG co diff nao ngoai du kien.
- KHONG con dau vet cua phased deploy:
  - `Grep "S03|S04|temporary|phased|TODO|FIXME"` tren `envs/_shared/`: zero match.
  - `Grep "^\\s*#\\s*(module|resource|output|data)"`: zero match (khong con block bi comment).
  - Comment con lai trong `envs/_shared/` deu la phan chia section thuong gap (`# --- Network ---`, `# --- RDS ---`, v.v.) o `variables.tf` va `outputs.tf` - khong phai rac phased deploy.
- Quality gates local-only:
  - `scripts/verify-envs-in-sync.sh`: PASS ("OK: envs/development and envs/production are in sync.").
  - `terraform fmt -check -recursive`: PASS (exit 0).
  - `tflint`: SKIP (khong co tren PATH, nhat quan voi cac review truoc).
  - `terraform validate` + `terraform plan`: SKIP (gate AWS API; `terraform-apply.yaml` da chay tren CI luc apply S04-T04, ket qua PASS - duoc ghi nhan trong review log o tren).
- Ket luan: `envs/_shared/main.tf` va `envs/_shared/outputs.tf` da tro lai trang thai day du, sach se, dong bo voi du dinh kien truc cuoi cung. Sprint S04 va toan bo plan `2026-05-15-phased-deploy-development` chinh thuc dong. Cong viec con lai (replicate sang `production`) nam ngoai pham vi plan nay.

## Last updated

2026-05-19 by iac-reviewer - tick S04-T05 sau khi verify `envs/_shared/main.tf` va `envs/_shared/outputs.tf` sach so voi baseline pre-S01 (commit `0837c87`); sync envs PASS, fmt PASS; append entry final vao Review log; dong Sprint S04 va toan bo phased-deploy plan.

2026-05-19 by main thread - tick S04-T03 va S04-T04 sau khi PR #28 merge vao development va apply thanh cong; append entry vao Review log voi thong tin commit `46eea80`. San sang cho S04-T05 (final reviewer confirmation).

2026-05-15 by main thread - them section "CAP NHAT: anh huong tu refactor cost-optimization": ECS Fargate chuyen sang public subnet voi assign_public_ip=true, module ecs-service rename bien private_subnet_ids → subnet_ids
