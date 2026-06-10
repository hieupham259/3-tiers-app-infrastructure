# Destroy Dev RDS Only - Targeted Destroy voi Staged prevent_destroy Removal

## Context

Workflow `terraform-destroy.yaml` da duoc tao truoc do nhung FAIL khi chay `terraform destroy`
toan bo vi 3 resource co `lifecycle { prevent_destroy = true }`:
- `module.stack.module.rds.aws_db_instance.this`
- `module.stack.module.rds.aws_secretsmanager_secret.db`
- `module.stack.module.frontend-cdn.aws_s3_bucket.frontend`

Nguoi dung da chot yeu cau HEP HON: chi cho phep xoa RIENG `aws_db_instance.this` cua
environment development. Giai phap gom 2 huong tac dong song song:

1. Sua workflow `terraform-destroy.yaml` de chay targeted destroy co dinh vao
   `module.stack.module.rds.aws_db_instance.this` (thay vi `terraform destroy` toan bo).
   Giu nguyen toan bo co che an toan hien co: `workflow_dispatch`, `confirm_destroy`,
   GitHub Environment gate, OIDC `gha-infra-apply`.

2. Go `prevent_destroy` khoi `aws_db_instance.this` trong `modules/rds/main.tf`
   (giu lai `ignore_changes`; GIU `prevent_destroy` tren `aws_secretsmanager_secret.db`
   va `aws_s3_bucket.frontend`). Vi module dung chung cho ca development va production,
   viec go `prevent_destroy` anh huong ca 2 env - kem rui ro prod duoc ghi ro trong plan.

Theo convention staged 2 PR cua repo:
- PR1 (Sprint S01 + S02): go `prevent_destroy` + targeted destroy workflow + review + plan.
- PR2 (Sprint S03): sau khi destroy dev DB xong, khoi phuc `prevent_destroy` tren
  `aws_db_instance.this` de bao ve lai ca 2 env.

## Sprints

| ID  | Title                                          | Status  | Owner of last update |
|-----|------------------------------------------------|---------|----------------------|
| S01 | Go prevent_destroy tren aws_db_instance.this   | planned | task-planner         |
| S02 | Sua workflow targeted destroy DB               | planned | task-planner         |
| S03 | Khoi phuc prevent_destroy sau khi destroy xong | planned | task-planner         |

## Open questions

- Khong co cau hoi pending: tat ca quyet dinh da duoc nguoi dung chot.

## Out-of-scope

- Khong destroy cac resource khac (Secret, S3, ECS, ALB, VPC, v.v.).
- Khong thay doi `prevent_destroy` tren `aws_secretsmanager_secret.db` hoac `aws_s3_bucket.frontend`.
- Khong destroy production DB (workflow chi target dev, production chi co the dung neu nguoi dung dispatch
  voi environment=production VA repo admin da cau hinh Required reviewers tren GitHub Environment "production").
- Khong thay doi `rds_deletion_protection` trong `terraform.tfvars` (da la `false` o dev).

## Rui ro can luu y

1. MAT DU LIEU: Xoa `aws_db_instance.this` o development la KHONG THE PHUC HOI (skip_final_snapshot=true
   cho dev). Tat ca data trong DB dev se mat vinh vien khi destroy chay xong.
2. ANH HUONG PRODUCTION: Module `modules/rds` dung chung. Viec go `prevent_destroy` khoi
   `aws_db_instance.this` trong Sprint S01 se anh huong ca production. Neu ai do vo tinh chay
   `terraform destroy` tren production TRUOC KHI Sprint S03 khoi phuc `prevent_destroy`, Terraform
   se co the xoa DB production. Giam thieu rui ro: (a) workflow da duoc sua o S02 de chi chay
   targeted destroy vao dev; (b) GitHub Environment "production" can co Required reviewers; (c) S03
   can duoc dispatch ngay sau khi destroy dev DB xong.
3. DOWNTIME: ECS tasks tren development se mat ket noi DB sau khi destroy.

## Last updated

2026-06-11 by task-planner
