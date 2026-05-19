# Initial Deploy Rollout (development -> production)

## Context

Sau khi hoan tat bootstrap (CFN stacks `tfstate-backend` + `github-oidc-roles`) va don dep cac placeholder `myorg`, repo da san sang trien khai toan bo ha tang Terraform cho ung dung 3-tier len AWS.

Chu repo: **hieupham259**.
AWS account dung chung cho ca dev va prod: **405226342924**.
Region: **us-east-1**.
Branch model: `master` (default, khong deploy), `development` (deploy dev), `production` (deploy prod). Promotion qua merge git, khong qua Terraform workspace.

File nay la runbook tracking. Agent va nguoi dung tick checkbox khi step hoan thanh. Step nao bi block thi append note vao muc "Block / open issues" o cuoi file.

## Phase A - GitHub repository setup (DONE)

- [x] **A.1** - Set GitHub Actions Repository Variables. `DEV_ACCOUNT_ID=405226342924`, `PROD_ACCOUNT_ID=405226342924`. Settings -> Secrets and variables -> Actions -> Variables tab. (User tu set.)
- [x] **A.2** - Tao GitHub Environments `development` va `production` voi Required reviewers = `hieupham259`, Deployment branches phai trung ten environment. (User tu setup, xac nhan qua screenshot.)
- [x] **A.3** - Hardening cho public repo: Settings -> Actions -> General -> "Fork pull request workflows from outside collaborators" = "Require approval for all outside collaborators". Workflow permissions = read-only default. (User tu setup.)
- [x] **A.4** - Tao 2 long-lived branches `development` va `production` tu `master`, push len origin. (User tu setup.)

## Phase B - First deploy to development (DONE - replaced by phased rollout)

Muc tieu: dua toan bo ha tang dev len AWS account 405226342924, verify resources hoat dong, before chuyen prod.

**Cap nhat 2026-05-19**: Toan bo viec "first deploy to development" KHONG duoc thuc hien bang mot lan deploy lon nhu plan ban dau. Thay vao do, no duoc tach thanh plan rieng `notes/plans/2026-05-15-phased-deploy-development/` voi 4 Sprint (S01 networking, S02 ECR/ALB/ECS-cluster, S03 RDS/IAM, S04 ECS service/CDN/observability) va kien truc cost-optimized (2 AZ, khong NAT/EIP, ECS Fargate trong public subnet). Plan phased-deploy da dong toan bo vao 2026-05-19. Cac checkbox duoi tick theo ket qua thuc te cua plan phased-deploy.

- [x] **B.1** - Review `envs/development/terraform.tfvars`. Xac nhan `vpc_cidr = "10.10.0.0/16"` (khong trung VPC nao da co trong account), cac block `domain_name`, `alarm_sns_topic_arn` van comment-out cho lan deploy dau. Acceptance: file khong co reference toi resource chua ton tai (cert ARN, hosted zone ID, SNS topic). **(Done qua S01-T01 cua plan phased-deploy)**
- [x] **B.2** - Tu `master` checkout `development`, pull latest. Tao feature branch tu `development` (vd `feature/initial-deploy`). **(Done - moi Sprint phased-deploy dung mot feature branch rieng tu `development`)**
- [x] **B.3** - Edit nhe `envs/development/terraform.tfvars` (vi du them comment hoac sua 1 tag) de tao diff trong `envs/**` -> dieu kien trigger `terraform-plan.yaml` tren PR. Commit va push feature branch len origin. **(Done - cac PR phased-deploy uncomment dan module call trong `envs/_shared/main.tf`)**
- [x] **B.4** - Mo PR base=`development`, head=`feature/initial-deploy`. Doi workflow `Terraform Plan` chay. Acceptance: `sync-check` job pass, `plan` job comment plan output len PR khong co error. **(Done qua nhieu PR cua phased-deploy: S01, S02a/b/c, S02d, S03, S04 - PR #28 la PR cuoi cung)**
- [x] **B.5** - Review plan tren PR. Xac nhan: chi co `create` actions, khong co `replace` hoac `destroy`, tong so resource khoang 30-50 (VPC + subnets + RDS + ECS + ALB + ECR + CloudFront + IAM + CloudWatch). Action `check-state-preservation` khong block. **(Done qua terraform-planner cho moi Sprint phased-deploy)**
- [x] **B.6** - Merge PR vao `development`. Push tu phia GitHub UI (Squash hoac Rebase tuy preference - khong ep buoc). **(Done - PR cuoi cung #28 merged 2026-05-19 17:23 +0700, commit `46eea80`)**
- [x] **B.7** - Push toi `development` se trigger `terraform-apply.yaml`. Vao Actions tab, click run -> click "Review deployments" -> tick `development` -> Approve. Job `apply` chay `terraform apply tfplan`. Acceptance: job ket thuc `Success`, log ket thuc bang `Apply complete!`. **(Done - `terraform-apply.yaml` PASS cho ca 4 Sprint)**
- [x] **B.8** - Verify resources tren AWS Console:
  - VPC `development-vpc` (10.10.0.0/16) va **4 subnet (2 public + 2 private)** - cost-optimized 2-AZ, khac voi plan ban dau (6 subnet). Xem `notes/plans/2026-05-15-phased-deploy-development/README.md` section "Quyet dinh kien truc cost-optimization".
  - RDS instance `development-rds-app` (status `available`, single-AZ, db.t4g.small) - **deployed qua S03 (plan rieng `2026-05-18-fix-secret-version-refresh-bomb`)**
  - ECS cluster `development-ecs-app`, service - **deployed qua S02c (cluster) + S04 (service); task running phu thuoc image trong ECR (xem D.3)**
  - ALB `development-alb-app` co DNS name - **deployed qua S02b**
  - ECR repo `development-ecr-app` - **deployed qua S02a**
  - CloudFront distribution status `Deployed` - **deployed qua S04**
  - CloudWatch log group cho ECS task - **deployed qua S04 (observability)**
- [ ] **B.9** - Note ket qua deploy vao file moi `notes/deploys/2026-05-12-dev-initial.md` (timestamp, ALB DNS, CloudFront domain, bat ky resource ID quan trong nao). **(CHUA TAO - ket qua deploy dang nam trong "Last updated" log cua `notes/plans/2026-05-15-phased-deploy-development/README.md`. Neu can file deploy log rieng theo dung format ban dau thi can tao bo sung.)**

## Phase C - Promote to production

Chi bat dau khi Phase B 100% done va dev chay on dinh it nhat 1 ngay (de catch drift hoac config sai som).

**Status 2026-05-19**: CHUA THUC HIEN. Theo phased-deploy README, sau khi moi Sprint dev hoan tat thi cho replicate sang `production` qua PR base=`production`. Hien tai feature branch `feature/phased-deploy-s04-full-stack` da co tat ca diff nhung chua mo PR vao `production`.

- [ ] **C.1** - Review `envs/production/terraform.tfvars`. Quyet dinh nhung gia tri can khac dev (vi du `vpc_cidr = "10.20.0.0/16"` de tach network, `rds_multi_az = true`, `rds_backup_retention_days = 30`, `rds_deletion_protection = true`, `ecs_desired_count >= 2`, `rds_instance_class` cao hon). LUU Y: dev va prod dung chung AWS account 405226342924 nen 2 set resource SE cung ton tai trong account; tach CIDR de tranh route conflict.
- [ ] **C.2** - Tao feature branch tu `production` (vd `feature/promote-to-prod`). Sync `envs/production/` voi cac thay doi can co (chi tfvars - cac file khac phai byte-identical voi dev theo `scripts/verify-envs-in-sync.sh`).
- [ ] **C.3** - Mo PR base=`production`, head=`feature/promote-to-prod`. Workflow `Terraform Plan` chay voi `ENV_DIR=production`. Review plan ky luong. Acceptance: chi `create` actions, so resource tuong tu dev.
- [ ] **C.4** - Merge PR vao `production`. Trigger `terraform-apply.yaml` voi `environment: production`.
- [ ] **C.5** - Approve deployment cho prod. Doi apply hoan tat (15-25 phut chu yeu RDS + CloudFront).
- [ ] **C.6** - Verify prod resources tren AWS Console (tuong tu B.8 nhung prefix `production-*`).
- [ ] **C.7** - Note ket qua deploy vao `notes/deploys/2026-05-12-prod-initial.md`.

## Phase D - Post-deploy operations

Sau khi dev va prod chay, bat cac job operational.

**Status 2026-05-19**: Tat ca D.1-D.6 CHUA xac nhan thuc hien. File workflow cho D.1 da ton tai san trong repo nhung chua co bang chung manual-trigger / cron run. D.4 (Route53) da xac nhan chua deploy - stack `global/route53/` con thieu `backend.tf` va chua co workflow apply.

- [ ] **D.1** - Verify drift detection workflows. `terraform-drift.yaml` va `cfn-drift-detect.yaml` da co - check trigger schedule (cron) co dung khong, manual trigger thu de xac nhan workflow chay duoc. **(File workflow da ton tai: `.github/workflows/terraform-drift.yaml`, `.github/workflows/cfn-drift-detect.yaml`. Chua xac nhan chay thuc te.)**
- [ ] **D.2** - Wire SNS topic cho ECS/RDS/ALB alarm. Tao topic `ops-alerts` trong account, set var `alarm_sns_topic_arn` trong `envs/<env>/terraform.tfvars`, re-deploy. **(`alarm_sns_topic_arn` van comment-out trong `envs/development/terraform.tfvars`.)**
- [ ] **D.3** - Build va push container image dau tien vao ECR `development-ecr-app` (frontend va backend repo). ECS service se tu pull va run task khi co image hop le.
- [ ] **D.4** - Quyet dinh ve domain. Neu dung Route53 + ACM, hoan thanh stack `global/route53/` (tao backend.tf rieng - co note trong `global/route53/README.md`), apply, lay nameservers, dang ky tai registrar. Sau do uncomment `domain_name`, `alb_acm_cert_arn`, `frontend_cf_cert_arn`, `hosted_zone_id` trong tfvars va re-deploy. **(Verified 2026-05-19: `global/route53/backend.tf` chua tao, chua co workflow apply cho `global/route53/`, `domain_name`/`alb_acm_cert_arn`/`frontend_cf_cert_arn`/`hosted_zone_id` van comment-out trong tfvars. Module CHUA deploy o bat ky Sprint nao.)**
- [ ] **D.5** - Security audit lai cho public repo: scan `gha-infra-plan` role trust policy, scan workflow trigger conditions, check IAM policy attached cho `gha-infra-apply` co exceeded scope khong. Dispatch `iac-reviewer` + `github-actions-reviewer` lam audit pass.
- [ ] **D.6** - Decide ve "Allow administrators to bypass configured protection rules" tren GitHub Environment `production`. Voi prod, nen tat option nay de admin (chinh user) khong the override approval gate.

## Block / open issues

Append issue moi vao day theo format:

```
- YYYY-MM-DD: <issue summary>
  - Detected by: <agent name or user>
  - Affected step: <step ID e.g. B.7>
  - Resolution: <pending | <commit-sha> | <link to PR>>
```

(Trong nay khi step bi fail, tag agent phu trach moi xu ly chi tiet vao file Sprint hoac chat reply.)

## Notes for agents reading this file

- File nay la single source of truth ve progress trien khai. Truoc khi tu y dispatch builder, doc lai phase hien tai, xac nhan step truoc da `[x]`, va check muc "Block / open issues" xem co block nao chua.
- Khong tu y tick checkbox neu chua thuc su verify acceptance criteria cua step do.
- Cac thay doi IaC code can thiet de unblock step (vi du sua `terraform.tfvars`, them resource moi) van phai qua agent team theo CLAUDE.md - khong edit truc tiep tu main thread.
- File nay nam trong `notes/` nen co the viet tieng Viet, khong dung emoji va decorative Unicode.

## References

- Bootstrap workflow: [.github/workflows/bootstrap.yaml](../../../.github/workflows/bootstrap.yaml)
- Plan workflow: [.github/workflows/terraform-plan.yaml](../../../.github/workflows/terraform-plan.yaml)
- Apply workflow: [.github/workflows/terraform-apply.yaml](../../../.github/workflows/terraform-apply.yaml)
- Dev tfvars: [envs/development/terraform.tfvars](../../../envs/development/terraform.tfvars)
- Prod tfvars: [envs/production/terraform.tfvars](../../../envs/production/terraform.tfvars)
- Backend dev: [envs/development/backend.tf](../../../envs/development/backend.tf)
- Backend prod: [envs/production/backend.tf](../../../envs/production/backend.tf)
- Repo conventions: [CLAUDE.md](../../../CLAUDE.md)
