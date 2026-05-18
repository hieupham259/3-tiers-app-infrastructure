# Sprint S01 - Patch gha-infra-plan Role

## Muc tieu

Them inline policy `secrets-read-for-refresh` vao `GhaInfraPlanRole` trong `bootstrap/03-github-oidc-roles.yaml` de cho phep `secretsmanager:GetSecretValue` tren path `/3-tiers-app/*`. Sau khi user redeploy CFN stack bootstrap, pipeline `terraform plan` co the refresh state ma khong bi AccessDenied.

Day la dieu kien tien quyet bat buoc (BLOCKER) cho S02: destroy plan cung can refresh state truoc khi tinh toan diff.

## Pre-conditions

- Branch `feature/phased-deploy-s03-rds-iam` hien tai (commit `9ff2855`) la noi dang bi loi.
- User se tao 1 PR moi tu branch nay (hoac branch moi tach ra) cho Phase 1 de merge vao `development`.
- CFN stack bootstrap da ton tai tren AWS account `development` va deploy duoc bang `aws cloudformation deploy`.

## Files bi anh huong

- `bootstrap/03-github-oidc-roles.yaml` (lines 54-69, block `Policies` cua `GhaInfraPlanRole`)

## Sub-tasks

- [x] S01-T01 - Them inline policy `secrets-read-for-refresh` vao `GhaInfraPlanRole` trong `bootstrap/03-github-oidc-roles.yaml`
  - Assignee: iac-builder
  - Inputs / preconditions: `bootstrap/03-github-oidc-roles.yaml` hien tai (da xac nhan o tren: `GhaInfraPlanRole.Properties.Policies` hien chi co 1 item la `tfstate-rw` o lines 55-69)
  - Outputs / artifacts: `bootstrap/03-github-oidc-roles.yaml` voi policy thu 2 duoc append vao list `Policies` cua `GhaInfraPlanRole`:
    ```yaml
    - PolicyName: secrets-read-for-refresh
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Action: secretsmanager:GetSecretValue
            Resource: !Sub "arn:aws:secretsmanager:*:${AWS::AccountId}:secret:/3-tiers-app/*"
    ```
  - Depends on: none
  - Notes: Chi them policy nay vao `GhaInfraPlanRole`, khong cham vao `GhaInfraApplyRole` hay cac role khac. Scope resource phai dung `!Sub "arn:aws:secretsmanager:*:${AWS::AccountId}:secret:/3-tiers-app/*"` (dung CloudFormation Fn::Sub, khong hardcode account ID). Day la inline policy TAM THOI se bi xoa o S04.

- [x] S01-T02 - Review diff S01-T01
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S01-T01
  - Outputs / artifacts: tick checkbox; bao cao findings neu co; reassign neu co van de
  - Depends on: S01-T01
  - Notes: Kiem tra dac biet: (1) scope resource cua `secretsmanager:GetSecretValue` phai la path `/3-tiers-app/*` cua account cu the, khong duoc dung `"*"` (over-permissive); (2) policy chi anh huong `GhaInfraPlanRole`, khong lam anh huong `GhaInfraApplyRole`; (3) khong co account ID hardcode (phai dung `!Sub "${AWS::AccountId}"`).

- [x] S01-T03 - User: redeploy CFN stack bootstrap tren AWS account `development`
  - Assignee: user
  - Inputs / preconditions: S01-T02 approve; PR da merge vao `development`
  - Outputs / artifacts: CFN stack update thanh cong; IAM role `gha-infra-plan` tren AWS Console co inline policy `secrets-read-for-refresh`
  - Depends on: S01-T02
  - Notes: |
      Quy trinh thu cong:
      1. Merge PR chua S01-T01 vao branch `development`.
      2. Xac dinh ten CFN stack bootstrap: xem `.github/workflows/bootstrap.yaml` hoac AWS Console > CloudFormation.
      3. Chay deploy:
         ```
         aws cloudformation deploy \
           --template-file bootstrap/03-github-oidc-roles.yaml \
           --stack-name <ten-stack> \
           --capabilities CAPABILITY_NAMED_IAM \
           --parameter-overrides GitHubOrg=<org> InfraRepo=<repo> AllowedBranch=development \
             TfstateBucketName=<bucket> TfstateBucketArn=<arn> TfstateKmsKeyArn=<arn> \
           --region us-east-1 \
           --profile <dev-profile>
         ```
      4. Verify: vao IAM Console > Roles > `gha-infra-plan` > tab Permissions, xac nhan inline policy `secrets-read-for-refresh` xuat hien.
      5. Rerun plan workflow tren PR `feature/phased-deploy-s03-rds-iam` (hoac bat ky PR nao khac vao `development`) de xac nhan refresh state khong con bi AccessDenied.

## Acceptance criteria

- `bootstrap/03-github-oidc-roles.yaml` co inline policy `secrets-read-for-refresh` tren `GhaInfraPlanRole`.
- Scope resource phai la `arn:aws:secretsmanager:*:${AWS::AccountId}:secret:/3-tiers-app/*` (dung `!Sub`).
- Khong co account ID, ARN hay secret value hardcode trong file.
- Sau khi user redeploy CFN va rerun plan workflow: log cua job `Terraform Plan / plan` tren GitHub Actions khong con dong `AccessDeniedException: ... secretsmanager:GetSecretValue`.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

### 2026-05-18 - iac-reviewer
- Verdict: approve
- Sub-tasks ticked: S01-T01
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0
- Ghi chu: Diff chi cham `bootstrap/03-github-oidc-roles.yaml` (+11 dong, 1 file). Inline policy `secrets-read-for-refresh` duoc append dung vi tri (sau `tfstate-rw`), YAML parse OK, `GhaInfraPlanRole.Properties.Policies` co dung 2 items. Action `secretsmanager:GetSecretValue` chinh xac (xac nhan voi AWS docs), resource scope `arn:aws:secretsmanager:*:${AWS::AccountId}:secret:/3-tiers-app/*` dung `!Sub` (khong hardcode account ID), least-privilege (chi GetSecretValue, khong Put/Delete/Update). Cac role khac (`GhaInfraApplyRole`, `GhaBackendDeployRole`, `GhaFrontendDeployRole`), `ManagedPolicyArns`, inline policy `tfstate-rw` cu, `Parameters`, `Outputs` deu khong bi cham. Comment tieng Anh, khong emoji, indentation 2-space dong nhat, ghi ro la temporary va se remove o S04.

### 2026-05-18 - main-thread (Sprint closure)
- Commit `ae16b4c` da push truc tiep vao `development` (do loi git tracking khi tao branch fix/secret-version-refresh-bomb-s01 voi startpoint `origin/development`, gay auto-tracking. Khong qua PR review tren GitHub UI; review value da duoc cung cap qua iac-reviewer agent o S01-T02). Khong workflow auto-trigger vi path filter cua terraform-apply chi match `envs/**` / `modules/**`.
- User trigger workflow Bootstrap (CFN - state backend + OIDC roles) voi `account = development`. Workflow run thanh cong.
- Sprint S01 dong. Sang S02.

## Last updated

2026-05-18 by main-thread (Sprint S01 closed)
