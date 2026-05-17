# Them tag Repository vao tat ca AWS resources

## Context

Nguoi dung yeu cau bo sung tag `Repository` vao toan bo AWS resources trong repo. Tag nay cho biet code IaC cua resource duoc quan ly boi repo nao, phuc vu viec truy vet chi phi va quan tri. Gia tri mac dinh la `3-tiers-app-infrastructure`; neu GitHub Actions co the truyen gia tri dong tu `GITHUB_REPOSITORY` (vd: `hieupham259/3-tiers-app-infrastructure`) thi dung gia tri thuc.

Phuong an duoc chon: them bien `repository` vao `envs/_shared/variables.tf` va `envs/development/variables.tf` / `envs/production/variables.tf`, dua vao `local.common_tags` trong `envs/_shared/main.tf` (mot diem duy nhat), truyen qua `TF_VAR_repository` tu GitHub Actions. Khong can sua bat ky resource block nao trong modules, vi tat ca module deu nhan `tags` tu `local.common_tags`.

Quyet dinh thiet ke:
- Tag key: `Repository` (chuan AWS tagging convention, dung nhat quan).
- Gia tri mac dinh: `3-tiers-app-infrastructure` (theo yeu cau nguoi dung).
- Co che truyen dong: `TF_VAR_repository=${{ github.repository }}` trong env block cua job `plan` va `apply`. `github.repository` tra ve `owner/repo-name`, vi du `hieupham259/3-tiers-app-infrastructure`. Neu muon chi lay ten repo (khong co owner prefix) thi dung `${{ github.event.repository.name }}`; plan chon `github.event.repository.name` vi no gon hon va khop voi default value.
- Bien `repository` duoc khai bao co `default = "3-tiers-app-infrastructure"` nen khong bat buoc phai set `TF_VAR_repository`; neu workflow khong set thi Terraform dung default.
- Hai env `envs/development` va `envs/production` dung cung mot `variables.tf` noi dung (tru `terraform.tfvars`, `backend.tf`, `providers.tf`): ca hai phai them bien `repository` dong thoi.

## Sprints

| ID  | Title                                    | Status  | Owner of last update |
|-----|------------------------------------------|---------|----------------------|
| S01 | Add Repository tag via shared env layer  | done tren `development` (merged + apply PASS 2026-05-17); cho replicate `production` | main thread |

## Open questions

Khong con cau hoi mo. Tat ca quyet dinh da duoc ghi ro trong Context.

## Out-of-scope

- Khong sua bat ky resource block nao ben trong `modules/` (module nhan tag qua `var.tags` - da la dung pattern, khong can doi).
- Khong them tag `Repository` vao `bootstrap/` CloudFormation (day la infra bootstrap rieng biet, nguoi dung khong yeu cau).
- Khong doi ten tag key thanh bat ky gia tri khac ngoai `Repository`.

## Last updated

2026-05-17 by main thread - User xac nhan PR da merge vao `development` va
`terraform-apply.yaml` chay PASS. Sprint S01 HOAN TAT tren `development`: tag `Repository` apply
in-place tren toan bo resource hien co. Cho replicate sang `production`.

2026-05-17 by main thread - cap nhat status S01: builder + reviewer xong; user da tao PR
(combined voi S02d ALB HTTP fix) tu `feature/phased-deploy-s02-ecr-alb-ecs` vao `development`,
workflow `terraform-plan.yaml` chay PASS, plan khong co replace/destroy do tag `Repository`
(in-place update). Cho buoc merge cua user.

2026-05-16 by task-planner
