# Sprint S02 - Destroy S03 Resources

## Muc tieu

Comment lai `module "rds"` va `module "iam_app_roles"` trong `envs/_shared/main.tf` de Terraform tinh toan destroy toan bo resource ma Sprint S03 cua ke hoach `2026-05-15-phased-deploy-development` da tao trong state dev. Sau khi apply, user force-delete secret trong AWS de xoa secret khoi trang thai "scheduled deletion" (recovery window 7 ngay), dam bao Phase 3 co the tao lai secret voi cung ten `/3-tiers-app/development/rds/master` ngay lap tuc.

Day la dieu kien tien quyet (BLOCKER) cho S03: S03 se tao lai secret voi cung ten, neu ten cu van con trong AWS (ke ca o trang thai "scheduled deletion"), `aws_secretsmanager_secret` se bao loi trung ten.

## Pre-conditions

- S01 da hoan thanh va CFN stack da duoc user redeploy: `gha-infra-plan` co the goi `secretsmanager:GetSecretValue`. Pipeline `terraform plan` da pass lai.
- State dev hien chua: `aws_secretsmanager_secret.db`, `aws_secretsmanager_secret_version.db`, `aws_security_group.this` (rds-sg), `aws_db_subnet_group.this`, IAM roles tu `module.iam_app_roles`. Khong co `aws_db_instance.this` (apply S03 fail truoc khi tao).
- `envs/_shared/main.tf` hien tai co `module "rds"` (lines 44-60) va `module "iam_app_roles"` (lines 62-68) dang uncommented.

## Luu y ky thuat quan trong

`aws_secretsmanager_secret.db` trong module RDS co `lifecycle { prevent_destroy = true }` (modules/rds/main.tf:37-40). Theo HashiCorp docs, `prevent_destroy` chi co hieu luc khi resource con duoc khai bao trong config. Khi comment out toan bo `module "rds"`, resource khong con trong config → constraint bi bo qua → Terraform tinh destroy binh thuong. KHONG can sua lifecycle block truoc khi comment-out.

`aws_db_instance.this` chua ton tai trong state (apply S03 fail truoc khi tao resource nay) → destroy plan se khong tinh resource nay.

## Files bi anh huong

- `envs/_shared/main.tf` (lines 44-68: comment lai 2 block module)

## Sub-tasks

- [ ] S02-T01 - Comment lai `module "rds"` va `module "iam_app_roles"` trong `envs/_shared/main.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: `envs/_shared/main.tf` hien tai (2 module dang uncommented o lines 44-68)
  - Outputs / artifacts: `envs/_shared/main.tf` voi 2 block module duoc comment lai; `envs/_shared/outputs.tf` comment lai `output "rds_endpoint"` (neu hien dang uncommented)
  - Depends on: none (code change khong phu thuoc S01; S01 chi can truoc khi chay plan)
  - Notes: |
      Them comment marker ro rang de S03 biet can uncomment lai:
      - `# S02-TEMP: commented out to destroy S03 resources, restore in S03`
      Kiem tra `envs/_shared/outputs.tf`: neu `output "rds_endpoint"` dang uncommented thi comment lai cung (reference `module.rds.endpoint` se fail khi module bi comment).
      Kiem tra `scripts/verify-envs-in-sync.sh` van pass sau khi sua (2 env phai in-sync).

- [ ] S02-T02 - Review diff S02-T01
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S02-T01
  - Outputs / artifacts: tick checkbox; bao cao findings; reassign neu co van de
  - Depends on: S02-T01
  - Notes: |
      Kiem tra dac biet:
      (1) Sau khi comment 2 module, khong co output/data source nao trong `envs/_shared/` con tham chieu toi `module.rds.*` hoac `module.iam_app_roles.*` o trang thai uncommented.
      (2) `scripts/verify-envs-in-sync.sh` phai pass (2 env phai identical).
      (3) Khong co thay doi ngoai `envs/_shared/` (modules/ khong bi cham).

- [ ] S02-T03 - Chay terraform plan xac nhan plan chi chua destroy cac resource S03 da tao
  - Assignee: terraform-planner
  - Inputs / preconditions: code sau S02-T01 da review S02-T02 approve; S01 da apply tren AWS (gha-infra-plan co quyen GetSecretValue)
  - Outputs / artifacts: bao cao plan chi tiet resource bi destroy; resource mong doi bi destroy: `aws_secretsmanager_secret_version.db`, `aws_secretsmanager_secret.db`, `aws_security_group_rule.ingress_from_ecs` (count=0, co the la no-op), `aws_security_group.this`, `aws_db_subnet_group.this`, cac IAM resource tu `module.iam_app_roles`
  - Depends on: S02-T02
  - Notes: Xac nhan KHONG co destroy/modify tren network, ECR, ALB, ECS cluster (da co tu Sprint S01-S02 cua phased-deploy). Kiem tra co resource nao unexpected khong.

- [ ] S02-T04 - User: merge PR S02 vao development va verify apply thanh cong
  - Assignee: user
  - Inputs / preconditions: S02-T03 xac nhan plan an toan
  - Outputs / artifacts: apply thanh cong; state dev khong con chua resource cua `module.rds` va `module.iam_app_roles`
  - Depends on: S02-T03
  - Notes: |
      Quy trinh:
      1. Tao PR vao `development` voi commit chua S02-T01.
      2. Doi plan workflow pass (gha-infra-plan gio co quyen GetSecretValue tu S01).
      3. Merge PR. Approve apply workflow trong GitHub Actions Environment `development`.
      4. Doi apply thanh cong.
      5. Verify tren AWS Console: khong con security group `development-rds-sg`, khong con DB subnet group, khong con IAM roles `3-tiers-app-development-task*`.
      Luu y: secret van con tren AWS o trang thai "scheduled deletion" (recovery window 7 ngay) → can buoc tiep theo.

- [ ] S02-T05 - User: force-delete secret `/3-tiers-app/development/rds/master` khoi AWS
  - Assignee: user
  - Inputs / preconditions: S02-T04 apply thanh cong; secret khong con trong Terraform state
  - Outputs / artifacts: secret bi xoa hoan toan khoi AWS (khong con o trang thai "scheduled deletion")
  - Depends on: S02-T04
  - Notes: |
      Chay lenh:
      ```
      aws secretsmanager delete-secret \
        --secret-id /3-tiers-app/development/rds/master \
        --force-delete-without-recovery \
        --region us-east-1 \
        --profile <dev-profile>
      ```
      Verify: vao AWS Console > Secrets Manager, xac nhan khong con secret nao ten `/3-tiers-app/development/rds/master` (ke ca o trang thai "scheduled deletion").
      Neu khong force-delete ngay, S03 phai doi 7 ngay hoac dung ten khac cho secret.

## Acceptance criteria

- `envs/_shared/main.tf` co 2 block module (`rds` va `iam_app_roles`) duoc comment lai voi marker `# S02-TEMP`.
- `scripts/verify-envs-in-sync.sh` pass.
- Terraform plan chi chua destroy resource cua module.rds va module.iam_app_roles; khong co thay doi tren network/ECR/ALB/ECS.
- Sau apply: AWS Console khong con RDS security group, DB subnet group, IAM task roles cua dev env.
- Sau force-delete: AWS Console Secrets Manager khong con secret `/3-tiers-app/development/rds/master`.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

## Last updated

2026-05-18 by task-planner
