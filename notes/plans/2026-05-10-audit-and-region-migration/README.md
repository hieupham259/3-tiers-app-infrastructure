# Audit IaC + Region Migration (ap-southeast-1 -> us-east-1)

## Context

Nguoi dung yeu cau thuc hien dong thoi 2 track cong viec tren repo `3-tiers-app-infrastructure`:

- **Track 1 - Audit IaC**: Soat toan bo IaC (Terraform modules, CloudFormation bootstrap, GitHub Actions workflows) doi chieu voi official AWS docs de phat hien resource sai, resource thua, bat nhat quan giua 2 env, vi pham convention repo.
- **Track 2 - Region migration**: Doi toan bo reference `ap-southeast-1` thanh `us-east-1` tren tat ca file (Terraform, CFN, GitHub Actions, README) ngoai tru `notes/` va `.claude/`. Bao gom viec xu ly state backend migration va canh bao ve tai nguyen cu bi bo roi tai `ap-southeast-1`.

## Quyet dinh ve thu tu Sprint

Audit duoc chay **truoc** region migration (S01 -> S02 -> S03):

- Neu audit phat hien resource can xoa hoac sua, region migration se touch it file hon.
- Neu migrate truoc, iac-reviewer se phai audit lai lan 2 sau khi file thay doi.
- Thay doi region khong phu thuoc ket qua audit ve mat logic, nhung audit tren file goc sach hon giup reviewer de scope hon.
- Moi Sprint co the review doc lap, giam ri-ro merge conflict.

## Tong quan audit - nhung diem can kiem tra chinh

Sau khi doc het repo, cac diem nghi van chinh can audit:

**modules/rds/main.tf**
- `aws_db_instance` thieu `lifecycle { prevent_destroy = true }` (quy tac operating rule 11).
- `aws_secretsmanager_secret` thieu `lifecycle { prevent_destroy = true }`.
- Comment `# UTC = 23:00 ICT` trong `backup_window` - ICT la UTC+7, 16:00 UTC = 23:00 ICT la dung, nhung sau khi doi region sang us-east-1, comment nay het nghia (us-east-1 la UTC-5/-4).

**modules/alb/main.tf**
- `aws_lb_listener.http_redirect` mo port 80, nhung khong co `aws_lb_listener` fallback cho HTTPS khi `existing_acm_cert_arn == null`. Hien tai ALB chi co listener 80->redirect va listener 443 conditional. Khi chua co cert, ALB chi co 1 listener (port 80 redirect den 443 nhung 443 chua mo) - co the la intended design nhung can verify.
- `aws_lb` thieu `lifecycle { prevent_destroy = true }` (khong phai stateful resource theo operating rule 11, nhung `enable_deletion_protection = true` da duoc set - oke).

**modules/ecs-service/main.tf**
- `awslogs-region` dung `data.aws_region.current.name` (dong 68) - dong nay dung `data` source nhung `data "aws_region" "current" {}` khai bao o dong 89, sau khi dung. Terraform cho phep thu tu bat ky nhung nen khai bao truoc cho ro rang. Can verify.
- `image_tag = "latest"` default - day la anti-pattern cho production ECR IMMUTABLE.

**modules/frontend-cdn/outputs.tf**
- Comment tieng Viet trong file `.tf` ("cho aws s3 sync", "vd:", "vd:") - vi pham quy tac English-only trong repo files.

**modules/ecr/main.tf**
- `encryption_configuration { encryption_type = "AES256" }` - AES256 la ECR-managed key. AWS khuyen nghi dung KMS cho production. Can ghi nhan la intentional hay thieu.

**envs/_shared/main.tf**
- Module `observability` bi thieu trong `envs/_shared/main.tf` (module duoc dinh nghia trong `modules/observability/` nhung khong duoc goi trong shared stack). Co the la intentional (chua wire) nhung can ghi nhan.

**bootstrap/02-tfstate-backend.yaml**
- Ten bucket `${BucketNamePrefix}-${AWS::AccountId}` khong co suffix region. Theo yeu cau, day la diem tot - bucket name khong lien quan den region. Nhung `backend.tf` cua ca 2 env deu co `region = "ap-southeast-1"` point den bucket nay - doi region trong `backend.tf` se doi endpoint S3 ma khong can doi ten bucket. Can luu y dieu nay trong plan.

**GitHub Actions workflows**
- `terraform-plan.yaml` va `terraform-apply.yaml`: `aws-region: ap-southeast-1` hardcoded, can doi thanh `us-east-1`.
- `terraform-drift.yaml`: tuong tu.
- `cfn-drift-detect.yaml`: tuong tu.
- `bootstrap.yaml`: `AWS_REGION: ap-southeast-1` hardcoded, can doi.
- `terraform-plan.yaml` va `terraform-apply.yaml` dung `terraform_version: 1.13.3` - day la version moi (Terraform 1.13.x chua release tinh den thoi diem viet plan nay). Can verify version co ton tai khong.

## Danh sach 20 file co reference ap-southeast-1

Grep ket qua cho thay reference `ap-southeast-1` trong cac file sau (bo qua `.claude/agents/` vi do la file cau hinh agent, khong phai IaC):

| STT | File | Dong | Loai |
|-----|------|------|------|
| 1 | `envs/development/backend.tf` | 7 | `region = "ap-southeast-1"` |
| 2 | `envs/production/backend.tf` | 7 | `region = "ap-southeast-1"` |
| 3 | `envs/development/terraform.tfvars` | 2 | `region = "ap-southeast-1"` |
| 4 | `envs/development/terraform.tfvars` | 28 | Comment ACM cert ARN |
| 5 | `envs/production/terraform.tfvars` | 2 | `region = "ap-southeast-1"` |
| 6 | `envs/production/terraform.tfvars` | 24 | Comment ACM cert ARN |
| 7 | `.github/workflows/bootstrap.yaml` | 21 | `AWS_REGION: ap-southeast-1` |
| 8 | `.github/workflows/terraform-plan.yaml` | 47 | `aws-region: ap-southeast-1` |
| 9 | `.github/workflows/terraform-apply.yaml` | 35 | `aws-region: ap-southeast-1` |
| 10 | `.github/workflows/terraform-drift.yaml` | 36 | `aws-region: ap-southeast-1` |
| 11 | `.github/workflows/cfn-drift-detect.yaml` | 25 | `aws-region: ap-southeast-1` |
| 12 | `global/route53/README.md` | 20 | Example backend.tf trong markdown |
| 13 | `modules/frontend-cdn/README.md` | 16 | Reference ALB cert region trong markdown |

Tong: **13 vi tri** trong 11 file IaC/workflow + 2 file README. Hai file README duoc iac-builder cap nhat cung voi IaC. Khong co file nao trong `notes/` hoac `.claude/` can thay doi (`.claude/agents/terraform-state-refactor.md` co example hardcode `ap-southeast-1a` la AZ name trong vi du minh hoa, khong phai config thuc - giu nguyen).

## Sprints

| ID | Tieu de | Trang thai | Nguoi cap nhat cuoi |
|----|---------|-----------|---------------------|
| S01 | IaC Audit - Terraform modules va CloudFormation | planned | task-planner |
| S02 | IaC Audit - GitHub Actions workflows | planned | task-planner |
| S03 | Region migration - GitHub Actions workflows | planned | task-planner |
| S04 | Region migration - Terraform + CFN + README | planned | task-planner |
| S05 | Migrate account IDs sang GitHub Actions Variables | planned | task-planner |
| S06 | Add check-state-preservation composite action | planned | task-planner |

Sprint cu bi xoa: S05 (State backend migration) da bi xoa truoc do: user xac nhan chua deploy AWS lan nao, khong co state file thuc te can migrate. Backend.tf region change duoc merge vao S04-T03.

### Thu tu thuc hien va dependency giua Sprints

```
S01 -----> S04 (T01 depends on S01-T09)
S02 -----> S03 (T01 depends on S02-T04)
           S03 + S04 -----> S05 (S05 phai chay SAU ca S03 va S04 vi S05 cham vao
                                 cac workflow files ma S03 da sua; tranh merge conflict)
           S05 -----> S06-T02 (terraform-plan.yaml)
           S05 -----> S06-T03 (terraform-apply.yaml)
S06-T01 --+
```

S05 va S06 co the bat dau sau khi S04-T04 (iac-reviewer approve S04) va S03-T02 (github-actions-reviewer approve S03) hoan thanh. S06-T01 (tao composite action, file moi, khong conflict) co the chay song song voi S05.

## Open questions

- Q1: `observability` module khong duoc wire vao `envs/_shared/main.tf`. Co phai intentional hay la bug?
  -> DA GIAI QUYET: User chon wire module vao `envs/_shared/main.tf`. Sub-task S01-T07a da duoc them vao S01.

- Q2: `terraform_version: 1.13.3` trong workflows - version nay co the chua ton tai. User muon giu nguyen hay doi ve version cu the?
  -> VAN LA OPEN QUESTION: Chuyen sang S02 de `github-action-builder` verify khi xu ly sub-task S02-T01. Sub-task S02-T01 da ghi nhan diem nay.

- Q3: State backend S3 bucket da duoc deploy chua? O region nao?
  -> DA GIAI QUYET: User xac nhan chua deploy AWS lan nao, khong co state file thuc te. Khong can state migration. S05 (state migration) da bi xoa. S04-T03 (doi backend.tf) khong con conditional.

- Q4: User co muon them Sprint de destroy tai nguyen cu o `ap-southeast-1` khong?
  -> DA GIAI QUYET: Khong co tai nguyen nao o `ap-southeast-1` (chua tung deploy). Khong can Sprint destroy.

- Q5: [HIGH - S02 reviewer] Account IDs `'111111111111'`/`'222222222222'` hardcode trong 5 workflow files. Vi pham CLAUDE.md "Secrets and sensitive data".
  -> DA GIAI QUYET: User approve them Sprint S05 de migrate sang `vars.DEV_ACCOUNT_ID`/`vars.PROD_ACCOUNT_ID` (GitHub Actions Repository Variables).

- Q6: [HIGH - S02 reviewer] Composite action `.github/actions/check-state-preservation/` chua ton tai. Rule #11 trong iac-builder agent yeu cau gate nay de ngan destroy stateful resource.
  -> DA GIAI QUYET: User approve them Sprint S06 de tao composite action va wire vao `terraform-plan.yaml` va `terraform-apply.yaml`.

## Out-of-scope

- Khong tao ACM certs moi o `us-east-1` (day la manual step hoac thuoc repo khac).
- Khong tao lai S3 tfstate bucket moi (do la bootstrap step - xem S05).
- Khong thay doi `bootstrap/01-trust-anchor.yaml` (OIDC provider la global IAM resource, khong phu thuoc region).
- Khong thay doi `.claude/agents/` du co reference `ap-southeast-1a` trong vi du minh hoa.

## Risks

- S05 da bi xoa: user xac nhan chua deploy AWS lan nao nen khong co ri-ro mat state file, khong co tai nguyen bi bo roi o `ap-southeast-1`.
- Ri-ro con lai duy nhat ve region: comment `# UTC = 23:00 ICT` trong `modules/rds/main.tf` se het nghia sau khi doi sang `us-east-1` (us-east-1 la UTC-5/-4, ICT la UTC+7). Sub-task S01-T02/S01-T03 se xu ly khi iac-builder doc module.

## Last updated

2026-05-10 by task-planner (update: them S05 migrate account IDs va S06 check-state-preservation; ghi nhan 2 finding HIGH tu reviewer S02 da duoc user approve; them dependency graph S05/S06; update open questions Q5/Q6)
