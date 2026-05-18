# Fix: Secret Version Refresh Bomb

## Cap nhat lan cuoi

2026-05-18 by task-planner (redesign S03 v2: cicd-inject Pattern C; S04 chuyen thanh mandatory cleanup)

---

## Boi canh

Trong qua trinh deploy giai doan S03 (uncomment module `rds` va `iam_app_roles` vao `envs/_shared/main.tf`), Terraform da apply thanh cong mot phan: `random_password.master`, `aws_secretsmanager_secret.db`, `aws_secretsmanager_secret_version.db`, `aws_security_group.this`, `aws_db_subnet_group.this`, va cac IAM role. Apply dung lai khi tao `aws_db_instance.this` vi `allocated_storage = 15GB` nho hon gioi han toi thieu cua PostgreSQL tren gp3 la 20GB.

Ket qua: state cua dev env hien chua `aws_secretsmanager_secret_version.db`. Resource nay dung argument `secret_string`, khien AWS provider goi `secretsmanager:GetSecretValue` moi khi refresh state (moi lan `terraform plan` hay `terraform apply`). Role `gha-infra-plan` chi co `ReadOnlyAccess` + inline policy tfstate --- `ReadOnlyAccess` co y khong bao gom `secretsmanager:GetSecretValue`. Hau qua: moi `terraform plan` bi AccessDenied, **dev env dong bang hoan toan** voi moi thay doi IaC qua pipeline.

Loi cu the dang xay ra tren PR `feature/phased-deploy-s03-rds-iam`:

```
Error: reading Secrets Manager Secret Version (...): AccessDeniedException:
User: arn:aws:sts::405226342924:assumed-role/gha-infra-plan/GitHubActions is
not authorized to perform: secretsmanager:GetSecretValue ...
```

---

## Giai phap chot

Xu ly theo 4 giai doan tuan tu:

- **Phase 1 (S01) - HOAN THANH**: Va tam `gha-infra-plan` role bang cach them inline policy `secrets-read-for-refresh` (`secretsmanager:GetSecretValue` tren `/3-tiers-app/*`) vao `bootstrap/03-github-oidc-roles.yaml`. User da redeploy CFN stack thu cong. Day la dieu kien tien quyet de plan workflow co the refresh state.

- **Phase 2 (S02) - HOAN THANH**: Comment lai `module "rds"` va `module "iam_app_roles"` trong `envs/_shared/main.tf` de Terraform destroy toan bo resource ma S03 da tao (nhung tao ra voi gia trị `aws_secretsmanager_secret_version` gay bomb). State dev da sach: khong con `aws_secretsmanager_secret_version.db` hay bat ky resource nao tu module rds/iam_app_roles.

- **Phase 3 (S03) - DANG THIET KE (v2)**: Refactor `modules/rds` theo Pattern C (CI/CD inject): Terraform chi quan ly metadata `aws_secretsmanager_secret` (khong co `secret_version`). Password RDS den tu GitHub Environment Secret `RDS_MASTER_PASSWORD`. Workflow inject gia tri secret sau apply bang `aws secretsmanager put-secret-value`. Sau Phase 3: bomb duoc pha vinh vien vi Terraform chi goi `DescribeSecret` (co trong `ReadOnlyAccess`), khong bao gio goi `GetSecretValue`.

- **Phase 3.5 (S04) - MANDATORY CLEANUP**: Xoa inline policy `secrets-read-for-refresh` khoi `GhaInfraPlanRole` trong CFN template. Sprint nay khong con la "optional" voi kien truc moi: `aws_secretsmanager_secret_version` khong con trong tfstate nen `gha-infra-plan` tuyet doi khong can quyen `GetSecretValue`. Giu lai inline policy thua tao ra bề mat tan cong khong can thiet. User redeploy CFN sau khi S03 apply thanh cong va bomb duoc xac nhan pha.

---

## Cay phu thuoc giua cac Sprint

```
S01 (patch bootstrap CFN + user redeploy) --- HOAN THANH
  |
  v
S02 (comment-out modules + apply + state sach) --- HOAN THANH
  |
  v
S03 (Pattern C: metadata-only secret + cicd inject + uncomment modules + apply)
  |
  v
S04 (mandatory cleanup: xoa inline policy secrets-read-for-refresh)
```

---

## Sprints

| ID  | Tieu de                                     | Trang thai      | Owner cap nhat |
|-----|---------------------------------------------|-----------------|----------------|
| S01 | Patch gha-infra-plan role                   | done            | task-planner   |
| S02 | Destroy S03 resources                       | done            | task-planner   |
| S03 | CI/CD Inject Secret Value (Pattern C)       | done (v2)       | main-thread    |
| S04 | Mandatory Cleanup: Revert Phase 1 policy    | planned         | task-planner   |

---

## Files bi anh huong

| File                                        | Sprint      | Thay doi |
|---------------------------------------------|-------------|----------|
| `bootstrap/03-github-oidc-roles.yaml`       | S01 (done), S04 | Them (S01 done) / Xoa inline policy `secrets-read-for-refresh` (S04) |
| `envs/_shared/main.tf`                      | S02 (done), S03 | Comment (S02 done) / Uncomment module rds + iam_app_roles; them `master_password = var.rds_master_password` (S03) |
| `envs/_shared/variables.tf`                 | S03         | Them variable `rds_master_password` |
| `envs/_shared/outputs.tf`                   | S03         | Uncomment `output "rds_endpoint"`; dam bao co `output "rds_secret_arn"` |
| `envs/development/variables.tf`             | S03         | Them variable `rds_master_password` |
| `envs/production/variables.tf`              | S03         | Them variable `rds_master_password` |
| `modules/rds/main.tf`                       | S03         | Xoa `random_password` + `aws_secretsmanager_secret_version`; doi secret name sang `credentials`; doi password source sang `var.master_password`; them `ignore_changes = [password]` |
| `modules/rds/variables.tf`                  | S03         | Them variable `master_password` (sensitive, nullable=false); xoa variable `master_password_length` neu co |
| `.github/workflows/terraform-apply.yaml`    | S03         | Them `TF_VAR_rds_master_password` env var; them step `Inject RDS secret value` sau apply |

---

## AWS resource bi tac dong

| Resource                                        | Action trong plan nay |
|-------------------------------------------------|-----------------------|
| `aws_secretsmanager_secret_version.db` (dev)    | Destroy (S02 done); KHONG tao lai (S03 v2 khong quan ly version trong Terraform) |
| `aws_secretsmanager_secret.db` (dev)            | Destroy (S02 done) + Re-create voi ten moi `credentials` (S03 done); gia tri inject boi CI/CD composite action `sync-secret-value` (S03 done) |
| `aws_security_group.this` (dev RDS SG)          | Destroy (S02 done) + Re-create (S03 done) |
| `aws_db_subnet_group.this` (dev)                | Destroy (S02 done) + Re-create (S03 done) |
| `aws_db_instance.this` (dev)                    | Chua tung ton tai trong state; da duoc tao lan dau boi S03 (status `available`) |
| IAM roles `3-tiers-app-development-task*` (dev) | Destroy (S02 done) + Re-create (S03 done) |
| `GhaInfraPlanRole` (CFN IAM resource)           | Update: them inline policy (S01 done), xoa inline policy (S04 mandatory cleanup) |

---

## Cau hoi mo

Khong con cau hoi mo. Kien truc Pattern C da duoc chot voi user truoc khi viet plan nay.

---

## Ngoai pham vi

- Sua loi `allocated_storage` < 20GB: van de nay da duoc fix trong S03 v2 (commit `087d81c` qua PR #23 bao gom fix `rds_storage_gb` 15 -> 20 trong `envs/development/terraform.tfvars`). Ca 2 env hien deu co `rds_storage_gb` >= 20 (dev=20, prod=100).
- Chinh sua cac module khac (ecs_service, frontend_cdn, observability): thuoc Sprint S04 cua ke hoach phased-deploy, khong lien quan den ke hoach fix bomb nay.
- Nang cap terraform hay provider version: da du dieu kien (Terraform 1.13.3, AWS provider 5.100.0).

---

## Trang thai sau S03 (2026-05-18)

S01, S02, S03 da hoan thanh. Apply tren `development` thanh cong sau khi gop 3 PR:

| PR | Commit | Noi dung |
|----|--------|----------|
| #22 | `efa4699` | S02: comment out module rds + iam_app_roles de destroy |
| #23 | `087d81c` | S03 v2: refactor cicd-inject (kien truc Pattern C) + fix rds_storage_gb + hotfix plan workflow placeholder |
| #24 | `3b114ca` | S03 v2 hotfix #2: hardcode secret name trong terraform-apply.yaml, bo `terraform output` dependency |

Trang thai AWS sau apply S03 v2:

- RDS instance `development-postgres`: `available`
- Secret `/3-tiers-app/development/rds/credentials`: ton tai, co value (JSON 4 field) duoc inject boi composite action `sync-secret-value` post-apply
- Secret cu `/3-tiers-app/development/rds/master`: van scheduled deletion (~2026-05-25 tu xoa)
- IAM task roles `3-tiers-app-development-task*`: ton tai
- Bomb defused: `aws_secretsmanager_secret_version` KHONG con trong tfstate; plan refresh chi goi `DescribeSecret` (co trong ReadOnlyAccess)

Buoc tiep theo: S04 (mandatory cleanup) - go inline policy `secrets-read-for-refresh` khoi `gha-infra-plan` vi khong con can `GetSecretValue` cho refresh nua.

---

## Last updated

2026-05-18 by main-thread (S03 closed; apply success on development; 3 PR merged: #22, #23, #24)
