# Sprint S02 - Un-comment per module (ECR -> ALB -> ECS cluster)

## Goal

Deploy tung module mot trong nhom 3 module "first wave" (ECR repo, ALB, ECS cluster). Moi module mot PR doc lap. Sau khi 3 sub-sprint hoan tat, `envs/_shared/main.tf` se co them 3 module active (ngoai module "network" tu S01) va `envs/_shared/outputs.tf` co 6 block companion (3 SSM parameter + 3 output) un-comment. Cac module `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability` van comment - cho S03/S04.

## CAP NHAT 2026-05-16: scope split per-module

Sprint S02 ban dau planned deploy 3 module trong cung 1 PR (~14 resource). User quyet dinh chia nho thanh 3 sub-sprint doc lap de:

- Verify tung module truoc khi qua module tiep theo (de pinpoint failure).
- Rollback don gian neu can (chi revert 1 module thay vi 3).
- Re-use cung pattern voi cac Sprint sau (S03 RDS, S04 ECS service / CDN / observability cung se split).

| Sub-sprint     | Module + companion blocks                                                                                    | Resource du kien                                                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| **S02a** | `module "ecr_backend"` + `aws_ssm_parameter "ecr_backend_url"` (+ `output "ecr_backend_url"` tuy chon) | 3 (ECR repo + lifecycle policy + SSM param)                                                                        |
| **S02b** | `module "alb"` + `aws_ssm_parameter "alb_dns_name"` + `output "alb_dns_name"`                          | 8 (LB + TG + 1 listener + SG + 3 SG rules + SSM param) - giam con 7 neu khong co ACM cert (HTTPS listener count=0) |
| **S02c** | `module "ecs_cluster"` + `aws_ssm_parameter "ecs_cluster_name"` + `output "ecs_cluster_name"`          | 3 (ECS cluster + cluster_capacity_providers + SSM param)                                                           |

Moi sub-sprint chay full cycle: iac-builder -> iac-reviewer -> terraform-planner -> user deploy len development -> verify -> (optional) replicate sang production.

## CAP NHAT 2026-05-16: bo marker `# PHASED-DEPLOY S01` trong _shared/main.tf

Toan bo 7 dong marker `# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04` da bi xoa khoi `envs/_shared/main.tf` (cac module van comment: `alb`, `ecs_cluster`, `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability`). Quyet dinh INTENTIONAL boi user.

Tradeoff:

- **Mat**: kha nang `grep '# PHASED-DEPLOY'` de quet nhanh cac module con pending o S03/S04.
- **Duoc**: file `_shared/main.tf` gon hon, doc that hon (chi nhin block comment thay vi co them marker meta).

Thay the cho tracking signal: Sprint plan files duoi `notes/plans/2026-05-15-phased-deploy-development/` la nguon su that chinh thuc cho biet module nao thuoc Sprint nao. iac-reviewer khi review S02b/S02c/S03/S04 KHONG can raise finding ve viec thieu marker.

## CAP NHAT 2026-05-16: discovery layer chinh thuc la SSM, KHONG dung `terraform output`

Reviewer S02a raise NIT-2 ve viec `envs/development/outputs.tf` khong ton tai nen `output "ecr_backend_url"` trong `envs/_shared/outputs.tf` khong noi len duoc `terraform output` o root. **NIT nay duoc DISMISS** voi rationale sau:

- S01 deploy `module "network"` thanh cong ma `_shared/outputs.tf` KHONG co `output "vpc_id"` / `output "private_subnet_ids"` / `output "public_subnet_ids"` - tuc la repo nay intentional khong dung `terraform output` o BAT KY cap nao tu dau.
- Design philosophy cua repo: discovery layer duy nhat la **SSM Parameter Store** voi path `/3-tiers-app/<env>/<service>/<attr>`. Cross-repo / cross-pipeline (app CI/CD) doc URL/endpoint qua SSM, khong qua `terraform output`.
- Ly do SSM tot hon `terraform output`: IAM permission control, audit trail, versioning, khong can Terraform CLI o consumer side, tranh accidental commit secrets.
- Neu fix NIT-2 (tao `envs/development/outputs.tf` + `envs/production/outputs.tf` cho ECR) se tao **inconsistency te hon**: ECR co root output nhung network khong; cac Sprint sau (S02b/S02c/S03/S04) phai nho tao theo - pha vo single-source-of-truth.

**Quy tac cho cac Sprint tiep theo**: KHONG can tao `envs/<env>/outputs.tf`. KHONG raise finding ve viec output `_shared` khong noi len root. Discovery di qua SSM la design intent.

## CAP NHAT 2026-05-16: pattern repo_name

User yeu cau dat ten ECR repo theo pattern `<base>-<environment>` thay vi literal co dinh. Khi un-comment `module "ecr_backend"`, gia tri phai la:

```hcl
repo_name = "3-tiers-app-backend-${var.environment}"
```

Khong duoc giu lai `"3-tiers-app-backend"` cu. Ket qua resource tren AWS: ECR repo ten `3-tiers-app-backend-development` (development) va `3-tiers-app-backend-production` (production). Luu y: pattern nay dung POSTFIX environment thay vi PREFIX nhu convention chung `${env}-<resource>-<role>` cua repo (vi du `development-alb`, `development-3-tiers-app`). User da chap nhan deviation nay; ghi nhan de iac-reviewer khong raise finding ve naming convention.

## Pham vi un-comment (tong hop)

### `envs/_shared/main.tf` - cac block tro thanh active

- S02a: `module "ecr_backend"` (dong 21-26 sau khi un-comment)
- S02b: `module "alb"` (dong 29-37 hien tai - van comment)
- S02c: `module "ecs_cluster"` (dong 40-44 hien tai - van comment)

### `envs/_shared/main.tf` - giu comment cho cac Sprint sau

- `module "rds"` (S03)
- `module "iam_app_roles"` (S03)
- `module "ecs_service"` (S04)
- `module "frontend_cdn"` (S04)
- `module "observability"` (S04)

### `envs/_shared/outputs.tf` - cac block companion

| Block                                    | Sub-sprint                             | Dong (file hien tai) |
| ---------------------------------------- | -------------------------------------- | -------------------- |
| `aws_ssm_parameter "ecr_backend_url"`  | S02a                                   | 22-26                |
| `output "ecr_backend_url"`             | S02a (optional - root khong re-export) | 73-76                |
| `aws_ssm_parameter "alb_dns_name"`     | S02b                                   | 40-44                |
| `output "alb_dns_name"`                | S02b                                   | 52-55                |
| `aws_ssm_parameter "ecs_cluster_name"` | S02c                                   | 4-8                  |
| `output "ecs_cluster_name"`            | S02c                                   | 47-50                |

### `envs/_shared/outputs.tf` - giu comment

- `aws_ssm_parameter.ecs_service_name`, `aws_ssm_parameter.ecs_task_definition_family` (S04 - ecs_service)
- `aws_ssm_parameter.frontend_bucket`, `aws_ssm_parameter.cloudfront_distribution_id` (S04 - frontend_cdn)
- `output "frontend_bucket"`, `output "cloudfront_distribution_id"` (S04)
- `output "rds_endpoint"` (S03)
- 3 `output "observability_*"` (S04)

## Definition of done (toan Sprint S02)

S02 considered done khi ca 3 sub-sprint S02a + S02b + S02c deploy len development thanh cong va ECR + ALB + ECS cluster ton tai tren AWS Console. Moi sub-sprint co Definition of done rieng - xem tung muc duoi.

---

## Sub-sprint S02a - ECR repo (+ SSM publish URL)

### Definition of done S02a

- `terraform fmt -check -recursive` pass.
- `terraform validate` trong `envs/development/` pass.
- `terraform plan`: 3 to add (`aws_ecr_repository`, `aws_ecr_lifecycle_policy`, `aws_ssm_parameter.ecr_backend_url`), 0 change, 0 destroy.
- Apply tren development thanh cong.
- AWS Console: ECR repo `3-tiers-app-backend-development` ton tai; SSM parameter `/3-tiers-app/development/ecr/backend_url` co value la repo URL.

### Sub-tasks S02a

- [X] S02a-T01 - Un-comment `module "ecr_backend"` + `aws_ssm_parameter "ecr_backend_url"` + `output "ecr_backend_url"`

  - Assignee: user (da thuc hien truc tiep tren branch `feature/phased-deploy-s02-ecr-alb-ecs`)
  - Done items:
    - `envs/_shared/main.tf` dong 21-26: `module "ecr_backend"` active, `repo_name = "3-tiers-app-backend-${var.environment}"`
    - `envs/_shared/outputs.tf` (~dong 19-23): `aws_ssm_parameter "ecr_backend_url"` active
    - `envs/_shared/outputs.tf` (~dong 71-74): `output "ecr_backend_url"` active
    - `envs/_shared/outputs.tf` dong 1: xoa header stale "# PHASED-DEPLOY S01: all outputs commented out..."
    - `envs/_shared/main.tf`: clean 8 vi tri double-blank-line (cosmetic, fmt-check da pass tu truoc)
  - Notes: Block `module "ecr_backend"` da co `repo_name` postfix-by-env theo quyet dinh CAP NHAT 2026-05-16. Output `output "ecr_backend_url"` van chua noi len `terraform output` vi `envs/development/outputs.tf` khong ton tai (gap kien truc tu S01) - khong block, chap nhan.
- [X] S02a-T02 - Review diff S02a

  - Assignee: iac-reviewer
  - Inputs: diff cua S02a-T01 vs `development`
  - Outputs: tick S02a-T01 neu OK; reassign neu phat hien BLOCKER
  - Notes: Kiem tra (1) khong co resource networking S01 bi thay doi; (2) SSM parameter path hop le; (3) `terraform validate` pass; (4) khong raise finding ve repo_name pattern postfix (da co exception).
- [X] S02a-T03 - terraform plan xac nhan 3 to add

  - Assignee: terraform-planner (verify boi main thread tu output plan do user cung cap 2026-05-16)
  - Outputs: bao cao plan chi tiet, xac nhan +3 / 0 change / 0 destroy
  - MOI TRUONG CHAY: chay tren CI runner khi mo PR (Terraform 1.13.3), khong chay duoc o local v1.9.2
  - Ket qua plan (2026-05-16):
    - +1 `module.stack.module.ecr_backend.aws_ecr_repository.this[0]` ten `3-tiers-app-backend-development`, IMMUTABLE, AES256, scan_on_push=true, 6 tag
    - +1 `module.stack.module.ecr_backend.aws_ecr_lifecycle_policy.this[0]` voi 2 rule (keep 30 tagged + expire untagged 7d)
    - +1 `module.stack.aws_ssm_parameter.ecr_backend_url` path `/3-tiers-app/development/ecr/backend_url`, type String, value (sensitive - provider default cho aws_ssm_parameter)
    - 12 resource networking S01 chi "Refreshing state" (read-only, khong bi modify)
    - **Total: 3 to add, 0 change, 0 destroy** - khop hoan toan expected
  - Ghi nhan minor inconsistency: SSM parameter khong duoc gan `tags = local.common_tags` (chi co 3 tag inherit tu provider default_tags, ECR repo co 6 tag). Khong block; defer cho Sprint cleanup neu can dong nhat tag policy.
- [X] S02a-T04 - Deploy S02a len branch development

  - Assignee: user
  - Inputs: S02a-T03 plan an toan
  - Outputs: ECR repo + SSM parameter ton tai tren development account (xac nhan boi user 2026-05-16)
  - Quy trinh da thuc hien:
    1. Push branch `feature/phased-deploy-s02-ecr-alb-ecs`, mo PR base=`development`.
    2. Doi `terraform-plan.yaml` chay; verify plan comment tren PR la +3.
    3. Merge PR vao `development`.
    4. `terraform-apply.yaml` trigger; vao Actions tab -> approve `development` environment.
    5. Verify Console: ECR repo `3-tiers-app-backend-development` + SSM parameter `/3-tiers-app/development/ecr/backend_url`.
    6. (Tuy chon) Replicate sang `production`: mo PR moi base=`production`, head=cung feature branch -> verify plan +3 / 0 destroy -> merge -> approve -> verify Console.

---

## Sub-sprint S02b - ALB (chay sau S02a)

### Definition of done S02b

- `terraform plan`: ~8 to add (1 LB + 1 target group + 1 HTTP listener + 1 security group + 3 SG rules + 1 SSM param). HTTPS listener khong duoc tao vi `alb_acm_cert_arn = null`.
- Apply tren development thanh cong.
- AWS Console: ALB `development-alb` ton tai, target group `development-tg` co (chua co target healthy vi chua co ECS service).

### Sub-tasks S02b

- [X] S02b-T01 - Un-comment `module "alb"` + companion outputs

  - Assignee: iac-builder
  - Files:
    - `envs/_shared/main.tf` dong 29-37: un-comment block `module "alb"`
    - `envs/_shared/outputs.tf` dong 40-44: un-comment `aws_ssm_parameter "alb_dns_name"`
    - `envs/_shared/outputs.tf` dong 52-55: un-comment `output "alb_dns_name"`
  - Notes: ALB ref `module.network.vpc_id` va `module.network.public_subnet_ids` - 2 output da co san tu S01. ALB co `enable_deletion_protection = true` - resource stateful, can luu y khi destroy.
- [X] S02b-T02 - Review diff S02b

  - Assignee: iac-reviewer
- [X] S02b-T03 - terraform plan xac nhan ~8 to add, 0 change, 0 destroy

  - Assignee: terraform-planner
  - Notes: Verify network resource khong bi thay doi; ECR resource S02a khong bi thay doi.
- [X] S02b-T04 - Deploy S02b len development

  - Assignee: user
  - Quy trinh tuong tu S02a-T04, branch moi `feature/phased-deploy-s02b-alb`.

---

## Sub-sprint S02c - ECS cluster (chay sau S02b)

### Definition of done S02c

- `terraform plan`: 3 to add (`aws_ecs_cluster`, `aws_ecs_cluster_capacity_providers`, `aws_ssm_parameter.ecs_cluster_name`).
- Apply tren development thanh cong.
- AWS Console: ECS cluster `development-3-tiers-app` ton tai voi capacity providers FARGATE + FARGATE_SPOT.

### Sub-tasks S02c

- [X] S02c-T01 - Un-comment `module "ecs_cluster"` + companion outputs

  - Assignee: iac-builder
  - Files:
    - `envs/_shared/main.tf` dong 40-44: un-comment block `module "ecs_cluster"`
    - `envs/_shared/outputs.tf` dong 4-8: un-comment `aws_ssm_parameter "ecs_cluster_name"`
    - `envs/_shared/outputs.tf` dong 47-50: un-comment `output "ecs_cluster_name"`
  - Notes: ECS cluster co `containerInsights = enabled` (default) - phat sinh chi phi CloudWatch Logs/Metrics. Co the override `enable_container_insights = false` neu muon tiet kiem them.
- [X] S02c-T02 - Review diff S02c

  - Assignee: iac-reviewer
- [ ] S02c-T03 - terraform plan xac nhan 3 to add

  - Assignee: terraform-planner
- [ ] S02c-T04 - Deploy S02c len development

  - Assignee: user
  - Quy trinh tuong tu S02a-T04, branch moi `feature/phased-deploy-s02c-ecs-cluster`.

---

## Review checklist

Cac reviewer tick box khi verify xong (theo tung sub-sprint).

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

### 2026-05-16 - iac-reviewer (S02a)

- Verdict: approve
- Sub-tasks ticked: S02a-T01 (giu nguyen [X] sau khi verify code khop voi description), S02a-T02 (chinh minh)
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none (S02a-T03 van assign cho terraform-planner nhu plan ban dau; S02a-T04 van assign cho user)
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 2
- Ghi chu:
  - Diff `envs/_shared/main.tf` un-comment dung block `module "ecr_backend"` dong 20-25 voi `repo_name = "3-tiers-app-backend-${var.environment}"`. Cac module con lai (`alb`, `ecs_cluster`, `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability`) van comment. KHONG raise finding ve viec xoa 7 marker `# PHASED-DEPLOY S01` (da co exception trong CAP NHAT 2026-05-16).
  - Diff `envs/_shared/outputs.tf` un-comment dung block `aws_ssm_parameter "ecr_backend_url"` (dong 20-24) va `output "ecr_backend_url"` (dong 71-74); xoa stale header dong 1. SSM path `/3-tiers-app/${var.environment}/ecr/backend_url` co leading slash, khong prefix `aws`/`ssm`, hop le theo AWS SSM naming rules. ECR repo name `3-tiers-app-backend-development` (30 ky tu) hop le theo AWS ECR naming rules (lowercase + hyphens, < 256 chars).
  - Khong co resource networking S01 bi thay doi (`module "network"` block giu nguyen dong 9-18).
  - Khong su dung `terraform workspace`, khong co provider block trong modules, khong co secrets/account-ID hardcoded, khong vi pham layout top-level. envs/development vs envs/production parity pass.
  - Day la new-resource un-comment, KHONG phai refactor -> khong can `moved`/`import`/`removed` blocks. ECR repository KHONG nam trong stateful allowlist (allowlist gom RDS/S3/KMS/EFS/DynamoDB/EIP/SecretsManager/ElastiCache/MSK/EKS) nen khong yeu cau `prevent_destroy = true`.
  - Quality gates:
    - `terraform fmt -check -recursive envs/_shared/` -> exit 0 (pass)
    - `terraform fmt -check -recursive modules/ecr/` -> exit 0 (pass)
    - `bash scripts/verify-envs-in-sync.sh` -> "OK: envs/development and envs/production are in sync."
    - `terraform validate` -> KHONG chay duoc cuc bo (Terraform local v1.9.2 < required v1.11). Theo plan, terraform-planner se verify tren CI runner (v1.13.3).
    - `tflint --recursive` -> KHONG chay duoc cuc bo (tflint khong cai). Han che moi truong, ghi nhan.
  - Finding NIT-1 (khong block): module `ecr` khong co `lifecycle { prevent_destroy = true }`. ECR khong nam trong stateful allowlist hien tai nen khong vi pham hard rule cua reviewer. Tuy nhien, neu repo bi destroy thi cac image (artifact deployed) se mat. Goi y (tuy chon, khong yeu cau cho S02a): them `prevent_destroy = true` trong module `ecr` o sprint sau neu user muon bao ve them. Khong block S02a.
  - Finding NIT-2 (khong block): `output "ecr_backend_url"` un-comment trong `envs/_shared/outputs.tf` nhung root `envs/development/outputs.tf` KHONG re-export. Da ghi nhan o Notes cua S02a-T01 ("khong noi len `terraform output`"). Doc bang SSM parameter van OK. Khong block.
- Playwright not used; no screenshots to clean.

### 2026-05-16 - iac-reviewer (S02b)

- Verdict: approve
- Sub-tasks ticked: S02b-T01, S02b-T02 (chinh minh)
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none (S02b-T03 van assign cho terraform-planner; S02b-T04 van assign cho user)
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 2
- Ghi chu:
  - Diff `envs/_shared/main.tf` un-comment dung block `module "alb"` (dong 27-35) voi 7 argument: `source`, `environment`, `vpc_id`, `public_subnet_ids`, `domain_name`, `existing_acm_cert_arn`, `tags`. Khop chinh xac voi `modules/alb/variables.tf` (7 variable required/optional, khong thua khong thieu). Cac module con lai (`ecs_cluster`, `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability`) van comment - dung scope S02b. Module `network` (S01) va `ecr_backend` (S02a) khong bi thay doi.
  - Diff `envs/_shared/outputs.tf` un-comment dung 2 block: `aws_ssm_parameter "alb_dns_name"` (dong 38-42, path `/3-tiers-app/${var.environment}/alb/dns_name`, type `String`, value `module.alb.dns_name`) va `output "alb_dns_name"` (dong 50-53). SSM path hop le theo AWS SSM naming rules (leading `/`, khong prefix `aws`/`ssm`).
  - Wiring verify: `module.network.vpc_id` va `module.network.public_subnet_ids` ton tai trong `modules/network/outputs.tf` (dong 1-3 va 16-19), type `string` va `list(string)` khop signature. `module.alb.dns_name` ton tai trong `modules/alb/outputs.tf` dong 11-14 (value `aws_lb.this.dns_name`).
  - Var `var.domain_name` (`envs/_shared/variables.tf` dong 77-81, default `null`) va `var.alb_acm_cert_arn` (dong 83-87, default `null`) deu da khai bao truoc do voi default an toan. tfvars development giu commented placeholder cho ca 2 -> `existing_acm_cert_arn = null` o module ALB -> HTTPS listener `count = 0`, HTTP listener default action la `fixed-response 503`.
  - Resource count cross-check voi expected `~8 to add`:
    - `aws_security_group.alb` (1)
    - `aws_security_group_rule.alb_ingress_https` (1)
    - `aws_security_group_rule.alb_ingress_http_redirect` (1)
    - `aws_security_group_rule.alb_egress_all` (1)
    - `aws_lb.this` (1)
    - `aws_lb_target_group.this` (1) - `target_type = "ip"` dung cho Fargate
    - `aws_lb_listener.http_redirect` (1) - luon tao, dynamic action chuyen sang `fixed-response 503` khi cert null
    - `aws_lb_listener.https` (0) - `count = var.existing_acm_cert_arn != null ? 1 : 0`
    - `aws_ssm_parameter.alb_dns_name` (1)
    - Total = **8 resource to add**, khop voi Definition of done S02b. Khong co resource lat (khong WAF, khong S3 access logs bucket auto-tao, khong null_resource/local-exec).
  - `enable_deletion_protection = true` da duoc set san trong `modules/alb/main.tf` dong 42 (cong voi `drop_invalid_header_fields = true` dong 43 - security hardening). Hand-off cua iac-builder ghi "module hien khong set enable_deletion_protection, mac dinh AWS = false" la **bao SAI**; code thuc te DA set true. Plan note dung. Khong block.
  - Khong su dung `terraform workspace`, khong co `provider` block trong `modules/`, khong co `moved`/`import`/`removed` block (un-comment = new resource, khong phai refactor), khong co CLI state mutation (`terraform state mv/rm`, `terraform import`) trong source/scripts.
  - Stateful allowlist check: `aws_lb`, `aws_lb_target_group`, `aws_lb_listener`, `aws_security_group`, `aws_ssm_parameter` KHONG nam trong stateful allowlist cua repo (allowlist gom RDS/S3/KMS/EFS/DynamoDB/EIP/SecretsManager/ElastiCache/MSK/EKS). `lifecycle { prevent_destroy = true }` khong bat buoc. ALB co `enable_deletion_protection = true` o AWS level la du.
  - Khong co secrets / account-ID hardcoded MOI trong diff S02b. Cac ARN `arn:aws:acm:us-east-1:405226342924:...` trong `envs/development/terraform.tfvars` la commented placeholder ton tai tu truoc S02b, khong thay doi boi sub-task nay.
  - Quality gates:
    - `terraform fmt -check -recursive envs/_shared/ modules/alb/` -> exit 0 (pass)
    - `bash scripts/verify-envs-in-sync.sh` -> "OK: envs/development and envs/production are in sync." (pass)
    - `diff envs/development/main.tf envs/production/main.tf` -> empty (parity pass)
    - `diff envs/development/variables.tf envs/production/variables.tf` -> empty (parity pass)
    - `terraform validate` -> KHONG chay duoc cuc bo (Terraform local v1.9.2 < required v1.11). Theo plan, terraform-planner verify tren CI runner (v1.13.3).
    - `tflint --recursive` -> KHONG chay duoc cuc bo (tflint khong cai). Han che moi truong.
  - Finding NIT-1 (khong block, reassign to user): variable `enable_waf` trong `modules/alb/variables.tf` dong 39-43 (default `false`) la **dead variable** - module khong co bat ky `aws_wafv2_*` resource nao. Variable nay ton tai tu truoc S02b, khong phai loi cua sub-task. Goi y cho Sprint cleanup sau: hoac implement WAF resource khi `enable_waf = true`, hoac xoa variable. Khong block S02b.
  - Finding NIT-2 (khong block, reassign to user): `aws_security_group_rule.alb_ingress_https` luon tao ingress 443 du HTTPS listener co `count = 0` khi `alb_acm_cert_arn = null`. Khong phai loi (SG rule pre-provision cho khi cert duoc add sau, tranh chicken-and-egg), nhung dang ghi nhan de main thread brief terraform-planner. Khong block S02b.
  - Note cho main thread (brief terraform-planner): expected plan +8 / 0 change / 0 destroy. 12 network resource (S01) + 3 ECR/SSM resource (S02a) chi "Refreshing state", khong bi modify. Neu plan output show >8 to add hoac bat ky change/destroy nao tren network/ECR, can investigate truoc khi apply.
- Playwright not used; no screenshots to clean.

### 2026-05-17 - iac-reviewer (S02c)

- Verdict: approve
- Sub-tasks ticked: S02c-T01, S02c-T02 (chinh minh)
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none (S02c-T03 van assign cho terraform-planner; S02c-T04 van assign cho user)
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 1
- Ghi chu:
  - Diff `git diff development -- envs/_shared/main.tf envs/_shared/outputs.tf` chi gom 2 file, 14 insertion + 14 deletion (rong = un-comment thuan, khong sua noi dung HCL nao khac). `envs/_shared/main.tf` dong 38-42 un-comment block `module "ecs_cluster"` voi 3 argument (`source = "../../modules/ecs-cluster"`, `environment`, `tags`) - khop chinh xac `modules/ecs-cluster/variables.tf` (chi `environment` la required khong default; `enable_container_insights`, `capacity_providers`, `default_capacity_provider`, `tags` deu co default an toan). Module `network` (S01), `ecr_backend` (S02a), `alb` (S02b) KHONG bi thay doi. Cac module `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability` van comment - dung scope S02c.
  - Diff `envs/_shared/outputs.tf` un-comment dung 2 block: `aws_ssm_parameter "ecs_cluster_name"` (dong 2-6, path `/3-tiers-app/${var.environment}/ecs/cluster_name`, type `String`, value `module.ecs_cluster.cluster_name`) va `output "ecs_cluster_name"` (dong 45-48). SSM path hop le theo AWS SSM naming rules (leading `/`, khong prefix `aws`/`ssm`, segment phan cap ro rang).
  - Wiring verify: `module.ecs_cluster.cluster_name` ton tai trong `modules/ecs-cluster/outputs.tf` dong 6-9 (value `aws_ecs_cluster.this.name`). Signature khop (string). Khong co consumer module nao trong S02c reference `cluster_id`/`cluster_arn` (cac module `ecs_service`, `observability` van comment).
  - Naming convention check: ECS cluster name `${var.environment}-3-tiers-app` -> resource AWS ten `development-3-tiers-app` (PREFIX environment, dung convention chung cua repo `${env}-<resource>-<role>`). KHAC voi ECR repo (`3-tiers-app-backend-${var.environment}` POSTFIX, exception 2026-05-16) - tuc la cluster nay tuan thu convention chinh, khong can exception.
  - Resource count cross-check voi expected `3 to add`:
    - `aws_ecs_cluster.this` (1) - ten `development-3-tiers-app`, `containerInsights = enabled`
    - `aws_ecs_cluster_capacity_providers.this` (1) - capacity providers `[FARGATE, FARGATE_SPOT]`, default strategy weight 100 FARGATE
    - `aws_ssm_parameter.ecs_cluster_name` (1)
    - Total = **3 resource to add**, khop voi Definition of done S02c. Module ecs-cluster KHONG tu tao `aws_cloudwatch_log_group` (Container Insights log group la AWS-managed runtime, dung). Khong co null_resource/local-exec.
  - Stateful allowlist check: `aws_ecs_cluster`, `aws_ecs_cluster_capacity_providers`, `aws_ssm_parameter` KHONG nam trong stateful allowlist cua repo (allowlist gom RDS/S3/KMS/EFS/DynamoDB/EIP/SecretsManager/ElastiCache/MSK/EKS/aws_eks_node_group). `lifecycle { prevent_destroy = true }` khong bat buoc. ECS cluster co the destroy-recreate ma khong mat du lieu khach hang (chi mat resource shell).
  - Khong su dung `terraform workspace`, khong co `provider` block trong `modules/ecs-cluster/`, khong co `moved`/`import`/`removed` block (un-comment = new resource, khong phai refactor), khong co CLI state mutation (`terraform state mv/rm`, `terraform import`) trong source/scripts/docs cua diff. Module `ecs-cluster` co `terraform { required_version = ">= 1.11" }` + `required_providers aws ~> 5.70` trong `versions.tf` - khop voi convention chung cua repo.
  - Container Insights tradeoff: `enable_container_insights = true` (default module) -> phat sinh chi phi CloudWatch Logs/Metrics runtime. KHONG raise finding theo huong dan: Sprint plan dong 200 da ghi nhan tradeoff intentional, override `enable_container_insights = false` la optional khi can tiet kiem.
  - Khong co secrets / account-ID hardcoded MOI trong diff S02c. Grep `arn:aws|405226342924|AKIA|password|secret` cho `envs/_shared/` chi match comment cu cho `module "rds"`/`ecs_service` (chua active) va ten variable `ecs_task_cpu`/`ecs_task_memory` - khong phai literal secret.
  - Quality gates:
    - `terraform fmt -check -recursive envs/_shared/ modules/ecs-cluster/` -> exit 0 (pass)
    - `bash scripts/verify-envs-in-sync.sh` -> "OK: envs/development and envs/production are in sync." (pass)
    - `diff envs/development/main.tf envs/production/main.tf` -> empty (parity pass)
    - `diff envs/development/variables.tf envs/production/variables.tf` -> empty (parity pass)
    - `envs/<env>/outputs.tf` KHONG ton tai o ca 2 env (dung design intent - SSM la discovery layer chinh thuc; NIT cu da dismiss 2026-05-16, KHONG raise lai).
    - `terraform validate` -> KHONG chay duoc cuc bo (Terraform local v1.9.2 < required v1.11). Theo plan, terraform-planner se verify tren CI runner (v1.13.3).
    - `tflint --recursive` -> KHONG chay duoc cuc bo (tflint khong cai). Han che moi truong.
  - Finding NIT-1 (khong block, reassign to user): `aws_ssm_parameter.ecs_cluster_name` (cung nhu `ecr_backend_url` va `alb_dns_name`) KHONG co block `tags = local.common_tags` - lap lai minor inconsistency da ghi nhan o S02a-T03. Defer cho Sprint cleanup neu user muon dong nhat tag policy giua SSM param va resource module. Khong block S02c.
  - Note cho main thread (brief terraform-planner): expected plan **+3 / 0 change / 0 destroy** tren development. 12 network resource (S01) + 3 ECR/SSM resource (S02a) + 8 ALB/SSM resource (S02b) chi "Refreshing state", khong bi modify. Neu plan output show >3 to add hoac bat ky change/destroy nao tren network/ECR/ALB, can investigate truoc khi apply. ECS cluster ten phai la `development-3-tiers-app`, capacity providers `[FARGATE, FARGATE_SPOT]`, default strategy FARGATE weight 100.
- Playwright not used; no screenshots to clean.

## Last updated

2026-05-16 by main thread - tick S02a-T04: user xac nhan ECR repo + SSM parameter da deploy thanh cong tren development account. Sub-sprint S02a HOAN TAT. San sang chuyen sang S02b (ALB).

2026-05-16 by main thread - tick S02a-T03 sau khi user cung cap terraform plan output: +3 / 0 change / 0 destroy khop expected; ghi nhan minor finding SSM parameter thieu tag (defer)

2026-05-16 by main thread - dismiss NIT-2 cua iac-reviewer (envs/development/outputs.tf khong ton tai); ghi rationale: repo intentional dung SSM la discovery layer duy nhat, S01 network cung khong co root output; quy tac cho cac Sprint sau

2026-05-16 by main thread - ghi nhan quyet dinh INTENTIONAL bo 7 marker `# PHASED-DEPLOY S01` khoi `_shared/main.tf`; iac-reviewer khong raise finding lien quan tracking marker

2026-05-16 by main thread - split S02 thanh 3 sub-sprint (S02a ECR / S02b ALB / S02c ECS cluster); moi sub-sprint co Definition of done + sub-tasks rieng. Tick S02a-T01 (user da un-comment ECR + SSM ecr_backend_url tren branch hien tai). Cap nhat bang Pham vi un-comment voi dong cu the trong outputs.tf

2026-05-16 by main thread - them quyet dinh pattern repo_name dung POSTFIX environment (`3-tiers-app-backend-${var.environment}`); ghi nhan user da un-comment `module "ecr_backend"` + sua truc tiep tren branch `feature/phased-deploy-s02-ecr-alb-ecs` (iac-builder van can xu ly phan con lai cua S02-T01)

2026-05-15 by main thread - doi marker PHASED-ROLLOUT thanh PHASED-DEPLOY; doi ten feature branch; them buoc replicate sang production
