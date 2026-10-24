# Setup Guide — `3-tiers-app-infrastructure`

> Hướng dẫn từng bước từ **"có 2 AWS accounts"** đến **"production stack đã chạy"**. Theo đúng kiến trúc trong [ARCHITECTURE.md](ARCHITECTURE.md).

> **Quy ước:**
> - 🟢 **LOCAL** = chỉ edit code + git commit/push (không chạy command hạ tầng)
> - 🔴 **MANUAL** = thao tác AWS Console (DUY NHẤT 2 lần trong toàn bộ vòng đời dự án)
> - ✅ **CI/CD** = GitHub Actions tự động (hoặc trigger qua UI)

> **Giả định trước khi bắt đầu:**
> - Bạn đã có **2 AWS accounts**: development (`111111111111`), production (`222222222222`). Thay account ID này bằng giá trị thực của bạn xuyên suốt guide.
> - Bạn có quyền **root hoặc admin** trên cả 2 accounts (cần để upload trust anchor).
> - Bạn có **GitHub organization** (`myorg` — thay bằng tên thực).
> - Region mặc định: `ap-southeast-1` (Singapore). Đổi nếu cần.

---

## 📋 Mục lục

- [Phase 0: Chuẩn bị](#phase-0-chuẩn-bị)
- [Phase 1: Khởi tạo GitHub repo](#phase-1-khởi-tạo-github-repo)
- [Phase 2: Cấu hình GitHub Environments](#phase-2-cấu-hình-github-environments)
- [Phase 3: Viết CFN bootstrap templates](#phase-3-viết-cfn-bootstrap-templates)
- [Phase 4: Viết workflow bootstrap.yaml](#phase-4-viết-workflow-bootstrapyml)
- [Phase 5: 🔴 MANUAL — Upload trust anchor (DEVELOPMENT)](#phase-5--manual--upload-trust-anchor-development)
- [Phase 6: 🔴 MANUAL — Upload trust anchor (PRODUCTION)](#phase-6--manual--upload-trust-anchor-production)
- [Phase 7: ✅ CI/CD — Bootstrap account DEVELOPMENT](#phase-7--cicd--bootstrap-account-development)
- [Phase 8: ✅ CI/CD — Bootstrap account PRODUCTION](#phase-8--cicd--bootstrap-account-production)
- [Phase 9: Viết Terraform modules](#phase-9-viết-terraform-modules)
- [Phase 10: Viết envs/_shared + envs/development + envs/production](#phase-10-viết-envs_shared--envsdevelopment--envsproduction)
- [Phase 11: Viết workflows Terraform](#phase-11-viết-workflows-terraform)
- [Phase 12: First apply DEVELOPMENT](#phase-12-first-apply-development)
- [Phase 13: Promote PRODUCTION](#phase-13-promote-production)
- [Phase 14: Verify & vận hành](#phase-14-verify--vận-hành)

---

## Phase 0: Chuẩn bị

### 0.1. Tools cần cài trên máy local

| Tool | Phiên bản | Mục đích |
|------|-----------|----------|
| Git | >= 2.40 | Source control |
| Editor (VS Code, ...) | bất kỳ | Edit code |
| GitHub CLI `gh` (optional) | >= 2.40 | Tạo repo + cấu hình từ command line |

> **Không cài `terraform`, `aws-cli`, `cloudformation`** — không chạy gì local.

### 0.2. Thông tin cần thu thập trước

Ghi lại các giá trị này — bạn sẽ điền vào nhiều file:

```
GitHub org name:                   myorg
Infrastructure repo name:          3-tiers-app-infrastructure
Backend repo name:                 3-tiers-app-backend
Frontend repo name:                3-tiers-app-frontend

AWS account ID (development):      111111111111
AWS account ID (production):       222222222222
AWS region:                        ap-southeast-1

Domain (Route53, optional):        myapp.example.com
Default tag "Owner":               platform-team@myorg.com
Default tag "CostCenter":          CC-12345
```

### 0.3. Quyền AWS cần có

- **Account development:** root user hoặc IAM user/role có `AdministratorAccess`. Cần để **1 lần** upload trust anchor.
- **Account production:** tương tự.

Sau khi upload trust anchor, role admin này có thể được retire — tất cả tiếp theo qua OIDC.

---

## Phase 1: Khởi tạo GitHub repo

### 1.1. 🟢 LOCAL — Tạo repo trên GitHub

```bash
# Cách 1: qua GitHub web UI
# → New repository → name: 3-tiers-app-infrastructure → Private → Create

# Cách 2: qua gh CLI
gh repo create myorg/3-tiers-app-infrastructure --private --description "Terraform infra for 3-tiers app"
```

### 1.2. 🟢 LOCAL — Clone về máy

```bash
git clone https://github.com/myorg/3-tiers-app-infrastructure.git
cd 3-tiers-app-infrastructure
```

### 1.3. 🟢 LOCAL — Tạo file cơ sở

Tạo các file/thư mục skeleton:

```
3-tiers-app-infrastructure/
├── .github/
│   ├── workflows/        # Sẽ thêm sau
│   └── CODEOWNERS
├── bootstrap/            # CFN templates
├── modules/              # Terraform reusable
├── envs/                 # Per-env layer
│   ├── _shared/          # Shared TF code
│   ├── development/
│   └── production/
├── global/               # Optional: route53, app roles
├── scripts/
├── .gitignore
├── .terraform-version
├── .tflint.hcl
├── README.md
└── ARCHITECTURE.md       # Đã có
```

**`.gitignore`:**
```
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
tfplan
crash.log
.DS_Store
.env
```

**`.terraform-version`:**
```
1.13.3
```

**`.github/CODEOWNERS`:**
```
# Bootstrap CFN templates — chỉ DevOps lead approve
/bootstrap/                  @myorg/devops-leads
/.github/workflows/          @myorg/devops-leads

# Production env — sre-leads + devops
/envs/production/                  @myorg/sre-leads @myorg/devops-leads
/envs/_shared/               @myorg/devops-leads
/modules/                    @myorg/devops-leads

# Development env — bất cứ ai trong team infra
/envs/development/           @myorg/infra-team
```

### 1.4. 🟢 LOCAL — Tạo 2 long-lived branches

```bash
git checkout -b development
git push -u origin development

git checkout -b production
git push -u origin production

# Quay về development để làm việc tiếp
git checkout development
```

### 1.5. 🟢 LOCAL/UI — Cấu hình branch protection

**Trên GitHub UI** (Settings → Branches → Add rule):

**Rule cho `development`:**
- ✅ Require pull request before merging (≥1 reviewer)
- ✅ Require status checks: `sync-check`, `plan (development)`, `plan (production)`, `tflint`, `tfsec`
- ✅ Require linear history
- ❌ Allow force pushes
- ❌ Allow deletions

**Rule cho `production`:**
- ✅ Require pull request before merging (≥1 reviewer)
- ✅ Require status checks: `sync-check`, `plan (production)`, `tflint`, `tfsec`
- ✅ Require linear history (fast-forward only)
- ✅ Restrict who can push: chỉ `@myorg/sre-leads`
- ❌ Allow force pushes
- ❌ Allow deletions
- ✅ Do not allow bypassing the above settings (admin không bypass)

### 1.6. 🟢 LOCAL — Set default branch

GitHub UI → Settings → General → Default branch → đổi thành `development`.

---

## Phase 2: Cấu hình GitHub Environments

GitHub UI → Settings → Environments → New environment.

### 2.1. Environment `bootstrap`

| Setting | Value |
|---------|-------|
| Required reviewers | 1 (vd: DevOps lead) |
| Wait timer | 0 |
| Deployment branches | `main` only (hoặc `master` — branch chứa CFN templates) |
| Environment secrets | (none) |
| Environment variables | (none — sẽ set sau) |

### 2.2. Environment `development`

| Setting | Value |
|---------|-------|
| Required reviewers | 0 (auto-deploy) |
| Wait timer | 0 |
| Deployment branches | `development` only |
| Environment variables | `AWS_ACCOUNT_ID = 111111111111`<br>`AWS_REGION = ap-southeast-1` |

### 2.3. Environment `production`

| Setting | Value |
|---------|-------|
| Required reviewers | 1 (SRE lead) |
| Wait timer | 5 minutes |
| Deployment branches | `production` only |
| Environment variables | `AWS_ACCOUNT_ID = 222222222222`<br>`AWS_REGION = ap-southeast-1` |

> **Vì sao tách Environment:** Không thể bypass — workflow gắn `environment: production` muốn assume role production **bắt buộc** chạy từ branch `production`. Đây là tầng bảo vệ thứ 2 sau OIDC trust condition.

---

## Phase 3: Viết CFN bootstrap templates

### 3.1. 🟢 LOCAL — `bootstrap/01-trust-anchor.yaml`

**Đây là template DUY NHẤT bạn upload manual qua Console.** Tạo OIDC provider + role `gha-bootstrap`.

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: |
  Trust anchor cho GitHub Actions OIDC.
  MANUAL STEP DUY NHẤT — sau đó mọi thứ qua CI/CD.

Parameters:
  GitHubOrg:
    Type: String
    Default: myorg
    Description: GitHub organization name

  RepoName:
    Type: String
    Default: 3-tiers-app-infrastructure

Resources:
  GitHubOidcProvider:
    Type: AWS::IAM::OIDCProvider
    DeletionPolicy: Retain
    UpdateReplacePolicy: Retain
    Properties:
      Url: https://token.actions.githubusercontent.com
      ClientIdList:
        - sts.amazonaws.com
      ThumbprintList:
        - 6938fd4d98bab03faadb97b34396831e3780aea1
        - 1c58a3a8518e8759bf075b76b750d4f2df264fcd

  GhaBootstrapRole:
    Type: AWS::IAM::Role
    DeletionPolicy: Retain
    UpdateReplacePolicy: Retain
    Properties:
      RoleName: gha-bootstrap
      MaxSessionDuration: 3600
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Ref GitHubOidcProvider
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                'token.actions.githubusercontent.com:aud': sts.amazonaws.com
              StringLike:
                'token.actions.githubusercontent.com:sub':
                  !Sub "repo:${GitHubOrg}/${RepoName}:environment:bootstrap"
      Tags:
        - { Key: ManagedBy, Value: cloudformation }
        - { Key: Component, Value: trust-anchor }
        - { Key: Critical, Value: 'true' }

Outputs:
  OidcProviderArn:
    Value: !Ref GitHubOidcProvider
    Export: { Name: github-oidc-provider-arn }
  BootstrapRoleArn:
    Value: !GetAtt GhaBootstrapRole.Arn
    Export: { Name: gha-bootstrap-role-arn }
```

### 3.2. 🟢 LOCAL — `bootstrap/02-tfstate-backend.yaml`

S3 state bucket + KMS — deploy qua CI/CD.

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: Terraform state backend (S3 + KMS) — deployed by CI/CD

Resources:
  TfstateKmsKey:
    Type: AWS::KMS::Key
    DeletionPolicy: Retain
    UpdateReplacePolicy: Retain
    Properties:
      Description: !Sub "KMS for Terraform state encryption (${AWS::AccountId})"
      EnableKeyRotation: true
      PendingWindowInDays: 30
      KeyPolicy:
        Version: '2012-10-17'
        Statement:
          - Sid: EnableRootPermissions
            Effect: Allow
            Principal: { AWS: !Sub "arn:aws:iam::${AWS::AccountId}:root" }
            Action: 'kms:*'
            Resource: '*'

  TfstateKmsAlias:
    Type: AWS::KMS::Alias
    Properties:
      AliasName: alias/tfstate
      TargetKeyId: !Ref TfstateKmsKey

  TfstateBucket:
    Type: AWS::S3::Bucket
    DeletionPolicy: Retain
    UpdateReplacePolicy: Retain
    Properties:
      BucketName: !Sub "myorg-tfstate-${AWS::AccountId}"
      VersioningConfiguration:
        Status: Enabled
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - BucketKeyEnabled: true
            ServerSideEncryptionByDefault:
              SSEAlgorithm: aws:kms
              KMSMasterKeyID: !GetAtt TfstateKmsKey.Arn
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      LifecycleConfiguration:
        Rules:
          - Id: expire-noncurrent
            Status: Enabled
            NoncurrentVersionExpiration:
              NoncurrentDays: 90
            AbortIncompleteMultipartUpload:
              DaysAfterInitiation: 7
      Tags:
        - { Key: ManagedBy, Value: cloudformation }
        - { Key: Component, Value: tfstate-backend }
        - { Key: Critical, Value: 'true' }

  TfstateBucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref TfstateBucket
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Sid: DenyInsecureTransport
            Effect: Deny
            Principal: '*'
            Action: 's3:*'
            Resource:
              - !GetAtt TfstateBucket.Arn
              - !Sub "${TfstateBucket.Arn}/*"
            Condition:
              Bool: { 'aws:SecureTransport': 'false' }
          - Sid: DenyUnencryptedUploads
            Effect: Deny
            Principal: '*'
            Action: 's3:PutObject'
            Resource: !Sub "${TfstateBucket.Arn}/*"
            Condition:
              StringNotEquals:
                's3:x-amz-server-side-encryption': 'aws:kms'

Outputs:
  BucketName:
    Value: !Ref TfstateBucket
    Export: { Name: tfstate-bucket-name }
  BucketArn:
    Value: !GetAtt TfstateBucket.Arn
    Export: { Name: tfstate-bucket-arn }
  KmsKeyArn:
    Value: !GetAtt TfstateKmsKey.Arn
    Export: { Name: tfstate-kms-key-arn }
  KmsKeyAlias:
    Value: !Ref TfstateKmsAlias
    Export: { Name: tfstate-kms-key-alias }
```

### 3.3. 🟢 LOCAL — `bootstrap/03-github-oidc-roles.yaml`

Long-lived roles cho terraform CI + app deploy CI.

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: GitHub Actions OIDC roles — deployed by CI/CD

Parameters:
  GitHubOrg:
    Type: String
    Default: myorg
  InfraRepo:
    Type: String
    Default: 3-tiers-app-infrastructure
  BackendRepo:
    Type: String
    Default: 3-tiers-app-backend
  FrontendRepo:
    Type: String
    Default: 3-tiers-app-frontend
  AllowedBranch:
    Type: String
    AllowedValues: [development, production]
    Description: Branch được phép apply (development cho account development, production cho account production)
  TfstateBucketName:
    Type: String
  TfstateBucketArn:
    Type: String
  TfstateKmsKeyArn:
    Type: String

Resources:
  # ─── Plan role: read-only AWS + read/write tfstate ─────────────
  GhaInfraPlanRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: gha-infra-plan
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/ReadOnlyAccess
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Sub "arn:aws:iam::${AWS::AccountId}:oidc-provider/token.actions.githubusercontent.com"
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                'token.actions.githubusercontent.com:aud': sts.amazonaws.com
              StringLike:
                'token.actions.githubusercontent.com:sub':
                  !Sub "repo:${GitHubOrg}/${InfraRepo}:*"
      Policies:
        - PolicyName: tfstate-rw
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: [s3:ListBucket]
                Resource: !Ref TfstateBucketArn
              - Effect: Allow
                Action: [s3:GetObject, s3:PutObject, s3:DeleteObject]
                Resource:
                  - !Sub "${TfstateBucketArn}/3-tiers-app/*/terraform.tfstate"
                  - !Sub "${TfstateBucketArn}/3-tiers-app/*/terraform.tfstate.tflock"
              - Effect: Allow
                Action: [kms:Encrypt, kms:Decrypt, kms:GenerateDataKey, kms:DescribeKey]
                Resource: !Ref TfstateKmsKeyArn

  # ─── Apply role: Admin + tfstate (chỉ branch tương ứng) ────────
  GhaInfraApplyRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: gha-infra-apply
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Sub "arn:aws:iam::${AWS::AccountId}:oidc-provider/token.actions.githubusercontent.com"
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                'token.actions.githubusercontent.com:aud': sts.amazonaws.com
                'token.actions.githubusercontent.com:sub':
                  !Sub "repo:${GitHubOrg}/${InfraRepo}:ref:refs/heads/${AllowedBranch}"

  # ─── Backend deploy role (push ECR + ECS update) ───────────────
  GhaBackendDeployRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: gha-backend-deploy
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Sub "arn:aws:iam::${AWS::AccountId}:oidc-provider/token.actions.githubusercontent.com"
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                'token.actions.githubusercontent.com:aud': sts.amazonaws.com
                'token.actions.githubusercontent.com:sub':
                  !Sub "repo:${GitHubOrg}/${BackendRepo}:ref:refs/heads/${AllowedBranch}"
      Policies:
        - PolicyName: ecr-ecs-deploy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - ecr:GetAuthorizationToken
                  - ecr:BatchCheckLayerAvailability
                  - ecr:GetDownloadUrlForLayer
                  - ecr:BatchGetImage
                  - ecr:InitiateLayerUpload
                  - ecr:UploadLayerPart
                  - ecr:CompleteLayerUpload
                  - ecr:PutImage
                Resource: '*'
              - Effect: Allow
                Action:
                  - ecs:UpdateService
                  - ecs:DescribeServices
                  - ecs:DescribeTaskDefinition
                  - ecs:RegisterTaskDefinition
                  - ecs:RunTask
                Resource: '*'
              - Effect: Allow
                Action: [ssm:GetParameter, ssm:GetParameters, ssm:GetParametersByPath]
                Resource: !Sub "arn:aws:ssm:*:${AWS::AccountId}:parameter/3-tiers-app/*"
              - Effect: Allow
                Action: iam:PassRole
                Resource: !Sub "arn:aws:iam::${AWS::AccountId}:role/3-tiers-app-*"

  # ─── Frontend deploy role (S3 sync + CF invalidate) ────────────
  GhaFrontendDeployRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: gha-frontend-deploy
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Federated: !Sub "arn:aws:iam::${AWS::AccountId}:oidc-provider/token.actions.githubusercontent.com"
            Action: sts:AssumeRoleWithWebIdentity
            Condition:
              StringEquals:
                'token.actions.githubusercontent.com:aud': sts.amazonaws.com
                'token.actions.githubusercontent.com:sub':
                  !Sub "repo:${GitHubOrg}/${FrontendRepo}:ref:refs/heads/${AllowedBranch}"
      Policies:
        - PolicyName: s3-cf-deploy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: [s3:PutObject, s3:DeleteObject, s3:ListBucket, s3:GetObject]
                Resource:
                  - !Sub "arn:aws:s3:::3-tiers-app-frontend-${AWS::AccountId}"
                  - !Sub "arn:aws:s3:::3-tiers-app-frontend-${AWS::AccountId}/*"
              - Effect: Allow
                Action: cloudfront:CreateInvalidation
                Resource: '*'
              - Effect: Allow
                Action: [ssm:GetParameter, ssm:GetParameters]
                Resource: !Sub "arn:aws:ssm:*:${AWS::AccountId}:parameter/3-tiers-app/*"

Outputs:
  InfraPlanRoleArn:    { Value: !GetAtt GhaInfraPlanRole.Arn }
  InfraApplyRoleArn:   { Value: !GetAtt GhaInfraApplyRole.Arn }
  BackendDeployRoleArn:  { Value: !GetAtt GhaBackendDeployRole.Arn }
  FrontendDeployRoleArn: { Value: !GetAtt GhaFrontendDeployRole.Arn }
```

### 3.4. 🟢 LOCAL — `bootstrap/README.md`

```markdown
# Bootstrap CloudFormation stacks

## File đây làm gì

| File | Provision qua | Tần suất |
|------|---------------|----------|
| `01-trust-anchor.yaml` | 🔴 MANUAL Console | 1 lần per account |
| `02-tfstate-backend.yaml` | ✅ CI/CD `bootstrap.yaml` | 1 lần đầu + khi update |
| `03-github-oidc-roles.yaml` | ✅ CI/CD `bootstrap.yaml` | 1 lần đầu + khi update |

## Quy trình deploy

1. Cloud admin upload `01-trust-anchor.yaml` qua AWS Console (xem SETUP-GUIDE Phase 5 + 6)
2. DevOps trigger workflow `bootstrap.yaml` qua GitHub Actions UI (xem SETUP-GUIDE Phase 7 + 8)

KHÔNG chạy `aws` hay `terraform` trên máy local.
```

### 3.5. 🟢 LOCAL — Commit lần đầu

```bash
git add bootstrap/ .github/CODEOWNERS .gitignore .terraform-version
git commit -m "feat: initial scaffolding + bootstrap CFN templates"
git push origin development
```

---

## Phase 4: Viết workflow `bootstrap.yaml`

### 4.1. 🟢 LOCAL — `.github/workflows/bootstrap.yaml`

```yaml
name: Bootstrap (CFN — state backend + OIDC roles)

on:
  workflow_dispatch:
    inputs:
      account:
        description: 'Target AWS account'
        type: choice
        required: true
        options: [development, production]

permissions:
  id-token: write
  contents: read

jobs:
  bootstrap:
    runs-on: ubuntu-latest
    environment: bootstrap        # ← buộc đi qua manual approval 1 reviewer
    env:
      AWS_REGION: ap-southeast-1
      ACCOUNT_ID: ${{ inputs.account == 'production' && '222222222222' || '111111111111' }}
      ALLOWED_BRANCH: ${{ inputs.account == 'production' && 'production' || 'development' }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (assume gha-bootstrap)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ env.ACCOUNT_ID }}:role/gha-bootstrap
          aws-region: ${{ env.AWS_REGION }}

      - name: Verify caller identity
        run: aws sts get-caller-identity

      - name: Deploy stack 02-tfstate-backend
        run: |
          aws cloudformation deploy \
            --stack-name tfstate-backend \
            --template-file bootstrap/02-tfstate-backend.yaml \
            --capabilities CAPABILITY_NAMED_IAM \
            --no-fail-on-empty-changeset

      - name: Read outputs from tfstate-backend
        id: tfstate
        run: |
          BUCKET=$(aws cloudformation describe-stacks --stack-name tfstate-backend \
            --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)
          BUCKET_ARN=$(aws cloudformation describe-stacks --stack-name tfstate-backend \
            --query 'Stacks[0].Outputs[?OutputKey==`BucketArn`].OutputValue' --output text)
          KMS_ARN=$(aws cloudformation describe-stacks --stack-name tfstate-backend \
            --query 'Stacks[0].Outputs[?OutputKey==`KmsKeyArn`].OutputValue' --output text)
          echo "bucket=$BUCKET" >> $GITHUB_OUTPUT
          echo "bucket_arn=$BUCKET_ARN" >> $GITHUB_OUTPUT
          echo "kms_arn=$KMS_ARN" >> $GITHUB_OUTPUT

      - name: Deploy stack 03-github-oidc-roles
        run: |
          aws cloudformation deploy \
            --stack-name github-oidc-roles \
            --template-file bootstrap/03-github-oidc-roles.yaml \
            --capabilities CAPABILITY_NAMED_IAM \
            --no-fail-on-empty-changeset \
            --parameter-overrides \
              AllowedBranch=${{ env.ALLOWED_BRANCH }} \
              TfstateBucketName=${{ steps.tfstate.outputs.bucket }} \
              TfstateBucketArn=${{ steps.tfstate.outputs.bucket_arn }} \
              TfstateKmsKeyArn=${{ steps.tfstate.outputs.kms_arn }}

      - name: Print role ARNs
        run: |
          aws cloudformation describe-stacks --stack-name github-oidc-roles \
            --query 'Stacks[0].Outputs' --output table
```

### 4.2. 🟢 LOCAL — Commit & push

```bash
git add .github/workflows/bootstrap.yaml
git commit -m "ci: add bootstrap workflow"
git push origin development

# Merge vào main/master để workflow chạy được trong Environment "bootstrap"
# (Environment bootstrap restricted to branch main)
gh pr create --base main --head development --title "Initial bootstrap setup"
# Sau khi merge PR này, branch main sẽ có workflow + CFN templates
```

> **Lưu ý:** Environment `bootstrap` restrict deployment branch = `main`. Nếu repo không có branch `main`, hãy đổi restriction sang branch chứa workflow.

---

## Phase 5: 🔴 MANUAL — Upload trust anchor (DEVELOPMENT)

**Đây là 1 trong 2 manual step duy nhất.**

### 5.1. Login Console account development

1. Mở browser → https://signin.aws.amazon.com/
2. Login với credentials admin của account **development** (`111111111111`)
3. Confirm góc phải header hiển thị account ID đúng

### 5.2. Switch region

Header → chọn region **`Asia Pacific (Singapore) ap-southeast-1`**.

### 5.3. Mở CloudFormation

Search bar trên header → gõ "CloudFormation" → click.

### 5.4. Create stack

1. Click **Create stack** → **With new resources (standard)**
2. **Prepare template:** "Choose an existing template"
3. **Specify template:** "Upload a template file"
4. Click **Choose file** → chọn file `bootstrap/01-trust-anchor.yaml` từ máy local
5. Click **Next**

### 5.5. Specify stack details

| Field | Value |
|-------|-------|
| Stack name | `trust-anchor` |
| GitHubOrg | `myorg` (đổi theo thực tế) |
| RepoName | `3-tiers-app-infrastructure` |

Click **Next**.

### 5.6. Configure stack options

- **Tags** (tự thêm để track):
  - `Project = 3-tiers-app`
  - `ManagedBy = cloudformation`
  - `Critical = true`
- **Permissions**: bỏ trống (dùng credentials hiện tại)
- **Stack failure options**: Roll back all stack resources (default)

Click **Next**.

### 5.7. Review & create

- ✅ Tick **"I acknowledge that AWS CloudFormation might create IAM resources with custom names"**
- Click **Submit**

### 5.8. Chờ CREATE_COMPLETE

- Stack hiện status `CREATE_IN_PROGRESS` → sau ~30 giây → `CREATE_COMPLETE`
- Tab **Resources** sẽ hiển thị: `GitHubOidcProvider`, `GhaBootstrapRole`
- Tab **Outputs**: copy `BootstrapRoleArn` (sẽ giống `arn:aws:iam::111111111111:role/gha-bootstrap`)

### 5.9. Verify

Tab **Resources** → click `GhaBootstrapRole` → ARN phải chính xác `arn:aws:iam::111111111111:role/gha-bootstrap`.

### 5.10. Logout

Header → tên user → **Sign out**.

---

## Phase 6: 🔴 MANUAL — Upload trust anchor (PRODUCTION)

**Lặp lại y hệt Phase 5 với account production.**

1. Login Console với credentials admin **account production** (`222222222222`)
2. Lặp lại 5.2 → 5.8
3. Stack name: `trust-anchor` (cùng tên, nhưng nằm ở account khác)
4. Verify role ARN: `arn:aws:iam::222222222222:role/gha-bootstrap`
5. Logout

**🎉 Phase 5 + 6 là MANUAL STEPS DUY NHẤT trong toàn bộ vòng đời.** Mọi thứ tiếp theo qua CI/CD.

---

## Phase 7: ✅ CI/CD — Bootstrap account DEVELOPMENT

### 7.1. Trigger workflow qua GitHub UI

1. Mở https://github.com/myorg/3-tiers-app-infrastructure/actions
2. Sidebar trái → click workflow **"Bootstrap (CFN — state backend + OIDC roles)"**
3. Click **Run workflow** (button bên phải)
4. **Use workflow from:** branch `main` (hoặc `master`)
5. **Target AWS account:** chọn `development`
6. Click **Run workflow**

### 7.2. Approve trong Environment `bootstrap`

1. Workflow run xuất hiện → click vào nó
2. Status: **"Waiting for review"**
3. Reviewer click **Review deployments** → tick `bootstrap` → **Approve and deploy**
4. Workflow tiếp tục chạy → ~2 phút → **CREATE_COMPLETE** cho cả 2 stacks

### 7.3. Verify trong AWS Console

(Chỉ để debug — không bắt buộc, có thể skip)

Login Console development → CloudFormation → 2 stacks mới: `tfstate-backend`, `github-oidc-roles`. Cả 2 status `CREATE_COMPLETE`.

S3 → tìm bucket `myorg-tfstate-111111111111` (đã tạo).

IAM → Roles → tìm `gha-infra-plan`, `gha-infra-apply`, `gha-backend-deploy`, `gha-frontend-deploy` (đã tạo).

---

## Phase 8: ✅ CI/CD — Bootstrap account PRODUCTION

Lặp lại Phase 7 với input `account=production`.

Sau Phase 8:
- Account development: có S3 bucket + KMS + 4 OIDC roles
- Account production: có S3 bucket + KMS + 4 OIDC roles
- **Tất cả các stack `apply Terraform` từ giờ chạy được qua CI/CD.**

---

## Phase 9: Viết Terraform modules

### 9.1. 🟢 LOCAL — Cấu trúc modules

```
modules/
├── network/
├── ecr/
├── rds/
├── ecs-cluster/
├── ecs-service/
├── alb/
├── frontend-cdn/
├── iam-app-roles/
└── observability/
```

Mỗi module có 5 file: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`.

### 9.2. 🟢 LOCAL — Skeleton module (ví dụ `network`)

**`modules/network/versions.tf`:**
```hcl
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}
```

**`modules/network/variables.tf`:**
```hcl
variable "environment" {
  type        = string
  description = "Tên environment (development, production)"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 3
}

# BYO pattern — nhận VPC/subnets có sẵn nếu account đã được cung cấp
variable "existing_vpc_id" {
  type        = string
  default     = null
  description = "Nếu set, dùng VPC này thay vì tạo mới"
}

variable "existing_private_subnet_ids" {
  type    = list(string)
  default = null
}

variable "existing_public_subnet_ids" {
  type    = list(string)
  default = null
}
```

**`modules/network/main.tf`:**
```hcl
locals {
  create_vpc = var.existing_vpc_id == null
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  count                = local.create_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.environment}-vpc" }
}

data "aws_vpc" "existing" {
  count = local.create_vpc ? 0 : 1
  id    = var.existing_vpc_id
}

# Public subnets (chỉ tạo nếu create_vpc)
resource "aws_subnet" "public" {
  count                   = local.create_vpc ? var.az_count : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.environment}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count             = local.create_vpc ? var.az_count : 0
  vpc_id            = aws_vpc.this[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + var.az_count)
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.environment}-private-${local.azs[count.index]}" }
}

# Internet GW + NAT GW + route tables — bỏ qua chi tiết, follow AWS-VPC module pattern
# ... (xem module github.com/terraform-aws-modules/terraform-aws-vpc cho reference)
```

**`modules/network/outputs.tf`:**
```hcl
output "vpc_id" {
  value = local.create_vpc ? aws_vpc.this[0].id : data.aws_vpc.existing[0].id
}

output "private_subnet_ids" {
  value = local.create_vpc ? aws_subnet.private[*].id : var.existing_private_subnet_ids
}

output "public_subnet_ids" {
  value = local.create_vpc ? aws_subnet.public[*].id : var.existing_public_subnet_ids
}
```

> **Tip:** Thay vì viết module `network` từ scratch, có thể dùng `terraform-aws-modules/vpc/aws` (community module phổ biến nhất) wrap thêm BYO logic. Module `rds`, `alb`, `ecs` cũng có community modules tương tự.

### 9.3. Các modules khác — pattern tương tự

| Module | Resources chính | BYO biến |
|--------|----------------|-----------|
| `ecr` | `aws_ecr_repository` + lifecycle policy | `existing_ecr_repo_url` |
| `rds` | `aws_db_subnet_group`, `aws_db_instance` (PostgreSQL) | `existing_kms_key_arn` |
| `ecs-cluster` | `aws_ecs_cluster` + capacity providers | — |
| `ecs-service` | `aws_ecs_task_definition`, `aws_ecs_service` | `existing_task_exec_role_arn` |
| `alb` | `aws_lb`, `aws_lb_listener`, `aws_lb_target_group` | `existing_acm_cert_arn` |
| `frontend-cdn` | `aws_s3_bucket`, `aws_cloudfront_distribution` + OAC | `existing_acm_cert_arn`, `existing_hosted_zone_id` |
| `iam-app-roles` | Task exec role, task role | `existing_task_exec_role_arn` |
| `observability` | CW log groups, metric alarms, dashboards | — |

(Phạm vi guide này chỉ skeleton — bạn fill dần theo feature cần.)

---

## Phase 10: Viết `envs/_shared` + `envs/development` + `envs/production`

### 10.1. 🟢 LOCAL — `envs/_shared/versions.tf`

```hcl
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
  }
}
```

### 10.2. 🟢 LOCAL — `envs/_shared/variables.tf`

```hcl
variable "environment" { type = string }
variable "region"      { type = string }

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "existing_vpc_id"             { type = string,       default = null }
variable "existing_private_subnet_ids" { type = list(string), default = null }
variable "existing_public_subnet_ids"  { type = list(string), default = null }

variable "rds_instance_class" { type = string, default = "db.t4g.small" }
variable "rds_multi_az"       { type = bool,   default = false }
variable "rds_storage_gb"     { type = number, default = 20 }

variable "ecs_task_cpu"      { type = number, default = 512 }
variable "ecs_task_memory"   { type = number, default = 1024 }
variable "ecs_desired_count" { type = number, default = 1 }

variable "domain_name" { type = string, default = null }

variable "tags" {
  type    = map(string)
  default = {}
}
```

### 10.3. 🟢 LOCAL — `envs/_shared/main.tf`

```hcl
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = "3-tiers-app"
    ManagedBy   = "terraform"
  })
}

module "network" {
  source = "../../modules/network"

  environment                  = var.environment
  vpc_cidr                     = var.vpc_cidr
  existing_vpc_id              = var.existing_vpc_id
  existing_private_subnet_ids  = var.existing_private_subnet_ids
  existing_public_subnet_ids   = var.existing_public_subnet_ids
}

module "ecr_backend" {
  source      = "../../modules/ecr"
  environment = var.environment
  repo_name   = "3-tiers-app-backend"
}

module "rds" {
  source            = "../../modules/rds"
  environment       = var.environment
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  instance_class    = var.rds_instance_class
  multi_az          = var.rds_multi_az
  allocated_storage = var.rds_storage_gb
}

module "ecs_cluster" {
  source      = "../../modules/ecs-cluster"
  environment = var.environment
}

module "alb" {
  source             = "../../modules/alb"
  environment        = var.environment
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  domain_name        = var.domain_name
}

module "ecs_service" {
  source              = "../../modules/ecs-service"
  environment         = var.environment
  cluster_name        = module.ecs_cluster.cluster_name
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  alb_target_group_arn = module.alb.target_group_arn
  alb_security_group_id = module.alb.security_group_id
  ecr_repository_url  = module.ecr_backend.repository_url
  rds_endpoint        = module.rds.endpoint
  rds_secret_arn      = module.rds.secret_arn
  task_cpu            = var.ecs_task_cpu
  task_memory         = var.ecs_task_memory
  desired_count       = var.ecs_desired_count
}

module "frontend_cdn" {
  source           = "../../modules/frontend-cdn"
  environment      = var.environment
  domain_name      = var.domain_name
}
```

### 10.4. 🟢 LOCAL — `envs/_shared/outputs.tf`

Publish các outputs lên SSM cho app repos đọc:

```hcl
resource "aws_ssm_parameter" "ecs_cluster_name" {
  name  = "/3-tiers-app/${var.environment}/ecs/cluster_name"
  type  = "String"
  value = module.ecs_cluster.cluster_name
}

resource "aws_ssm_parameter" "ecs_service_name" {
  name  = "/3-tiers-app/${var.environment}/ecs/service_name"
  type  = "String"
  value = module.ecs_service.service_name
}

resource "aws_ssm_parameter" "ecr_backend_url" {
  name  = "/3-tiers-app/${var.environment}/ecr/backend_url"
  type  = "String"
  value = module.ecr_backend.repository_url
}

resource "aws_ssm_parameter" "frontend_bucket" {
  name  = "/3-tiers-app/${var.environment}/frontend/bucket_name"
  type  = "String"
  value = module.frontend_cdn.bucket_name
}

resource "aws_ssm_parameter" "cloudfront_distribution_id" {
  name  = "/3-tiers-app/${var.environment}/frontend/cloudfront_id"
  type  = "String"
  value = module.frontend_cdn.distribution_id
}

resource "aws_ssm_parameter" "alb_dns_name" {
  name  = "/3-tiers-app/${var.environment}/alb/dns_name"
  type  = "String"
  value = module.alb.dns_name
}

# Output cho Terraform layer (nếu cần expose ngoài)
output "ecs_cluster_name"    { value = module.ecs_cluster.cluster_name }
output "alb_dns_name"        { value = module.alb.dns_name }
output "frontend_bucket"     { value = module.frontend_cdn.bucket_name }
```

### 10.5. 🟢 LOCAL — `envs/development/backend.tf`

```hcl
terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "myorg-tfstate-111111111111"
    key          = "3-tiers-app/development/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    kms_key_id   = "alias/tfstate"
    use_lockfile = true
  }
}
```

### 10.6. 🟢 LOCAL — `envs/development/providers.tf`

```hcl
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "3-tiers-app"
      ManagedBy   = "terraform"
    }
  }
}
```

> **Lưu ý:** Không có `assume_role` block ở đây — workflow `terraform-apply.yaml` sẽ assume role `gha-infra-apply` qua `aws-actions/configure-aws-credentials` trước khi chạy `terraform`.

### 10.7. 🟢 LOCAL — `envs/development/main.tf`

```hcl
module "stack" {
  source = "../_shared"

  environment                  = var.environment
  region                       = var.region
  vpc_cidr                     = var.vpc_cidr
  existing_vpc_id              = var.existing_vpc_id
  existing_private_subnet_ids  = var.existing_private_subnet_ids
  existing_public_subnet_ids   = var.existing_public_subnet_ids
  rds_instance_class           = var.rds_instance_class
  rds_multi_az                 = var.rds_multi_az
  rds_storage_gb               = var.rds_storage_gb
  ecs_task_cpu                 = var.ecs_task_cpu
  ecs_task_memory              = var.ecs_task_memory
  ecs_desired_count            = var.ecs_desired_count
  domain_name                  = var.domain_name
  tags                         = var.tags
}
```

### 10.8. 🟢 LOCAL — `envs/development/variables.tf`

Khai báo lại đầy đủ các variable (Terraform yêu cầu var phải declare ở root). Có thể copy từ `_shared/variables.tf`.

### 10.9. 🟢 LOCAL — `envs/development/terraform.tfvars`

```hcl
environment = "development"
region      = "ap-southeast-1"

# Trường hợp 1 (account rỗng — tự tạo VPC)
vpc_cidr = "10.10.0.0/16"
# existing_vpc_id = null  (default)

# Hoặc Trường hợp 2 (account có sẵn VPC)
# existing_vpc_id             = "vpc-0abc..."
# existing_private_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
# existing_public_subnet_ids  = ["subnet-ddd", "subnet-eee", "subnet-fff"]

rds_instance_class = "db.t4g.small"
rds_multi_az       = false
rds_storage_gb     = 20

ecs_task_cpu      = 512
ecs_task_memory   = 1024
ecs_desired_count = 1

# domain_name = "development.myapp.example.com"

tags = {
  Owner      = "platform-team@myorg.com"
  CostCenter = "CC-12345"
}
```

### 10.10. 🟢 LOCAL — `envs/production/`

Copy từ `envs/development/`, đổi:
- `backend.tf`: `bucket = "myorg-tfstate-222222222222"`, `key = "3-tiers-app/production/terraform.tfstate"`
- `main.tf`: **GIỐNG HỆT** `envs/development/main.tf` (bit-for-bit)
- `variables.tf`: **GIỐNG HỆT**
- `terraform.tfvars`: giá trị production:

```hcl
environment = "production"
region      = "ap-southeast-1"

vpc_cidr = "10.20.0.0/16"

rds_instance_class = "db.r6g.large"
rds_multi_az       = true
rds_storage_gb     = 100

ecs_task_cpu      = 2048
ecs_task_memory   = 4096
ecs_desired_count = 3

# domain_name = "myapp.example.com"

tags = {
  Owner      = "platform-team@myorg.com"
  CostCenter = "CC-12345"
}
```

### 10.11. 🟢 LOCAL — `scripts/verify-envs-in-sync.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

FILES=(main.tf variables.tf)

for f in "${FILES[@]}"; do
  if ! diff -q "envs/development/$f" "envs/production/$f" > /dev/null; then
    echo "ERROR: envs/development/$f và envs/production/$f phải IDENTICAL"
    diff "envs/development/$f" "envs/production/$f" || true
    exit 1
  fi
done

echo "OK: envs/development và envs/production đồng bộ."
```

```bash
chmod +x scripts/verify-envs-in-sync.sh
```

### 10.12. 🟢 LOCAL — Commit

```bash
git checkout -b feat/initial-infra
git add modules/ envs/ scripts/
git commit -m "feat: initial modules + envs/_shared + envs/{development,production}"
git push origin feat/initial-infra
```

---

## Phase 11: Viết workflows Terraform

### 11.1. 🟢 LOCAL — `.github/workflows/terraform-plan.yaml`

```yaml
name: Terraform Plan

on:
  pull_request:
    branches: [development, production]
    paths: ['envs/**', 'modules/**', 'scripts/**']

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  sync-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash scripts/verify-envs-in-sync.sh

  plan:
    needs: sync-check
    strategy:
      fail-fast: false
      matrix:
        include:
          - { env: development, account_id: '111111111111' }
          - { env: production, account_id: '222222222222' }
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: envs/${{ matrix.env }}
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.13.3

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ matrix.account_id }}:role/gha-infra-plan
          aws-region: ap-southeast-1

      - run: terraform init -no-color
      - run: terraform fmt -check -recursive
        working-directory: .
      - run: terraform validate -no-color
      - id: plan
        run: terraform plan -no-color -out=tfplan -input=false
        continue-on-error: true

      - name: Comment plan on PR
        uses: actions/github-script@v7
        with:
          script: |
            const output = `### Terraform Plan — \`${{ matrix.env }}\` ${{ steps.plan.outcome == 'success' && '✅' || '❌' }}\n\n<details><summary>Plan output</summary>\n\n\`\`\`\n${{ steps.plan.outputs.stdout }}\n\`\`\`\n\n</details>`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            });

      - if: steps.plan.outcome == 'failure'
        run: exit 1
```

### 11.2. 🟢 LOCAL — `.github/workflows/terraform-apply.yaml`

```yaml
name: Terraform Apply

on:
  push:
    branches: [development, production]
    paths: ['envs/**', 'modules/**']

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: ${{ github.ref == 'refs/heads/production' && 'production' || 'development' }}
    env:
      ENV_DIR: ${{ github.ref == 'refs/heads/production' && 'production' || 'development' }}
      ACCOUNT_ID: ${{ github.ref == 'refs/heads/production' && '222222222222' || '111111111111' }}
    defaults:
      run:
        working-directory: envs/${{ env.ENV_DIR }}
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.13.3

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ env.ACCOUNT_ID }}:role/gha-infra-apply
          aws-region: ap-southeast-1

      - run: terraform init -no-color
      - run: terraform plan -no-color -out=tfplan -input=false
      - run: terraform apply -no-color -input=false tfplan
```

### 11.3. 🟢 LOCAL — `.github/workflows/terraform-drift.yaml`

```yaml
name: Terraform Drift Detection

on:
  schedule:
    - cron: '0 18 * * *'   # 01:00 ICT mỗi ngày
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  drift:
    strategy:
      fail-fast: false
      matrix:
        include:
          - { env: development, ref: development, account_id: '111111111111' }
          - { env: production, ref: production, account_id: '222222222222' }
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: envs/${{ matrix.env }}
    steps:
      - uses: actions/checkout@v4
        with: { ref: ${{ matrix.ref }} }
      - uses: hashicorp/setup-terraform@v3
        with: { terraform_version: 1.13.3 }
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ matrix.account_id }}:role/gha-infra-plan
          aws-region: ap-southeast-1
      - run: terraform init -no-color
      - run: terraform plan -detailed-exitcode -no-color
        # exit code 0 = no diff, 2 = diff (drift). Fail step nếu = 2.
```

### 11.4. 🟢 LOCAL — Commit

```bash
git add .github/workflows/
git commit -m "ci: add terraform plan/apply/drift workflows"
git push origin feat/initial-infra
```

---

## Phase 12: First apply DEVELOPMENT

### 12.1. 🟢 LOCAL — Mở PR

```bash
gh pr create \
  --base development \
  --head feat/initial-infra \
  --title "feat: initial infrastructure" \
  --body "Initial infra: VPC, RDS, ECS, ALB, S3+CF for both development and production"
```

### 12.2. ✅ CI/CD — Plan tự chạy

PR mới → workflow `terraform-plan.yaml` chạy:
- Job `sync-check` → pass (envs đồng bộ)
- Job `plan (development)` → comment vào PR với plan development
- Job `plan (production)` → comment với plan production (cùng code, account khác)

### 12.3. Reviewer review plan

- Đọc 2 comments plan (development + production)
- Xác nhận resources sẽ tạo phù hợp
- Approve PR

### 12.4. ✅ CI/CD — Merge → Apply DEVELOPMENT

- Merge PR → `development` branch
- Workflow `terraform-apply.yaml` trigger:
  - Environment = `development` (auto, không cần approve)
  - Assume role `gha-infra-apply` ở account development
  - `terraform apply` → ~10-15 phút (RDS chậm nhất)
- Status: `Success` → infra development đã sẵn sàng

### 12.5. ✅ CI/CD — Verify

(Optional) Login Console development → kiểm tra:
- VPC: tag `Environment=development` đã tạo
- RDS: instance đang chạy
- ECS cluster: đã tạo (chưa có service vì chưa có image)
- S3 bucket frontend: đã tạo
- CloudFront distribution: đã tạo
- SSM Parameter Store: 6 parameters dưới `/3-tiers-app/development/...`

---

## Phase 13: Promote PRODUCTION

### 13.1. 🟢 LOCAL — Mở PR `development → production`

```bash
gh pr create \
  --base production \
  --head development \
  --title "promote: development → production (initial infra)" \
  --body "Promote initial infra to production after development verified"
```

### 13.2. ✅ CI/CD — Plan production tự chạy

PR mới → `terraform-plan.yaml`:
- `sync-check` pass
- `plan (production)` comment vào PR

### 13.3. SRE leads review

- 1 reviewer approve
- Đọc plan production kỹ (instance lớn, multi-AZ, ...)

### 13.4. ✅ CI/CD — Merge → Apply PRODUCTION

- Merge PR (fast-forward only)
- Workflow `terraform-apply.yaml` trigger với `environment: production`
- **Pause:** Environment `production` yêu cầu manual approval 1 reviewer + wait timer 5 phút
- Sau approve → `terraform apply` chạy ở account production
- ~15-20 phút → done

### 13.5. ✅ Verify

(Optional) Login Console production → kiểm tra resources giống bước 12.5 nhưng ở scale production.

---

## Phase 14: Verify & vận hành

### 14.1. Smoke tests

- Backend `curl` ALB DNS từ máy local: `curl https://<alb-dns>/health` (nếu app có endpoint)
- Frontend: mở `https://<cloudfront-domain>/` (sẽ trắng vì chưa upload — chờ frontend deploy)

### 14.2. Drift detection

- Workflow `terraform-drift.yaml` chạy hàng đêm 01:00 ICT
- Nếu detect drift → step fail → notify Slack (cấu hình thêm step Slack notification)

### 14.3. Update infrastructure

```
Dev workflow:
  feat/x → PR vào development
  → CI plan (development + production) comment vào PR
  → 1 reviewer approve → merge
  → Auto-apply development account ✅

Promote:
  PR development → production
  → CI plan (production) comment vào PR
  → 1 SRE lead approve → merge
  → Manual approve trong Environment "production" → wait 5min
  → Apply production account ✅
```

### 14.4. Update bootstrap stacks (rare)

Nếu cần update `bootstrap/02-tfstate-backend.yaml` hoặc `03-github-oidc-roles.yaml`:
1. Edit YAML, push lên branch `main`
2. Tab Actions → "Bootstrap" → Run workflow → chọn account
3. 1 reviewer approve trong Environment `bootstrap`
4. CI redeploy CFN stack (idempotent)

### 14.5. Update trust anchor (very rare)

Chỉ khi:
- Rotate OIDC thumbprint (GitHub đổi cert)
- Chuyển org name

→ Manual qua Console (giống Phase 5/6).

---

## 🎯 Tóm tắt

**Tổng thao tác manual provision hạ tầng trong toàn bộ vòng đời dự án:**
- Phase 5: 1 lần upload CFN qua Console (account development) — ~5 phút
- Phase 6: 1 lần upload CFN qua Console (account production) — ~5 phút

**Tất cả còn lại** (state bucket, KMS, OIDC roles, VPC, RDS, ECS, ALB, S3+CF, monitoring, drift detection, app deploy) đều qua **GitHub Actions CI/CD**.

**Code-only workflow:**
- Edit `.tf` / `.yaml` files
- Commit + push
- Tạo PR
- Reviewer approve trong GitHub UI
- Watch CI logs

→ Không bao giờ chạy `terraform`, `aws-cli`, hoặc bất cứ command provision hạ tầng nào trên máy local.
