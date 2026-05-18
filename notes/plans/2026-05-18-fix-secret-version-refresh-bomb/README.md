# Fix: Secret Version Refresh Bomb

## Boi canh

Trong qua trinh deploy giai doan S03 (uncomment module `rds` va `iam_app_roles` vao `envs/_shared/main.tf`), Terraform da apply thanh cong mot phan: `random_password.master`, `aws_secretsmanager_secret.db`, `aws_secretsmanager_secret_version.db`, `aws_security_group.this`, `aws_db_subnet_group.this`, va cac IAM role. Apply dung lai khi tao `aws_db_instance.this` vi `allocated_storage = 15GB` nho hon gioi han toi thieu cua PostgreSQL tren gp3 la 20GB.

Ket qua: state cua dev env hien chua `aws_secretsmanager_secret_version.db`. Resource nay dung argument `secret_string`, khien AWS provider goi `secretsmanager:GetSecretValue` moi khi refresh state (moi lan `terraform plan` hay `terraform apply`). Role `gha-infra-plan` chi co `ReadOnlyAccess` + inline policy tfstate --- `ReadOnlyAccess` co y khong bao gom `secretsmanager:GetSecretValue`. Hau qua: moi `terraform plan` bi AccessDenied, **dev env dong bang hoan toan** voi moi thay doi IaC qua pipeline.

Loi cu the dang xay ra tren PR `feature/phased-deploy-s03-rds-iam`:

```
Error: reading Secrets Manager Secret Version (...): AccessDeniedException:
User: arn:aws:sts::405226342924:assumed-role/gha-infra-plan/GitHubActions is
not authorized to perform: secretsmanager:GetSecretValue ...
```

## Giai phap chot

Xu ly theo 4 giai doan tuan tu:

- **Phase 1 (S01)**: Va tam `gha-infra-plan` role bang cach them inline policy `secrets-read-for-refresh` (`secretsmanager:GetSecretValue` tren `/3-tiers-app/*`) vao `bootstrap/03-github-oidc-roles.yaml`. User redeploy CFN stack thu cong. Day la dieu kien tien quyet de plan workflow co the refresh state.
- **Phase 2 (S02)**: Comment lai `module "rds"` va `module "iam_app_roles"` trong `envs/_shared/main.tf` de Terraform destroy toan bo resource ma S03 da tao. Sau apply, user force-delete secret de tra ve trang thai sach (khong con secret trong AWS). Day la dieu kien tien quyet de tao lai secret voi cung ten.
- **Phase 3 (S03)**: Refactor `modules/rds/main.tf` doi `secret_string` sang `secret_string_wo` (write-only attribute, Terraform >= 1.11), dong thoi uncomment lai 2 module. Sau Phase 3: bomb duoc pha bom vinh vien vi Read cua `aws_secretsmanager_secret_version` voi `secret_string_wo` chi goi `ListSecretVersionIds` (quyen da co trong `ReadOnlyAccess`), khong goi `GetSecretValue` nua.
- **Phase 3.5 (S04, optional)**: Sau khi Phase 3 chung minh `gha-infra-plan` khong con can `GetSecretValue`, gỡ inline policy `secrets-read-for-refresh` khoi CFN template de dat least-privilege.

## Cay phu thuoc giua cac Sprint

```
S01 (patch bootstrap CFN + user redeploy)
  |
  v
S02 (comment-out modules + apply + user force-delete secret)
  |
  v
S03 (refactor secret_string_wo + uncomment modules + apply)
  |
  v
S04 (optional: revert Phase 1, gỡ inline policy)
```

## Sprints

| ID  | Tieu de                          | Trang thai | Owner cap nhat |
|-----|----------------------------------|------------|----------------|
| S01 | Patch gha-infra-plan role        | planned    | task-planner   |
| S02 | Destroy S03 resources            | planned    | task-planner   |
| S03 | Refactor secret_string_wo        | planned    | task-planner   |
| S04 | (Optional) Revert Phase 1        | planned    | task-planner   |

## Files bi anh huong

| File                                        | Sprint      | Thay doi |
|---------------------------------------------|-------------|----------|
| `bootstrap/03-github-oidc-roles.yaml`       | S01, S04    | Them / Xoa inline policy `secrets-read-for-refresh` |
| `envs/_shared/main.tf`                      | S02, S03    | Comment / uncomment module rds + iam_app_roles |
| `modules/rds/main.tf` (lines 43-51)         | S03         | Doi `secret_string` sang `secret_string_wo` + them `secret_string_wo_version` |

## AWS resource bi tac dong

| Resource                                        | Action trong plan nay |
|-------------------------------------------------|-----------------------|
| `aws_secretsmanager_secret_version.db` (dev)    | Destroy (S02) + Re-create (S03) |
| `aws_secretsmanager_secret.db` (dev)            | Destroy (S02, prevent_destroy duoc bo qua vi comment-out module) + Re-create (S03) |
| `aws_security_group.this` (dev RDS SG)          | Destroy (S02) + Re-create (S03) |
| `aws_db_subnet_group.this` (dev)                | Destroy (S02) + Re-create (S03) |
| IAM roles `3-tiers-app-development-task*` (dev) | Destroy (S02) + Re-create (S03) |
| `aws_db_instance.this` (dev)                    | Chua ton tai trong state (apply S03 failed truoc khi tao) |
| `GhaInfraPlanRole` (CFN IAM resource)           | Update: them inline policy (S01), xoa inline policy (S04) |

## Cau hoi mo

Khong con cau hoi mo. Giai phap da duoc chot qua thao luan voi user truoc khi viet plan nay.

## Ngoai pham vi

- Sua loi `allocated_storage` < 20GB cho `aws_db_instance`: KHONG thuoc Sprint nay. Day la van de doc lap voi bom, da duoc user fix o commit `9ff2855` (revert `rds_storage_gb` ve 20 trong `envs/development/terraform.tfvars`). Hien tai ca 2 env deu co `rds_storage_gb` >= 20 (dev=20, prod=100). Bom van se kich hoat o lan plan thu 2 du apply 15GB co thanh cong hay khong --- 2 van de hoan toan tach biet.
- Chinh sua workflow GitHub Actions (khong can thay doi).
- Nang cap terraform hay provider version (da du dieu kien: Terraform 1.13.3 >= 1.11, AWS provider 5.100.0 >= 5.89).

## Last updated

2026-05-18 by main-thread (lam ro `allocated_storage` khong thuoc pham vi Sprint --- la van de doc lap)
