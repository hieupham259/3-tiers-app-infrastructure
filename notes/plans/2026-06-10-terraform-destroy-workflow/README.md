# Terraform Destroy Workflow

## Context

Nguoi dung yeu cau tao mot GitHub Actions workflow cho phep destroy toan bo Terraform resources cua mot environment. Workflow chi co the duoc kich hoat thu cong (manual) qua GitHub UI (`workflow_dispatch`), khong co push hay PR trigger. Theo rang buoc cua CLAUDE.md, production destroy can phai co manual approval gate nghiem ngat de tranh destroy nham.

## Sprints

| ID  | Title                              | Status  | Owner of last update |
|-----|------------------------------------|---------|----------------------|
| S01 | Create terraform-destroy workflow  | planned | task-planner         |

## Open questions

- Khong co cau hoi con pending: tat ca cac quyet dinh thiet ke da duoc xac dinh tu context repo va rang buoc CLAUDE.md.

## Out-of-scope

- Khong sua doi bat ky IaC source nao duoi `modules/`, `envs/`, `global/`, `bootstrap/`.
- Khong tao OIDC role moi: workflow tai su dung role `gha-infra-apply` hien co (co quyen du de destroy). Neu role can them quyen, nguoi dung se phai cap nhat thu cong.
- Khong thay doi `terraform.tfvars` de tat `rds_deletion_protection`: viec nay la tuy chon va phai do nguoi dung quyet dinh truoc khi chay destroy.

## Last updated

2026-06-10 by task-planner
