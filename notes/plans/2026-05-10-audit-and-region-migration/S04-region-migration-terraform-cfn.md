# Sprint S04 - Region Migration: Terraform, CloudFormation, README

## Goal

Doi toan bo reference `ap-southeast-1` thanh `us-east-1` trong cac file Terraform (`envs/`, `global/`, module README), CloudFormation (`bootstrap/`), va file README (ngoai tru `notes/` va `.claude/`). Day la Sprint phuc tap nhat ve mat logic vi phai xu ly constraint CloudFront/ACM, `backend.tf` region change, va ghi nhan canh bao. Chay sau S01 (Terraform audit xong) va song song voi hoac sau S03.

## Definition of done

- Khong con chuoi `ap-southeast-1` nao trong bat ky file Terraform, CFN, hoac README nao (ngoai tru `notes/` va `.claude/`).
- `envs/development/providers.tf` va `envs/production/providers.tf`: `provider "aws"` dung `var.region` (lay gia tri tu `terraform.tfvars`), khong hardcode. Provider alias `us_east_1` giu nguyen region `us-east-1` (CloudFront + ACM).
- `envs/development/terraform.tfvars` va `envs/production/terraform.tfvars`: `region = "us-east-1"`.
- `envs/development/backend.tf` va `envs/production/backend.tf`: `region = "us-east-1"` (CAUTION: viec nay chi an toan sau khi S05 - state migration - duoc thuc hien hoac xac nhan bucket da o us-east-1).
- Comment ACM cert ARN trong `.tfvars` duoc cap nhat tu `ap-southeast-1` sang `us-east-1`.
- `global/route53/README.md`: example backend.tf duoc cap nhat.
- `modules/frontend-cdn/README.md`: reference "ALB cert lives in `ap-southeast-1`" duoc sua thanh `us-east-1`.
- `scripts/verify-envs-in-sync.sh` sach.
- `terraform fmt -check -recursive` sach.
- `terraform validate` sach (luu y: validate chi kiem tra syntax, khong ket noi AWS).
- `tflint --recursive` sach.

## Luu y quan trong ve CloudFront + ACM constraint

- CloudFront va ACM certificate cho CloudFront **bat buoc o `us-east-1`**. Day la AWS hard constraint, khong the thay doi.
- `modules/frontend-cdn/main.tf`: KHONG co hardcode region nao cho CloudFront. `aws_cloudfront_distribution` la global resource, khong phu thuoc region cua provider. `aws_s3_bucket.frontend` dung default provider (region tu `var.region`).
- `providers.tf` trong ca 2 env da co alias provider `us_east_1` voi `region = "us-east-1"` cho ACM cert CloudFront - day la dung, giu nguyen.
- Comment trong `modules/frontend-cdn/README.md` noi "ALB cert lives in `ap-southeast-1`" can doi thanh "ALB cert lives in `us-east-1`" sau khi migrate.

## Luu y ve backend.tf

User da xac nhan (Q3): chua deploy AWS lan nao, khong co state file thuc te. Do do:
- Khong co state migration can thuc hien.
- S05 da duoc xoa khoi plan.
- Sub-task S04-T03 doi `backend.tf` region la AN TOAN thuc hien ngay trong S04, khong phu thuoc vao bat ky Sprint nao khac.
- Khi user lan dau deploy bootstrap.yaml (sau khi S04 hoan thanh), bucket tfstate se duoc tao o `us-east-1` tu dau.

## Danh sach thay doi cu the

| File | Dong | Hien tai | Sau khi sua |
|------|------|----------|-------------|
| `envs/development/terraform.tfvars` | 2 | `region = "ap-southeast-1"` | `region = "us-east-1"` |
| `envs/development/terraform.tfvars` | 28 | comment ACM `:ap-southeast-1:` | comment ACM `:us-east-1:` |
| `envs/production/terraform.tfvars` | 2 | `region = "ap-southeast-1"` | `region = "us-east-1"` |
| `envs/production/terraform.tfvars` | 24 | comment ACM `:ap-southeast-1:` | comment ACM `:us-east-1:` |
| `envs/development/backend.tf` | 7 | `region = "ap-southeast-1"` | `region = "us-east-1"` |
| `envs/production/backend.tf` | 7 | `region = "ap-southeast-1"` | `region = "us-east-1"` |
| `global/route53/README.md` | 20 | `region = "ap-southeast-1"` | `region = "us-east-1"` |
| `modules/frontend-cdn/README.md` | 16 | "ALB cert lives in `ap-southeast-1`" | "ALB cert lives in `us-east-1`" |

Tong: 8 vi tri trong 6 files.

## Sub-tasks

- [x] S04-T01 - Doi region trong terraform.tfvars (ca 2 env)
  - Assignee: iac-builder
  - Inputs / preconditions: S01-T10 (terraform-planner S01 xong). Files: `envs/development/terraform.tfvars`, `envs/production/terraform.tfvars`.
  - Outputs / artifacts: `region` doi thanh `us-east-1`, comment ACM cert ARN doi thanh `us-east-1` trong ca 2 file.
  - Depends on: S01-T09 (audit xong, file sach)
  - Notes: `terraform.tfvars` la file duoc phep khac nhau giua 2 env (theo convention). Nhung ca 2 env deu doi sang us-east-1 nen noi dung `region` se giong nhau (van hop le).

- [x] S04-T02 - Doi region trong README files (global/route53, modules/frontend-cdn)
  - Assignee: iac-builder
  - Inputs / preconditions: none. Files: `global/route53/README.md`, `modules/frontend-cdn/README.md`.
  - Outputs / artifacts: 2 file README duoc cap nhat. Comment trong `modules/frontend-cdn/README.md` doi tu "ALB cert lives in `ap-southeast-1`" thanh "ALB cert lives in `us-east-1`".
  - Depends on: none (co the chay song song voi S04-T01)
  - Notes: README files la doc, khong anh huong den terraform plan.

- [x] S04-T03 - Doi region trong backend.tf (ca 2 env)
  - Assignee: iac-builder
  - Inputs / preconditions: User da xac nhan chua deploy AWS lan nao (Q3) - khong co state migration can thuc hien. Files: `envs/development/backend.tf`, `envs/production/backend.tf`.
  - Outputs / artifacts: `envs/development/backend.tf` va `envs/production/backend.tf`: `region = "us-east-1"`. Khi user lan dau chay bootstrap.yaml, bucket tfstate se duoc tao moi tai `us-east-1`.
  - Depends on: S04-T01 (co the chay song song voi S04-T01 va S04-T02)
  - Notes: An toan de thuc hien ngay vi chua co state file thuc te. S05 da bi xoa vi khong con manual state migration steps.

- [x] S04-T04 - Review S04 Terraform + CFN + README region migration
  - Assignee: iac-reviewer
  - Inputs / preconditions: S04-T01, S04-T02, S04-T03 hoan thanh.
  - Outputs / artifacts: Xac nhan grep `ap-southeast-1` tren scope files (tru `notes/` va `.claude/`) tra ve rong. Tick checkboxes. Reassign neu can.
  - Depends on: S04-T01, S04-T02, S04-T03

- [ ] S04-T05 - Terraform plan sau khi doi region (development va production)
  - Assignee: terraform-planner
  - Inputs / preconditions: S04-T03 da merge (backend.tf da doi region). User chua deploy AWS nen plan se chay o local mode hoac voi mock backend. Luu y: `terraform init` se can bucket tfstate ton tai - neu bucket chua duoc deploy, dung flag `-backend=false` hoac comment backend block de chay validate/plan.
  - Outputs / artifacts: Plan output (hoac validate output neu backend chua ton tai). Xac nhan:
    - Network resources (VPC, subnet, NAT) se bi **CREATE** (moi hoan toan o us-east-1).
    - RDS, ECR, ECS, ALB se bi **CREATE** (region-specific resources, moi hoan toan).
    - CloudFront distribution se bi **CREATE** (global resource nhung chua tung deploy).
    - S3 frontend bucket se bi **CREATE**.
    - KMS key, Secrets Manager: se duoc **CREATE** moi.
    - Khong co **REPLACE** hay **DESTROY** vi khong co state file thuc te nao.
  - Depends on: S04-T03, S04-T04

## Review checklist

- [x] S04-T01: `region = "us-east-1"` trong ca 2 `terraform.tfvars`; comment ACM da cap nhat
- [x] S04-T02: 2 README da cap nhat, khong con `ap-southeast-1` trong markdown (tru `notes/` va `.claude/`)
- [x] S04-T03: `backend.tf` da doi region sang `us-east-1` o ca 2 env
- [x] Grep `ap-southeast-1` tren toan bo repo (tru `notes/` va `.claude/`) tra ve rong
- [x] `scripts/verify-envs-in-sync.sh` sach
- [x] `terraform fmt -check -recursive` sach

## Review log

(Reviewer append findings vao day sau khi chay review)

### 2026-05-10 - iac-reviewer (wave 2 - region migration)
- Verdict: approve
- Sub-tasks ticked: S04-T01, S04-T02, S04-T03, S04-T04
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none (S04-T05 van con cho terraform-planner, khong reassign tu day)
- Open questions raised:
  - Q1 (cho user): provider alias `aws.us_east_1` trong ca 2 `envs/*/providers.tf` hien khong duoc dung o bat ky resource nao (`grep aws.us_east_1` tra ve rong). Builder quyet dinh giu lam intent marker cho ACM/CloudFront tuong lai (da approve trong Sprint S04 DoD line 10). Reviewer dong y giu, vi neu sau nay default region doi sang region khac (vi du us-west-2), alias us-east-1 van can cho CloudFront cert. Hien tai alias redundant vi default cung la us-east-1 - co the gay nham lan cho dev khac. Goi y NIT (khong block): them comment phia tren block alias giai thich ro tai sao van giu khi default = us-east-1. Quyet dinh giu hay xoa thuoc ve user.
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 1
- Verification details:
  - Grep `ap-southeast-1` tren `modules/`, `envs/`, `global/`, `bootstrap/`: 0 hit. Acceptance gate pass.
  - `envs/development/terraform.tfvars:2` va `envs/production/terraform.tfvars:2`: `region = "us-east-1"` OK.
  - `envs/development/terraform.tfvars:28,29,35` va `envs/production/terraform.tfvars:24,25,31`: 3 comment ACM/SNS ARN da doi suffix region thanh `us-east-1`. Builder note: phat hien ngoai plan (alarm_sns_topic_arn comment) cung da sua, dung va can thiet cho acceptance gate.
  - `envs/development/backend.tf:7` va `envs/production/backend.tf:7`: `region = "us-east-1"` OK.
  - `global/route53/README.md:20`: example backend.tf da doi.
  - `modules/frontend-cdn/README.md:11,16`: 2 reference da doi sang `us-east-1`. Luu y line 16 hien doc: "do NOT share it with the ALB cert (ALB cert lives in `us-east-1`)". Sau khi migrate, ca CloudFront cert va ALB cert deu nam o us-east-1 - cau "do NOT share it" van dung (CloudFront cert va ALB cert la 2 cert rieng cho 2 dich vu khac nhau, dung shared se gay coupling), nhung ly do van con o region thi khong con dung sau migration. Day chi la NIT van phong, khong anh huong logic, khong block.
  - `envs/development/providers.tf` va `envs/production/providers.tf`: byte-identical. Default provider dung `var.region` (resolve thanh us-east-1). Alias `us_east_1` giu nguyen region hardcode `us-east-1` - dung theo Sprint S04 DoD.
  - `terraform fmt -check -recursive` clean (exit 0).
  - `scripts/verify-envs-in-sync.sh` clean ("OK: envs/development and envs/production are in sync.").
  - `terraform validate` per env: KHONG chay duoc local (terraform 1.9.2 < repo pin >= 1.11). Defer cho terraform-planner trong S04-T05.
  - `tflint --recursive`: KHONG chay duoc local (binary chua cai). Defer cho CI hoac terraform-planner.

## Last updated

2026-05-10 by task-planner (update: xoa dependency S05 cho S04-T03 sau khi user xac nhan chua deploy AWS; S04-T03 khong con CONDITIONAL)
