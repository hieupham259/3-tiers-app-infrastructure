# Sprint S04 - Mandatory Cleanup: Xoa inline policy secrets-read-for-refresh

## Cap nhat lan cuoi

2026-05-18 by task-planner (chuyen tu "optional" sang mandatory voi kien truc S03 v2 cicd-inject)

---

## Ly do thay doi trang thai (optional -> mandatory)

Sprint S03 v1 (`secret_string_wo`) van giu `aws_secretsmanager_secret_version` trong tfstate, nen con ky nang inline policy `secrets-read-for-refresh` la safe fallback co ich.

Sprint S03 v2 (cicd-inject, Pattern C) loai bo hoan toan `aws_secretsmanager_secret_version` khoi Terraform. Terraform chi con quan ly metadata `aws_secretsmanager_secret` (goi `DescribeSecret` khi refresh --- co trong `ReadOnlyAccess`). `GetSecretValue` TUYET DOI KHONG BAO GIO duoc goi boi `terraform plan` hay `terraform apply` nua.

Ket luan: giu inline policy `secrets-read-for-refresh` la thua, tao ra bề mat tan cong khong can thiet, vi pham least-privilege. Sprint S04 khong con la tuy chon --- phai chay sau khi S03 apply thanh cong va bomb duoc xac nhan pha.

---

## Muc tieu

Xoa inline policy `secrets-read-for-refresh` khoi `GhaInfraPlanRole` trong `bootstrap/03-github-oidc-roles.yaml`, tra role nay ve trang thai least-privilege: chi co `ReadOnlyAccess` + inline policy `tfstate-rw`. User redeploy CFN stack. Sau do `gha-infra-plan` khong con quyen `secretsmanager:GetSecretValue` --- va pipeline plan van chay binh thuong vi S03 v2 da loai bo nguyen nhan goc.

---

## Pre-conditions

- S03 da hoan thanh day du: apply thanh cong, RDS instance trang thai `available`, secret `/3-tiers-app/development/rds/credentials` co value.
- User da chay PR test va xac nhan plan workflow pass hoan toan: khong co loi `AccessDeniedException` trong log (Step 7 cua S03-T09).
- Branch `feature/phased-deploy-s03-rds-iam` (hoac branch tao moi cho S04) san sang cho commit tiep theo.

---

## Files bi anh huong

- `bootstrap/03-github-oidc-roles.yaml` (xoa inline policy `secrets-read-for-refresh` da them o S01)

---

## Sub-tasks

- [ ] S04-T01 - Xoa inline policy `secrets-read-for-refresh` khoi `GhaInfraPlanRole` trong `bootstrap/03-github-oidc-roles.yaml`
  - Assignee: iac-builder
  - Inputs / preconditions: `bootstrap/03-github-oidc-roles.yaml` hien tai co inline policy `secrets-read-for-refresh` (duoc them o S01)
  - Outputs / artifacts: `bootstrap/03-github-oidc-roles.yaml` voi toan bo block `secrets-read-for-refresh` duoc xoa khoi list `Policies` cua `GhaInfraPlanRole`; list `Policies` chi con 1 item la `tfstate-rw` (tra ve trang thai truoc S01 chinh xac)
  - Depends on: none
  - Notes: Khong sua bat ky policy nao khac. Khong cham `GhaInfraApplyRole`, `GhaBackendDeployRole`, `GhaFrontendDeployRole`, hay bat ky resource nao khac. File sau khi sua phai co `GhaInfraPlanRole.Properties.Policies` chi chua 1 phan tu (`tfstate-rw`).

- [ ] S04-T02 - Review diff S04-T01
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S04-T01
  - Outputs / artifacts: tick checkbox; bao cao findings co severity tag; reassign neu co van de
  - Depends on: S04-T01
  - Notes: |
      Kiem tra:
      (1) Chi co xoa inline policy `secrets-read-for-refresh`, khong co thay doi nao khac trong file.
      (2) `GhaInfraPlanRole` sau khi xoa van co inline policy `tfstate-rw` day du (PolicyName, PolicyDocument, Statement, Action, Resource).
      (3) Cac role khac (GhaInfraApplyRole, GhaBackendDeployRole, GhaFrontendDeployRole) khong bi cham.
      (4) File sau khi sua identical voi noi dung truoc khi S01 bat dau (tru cac thay doi khac neu co).

- [ ] S04-T03 - User: redeploy CFN stack bootstrap tren ca 2 AWS account (development va production)
  - Assignee: user
  - Inputs / preconditions: S04-T02 approve; PR da merge vao `development` (va `production` neu production da duoc setup)
  - Outputs / artifacts: CFN stack update thanh cong; IAM role `gha-infra-plan` KHONG CON co inline policy `secrets-read-for-refresh` tren AWS Console
  - Depends on: S04-T02
  - Notes: |
      Quy trinh thu cong (tuong tu S01-T03 nhung la xoa policy thay vi them):
      1. Commit S04-T01, push, tao PR, merge vao `development`.
      2. Chay AWS CLI update stack cho account `development` (dung cung parameters nhu S01-T03):
         aws cloudformation deploy \
           --template-file bootstrap/03-github-oidc-roles.yaml \
           --stack-name <ten-stack> \
           --capabilities CAPABILITY_NAMED_IAM \
           --parameter-overrides <cac param nhu truoc>
      3. Verify: IAM Console > Roles > gha-infra-plan > tab Permissions.
         Xac nhan: inline policy `secrets-read-for-refresh` KHONG CON trong danh sach Permissions.
         Xac nhan: inline policy `tfstate-rw` VAN CON.
      4. Final verification: tao 1 PR test nho (sua comment trong terraform.tfvars).
         Plan workflow phai pass hoan toan MA KHONG CO quyen `secretsmanager:GetSecretValue`.
      5. Neu pass: toan bo ke hoach fix bomb hoan chinh. Least-privilege dat duoc.
      6. Neu fail (AccessDenied bat ngo): lap tuc revert bang cach redeploy CFN voi phien ban truoc (co inline policy). Bao cao lai voi team.
      7. Lap lai cho account `production` neu can thiet.

---

## Acceptance criteria

- `bootstrap/03-github-oidc-roles.yaml`: `GhaInfraPlanRole` chi co 1 inline policy `tfstate-rw` (khong con `secrets-read-for-refresh`).
- Sau user redeploy CFN: IAM role `gha-infra-plan` tren AWS Console khong con inline policy `secrets-read-for-refresh`.
- Final PR test: plan workflow pass hoan toan, khong co `AccessDeniedException`, khong can `GetSecretValue`.

---

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

---

## Last updated

2026-05-18 by task-planner (chuyen tu optional sang mandatory: kien truc S03 v2 loai bo aws_secretsmanager_secret_version khoi tfstate, GetSecretValue tuyet doi khong can thiet)
