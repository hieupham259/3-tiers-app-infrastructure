# Sprint S04 (Optional) - Revert Phase 1: Gỡ inline policy secrets-read-for-refresh

## SPRINT NAY LA TUY CHON (OPTIONAL)

Chi chay Sprint nay sau khi S03 da apply thanh cong VA user da xac nhan PR test pass hoan toan (plan workflow khong con loi AccessDeniedException) --- chung minh thiet ke `secret_string_wo` khong can quyen `secretsmanager:GetSecretValue` cho `gha-infra-plan`.

Neu chua xac nhan, giu nguyen inline policy tu S01 (safe fallback).

## Muc tieu

Xoa inline policy `secrets-read-for-refresh` khoi `GhaInfraPlanRole` trong `bootstrap/03-github-oidc-roles.yaml` de dua role nay ve trang thai least-privilege: chi co `ReadOnlyAccess` + inline policy `tfstate-rw`. Sau khi user redeploy CFN, `gha-infra-plan` khong con quyen `secretsmanager:GetSecretValue` --- nhung pipeline plan van chay binh thuong vi `aws_secretsmanager_secret_version.db` voi `secret_string_wo` chi goi `ListSecretVersionIds`.

## Pre-conditions

- S03 da hoan thanh day du: RDS instance `available`, bomb duoc pha.
- User da chay PR test va xac nhan plan workflow pass khong co loi `secretsmanager:GetSecretValue`.
- Sprint nay duoc user xu ly chinh xac nhu S01: iac-builder sua file, iac-reviewer review, user redeploy CFN.

## Files bi anh huong

- `bootstrap/03-github-oidc-roles.yaml` (xoa inline policy `secrets-read-for-refresh` da them o S01)

## Sub-tasks

- [ ] S04-T01 - Xoa inline policy `secrets-read-for-refresh` khoi `GhaInfraPlanRole` trong `bootstrap/03-github-oidc-roles.yaml`
  - Assignee: iac-builder
  - Inputs / preconditions: `bootstrap/03-github-oidc-roles.yaml` hien tai co inline policy `secrets-read-for-refresh` (duoc them o S01)
  - Outputs / artifacts: `bootstrap/03-github-oidc-roles.yaml` voi block `secrets-read-for-refresh` duoc xoa khoi list `Policies` cua `GhaInfraPlanRole`; list `Policies` chi con 1 item la `tfstate-rw` (tra ve trang thai nhu truoc S01)
  - Depends on: none
  - Notes: Khong sua bat ky policy nao khac. Khong cham `GhaInfraApplyRole` hay cac role khac. File sau khi sua phai identical voi trang thai truoc khi S01 bat dau.

- [ ] S04-T02 - Review diff S04-T01
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S04-T01
  - Outputs / artifacts: tick checkbox; bao cao findings; reassign neu co van de
  - Depends on: S04-T01
  - Notes: |
      Kiem tra: (1) chi co xoa inline policy `secrets-read-for-refresh`, khong co thay doi nao khac; (2) `GhaInfraPlanRole` sau khi xoa van co inline policy `tfstate-rw` day du; (3) cac role khac (GhaInfraApplyRole, GhaBackendDeployRole, GhaFrontendDeployRole) khong bi cham.

- [ ] S04-T03 - User: redeploy CFN stack bootstrap tren ca 2 AWS account (development va production)
  - Assignee: user
  - Inputs / preconditions: S04-T02 approve; PR da merge vao `development` (va `production` neu dang trien khai production)
  - Outputs / artifacts: CFN stack update thanh cong; IAM role `gha-infra-plan` khong con co inline policy `secrets-read-for-refresh` tren AWS Console
  - Depends on: S04-T02
  - Notes: |
      Quy trinh thu cong (tuong tu S01-T03 nhung khac la xoa policy):
      1. Merge PR chua S04-T01 vao `development` (va tao PR tuong tu vao `production` neu can).
      2. Chay `aws cloudformation deploy` voi cung parameters nhu S01-T03 cho account `development`.
      3. Verify: vao IAM Console > Roles > `gha-infra-plan` > tab Permissions, xac nhan inline policy `secrets-read-for-refresh` KHONG CON trong danh sach.
      4. Chay 1 PR test cuoi cung: plan workflow phai pass hoan toan ma khong co quyen `secretsmanager:GetSecretValue` trong role.
      5. Neu pass: giai doan fix hoan chinh. Least-privilege dat duoc.
      6. Neu fail (AccessDenied bat ngo): revert bang cach redeploy CFN voi phien ban S01 (co inline policy). Bao cao lai voi team.

## Acceptance criteria

- `bootstrap/03-github-oidc-roles.yaml` tro ve trang thai truoc S01: `GhaInfraPlanRole` chi co 1 inline policy `tfstate-rw`.
- Sau user redeploy CFN: IAM role `gha-infra-plan` tren AWS Console khong con inline policy `secrets-read-for-refresh`.
- PR test sau redeploy: plan workflow pass, khong co `AccessDeniedException`.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

## Last updated

2026-05-18 by task-planner
