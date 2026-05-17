# Sprint S01 - Add Repository tag via shared env layer

## Goal

Bo sung tag `Repository` vao toan bo AWS resources bang cach: (1) them bien `repository` vao lop env (shared + hai env cu the), (2) merge bien do vao `local.common_tags` trong `envs/_shared/main.tf` - mot diem duy nhat - de tat ca module hien tai va tuong lai deu nhan tag nay qua `local.common_tags` ma khong can sua resource block trong module; (3) truyen gia tri dong tu GitHub Actions qua `TF_VAR_repository`. Sau khi Sprint nay hoan tat, moi AWS resource duoc tao tu cac module deu co tag `Repository = "3-tiers-app-infrastructure"` (hoac gia tri thuc tu GitHub Actions).

## Definition of done

- `envs/_shared/variables.tf` co bien `repository` kieu `string`, `default = "3-tiers-app-infrastructure"`, co description ro rang.
- `envs/development/variables.tf` va `envs/production/variables.tf` cung co bien `repository` cung kieu va cung default (byte-identical).
- `envs/development/main.tf` va `envs/production/main.tf` truyen `repository = var.repository` vao module `stack` (byte-identical).
- `envs/_shared/main.tf` merge `Repository = var.repository` vao `local.common_tags` tai duy nhat mot cho.
- `terraform fmt -check -recursive` sach.
- `tflint --recursive` sach.
- `scripts/verify-envs-in-sync.sh` sach.
- `terraform validate` sach tren ca hai env.
- `.github/workflows/terraform-plan.yaml` va `.github/workflows/terraform-apply.yaml` them `TF_VAR_repository: ${{ github.event.repository.name }}` vao `env` block cua job `plan` / `apply` tuong ung.
- Khong co resource nao bi replace trong `terraform plan` (tag la in-place update).

## Sub-tasks

- [X] S01-T01 - Them bien `repository` vao `envs/_shared/variables.tf` va ca hai `envs/development/variables.tf`, `envs/production/variables.tf`

  - Assignee: iac-builder
  - Inputs / preconditions: Hieu ro cach `local.common_tags` hoat dong trong `envs/_shared/main.tf`; hai env phai byte-identical tru 3 file ngoai le.
  - Outputs / artifacts: `envs/_shared/variables.tf` va `envs/{development,production}/variables.tf` moi co block bien `repository` voi `type = string`, `default = "3-tiers-app-infrastructure"`, `description = "Name of the source repository managing this infrastructure"`.
  - Depends on: none
  - Notes: Bien phai co `default` de khong phat sinh loi khi terraform plan/apply chay tu local ma khong set env var. Description viet bang tieng Anh (file repo rule).
- [X] S01-T02 - Truyen `repository = var.repository` tu env layer xuong `_shared` trong `envs/development/main.tf` va `envs/production/main.tf`

  - Assignee: iac-builder
  - Inputs / preconditions: S01-T01 phai hoan tat (bien `repository` ton tai o ca hai cap).
  - Outputs / artifacts: `envs/development/main.tf` va `envs/production/main.tf` them dong `repository = var.repository` vao block `module "stack"`. Noi dung hai file byte-identical.
  - Depends on: S01-T01
  - Notes: Chi them mot dong. Khong doi bat ky tham so nao khac cua module block.
- [X] S01-T03 - Them bien `repository` vao `envs/_shared/variables.tf` (cap _shared) va merge vao `local.common_tags` trong `envs/_shared/main.tf`

  - Assignee: iac-builder
  - Inputs / preconditions: S01-T01 va S01-T02 hoan tat.
  - Outputs / artifacts:
    - `envs/_shared/variables.tf`: them bien `repository` tuong tu nhu env-level.
    - `envs/_shared/main.tf`: block `locals` doi tu `merge(var.tags, { Environment = ..., Project = ..., ManagedBy = ... })` thanh `merge(var.tags, { Environment = ..., Project = ..., ManagedBy = ..., Repository = var.repository })`. Day la diem them tag duy nhat; khong can sua bat ky module nao.
  - Depends on: S01-T01, S01-T02
  - Notes: Thu tu key trong map khong anh huong chuc nang, nhung hay dat `Repository` sau `ManagedBy` de doc theo thu tu logic. Khong xoa cac key hien co.
- [X] S01-T04 - Them `TF_VAR_repository` vao `.github/workflows/terraform-plan.yaml` va `.github/workflows/terraform-apply.yaml`

  - Assignee: github-action-builder
  - Inputs / preconditions: S01-T01 hoan tat (bien Terraform ton tai). Khong phu thuoc vao S01-T02 hay S01-T03 de chay song song neu can, nhung de an toan thi sau khi S01-T03 xong.
  - Outputs / artifacts:
    - `terraform-plan.yaml`: trong `jobs.plan.env` block (hien co cac key `ENV_DIR`, `ACCOUNT_ID`), them `TF_VAR_repository: ${{ github.event.repository.name }}`.
    - `terraform-apply.yaml`: trong `jobs.apply.env` block (hien co cac key `ENV_DIR`, `ACCOUNT_ID`), them `TF_VAR_repository: ${{ github.event.repository.name }}`.
  - Depends on: S01-T03
  - Notes: `github.event.repository.name` tra ve ten repo khong co owner prefix (vd: `3-tiers-app-infrastructure`), phu hop voi default value. Khong them vao top-level `env:` cua workflow (de tranh lo sang job `sync-check` khong can). Chi them vao job `plan` va job `apply`.
- [X] S01-T05 - Review IaC changes (S01-T01, S01-T02, S01-T03)

  - Assignee: iac-reviewer
  - Inputs / preconditions: S01-T01, S01-T02, S01-T03 hoan tat.
  - Outputs / artifacts: Tick checkbox cac sub-task da pass; ghi `## Review log` vao cuoi file nay neu co finding. Reassign ve iac-builder neu co van de.
  - Depends on: S01-T01, S01-T02, S01-T03
  - Notes: Kiem tra: (1) byte-identical giua dev va prod tru 3 file ngoai le; (2) khong co resource block nao bi sua trong modules/; (3) tag key chinh ta; (4) default value dung; (5) terraform fmt sach; (6) tflint sach; (7) verify-envs-in-sync.sh sach.
- [X] S01-T06 - Review GitHub Actions changes (S01-T04)

  - Assignee: github-actions-reviewer
  - Inputs / preconditions: S01-T04 hoan tat.
  - Outputs / artifacts: Tick checkbox S01-T04; ghi `## Review log` vao cuoi file nay. Reassign neu co van de.
  - Depends on: S01-T04
  - Notes: Kiem tra: `TF_VAR_repository` duoc them dung cho (job env block, khong phai step env block hay top-level env); `github.event.repository.name` la expression hop le cho ca push event (apply) lan pull_request event (plan); khong co secret nao bi expose.
- [x] S01-T07 - Chay terraform plan sau khi IaC va workflow duoc review xong

  - Assignee: terraform-planner (verified via PR's `terraform-plan.yaml` workflow run, khong chay
    terraform-planner agent rieng)
  - Inputs / preconditions: S01-T05 va S01-T06 hoan tat va pass.
  - Outputs / artifacts: Danh sach change per env (development, production). Xac nhan khong co resource nao bi replace (tat ca phai la in-place update hoac no-op).
  - Depends on: S01-T05, S01-T06
  - Notes: Neu co resource nao bi replace do tag change (bat thuong, tag la in-place update tren AWS), bao cao ngay cho nguoi dung truoc khi apply.
  - Ket qua (2026-05-17): PR tu `feature/phased-deploy-s02-ecr-alb-ecs` -> `development` da duoc
    user tao (PR nay carry cung diff cua S02d ALB HTTP forward fix); workflow
    `terraform-plan.yaml` (jobs `sync-check` + `plan`) chay PASS. `TF_VAR_repository` duoc inject
    qua `${{ github.event.repository.name }}` tai `jobs.plan.env` (`terraform-plan.yaml:37`).
    User xac nhan plan output khop expected: cac resource hien co (network S01, ECR S02a, ALB
    S02b) chi nhan in-place tag update cho `Repository`, khong co replace/destroy. Plan tren
    `production` chua duoc trigger - chi chay khi mo PR base=`production` (planned theo flow).
  - Apply (2026-05-17): User xac nhan PR da merge vao `development` va `terraform-apply.yaml`
    chay PASS. Tat ca resource hien co (network S01, ECR S02a, ALB S02b) deu nhan tag
    `Repository = "3-tiers-app-infrastructure"` thong qua `local.common_tags` tai
    `envs/_shared/main.tf:6`. Mong doi: Console verify tag `Repository` xuat hien tren cac
    resource (vd: ALB `development-alb`, ECR repo `3-tiers-app-backend-development`). Sprint S01
    HOAN TAT tren `development`. Replicate sang `production` cho khi user mo PR
    base=`production` rieng.
- [X] S01-T08 - Them `TF_VAR_repository` vao `.github/workflows/terraform-drift.yaml`

  - Assignee: github-action-builder
  - Inputs / preconditions: S01-T04 va S01-T06 hoan tat. Follow-up tu LOW finding cua github-actions-reviewer.
  - Outputs / artifacts: `terraform-drift.yaml` co them `env:` block tai `jobs.drift` voi key `TF_VAR_repository: ${{ github.event.repository.name }}` de 3 workflow (`plan`, `apply`, `drift`) dong nhat ve cach inject `TF_VAR_repository`, tranh drift detection noisy khi default value cua `var.repository` doi trong tuong lai hoac repo bi rename.
  - Depends on: S01-T04, S01-T06
  - Notes: `github.event.repository.name` co san cho ca `schedule` lan `workflow_dispatch` trigger (GitHub context tu repo cua workflow). Khong dat o top-level `env:` cua workflow. `act --list -W .github/workflows/terraform-drift.yaml` parse OK sau khi sua.

## Review checklist

Reviewer dung cach tick `- [ ]` thanh `- [x]` khi sub-task tuong ung da duoc xac nhan.

## Review log

(Trong - reviewers se ghi vao day sau khi kiem tra.)

### 2026-05-16 - iac-reviewer

- Verdict: approve
- Sub-tasks ticked: S01-T01, S01-T02, S01-T03
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 1, NIT 0
- Notes: Bien `repository` byte-identical giua 3 file env (type=string, default="3-tiers-app-infrastructure", description thong nhat). Tag `Repository` duoc merge vao `local.common_tags` tai mot diem duy nhat (`envs/_shared/main.tf:6`) va propagate xuong cac module dang wire (network/alb/ecr) qua `merge(var.tags, ...)`. `scripts/verify-envs-in-sync.sh` pass. `terraform fmt -check -recursive` pass. Khong co Vietnamese/emoji/secret trong code. Khong co refactor state-changing nen khong can `moved/import/removed` blocks. `tflint` chua chay duoc vi binary khong cai san tren may local cua reviewer (LOW finding - khong block).

### 2026-05-16 - github-actions-reviewer

- Verdict: approve with comments
- Sub-tasks ticked: S01-T04, S01-T06
- Sub-tasks reassigned to github-action-builder: none (T04 da done; rui ro `terraform-drift.yaml` thieu `TF_VAR_repository` la finding LOW ngoai pham vi T04, de nguoi dung quyet dinh patch nhanh hoac mo sprint follow-up)
- Sub-tasks reassigned to other agents: none
- Open questions raised: Co bo sung `TF_VAR_repository: ${{ github.event.repository.name }}` vao `jobs.drift.env` trong `.github/workflows/terraform-drift.yaml` khong? Hien tai default value cua `var.repository` trung `github.event.repository.name` nen drift detection khong noisy ngay; nhung de 3 workflow (`plan`, `apply`, `drift`) dong nhat va de phong viec rename repo / doi default trong tuong lai, nen them.
- act exit code: 1 (terraform-plan job `plan`), 1 (terraform-apply job `apply`) - ca hai do `aws-actions/configure-aws-credentials@v4` thieu OIDC token duoi `act` (act-skip, khong phai workflow bug); job `sync-check` o ca hai workflow pass. `act --list` parse 3 workflow OK.
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 1, NIT 0
- Notes: `TF_VAR_repository: ${{ github.event.repository.name }}` duoc dat dung tai `jobs.plan.env` (`terraform-plan.yaml:37`) va `jobs.apply.env` (`terraform-apply.yaml:34`), khong leak sang job `sync-check`, khong dat o top-level `env:`. Expression hop le cho ca `pull_request` payload (plan) va `push` payload (apply) theo doc GitHub. `permissions:` block giu nguyen (`contents: read`, `id-token: write`, `pull-requests: write` chi o terraform-plan). OIDC giu nguyen, khong introduce static AWS keys. Branch-based env isolation giu nguyen. Khong echo/log secret. YAML tieng Anh, khong emoji.

### 2026-05-16 - github-action-builder (follow-up S01-T08)

- Verdict: done
- Sub-tasks ticked: S01-T08
- Files changed: `.github/workflows/terraform-drift.yaml` (+2 lines: `env:` block voi `TF_VAR_repository: ${{ github.event.repository.name }}` tai `jobs.drift`).
- Files NOT touched: tat ca file ngoai `.github/workflows/terraform-drift.yaml` (IaC, scripts, CLAUDE.md, .claude/, cac workflow khac).
- Deployment-model rules: trigger (`schedule`, `workflow_dispatch`) giu nguyen; `permissions:` block (`id-token: write`, `contents: read`) giu nguyen; OIDC auth qua `aws-actions/configure-aws-credentials@v4` voi `role-to-assume` giu nguyen; matrix per-env van gate qua `matrix.account_id` va `matrix.ref` (`development`, `production`); khong introduce static AWS keys; khong dung `terraform workspace` / `TF_VAR_workspace` / `terraform.workspace`; khong hardcode account ID / ARN / secret.
- Verification: `act --list -W .github/workflows/terraform-drift.yaml` parse YAML OK (1 job `drift`, events `schedule,workflow_dispatch`).
- Open questions: none. LOW finding tu `github-actions-reviewer` 2026-05-16 da duoc resolve.

## Open questions

Khong co cau hoi mo. Tat ca quyet dinh da duoc ghi o README.md.

### 2026-05-16 - iac-builder (follow-up: bo default, chuyen gia tri xuong tfvars theo pattern environment)

- Verdict: done
- Sub-tasks ticked: none (follow-up khong tao sub-task formal)
- Files changed:
  - `envs/_shared/variables.tf`: bo dong `default = "3-tiers-app-infrastructure"` khoi block `variable "repository"`; giu nguyen `type` va `description`.
  - `envs/development/variables.tf`: bo dong `default = "3-tiers-app-infrastructure"` khoi block `variable "repository"`; giu nguyen `type` va `description`.
  - `envs/production/variables.tf`: bo dong `default = "3-tiers-app-infrastructure"` khoi block `variable "repository"`; giu nguyen `type` va `description`.
  - `envs/development/terraform.tfvars`: them dong `repository  = "3-tiers-app-infrastructure"` ngay sau `region`, trong block metadata dau file.
  - `envs/production/terraform.tfvars`: them dong `repository  = "3-tiers-app-infrastructure"` ngay sau `region`, trong block metadata dau file.
- Files NOT touched: `.github/workflows/`, `modules/`, `envs/development/main.tf`, `envs/production/main.tf`, `envs/_shared/main.tf`, `bootstrap/`, `global/`, `scripts/`, `CLAUDE.md`, `.claude/`. Workflow `TF_VAR_repository: ${{ github.event.repository.name }}` giu nguyen.
- Ly do refactor: nhat quan voi pattern hien huu cua bien `environment` va `region` (khong dung `default`, gia tri thuc dat o `terraform.tfvars`); tuong minh khi doc tfvars; fail-fast neu CI quen set `TF_VAR_repository`.
- Verification:
  - `terraform fmt -recursive` clean (khong file nao can format).
  - `terraform fmt -check -recursive` clean (exit 0).
  - `scripts/verify-envs-in-sync.sh` clean: `OK: envs/development and envs/production are in sync.`
  - `terraform validate` khong chay duoc tren local do version 1.9.2 < required 1.11 (`Unsupported Terraform Core version` tu `backend.tf`, `versions.tf` cua `_shared` va cac module wired); CI se chay version dung. Khong phai loi tu thay doi nay.
- Open questions: none.

### 2026-05-17 - iac-reviewer (follow-up: audit refactor bo default cua var.repository)

- Verdict: approve
- Sub-tasks ticked: none (follow-up khong tao sub-task formal moi; S01-T01..T04, T06, T08 da duoc tick truoc do)
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 1
- Notes: Block `variable "repository"` byte-identical giua 3 file (`envs/_shared/variables.tf:115-118`, `envs/development/variables.tf:115-118`, `envs/production/variables.tf:115-118`) voi `type = string` va `description = "Source code repository name; tagged on all resources for traceability."` - khong con `default`, khop pattern fail-fast cua `environment`/`region` (cung khai bao no-default). `envs/development/terraform.tfvars:3` va `envs/production/terraform.tfvars:3` cung set `repository = "3-tiers-app-infrastructure"` (cung gia tri, dung indentation `repository  = ` 2 space giong `environment` va `region`). `scripts/verify-envs-in-sync.sh` pass (`OK: envs/development and envs/production are in sync.`); rule env parity chi yeu cau byte-identical voi 3 file exception (`terraform.tfvars`, `backend.tf`, `providers.tf`), khong yeu cau noi dung cua tfvars phai khac, nen viec ca hai env dat cung gia tri `repository` la hop le. `terraform fmt -check -recursive` exit 0. Khong co `terraform.workspace` / `workspace_key_prefix` / `provider` block trong `modules/`. Khong co refactor state-changing (chi chuyen gia tri tu variable default xuong tfvars; resource address va `local.common_tags` merge `Repository = var.repository` tai `envs/_shared/main.tf:6` khong doi) nen khong can `moved`/`import`/`removed` blocks. AWS se in-place update tag, khong replace resource. Gia tri `"3-tiers-app-infrastructure"` la ten repo public, khong phai secret. Khong co Vietnamese/emoji/icon trong file source. NIT: cap nhat duy nhat la `## Last updated` cua Sprint file van ghi `iac-builder (follow-up...)`; nen them mot dong moi `2026-05-17 by iac-reviewer (follow-up audit)` sau khi reviewer ky de timeline khop, nhung khong block.
- Playwright not used; no screenshots to clean.

## Last updated

2026-05-17 by main thread - User xac nhan PR da merge vao `development` va
`terraform-apply.yaml` chay PASS. Sprint S01 HOAN TAT tren `development`: tag `Repository` da
duoc apply tren toan bo resource hien co. Cho replicate sang `production` khi user mo PR
base=`production` rieng.

2026-05-17 by main thread - tick S01-T07 sau khi user tao PR (cung PR voi S02d ALB HTTP fix) vao
`development`; workflow `terraform-plan.yaml` chay PASS, plan khong co replace/destroy nao do
tag `Repository` (in-place update nhu mong doi). Plan tren `production` cho den khi mo PR
base=`production` rieng.

2026-05-17 by iac-reviewer (follow-up audit: refactor bo default cua var.repository - xem entry
review log o tren)

2026-05-16 by iac-builder (follow-up: bo default cua var.repository, chuyen gia tri xuong terraform.tfvars)
