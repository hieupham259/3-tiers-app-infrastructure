# CI/CD Chain of Trust — Full luồng từ T-7 đến T+30

> Giải thích đầy đủ cách `terraform-plan.yaml` và `terraform-apply.yaml` connect được vào đúng AWS environment, bắt đầu từ "chưa có gì" cho đến "developer thêm resource hàng ngày".

---

## Chain of Trust 3 lớp

```
┌──────────────────────────────────────────────────────────────────┐
│ Lớp 0 — TRUST ANCHOR (Manual upload qua Console)                 │
│   Tạo: OIDC provider + gha-bootstrap role                        │
│   File: bootstrap/01-trust-anchor.yaml                           │
│   Lifecycle: 1 lần per account, gần như không đụng lại           │
└────────────────────────┬─────────────────────────────────────────┘
                         │ tạo nền tảng cho
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ Lớp 1 — BOOTSTRAP STACKS (qua bootstrap.yaml workflow)            │
│   Tạo: S3 state bucket + KMS                                     │
│         gha-infra-plan, gha-infra-apply                          │
│         gha-backend-deploy, gha-frontend-deploy                  │
│   File: bootstrap/02-tfstate-backend.yaml                        │
│         bootstrap/03-github-oidc-roles.yaml                      │
│   Lifecycle: 1 lần đầu + redeploy khi update CFN templates       │
└────────────────────────┬─────────────────────────────────────────┘
                         │ tạo nền tảng cho
                         ▼
┌──────────────────────────────────────────────────────────────────┐
│ Lớp 2 — INFRASTRUCTURE STACKS (qua terraform-apply.yaml)          │
│   Tạo: VPC, RDS, ECS, ALB, S3+CloudFront...                      │
│   File: envs/development/, envs/production/                                    │
│   Lifecycle: mỗi PR thay đổi code Terraform                      │
└──────────────────────────────────────────────────────────────────┘
```

**Quan trọng:** Mỗi lớp **dùng credentials/role do lớp trên tạo ra**. Đây là chain of trust.

---

## Full timeline

### 📅 T-7 ngày: Cloud admin upload trust anchor (LẦN ĐẦU SETUP, MANUAL)

**Account DEVELOPMENTELOPMENT:**
1. Cloud admin login Console account development qua SSO
2. CloudFormation → Create stack → upload `bootstrap/01-trust-anchor.yaml`
3. CFN tạo:
   - `AWS::IAM::OIDCProvider` — đăng ký GitHub là trusted IdP
   - `AWS::IAM::Role` tên `gha-bootstrap` (trust scope: chỉ env `bootstrap`)
4. `CREATE_COMPLETE`

**Account PRODUCTIONUCTION:** Lặp lại y hệt.

→ Sau T-7: **CẢ 2 accounts đã có OIDC provider + gha-bootstrap role.**

> Đây là 2 manual steps DUY NHẤT trong toàn bộ vòng đời. Sau đây không bao giờ chạy lại.

---

### 📅 T-1 ngày: DevOps trigger `bootstrap.yaml` (CI/CD, LẦN ĐẦU)

#### Bước A: Trigger workflow cho account DEVELOPMENTELOPMENT

DevOps lead vào GitHub UI:
- Tab **Actions** → workflow **"Bootstrap (CFN — state backend + OIDC roles)"**
- Click **Run workflow** → branch `main` → input `account=development` → Submit

#### Bước B: GitHub Environment `bootstrap` block workflow

Workflow status: `Waiting for review`. Environment `bootstrap` config:
- Required reviewers: 1
- Deployment branches: `main` only

→ 1 reviewer approve trong UI → workflow tiếp tục.

#### Bước C: Workflow assume `gha-bootstrap` role ở account DEVELOPMENTELOPMENT

```yaml
# .github/workflows/bootstrap.yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::111111111111:role/gha-bootstrap
    aws-region: ap-southeast-1
```

**Token flow:**
```
1. GitHub cấp JWT:
   sub: "repo:myorg/3-tiers-app-infrastructure:environment:bootstrap"
   aud: "sts.amazonaws.com"

2. Action gọi sts:AssumeRoleWithWebIdentity
   RoleArn: arn:aws:iam::111111111111:role/gha-bootstrap

3. AWS account development (111...) check trust policy của gha-bootstrap:
   Condition matched:
     - aud == "sts.amazonaws.com" ✓
     - sub LIKE "repo:myorg/...:environment:bootstrap" ✓
   → Trả temp credentials (1h, account 111...)

4. Workflow giờ "đang ở trong" account development, có quyền Admin (vì gha-bootstrap có AdministratorAccess)
```

#### Bước D: Workflow deploy `02-tfstate-backend.yaml`

```yaml
- name: Deploy stack 02-tfstate-backend
  run: |
    aws cloudformation deploy \
      --stack-name tfstate-backend \
      --template-file bootstrap/02-tfstate-backend.yaml \
      --capabilities CAPABILITY_NAMED_IAM
```

CFN trong account development tạo:
- KMS key `alias/tfstate`
- S3 bucket `myorg-tfstate-111111111111` (versioning, encryption, lifecycle)
- Bucket policy (deny insecure transport)

→ State backend account development đã sẵn sàng.

#### Bước E: Read outputs từ stack vừa tạo

```yaml
- id: tfstate
  run: |
    BUCKET=$(aws cloudformation describe-stacks --stack-name tfstate-backend ...)
    KMS_ARN=$(aws cloudformation describe-stacks --stack-name tfstate-backend ...)
    echo "bucket=$BUCKET" >> $GITHUB_OUTPUT
    echo "kms_arn=$KMS_ARN" >> $GITHUB_OUTPUT
```

→ Có giá trị `myorg-tfstate-111111111111` và KMS ARN để inject vào stack tiếp theo.

#### Bước F: Workflow deploy `03-github-oidc-roles.yaml`

```yaml
- name: Deploy stack 03-github-oidc-roles
  run: |
    aws cloudformation deploy \
      --stack-name github-oidc-roles \
      --template-file bootstrap/03-github-oidc-roles.yaml \
      --capabilities CAPABILITY_NAMED_IAM \
      --parameter-overrides \
        AllowedBranch=development \
        TfstateBucketName=myorg-tfstate-111111111111 \
        TfstateBucketArn=arn:aws:s3:::myorg-tfstate-111111111111 \
        TfstateKmsKeyArn=arn:aws:kms:...
```

CFN trong account development tạo **4 roles long-lived**:
- `gha-infra-plan` — trust: any branch của infra repo, permissions: ReadOnly + tfstate-rw
- `gha-infra-apply` — trust: branch `development` only, permissions: AdministratorAccess
- `gha-backend-deploy` — trust: branch `development` only, permissions: ECR + ECS
- `gha-frontend-deploy` — trust: branch `development` only, permissions: S3 + CF

→ Account development giờ có đủ roles để các workflow khác (terraform-*.yaml, deploy-*.yaml ở 3 repos) sử dụng.

#### Bước G: Trigger lại `bootstrap.yaml` cho account PRODUCTIONUCTION

DevOps lead lặp lại Bước A-F với input `account=production`. Khác biệt:
- Assume role `arn:aws:iam::222222222222:role/gha-bootstrap` (qua trust anchor đã tạo từ T-7)
- CFN tạo state bucket `myorg-tfstate-222222222222`
- 4 roles trong account production, nhưng `AllowedBranch=production` (chỉ branch `production` assume được apply role)

→ Sau T-1: **CẢ 2 accounts đã có:**
- ✅ State bucket + KMS
- ✅ gha-infra-plan (trust: any branch)
- ✅ gha-infra-apply (trust: branch tương ứng env)
- ✅ gha-backend-deploy + gha-frontend-deploy

> **`bootstrap.yaml` chỉ chạy lại khi cần update các CFN templates 02/03** (ví dụ: thêm role mới, thay lifecycle bucket, rotate KMS). Inactive 99% thời gian.

---

### 📅 T+0: Developer thêm resource Terraform (DAILY WORKFLOW)

Đến đây mới đến luồng daily. Nhưng giờ bạn hiểu **tại sao** các role tồn tại.

#### T+0 → T+8: PR vào `development`, plan + apply DEVELOPMENT

Khi `terraform-plan.yaml` chạy:

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::111111111111:role/gha-infra-plan
```

**Role `gha-infra-plan` ở account development** đã được tạo bởi `bootstrap.yaml` (Bước F của T-1). Trust policy của nó:

```yaml
# trong 03-github-oidc-roles.yaml
GhaInfraPlanRole:
  AssumeRolePolicyDocument:
    Statement:
      - Principal:
          Federated: !Sub "arn:aws:iam::${AWS::AccountId}:oidc-provider/token.actions.githubusercontent.com"
          # ← OIDC provider này đã được tạo bởi 01-trust-anchor.yaml ở T-7!
        Action: sts:AssumeRoleWithWebIdentity
        Condition:
          StringEquals:
            'token.actions.githubusercontent.com:aud': sts.amazonaws.com
          StringLike:
            'token.actions.githubusercontent.com:sub':
              !Sub "repo:${GitHubOrg}/${InfraRepo}:*"
```

→ Workflow assume được vì:
1. OIDC provider tồn tại (do trust anchor T-7 tạo)
2. Role gha-infra-plan tồn tại (do bootstrap.yaml T-1 tạo)
3. JWT của workflow match trust condition (`sub` LIKE `repo:myorg/3-tiers-app-infrastructure:*`)

#### Khi `terraform-apply.yaml` chạy (push lên `development`):

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::111111111111:role/gha-infra-apply
```

Trust policy của `gha-infra-apply` ở account development:

```yaml
Condition:
  StringEquals:
    'token.actions.githubusercontent.com:aud': sts.amazonaws.com
    'token.actions.githubusercontent.com:sub':
      "repo:myorg/3-tiers-app-infrastructure:ref:refs/heads/development"
      # ← AllowedBranch=development khi deploy 03 ở account development
```

→ Workflow chạy từ branch `development` thì sub match → assume được. Nếu chạy từ branch khác → AWS từ chối.

---

## Visualize chain of trust

```
                    ┌─────────────────────────────────┐
                    │  GitHub OIDC IdP                │
                    │  token.actions.githubusercontent│
                    │  .com                           │
                    └─────────┬───────────────────────┘
                              │ cấp JWT cho mỗi workflow run
                              ▼
        ┌─────────────────────────────────────────────────┐
        │ Workflow runtime (GitHub-hosted runner)         │
        │ JWT: { sub: "repo:.../...development|production...", │
        │        aud: "sts.amazonaws.com" }               │
        └────────────┬───────────────────┬────────────────┘
                     │                   │
        ┌────────────▼─────────┐   ┌─────▼───────────────┐
        │  AWS account DEVELOPMENTELOPMENT     │   │  AWS account PRODUCTIONUCTION   │
        │  (111111111111)      │   │  (222222222222)     │
        │                      │   │                     │
        │ ┌──────────────────┐ │   │ ┌─────────────────┐ │
        │ │ OIDC Provider    │ │   │ │ OIDC Provider   │ │
        │ │ (T-7: trust      │ │   │ │ (T-7: trust     │ │
        │ │  anchor created) │ │   │ │  anchor created)│ │
        │ └────────┬─────────┘ │   │ └────────┬────────┘ │
        │          │           │   │          │          │
        │ ┌────────▼─────────┐ │   │ ┌────────▼────────┐ │
        │ │ gha-bootstrap    │ │   │ │ gha-bootstrap   │ │
        │ │ (T-7: by trust   │ │   │ │ (T-7)           │ │
        │ │  anchor)         │ │   │ │                 │ │
        │ │                  │ │   │ │                 │ │
        │ │ → dùng để chạy   │ │   │ │ → dùng để chạy  │ │
        │ │   bootstrap.yaml  │ │   │ │   bootstrap.yaml │ │
        │ └────────┬─────────┘ │   │ └────────┬────────┘ │
        │          │ creates   │   │          │ creates  │
        │ ┌────────▼─────────┐ │   │ ┌────────▼────────┐ │
        │ │ S3 myorg-tfstate │ │   │ │ S3 myorg-tfstate│ │
        │ │ -111111111111    │ │   │ │ -222222222222   │ │
        │ │ + KMS            │ │   │ │ + KMS           │ │
        │ ├──────────────────┤ │   │ ├─────────────────┤ │
        │ │ gha-infra-plan   │ │   │ │ gha-infra-plan  │ │
        │ │ trust: any branch│ │   │ │ trust: any      │ │
        │ ├──────────────────┤ │   │ ├─────────────────┤ │
        │ │ gha-infra-apply  │ │   │ │ gha-infra-apply │ │
        │ │ trust: branch    │ │   │ │ trust: branch   │ │
        │ │ "development"    │ │   │ │ "production"    │ │
        │ ├──────────────────┤ │   │ ├─────────────────┤ │
        │ │ gha-backend-     │ │   │ │ gha-backend-    │ │
        │ │ deploy           │ │   │ │ deploy          │ │
        │ ├──────────────────┤ │   │ ├─────────────────┤ │
        │ │ gha-frontend-    │ │   │ │ gha-frontend-   │ │
        │ │ deploy           │ │   │ │ deploy          │ │
        │ └────────┬─────────┘ │   │ └────────┬────────┘ │
        │          │ uses      │   │          │ uses     │
        │ ┌────────▼─────────┐ │   │ ┌────────▼────────┐ │
        │ │ terraform-*.yaml  │ │   │ │ terraform-*.yaml │ │
        │ │ when branch =    │ │   │ │ when branch =   │ │
        │ │ development      │ │   │ │ production      │ │
        │ └────────┬─────────┘ │   │ └────────┬────────┘ │
        │          │ creates   │   │          │ creates  │
        │ ┌────────▼─────────┐ │   │ ┌────────▼────────┐ │
        │ │ VPC, RDS, ECS,   │ │   │ │ VPC, RDS, ECS,  │ │
        │ │ ALB, S3+CF, ...  │ │   │ │ ALB, S3+CF, ... │ │
        │ └──────────────────┘ │   │ └─────────────────┘ │
        └──────────────────────┘   └─────────────────────┘
```

---

## Tóm tắt: workflow nào dùng role nào, từ đâu mà có

| Workflow | Role assume | Account | Role được tạo bởi | Khi nào tạo |
|----------|-------------|---------|------------------|-------------|
| `bootstrap.yaml` (input=development) | `gha-bootstrap` | DEVELOPMENT | `01-trust-anchor.yaml` (manual) | T-7 |
| `bootstrap.yaml` (input=production) | `gha-bootstrap` | PRODUCTION | `01-trust-anchor.yaml` (manual) | T-7 |
| `terraform-plan.yaml` (PR base=development) | `gha-infra-plan` | DEVELOPMENT | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `terraform-plan.yaml` (PR base=production) | `gha-infra-plan` | PRODUCTION | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `terraform-apply.yaml` (push development) | `gha-infra-apply` | DEVELOPMENT | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `terraform-apply.yaml` (push production) | `gha-infra-apply` | PRODUCTION | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `terraform-drift.yaml` | `gha-infra-plan` | DEVELOPMENT + PRODUCTION | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `cfn-drift-detect.yaml` | `gha-infra-plan` | DEVELOPMENT + PRODUCTION | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `deploy-development.yaml` (backend repo) | `gha-backend-deploy` | DEVELOPMENT | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `deploy-production.yaml` (backend repo) | `gha-backend-deploy` | PRODUCTION | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `deploy-development.yaml` (frontend repo) | `gha-frontend-deploy` | DEVELOPMENT | `bootstrap.yaml` deploy `03-...yaml` | T-1 |
| `deploy-production.yaml` (frontend repo) | `gha-frontend-deploy` | PRODUCTION | `bootstrap.yaml` deploy `03-...yaml` | T-1 |

---

## Tần suất chạy mỗi workflow

| Workflow | Tần suất | Trigger |
|----------|----------|---------|
| `01-trust-anchor.yaml` (manual) | **2 lần TỔNG VÒNG ĐỜI** | Cloud admin upload Console |
| `bootstrap.yaml` | **1 lần đầu + khi update CFN templates** | DevOps trigger workflow_dispatch |
| `terraform-plan.yaml` | Mỗi PR | `pull_request` event |
| `terraform-apply.yaml` | Mỗi merge | `push` event |
| `terraform-drift.yaml` | Hàng đêm | `schedule` cron |
| `cfn-drift-detect.yaml` | Hàng tuần | `schedule` cron |

---

## Nếu trust anchor không tồn tại trước → bootstrap.yaml fail

Giả sử bạn quên Phase 5/6, push code lên main và trigger `bootstrap.yaml`:

```
Step: configure-aws-credentials
  ↓
  AssumeRoleWithWebIdentity:
    RoleArn: arn:aws:iam::111111111111:role/gha-bootstrap

  AWS response:
    Error: An error occurred (NoSuchEntity) when calling the
    AssumeRoleWithWebIdentity operation: Role
    arn:aws:iam::111111111111:role/gha-bootstrap does not exist.
```

→ Workflow fail. Không cách nào tự fix mà không upload trust anchor manual trước.

**Kết luận:** Trust anchor là **prerequisite** cho mọi thứ khác. Nó là **gốc của chain of trust**.

---

## Nếu bootstrap.yaml chưa chạy → terraform-plan/apply fail

Tương tự, nếu chưa chạy `bootstrap.yaml` mà bạn merge PR vào `development`:

```
terraform-apply.yaml:
Step: configure-aws-credentials
  RoleArn: arn:aws:iam::111111111111:role/gha-infra-apply

  AWS response:
    Error: Role gha-infra-apply does not exist.
```

→ Workflow fail. Không apply được Terraform vì role chưa tồn tại.

**Kết luận:** Phải chạy `bootstrap.yaml` trước khi `terraform-*.yaml` có thể hoạt động.

---

## Câu hỏi: connect đúng AWS environment thế nào?

`terraform-plan.yaml` và `terraform-apply.yaml` "connect đúng AWS environment" qua **3 thông tin**:

```yaml
# terraform-apply.yaml
env:
  ACCOUNT_ID: ${{ github.ref == 'refs/heads/production' && '222222222222' || '111111111111' }}

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::${{ env.ACCOUNT_ID }}:role/gha-infra-apply  # ← (1)
      aws-region: ap-southeast-1                                                # ← (2)
```

```hcl
# envs/development/backend.tf hoặc envs/production/backend.tf
backend "s3" {
  bucket = "myorg-tfstate-${ACCOUNT_ID}"   # ← (3)
}
```

3 thông tin **phải nhất quán**:
- (1) Role ARN chứa account ID → workflow assume role TRONG account đó → temp credentials thuộc account đó
- (2) Region → API calls tới region đó
- (3) State bucket name → state lưu trong account đó

**Cả 3 cùng dẫn về 1 account.** Mọi thứ Terraform tạo qua provider AWS sẽ tạo trong account đó (vì temp credentials ở account đó).

→ **Branch determines all 3:** push lên branch `development` → 3 thông tin all point to account development. Push lên branch `production` → 3 thông tin all point to account production.

→ **Code identical giữa 2 branches**, chỉ tệp `backend.tf` (cụ thể là bucket name) khác. Workflow tự chọn `envs/development/` hoặc `envs/production/` theo `github.ref`.

---

## Sơ đồ Sequence: từ `git push` đến AWS resource tạo

```
Developer            GitHub Repo         GitHub Actions       AWS STS               AWS API
    │                    │                     │                  │                    │
    │ git push           │                     │                  │                    │
    │ (development)      │                     │                  │                    │
    │ ─────────────────► │                     │                  │                    │
    │                    │ trigger event       │                  │                    │
    │                    │ ──────────────────► │                  │                    │
    │                    │                     │                  │                    │
    │                    │                     │ resolve env:     │                    │
    │                    │                     │ ENV_DIR=devel..  │                    │
    │                    │                     │ ACCOUNT_ID=111.. │                    │
    │                    │                     │                  │                    │
    │                    │                     │ request OIDC JWT │                    │
    │                    │ ◄────────────────── │                  │                    │
    │                    │ ──────────────────► │ JWT(sub:devel..) │                    │
    │                    │                     │                  │                    │
    │                    │                     │ AssumeRoleWith   │                    │
    │                    │                     │ WebIdentity      │                    │
    │                    │                     │ (RoleArn=111..   │                    │
    │                    │                     │  /gha-infra-     │                    │
    │                    │                     │  apply, JWT)     │                    │
    │                    │                     │ ───────────────► │                    │
    │                    │                     │                  │ verify JWT sig     │
    │                    │                     │                  │ check trust policy │
    │                    │                     │                  │ → match (development)│
    │                    │                     │ ◄─────────────── │                    │
    │                    │                     │ Temp creds (1h)  │                    │
    │                    │                     │                  │                    │
    │                    │                     │ terraform init   │                    │
    │                    │                     │ (read backend.tf │                    │
    │                    │                     │  → bucket=111..) │                    │
    │                    │                     │ ────────────────────────────────────► │
    │                    │                     │                  │ S3 GetObject       │
    │                    │                     │                  │ (state file)       │
    │                    │                     │ ◄──────────────────────────────────── │
    │                    │                     │ state contents   │                    │
    │                    │                     │                  │                    │
    │                    │                     │ S3 PutObject     │                    │
    │                    │                     │ (.tflock)        │                    │
    │                    │                     │ ────────────────────────────────────► │
    │                    │                     │                  │ lock acquired      │
    │                    │                     │                  │                    │
    │                    │                     │ terraform plan   │                    │
    │                    │                     │ + apply          │                    │
    │                    │                     │ ────────────────────────────────────► │
    │                    │                     │                  │ ec2:CreateVpc...   │
    │                    │                     │                  │ rds:CreateDBInst.. │
    │                    │                     │                  │ s3:CreateBucket.   │
    │                    │                     │                  │ (TẠO TRONG ACCOUNT │
    │                    │                     │                  │  111... vì creds   │
    │                    │                     │                  │  thuộc về 111...)  │
    │                    │                     │ ◄──────────────────────────────────── │
    │                    │                     │                  │                    │
    │                    │                     │ release lock     │                    │
    │                    │                     │ ────────────────────────────────────► │
    │                    │                     │                  │ S3 DeleteObject    │
    │                    │                     │                  │ (.tflock)          │
    │                    │                     │                  │                    │
    │                    │                     │ job done →       │                    │
    │                    │                     │ creds expire     │                    │
```

---

## Tóm lại

- **Trust anchor (T-7, manual)** = gốc, tạo OIDC + bootstrap role
- **bootstrap.yaml (T-1, CI/CD)** = dùng bootstrap role để tạo state bucket + 4 long-lived roles
- **terraform-*.yaml (T+0, CI/CD)** = dùng 4 long-lived roles để chạy Terraform hàng ngày

Mỗi lớp **không thể tồn tại** nếu lớp trên chưa được setup. Đây là chain of trust **bắt buộc tuần tự**.
