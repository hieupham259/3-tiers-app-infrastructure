# Research: Bootstrap qua CI/CD — quyết định cuối

> **Ràng buộc dự án (cứng):**
> 1. Mọi resource hạ tầng provision qua **CI/CD** (GitHub Actions).
> 2. KHÔNG chạy command thủ công ở máy local.
> 3. KHÔNG click thủ công Console (trừ khi không thể tránh khỏi).

> **Quyết định:**
> - **Trust anchor (1 lần per account):** Upload 1 CFN template duy nhất qua AWS Console = bước manual không thể tránh khỏi.
> - **Tất cả còn lại (state bucket, OIDC roles, hạ tầng app):** 100% qua GitHub Actions workflows.

---

## 1. Sự thật cốt lõi: bootstrap luôn cần "trust anchor"

CI/CD muốn provision AWS resources → cần credentials/role để gọi AWS API. Nhưng cái role đó **ai tạo**?

- Nếu CI/CD tạo → cần role có sẵn để CI/CD gọi → vòng lặp.
- Nếu Terraform/CFN tạo qua CI/CD → cần role để chạy Terraform/CFN → vòng lặp.

→ **Phải có 1 "trust anchor"** đầu tiên — bằng chứng đầu tiên rằng GitHub Actions được phép vào AWS account này.

**Cách duy nhất để có zero manual step:** Org đã pre-setup AWS Identity Center (SSO) federation với GitHub Enterprise — đây là setup cấp tổ chức 1 lần cho TẤT CẢ repos. Nếu chưa có, bắt buộc phải có 1 manual step để tạo trust anchor.

→ Cho dự án này (giả sử org chưa có pre-setup), chấp nhận **1 manual step duy nhất** = upload 1 CFN template qua Console.

---

## 2. Pattern 3 lớp đã chọn

```
┌──────────────────────────────────────────────────────────────────┐
│ LỚP 0 — TRUST ANCHOR                                             │
│   File: bootstrap/01-trust-anchor.yaml                           │
│   Provision: 🔴 MANUAL (Console upload, 1 lần per account, 5min) │
│   Tạo: OIDC provider + role `gha-bootstrap`                      │
│   Trust scope: chỉ workflow trong GitHub Environment "bootstrap" │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ LỚP 1 — BOOTSTRAP STACKS                                         │
│   File: bootstrap/02-tfstate-backend.yaml                        │
│         bootstrap/03-github-oidc-roles.yaml                      │
│   Provision: ✅ CI/CD (workflow bootstrap.yaml, workflow_dispatch)│
│   Tạo: S3 state bucket + KMS, gha-infra-{plan,apply},            │
│        gha-{backend,frontend}-deploy roles                       │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ LỚP 2 — INFRASTRUCTURE STACKS                                    │
│   File: envs/development/*, envs/production/* (Terraform)                      │
│   Provision: ✅ CI/CD (workflow terraform-apply.yaml, on push)    │
│   Tạo: VPC, RDS, ECS, ALB, S3+CF...                              │
└──────────────────────────────────────────────────────────────────┘
                              ↓
┌──────────────────────────────────────────────────────────────────┐
│ LỚP 3 — APP DEPLOYMENT                                           │
│   Provision: ✅ CI/CD (workflows trong backend/frontend repo)    │
│   Push image, sync S3, ECS update, CF invalidate                 │
└──────────────────────────────────────────────────────────────────┘
```

---

## 3. Các approach đã loại bỏ

| Approach | Lý do loại |
|----------|-----------|
| Terraform local-state → migrate | ❌ Yêu cầu chạy `terraform` ở local |
| Terragrunt | ❌ Yêu cầu chạy ở local + thêm tool |
| Atmos | ❌ Tương tự |
| AWS CLI script local | ❌ Chạy local |
| Manual click Console toàn bộ | ❌ Không IaC, drift, không reproducible |
| AWS CloudShell qua browser | ⚠️ Vẫn là manual, không phải CI/CD |
| CFN deploy qua Console UI cho TẤT CẢ stacks | ⚠️ Manual step quá nhiều |
| **CFN trust anchor + CI/CD cho mọi thứ khác** | ✅ Chosen |

---

## 4. Trust anchor minimization

Trust anchor là **1 CFN template duy nhất** tạo:
- 1 OIDC provider (`token.actions.githubusercontent.com`)
- 1 IAM role `gha-bootstrap` với:
  - **Trust hẹp:** chỉ assume từ workflow trong GitHub Environment `bootstrap` của repo cụ thể
  - **Quyền đủ cho bootstrap:** AdministratorAccess (vì cần tạo IAM, KMS, S3 — narrower policy phức tạp)

```yaml
GhaBootstrapRole:
  AssumeRolePolicyDocument:
    Statement:
      - Principal: { Federated: !Ref GitHubOidcProvider }
        Action: sts:AssumeRoleWithWebIdentity
        Condition:
          StringEquals: { 'token.actions.githubusercontent.com:aud': sts.amazonaws.com }
          StringLike:
            'token.actions.githubusercontent.com:sub':
              "repo:myorg/3-tiers-app-infrastructure:environment:bootstrap"
```

**GitHub Environment `bootstrap`** được protect:
- Manual approval 1 reviewer
- Deployment branch restriction = `main` (hoặc `master`)
- Restricted to specific actors (CODEOWNERS only)

→ Ngay cả khi attacker push code vào branch `development`, **không thể** assume `gha-bootstrap` role vì điều kiện `:environment:bootstrap` không match.

---

## 5. Workflow chuỗi

### Lần đầu setup (do DevOps lead + cloud admin phối hợp)

```
DevOps lead:
  ├── Viết bootstrap/{01,02,03}.yaml
  ├── Viết .github/workflows/bootstrap.yaml
  ├── Setup GitHub Environment "bootstrap" với reviewers + branch restrictions
  └── Push lên branch main

Cloud admin (DUY NHẤT 2 lần manual):
  ├── Login AWS Console account development (111111111111)
  │   └── CloudFormation → Create stack → upload 01-trust-anchor.yaml
  │       └── Tạo OIDC + gha-bootstrap role
  └── Login AWS Console account production (222222222222)
      └── Lặp lại

DevOps lead (qua GitHub UI):
  ├── Tab Actions → "Bootstrap" → Run workflow → account=development
  │   └── 1 reviewer approve → CI deploy stacks 02 + 03 vào development
  └── Tab Actions → "Bootstrap" → Run workflow → account=production
      └── 1 reviewer approve → CI deploy stacks 02 + 03 vào production
```

### Vòng đời tiếp theo (zero manual)

```
Dev viết code → push branch development
  ↓
GitHub Actions terraform-plan.yaml: PR comment với plan
  ↓
Reviewer approve → merge → terraform-apply.yaml → CI apply development
  ↓
PR development → production → manual approve trong Environment "production"
  ↓
CI apply production
```

---

## 6. So sánh số manual step

| Approach | Manual steps lifetime | Risk |
|----------|----------------------|------|
| Terraform local-migrate | 5 commands × N accounts mỗi lần update bootstrap | Credentials trên local |
| CFN qua Console UI cho mọi stack | 4 stacks × N accounts × mỗi update = nhiều | Click error |
| CFN qua CloudShell mọi stack | N commands trong shell × N accounts | Click error |
| **CFN trust-anchor + CI/CD** | **2 lần** (1 lần đầu mỗi account, vĩnh viễn) | Tối thiểu |

---

## 7. Update bootstrap stacks sau này

Khi cần update `02-tfstate-backend.yaml` (vd: rotate KMS, thay lifecycle):
1. Edit YAML, push lên branch main
2. Trigger workflow `bootstrap.yaml` → CI redeploy stack
3. **Không** cần đụng Console hay máy local

CFN `aws cloudformation deploy` idempotent → chạy lại nhiều lần OK.

Khi cần update `01-trust-anchor.yaml` (vd: rotate OIDC thumbprint):
- Phải manual qua Console (vì đây là trust anchor) — nhưng tần suất gần như zero (OIDC thumbprint của GitHub đổi rất hiếm).

---

## 8. Drift detection cũng qua CI/CD

Workflow `cfn-drift-detect.yaml` chạy schedule weekly:

```yaml
on:
  schedule: [{ cron: '0 18 * * 0' }]   # Sun 01:00 ICT
  workflow_dispatch:

jobs:
  drift:
    strategy:
      matrix:
        account: [development, production]
    steps:
      - assume gha-infra-plan role (read-only)
      - aws cloudformation detect-stack-drift cho 02-tfstate-backend, 03-github-oidc-roles
      - if drift → notify Slack
```

→ Không cần chạy gì local để check drift.

---

## 9. Trade-offs

**Phải chấp nhận:**
1. **2 lần upload Console** ban đầu (không thể tránh nếu org chưa có SSO federation).
2. **Trust anchor có quyền AdministratorAccess** → cần protect chặt qua GitHub Environment.
3. **Phải maintain CFN YAML** cho 3 templates (~200 dòng tổng).

**Đổi lại:**
1. Sau setup, **0 thao tác hạ tầng manual** trong toàn vòng đời dự án.
2. **0 credentials AWS dài hạn** trên máy local.
3. **Audit trail đầy đủ** — mọi provision đều có CloudTrail + GitHub Actions log + commit history.
4. **Reproducible 100%** — code = infrastructure.

---

## 10. Sources

- [Configuring OpenID Connect in AWS (GitHub Docs)](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS CloudFormation deploy via GitHub Actions](https://github.com/aws-actions/aws-cloudformation-github-deploy)
- [GitHub Environment protection rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [AWS CloudFormation drift detection](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html)
- [Trust anchor pattern for IaC bootstrap (HashiCorp Discuss)](https://discuss.hashicorp.com/t/feature-request-terraform-state-locking-in-aws-with-s3-strong-consistency-no-dynamodb/18456)
