# Sprint S03 - Refactor secret_string_wo va Recreate RDS Resources

## Muc tieu

Sua `modules/rds/main.tf` doi `secret_string` sang `secret_string_wo` (write-only attribute, yeu cau Terraform >= 1.11) tren resource `aws_secretsmanager_secret_version.db`, dong thoi uncomment lai `module "rds"` va `module "iam_app_roles"` trong `envs/_shared/main.tf`. Sau khi apply: bomb duoc pha vinh vien --- Read cua `aws_secretsmanager_secret_version` voi `secret_string_wo` chi goi `ListSecretVersionIds` (quyen da co trong `ReadOnlyAccess`), khong goi `GetSecretValue` nua.

Thiet ke AWS giu nguyen y chang: secret name `/3-tiers-app/<env>/rds/master`, value la JSON `{username, password, dbname, port}`, `random_password` van do Terraform quan ly.

## Pre-conditions

- S02 da hoan thanh day du: apply thanh cong + user da force-delete secret `/3-tiers-app/development/rds/master` khoi AWS (secret khong con o trang thai "scheduled deletion").
- State dev sach: khong con resource nao tu `module.rds` hay `module.iam_app_roles`.
- `envs/_shared/main.tf` hien tai co 2 module bi comment voi marker `# S02-TEMP`.

## Cac chi tiet ky thuat quan trong

### Attribute `secret_string_wo`

- Khai bao: `secret_string_wo = jsonencode({...})` thay the `secret_string = jsonencode({...})`.
- Kem theo: `secret_string_wo_version = 1` (bat buoc; dung de trigger rotate sau nay bang cach tang len 2, 3,...).
- Terraform ghi gia tri vao AWS nhung KHONG luu vao state va KHONG goi `GetSecretValue` khi refresh.
- Chuc nang Read cua provider goi `ListSecretVersionIds` thay the --- quyen nay co trong `ReadOnlyAccess`.

### Giu nguyen thiet ke AWS

- Secret name: `/3-tiers-app/${var.environment}/rds/master` --- khong doi.
- Secret value structure: `{username, password, dbname, port}` --- khong doi.
- `random_password.master` van do Terraform quan ly --- khong doi.
- Output `module.rds.secret_arn` tro ve `aws_secretsmanager_secret.db.arn` --- khong doi.
- `modules/iam-app-roles/main.tf` (IAM policy `secretsmanager:GetSecretValue` tren `var.rds_secret_arn` cho ECS task-exec role) --- KHONG cham.

## Files bi anh huong

- `modules/rds/main.tf` (lines 43-51: resource `aws_secretsmanager_secret_version.db`)
- `envs/_shared/main.tf` (lines 44-68: uncomment lai 2 block module)
- `envs/_shared/outputs.tf` (uncomment lai `output "rds_endpoint"` neu dang comment)

## Sub-tasks

- [ ] S03-T01 - Doi `secret_string` sang `secret_string_wo` trong `modules/rds/main.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: `modules/rds/main.tf` hien tai (lines 43-51: resource `aws_secretsmanager_secret_version.db` dung `secret_string`)
  - Outputs / artifacts: `modules/rds/main.tf` voi lines 43-51 duoc sua:
    - Xoa argument `secret_string = jsonencode({...})`
    - Them argument `secret_string_wo = jsonencode({username = var.master_username, password = random_password.master.result, dbname = var.db_name, port = 5432})`
    - Them argument `secret_string_wo_version = 1`
    - Khong doi bat ky argument hay block nao khac trong resource nay
    - Khong doi cac resource khac trong file (random_password, aws_secretsmanager_secret, aws_db_instance, aws_security_group, aws_db_subnet_group)
  - Depends on: none
  - Notes: |
      Gia tri `secret_string_wo_version = 1` la so nguyen, khong phai string. Trong tuong lai, de rotate secret, tang gia tri nay len 2, 3,... de trigger re-write. Day la co che chinh thuc cua write-only attribute cho rotation.

- [ ] S03-T02 - Uncomment lai `module "rds"` va `module "iam_app_roles"` trong `envs/_shared/main.tf`; uncomment `output "rds_endpoint"`
  - Assignee: iac-builder
  - Inputs / preconditions: S03-T01 done; `envs/_shared/main.tf` co 2 module dang comment voi marker `# S02-TEMP`
  - Outputs / artifacts:
    - `envs/_shared/main.tf` voi 2 block module duoc uncomment; marker `# S02-TEMP` duoc xoa; comment `# S03: temporary ...` giu lai (cac gia tri tam thoi `ingress_security_group_ids = []` va `frontend_bucket_arn = null` van giu nhu S03 phased-deploy da co --- se phuc hoi o Sprint S04 cua ke hoach phased-deploy)
    - `envs/_shared/outputs.tf` voi `output "rds_endpoint"` duoc uncomment
  - Depends on: S03-T01
  - Notes: |
      Giu nguyen cac comment tam thoi da co tu Sprint S03 phased-deploy:
      - `ingress_security_group_ids = [] # S03: temporary empty list, restored in S04`
      - `frontend_bucket_arn = null # S03: temporary null, restored in S04`
      Khong uncomment module `ecs_service`, `frontend_cdn`, `observability` --- cac module nay van thuoc Sprint S04 cua ke hoach phased-deploy.

- [ ] S03-T03 - Review diff S03 (T01, T02)
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S03-T01, S03-T02
  - Outputs / artifacts: tick checkbox tung sub-task; bao cao findings; reassign neu co van de
  - Depends on: S03-T02
  - Notes: |
      Kiem tra dac biet:
      (1) `modules/rds/main.tf` lines 43-51: chi co `secret_string_wo` va `secret_string_wo_version = 1`; khong con `secret_string`; structure JSON giu nguyen 4 field.
      (2) `secret_string_wo_version` phai la so nguyen, khong phai string.
      (3) `envs/_shared/main.tf` 2 module uncomment voi cac comment tam thoi dung mau.
      (4) `scripts/verify-envs-in-sync.sh` pass.
      (5) `modules/iam-app-roles/main.tf` khong bi cham.
      (6) Khong co hardcode account ID, ARN, password, hay secret value trong bat ky file.

- [ ] S03-T04 - Chay terraform plan xac nhan plan tao lai resource voi secret_string_wo
  - Assignee: terraform-planner
  - Inputs / preconditions: code sau S03-T03 approve
  - Outputs / artifacts: bao cao plan chi tiet; resource mong doi duoc tao: `random_password.master` (1), `aws_secretsmanager_secret.db` (1), `aws_secretsmanager_secret_version.db` (1), `aws_security_group.this` (1), `aws_db_subnet_group.this` (1), `aws_db_instance.this` (1), IAM resources tu `module.iam_app_roles`
  - Depends on: S03-T03
  - Notes: |
      Xac nhan: (1) khong co destroy tren network/ECR/ALB/ECS; (2) `aws_secretsmanager_secret_version.db` trong plan la create (khong phai update); (3) bien `secret_string_wo` khong xuat hien trong plan output (write-only attribute bi che trong plan JSON).

- [ ] S03-T05 - User: merge PR S03 vao development va verify apply + verify bomb duoc pha
  - Assignee: user
  - Inputs / preconditions: S03-T04 xac nhan plan an toan
  - Outputs / artifacts: apply thanh cong; RDS instance trang thai `available`; kiem tra PR test xac nhan plan workflow khong con loi AccessDenied ngay ca khi gha-infra-plan khong co inline policy GetSecretValue
  - Depends on: S03-T04
  - Notes: |
      Quy trinh apply:
      1. Tao PR vao `development` voi commit chua S03-T01, T02.
      2. Doi plan workflow pass.
      3. Merge. Approve apply workflow trong GitHub Actions Environment `development`.
      4. Doi apply thanh cong (RDS instance mat khoang 10-15 phut).
      5. Verify tren AWS Console: RDS instance `development-postgres` trang thai `available`; secret `/3-tiers-app/development/rds/master` ton tai; IAM roles `3-tiers-app-development-task*` ton tai.

      Verify bomb duoc pha:
      6. Tao 1 PR test (vi du: sua 1 comment khong quan trong trong terraform.tfvars).
      7. Doi plan workflow pass HOAN TOAN: khong co dong `AccessDeniedException` trong log, kể ca khi secret version duoc refresh.
      8. Neu step 7 pass ma KHONG can inline policy `secrets-read-for-refresh` (co the test bang cach xem log, plan gio dung `ListSecretVersionIds` thay vi `GetSecretValue`) thi bomb da duoc pha.
      Note: co the de S04 (optional) sau khi da xac nhan step 7.

## Acceptance criteria

- `modules/rds/main.tf` co `secret_string_wo` va `secret_string_wo_version = 1` thay the `secret_string`.
- `envs/_shared/main.tf` co 2 module uncommented voi comment tam thoi dung mau.
- `scripts/verify-envs-in-sync.sh` pass.
- `terraform fmt -check -recursive` pass.
- Apply thanh cong: RDS instance `available`, secret ton tai, IAM roles ton tai.
- PR test sau apply: plan workflow pass, khong co `AccessDeniedException` lien quan den `secretsmanager:GetSecretValue` trong log refresh.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

## Last updated

2026-05-18 by main-thread (go S03-T02 kiem tra rds_storage_gb vi lac de khoi muc tieu fix bom)
