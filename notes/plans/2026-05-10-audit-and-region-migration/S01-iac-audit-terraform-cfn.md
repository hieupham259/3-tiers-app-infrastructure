# Sprint S01 - IaC Audit: Terraform modules va CloudFormation

## Goal

Soat toan bo Terraform modules (`modules/**`), env layer (`envs/**`, `global/**`), va CloudFormation stacks (`bootstrap/*.yaml`) doi chieu voi official AWS documentation, phat hien va sua cac loi: resource sai property, resource thua, thieu `lifecycle { prevent_destroy = true }` tren stateful resource, vi pham convention repo (English-only, tagging, naming), va bat nhat quan giua 2 env. Sau Sprint nay, toan bo IaC Terraform + CFN dat chuan truoc khi region migration bat dau.

## Definition of done

- `iac-reviewer` xac nhan khong con finding nao o muc BLOCKER hoac ERROR trong Terraform modules va CFN stacks.
- `terraform fmt -check -recursive` sach.
- `terraform validate` sach cho ca 2 env.
- `tflint --recursive` sach.
- `scripts/verify-envs-in-sync.sh` sach.
- Tat ca comment tieng Viet trong file `.tf` da duoc chuyen sang tieng Anh.
- `aws_db_instance` va `aws_secretsmanager_secret` trong `modules/rds/main.tf` co `lifecycle { prevent_destroy = true }`.
- `aws_s3_bucket.frontend` trong `modules/frontend-cdn/main.tf` co `lifecycle { prevent_destroy = true }`.
- `terraform-planner` chay sach va plan khop voi du kien cua iac-builder.

## Sub-tasks

- [x] S01-T01 - Research Terraform AWS provider docs cho cac resource trong scope audit
  - Assignee: iac-builder (su dung skill `research-iac-resource`)
  - Inputs / preconditions: Danh sach resource can research: `aws_db_instance`, `aws_secretsmanager_secret`, `aws_lb` / `aws_lb_listener` / `aws_lb_target_group`, `aws_ecs_task_definition` / `aws_ecs_service` / `aws_ecs_cluster_capacity_providers`, `aws_cloudfront_distribution` / `aws_cloudfront_origin_access_control`, `aws_ecr_repository` / `aws_ecr_lifecycle_policy`, `aws_s3_bucket` (+ sub-resources), `aws_eip` / `aws_nat_gateway`, `aws_cloudwatch_metric_alarm`, `aws_ssm_parameter`, `AWS::KMS::Key`, `AWS::S3::Bucket`, `AWS::IAM::Role` (CFN).
  - Outputs / artifacts: Research notes, danh sach property deprecated / wrong / missing cho tung resource.
  - Depends on: none
  - Notes: `cfn-resource-research` skill dung cho CFN resources trong `bootstrap/*.yaml`; `research-iac-resource` skill dung cho Terraform resources.

- [x] S01-T02 - Fix: them `lifecycle { prevent_destroy = true }` vao stateful resources
  - Assignee: iac-builder
  - Inputs / preconditions: S01-T01 hoan thanh. Files: `modules/rds/main.tf`, `modules/frontend-cdn/main.tf`.
  - Outputs / artifacts:
    - `modules/rds/main.tf`: them `lifecycle { prevent_destroy = true }` vao `aws_db_instance.this` va `aws_secretsmanager_secret.db`.
    - `modules/frontend-cdn/main.tf`: them `lifecycle { prevent_destroy = true }` vao `aws_s3_bucket.frontend`.
  - Depends on: S01-T01
  - Notes: Theo operating rule 11. Khong xoa `ignore_changes` hien co.

- [x] S01-T03 - Fix: chuyen comment tieng Viet trong modules sang tieng Anh
  - Assignee: iac-builder
  - Inputs / preconditions: none. Files bi anh huong:
    - `modules/frontend-cdn/outputs.tf` dang 1 ("cho aws s3 sync"), dong 7 ("cho aws cloudfront create-invalidation"), dong 15 ("vd: dxxxx.cloudfront.net").
    - Kiem tra them cac file `.tf` khac co comment tieng Viet khong.
  - Outputs / artifacts: Cac comment duoc viet lai bang tieng Anh, giu nguyen noi dung ky thuat.
  - Depends on: none (co the song song voi S01-T02)
  - Notes: Vi pham rule "English-only in every committed file" trong CLAUDE.md.

- [x] S01-T04 - Audit: kiem tra ALB listener logic khi chua co ACM cert
  - Assignee: iac-builder (su dung skill `research-iac-resource`)
  - Inputs / preconditions: S01-T01 hoan thanh. File: `modules/alb/main.tf`.
  - Outputs / artifacts: Xac nhan hoac sua logic: khi `existing_acm_cert_arn == null`, ALB chi co port 80 redirect den 443 nhung 443 chua co listener. Neu day la intentional (deploy truoc, gan cert sau), them comment giai thich. Neu la bug, sua bang cach them fallback listener hoac output canh bao.
  - Depends on: S01-T01
  - Notes: Hien tai `aws_lb_listener.https` la conditional (count = 0 khi khong co cert). `aws_lb_listener.http_redirect` luon redirect sang 443. Day co the la nguon goc loi 503 neu ALB duoc access truoc khi cert gan. Nen xem xet them `default_action.type = "fixed-response"` khi chua co cert.

- [x] S01-T05 - Audit: kiem tra ECR encryption type
  - Assignee: iac-builder (su dung skill `research-iac-resource`)
  - Inputs / preconditions: S01-T01 hoan thanh. File: `modules/ecr/main.tf`.
  - Outputs / artifacts: Xac nhan `encryption_type = "AES256"` la intentional (ECR-managed key, khong can KMS rieng) hay can doi sang KMS. Neu intentional, them comment giai thich.
  - Depends on: S01-T01

- [x] S01-T06 - Audit: kiem tra `image_tag = "latest"` trong ecs-service module
  - Assignee: iac-builder (su dung skill `research-iac-resource`)
  - Inputs / preconditions: S01-T01 hoan thanh. File: `modules/ecs-service/variables.tf` (dong 44-46), `modules/ecs-service/main.tf` (dong 51).
  - Outputs / artifacts: Xac nhan co the dung `latest` voi ECR IMMUTABLE (IMMUTABLE ngan overwrite tag nhung `latest` van la tag hop le). Them comment giai thich: ECR IMMUTABLE ngan overwrite, app pipeline se set tag cu the khi deploy. `lifecycle { ignore_changes = [container_definitions] }` da bao phu viec nay.
  - Depends on: S01-T01

- [x] S01-T07 - Audit: verify `observability` module co duoc wire vao env layer khong (da giai quyet - Q1)
  - Assignee: iac-builder
  - Inputs / preconditions: User da xac nhan: wire module vao `envs/_shared/main.tf`. Files: `envs/_shared/main.tf`, `envs/_shared/outputs.tf`, `modules/observability/`.
  - Outputs / artifacts: Xac nhan viec wire module trong S01-T07a duoc thuc hien dung. Sub-task nay la "audit step" - iac-builder co the bo qua neu S01-T07a da hoan thanh.
  - Depends on: none
  - Notes: User quyet dinh tai Q1: wire module vao `envs/_shared/main.tf`. Xem S01-T07a de biet chi tiet implementation.

- [x] S01-T07a - Wire module `observability` vao `envs/_shared/main.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: User da xac nhan wire module (Q1). Module nam o `modules/observability/`. Inputs can truyen:
    - `environment` = `var.environment` (co san trong _shared layer)
    - `ecs_cluster_name` = `module.ecs_cluster.cluster_name`
    - `ecs_service_name` = `module.ecs_service.service_name`
    - `rds_instance_id` = `module.rds.db_instance_id` (can verify output name trong `modules/rds/outputs.tf`)
    - `alb_arn_suffix` = `module.alb.alb_arn_suffix` (can verify output name trong `modules/alb/outputs.tf`)
    - `alarm_sns_topic_arn` = null (hoac bien `var.alarm_sns_topic_arn` neu muon expose len _shared layer)
    - `tags` = `local.common_tags`
  - Outputs / artifacts:
    - `envs/_shared/main.tf`: them block `module "observability"` sau `module "frontend_cdn"` va truoc het file.
    - `envs/_shared/outputs.tf` (tuy chon): neu can expose alarm ARNs de debugging, them 3 outputs: `observability_ecs_cpu_alarm_arn`, `observability_rds_connections_alarm_arn`, `observability_alb_5xx_alarm_arn`. Neu khong can expose, khong them (module van chay va tao alarms).
  - Depends on: S01-T01 (research module observability neu can), S01-T07
  - Notes: Day la ADD module moi, khong phai refactor resource da ton tai -> khong can `terraform-state-refactor`. Sau khi them, iac-builder phai verify output name cua `modules/rds` va `modules/alb` bang cach doc `modules/rds/outputs.tf` va `modules/alb/outputs.tf` truoc khi viet. `alarm_sns_topic_arn` nen duoc truyen qua variable moi trong `envs/_shared/variables.tf` (default = null) thay vi hardcode null, de user co the set gia tri sau.

- [x] S01-T08 - Audit: verify CloudFormation property correctness trong bootstrap stacks
  - Assignee: iac-builder (su dung skill `cfn-resource-research`)
  - Inputs / preconditions: S01-T01 hoan thanh. Files: `bootstrap/01-trust-anchor.yaml`, `bootstrap/02-tfstate-backend.yaml`, `bootstrap/03-github-oidc-roles.yaml`.
  - Outputs / artifacts:
    - Xac nhan `ThumbprintList` trong `AWS::IAM::OIDCProvider` (GitHub OIDC): 2 thumbprints hien co (`6938fd4d98bab03faadb97b34396831e3780aea1`, `1c58a3a8518e8759bf075b76b750d4f2df264fcd`) la up-to-date khong. AWS hien nay khong can thiet phai khai bao thumbprint cho GitHub OIDC (CA certificate validation), nhung gia tri sai se bi rejected.
    - Xac nhan `PendingWindowInDays: 30` trong `AWS::KMS::Key` la dung (range 7-30 theo AWS docs).
    - Xac nhan `NoncurrentVersionExpiration` trong S3 lifecycle co cau truc dung.
    - Kiem tra `GhaBackendDeployRole` va `GhaFrontendDeployRole` trong `03-github-oidc-roles.yaml` thieu `DeletionPolicy: Retain` va `UpdateReplacePolicy: Retain` (trong khi `GhaBootstrapRole` co).
    - Kiem tra xem `iam:PassRole` trong `GhaBackendDeployRole` co qua broad khong (`arn:aws:iam::*:role/3-tiers-app-*`).
  - Depends on: S01-T01

- [ ] S01-T09 - Review S01 (IaC Audit - Terraform + CFN)
  - Assignee: iac-reviewer
  - Inputs / preconditions: S01-T02, S01-T03, S01-T04, S01-T05, S01-T06, S01-T07a, S01-T08 hoan thanh.
  - Outputs / artifacts: Findings severity-tagged. Tick checkbox cho sub-tasks da xong. Reassign sub-tasks chua xong hoac bi hong ve iac-builder.
  - Depends on: S01-T02, S01-T03, S01-T04, S01-T05, S01-T06, S01-T07a, S01-T08

- [ ] S01-T10 - Terraform plan kiem tra sau audit
  - Assignee: terraform-planner
  - Inputs / preconditions: S01-T09 approved. `iac-reviewer` da tick het checkbox.
  - Outputs / artifacts: Plan output cho `envs/development` va `envs/production`. Xac nhan chi co change tuong ung voi cac fix trong S01-T02, S01-T04, S01-T07 (lifecycle rules, listener logic, observability wire-in neu applicable). Khong co unexpected replacement.
  - Depends on: S01-T09

## Review checklist

Reviewer se tick cac hop duoi day khi verify xong:

- [x] S01-T02: `prevent_destroy = true` da them vao dung resource trong `modules/rds/main.tf` va `modules/frontend-cdn/main.tf`
- [x] S01-T03: Khong con comment tieng Viet trong bat ky file `.tf` nao
- [x] S01-T04: ALB listener logic duoc giai thich ro hoac duoc sua
- [x] S01-T05: ECR encryption type duoc xac nhan hoac cap nhat
- [x] S01-T06: `image_tag` default duoc comment ro rang
- [x] S01-T07a: module `observability` duoc wire vao `envs/_shared/main.tf` voi dung inputs; variable `alarm_sns_topic_arn` duoc expose qua `envs/_shared/variables.tf`
- [x] S01-T08: CFN stacks khong con property sai; `DeletionPolicy`/`UpdateReplacePolicy` duoc kiem tra
- [x] `terraform fmt -check -recursive` sach
- [ ] `terraform validate` sach ca 2 env (khong chay duoc local: terraform 1.9.2 < repo pin 1.13.3)
- [ ] `tflint --recursive` sach (khong cai dat local)
- [x] `scripts/verify-envs-in-sync.sh` sach

## Review log

(Reviewer append findings vao day sau khi chay review)

### 2026-05-10 - iac-reviewer
- Verdict: approve with comments
- Sub-tasks ticked: S01-T01, S01-T02, S01-T03, S01-T04, S01-T05, S01-T06, S01-T07, S01-T07a, S01-T08
- Sub-tasks reassigned to iac-builder: none (cac finding MEDIUM/HIGH duoi day la nice-to-have, khong block)
- Sub-tasks reassigned to other agents:
  - F-01 (chinh sua `.github/workflows/terraform-apply.yaml`) -> github-action-builder: file workflow nay bi sua trong cung working tree nhung khong duoc liet ke trong hand-off cua iac-builder. Theo CLAUDE.md, iac-builder bi cam edit file `.github/`. Su sua doi (them job `sync-check`, them `concurrency`) la HOP LY ve mat noi dung va co the giu lai, nhung phai duoc github-action-builder/github-actions-reviewer xac nhan trong S02 thay vi di lam thang qua iac-builder. Day la vi pham scope, khong vi pham noi dung.
- Open questions raised:
  - Q1 (cho user): co muon them `prevent_destroy = true` cho `aws_eip.nat` (modules/network/main.tf:42) trong sprint sau khong? EIP la stateful (mat IP = mat allowlist ben thu ba). Hien khong nam trong scope S01.
  - Q2 (cho user): account IDs `111111111111`/`222222222222` trong `envs/*/backend.tf` va `README.md` la RFC dummy hay account that? Neu account that, vi pham CLAUDE.md "no hardcoded account IDs" - phai chuyen sang variable + tfvars khong commit. Neu chi la placeholder cho documentation, them comment ghi ro.
- Findings count: BLOCKER 0, HIGH 1, MEDIUM 4, LOW 2, NIT 0

Cross-cutting note tu S02 (account IDs `111111111111`/`222222222222`): da verify - khong anh huong toi `bootstrap/*.yaml`. Ca 3 file CFN bootstrap deu dung `${AWS::AccountId}` (CFN intrinsic) thay vi hardcode. Account IDs xuat hien tai `envs/development/backend.tf:5`, `envs/production/backend.tf:5`, `README.md:12`, `global/route53/README.md:18`, va comments trong `envs/*/terraform.tfvars`. Trong scope IaC reviewer, day la LOW-HIGH tuy vao quyet dinh cua user (xem Q2).

### 2026-05-10 - iac-reviewer (wave 2 follow-up - lifecycle comments)
- Verdict: approve
- Sub-tasks ticked: none (S01 sub-tasks da tick het tu wave 1; day la follow-up tren 3 finding MEDIUM cu trong review log)
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0
- Verification details:
  - `modules/rds/main.tf:38` - comment cho `aws_secretsmanager_secret.db` giai thich ro hau qua: "deleting this secret strands the RDS master credentials and breaks every running ECS task until the secret is rotated and re-injected." OK, dung trong tam.
  - `modules/rds/main.tf:92` - comment cho `aws_db_instance.this` giai thich ro: "this is the primary application database; recovery requires a snapshot restore and incurs full app downtime." OK, dung trong tam.
  - `modules/frontend-cdn/main.tf:9` - comment cho `aws_s3_bucket.frontend` giai thich ro: "the bucket name is account-scoped and serves as the CloudFront origin; recreating it breaks the distribution and requires a full re-upload of frontend artifacts." OK, dung trong tam.
  - 3 finding MEDIUM cu trong wave-1 review log lien quan den comment thieu tren `prevent_destroy` -> da resolve. Khong con MEDIUM finding nao tren chu de nay.
  - `terraform fmt -check -recursive` clean. `scripts/verify-envs-in-sync.sh` clean. `tflint --recursive` khong chay duoc local (binary chua cai), van la NOT_RUN giong wave 1.
  - Diff `modules/rds/main.tf` co alignment lai 3 line `performance_insights_enabled` / `deletion_protection` / `skip_final_snapshot` do `terraform fmt` reformat sau khi them dong dai `final_snapshot_identifier`. Day la behavior chinh xac cua `terraform fmt`, khong phai logic drift.

## Last updated

2026-05-10 by task-planner (update: them S01-T07a sau khi user tra loi Q1 - wire observability module)
