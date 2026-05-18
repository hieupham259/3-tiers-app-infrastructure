# Sprint S03 - CI/CD Inject Secret Value (Pattern C)

## Cap nhat lan cuoi

2026-05-18 by task-planner (rewrite hoan toan tu S03 v1 `secret_string_wo` sang S03 v2 `cicd-inject`)

---

## Muc tieu

Refactor `modules/rds` de tach biet hai trach nhiem:

1. Terraform chi quan ly metadata cua secret (`aws_secretsmanager_secret`): name, description, KMS key, tags, lifecycle. Terraform KHONG quan ly gia tri (value) cua secret.
2. CI/CD workflow (`terraform-apply.yaml`) inject gia tri secret sau khi `terraform apply` thanh cong, bang cach goi `aws secretsmanager put-secret-value`.

Password RDS xuat phat tu GitHub Environment Secret `RDS_MASTER_PASSWORD` (rieng cho tung env: `development` va `production`). Password KHONG nằm trong code, KHONG trong tfstate, KHONG trong Terraform variables file.

Sau khi Sprint nay hoan thanh:
- Terraform plan chi goi `DescribeSecret` khi refresh metadata --- quyen nay co trong `ReadOnlyAccess` --- bomb duoc pha vinh vien.
- `aws_secretsmanager_secret_version` KHONG bao gio trong tfstate -> khong bao gio goi `GetSecretValue`.
- `gha-infra-plan` role KHONG can quyen `GetSecretValue` nua -> inline policy `secrets-read-for-refresh` (them o S01) tro nen thua va se duoc xoa o S04.

---

## Pre-conditions

- S02 da hoan thanh day du: apply comment-out thanh cong; state dev sach (khong con resource nao tu `module.rds` hay `module.iam_app_roles`).
- Secret cu `/3-tiers-app/development/rds/master` dang o trang thai "scheduled deletion" (7 ngay tu ~2026-05-18, tu xoa ~2026-05-25). Secret moi se co ten KHAC (`credentials` thay vi `master`) nen KHONG conflict --- KHONG can doi.
- `envs/_shared/main.tf` hien tai co 2 module bi comment voi marker `# S02-TEMP`.
- User se add GitHub Environment Secret `RDS_MASTER_PASSWORD` (T07) TRUOC khi merge PR S03 vao `development`.

---

## Chi tiet ky thuat

### Secret name moi

`/3-tiers-app/${var.environment}/rds/credentials`

(Doi tu `master` thanh `credentials` de tranh nhap nho voi secret cu dang scheduled deletion.)

### Cai gi Terraform quan ly (metadata only)

```
resource "aws_secretsmanager_secret" "db" {
  name        = "/3-tiers-app/${var.environment}/rds/credentials"
  description = "RDS master credentials for ${var.environment}"
  kms_key_id  = var.kms_key_arn
  tags        = merge(var.tags, { Name = "/3-tiers-app/${var.environment}/rds/credentials" })

  lifecycle {
    prevent_destroy = true
  }
}
```

Khong co `aws_secretsmanager_secret_version`. Khong co `random_password`. Password den tu `var.master_password`.

### Cai gi CI/CD quan ly (gia tri secret)

Sau buoc `terraform apply` thanh cong, workflow them 1 step:

```bash
aws secretsmanager put-secret-value \
  --secret-id "$(terraform output -raw rds_secret_arn)" \
  --secret-string "{\"username\":\"app_admin\",\"password\":\"$TF_VAR_rds_master_password\",\"dbname\":\"appdb\",\"port\":5432}"
```

Step nay PHAI fail workflow neu khong thanh cong (khong dung `continue-on-error`). Neu fail, user rerun workflow sau khi debug.

### Password flow

```
GitHub Environment Secret RDS_MASTER_PASSWORD
  |
  v (set boi workflow: TF_VAR_rds_master_password)
aws_db_instance.this.password = var.master_password
  |
  v (sau apply)
aws secretsmanager put-secret-value (CI/CD step)
  |
  v
Secret value: {"username":"app_admin","password":"<password>","dbname":"appdb","port":5432}
```

### Lifecycle ignore_changes tren aws_db_instance

```hcl
lifecycle {
  ignore_changes  = [password]
  prevent_destroy = true
}
```

`ignore_changes = [password]` dam bao: neu TF_VAR_rds_master_password thay doi (rotation), Terraform KHONG plan replace RDS instance. Password chi thay doi tren AWS khi user cap nhat GitHub Environment Secret VA re-apply.

### Idempotency cua PutSecretValue

Neu workflow chay lai (retry), `put-secret-value` goi 2 lan -> AWS tao 2 version (AWSPENDING -> AWSCURRENT). Chap nhan duoc: latest version luon active, gia tri giong nhau.

### Quyen IAM

- `gha-infra-apply` role co `AdministratorAccess` -> da bao gom `secretsmanager:PutSecretValue` -> KHONG can thay doi.
- `gha-infra-plan` role: `secretsmanager:GetSecretValue` tu S01 khong con can thiet voi kien truc moi. S04 se xoa inline policy nay (mandatory, khong con optional).

### Drift detection (metadata only)

`aws_secretsmanager_secret.db` trong state chi chua metadata. Terraform chi goi `DescribeSecret` khi refresh -> quyen nay trong `ReadOnlyAccess` -> an toan. Gia tri secret (JSON password) KHONG trong tfstate -> Terraform khong detect drift tren value. Source of truth cho value la GitHub Environment Secret.

### Multi-env support

Workflow dang co:
```yaml
environment: ${{ github.ref == 'refs/heads/production' && 'production' || 'development' }}
```

- Push vao branch `development` -> GitHub Environment `development` -> `secrets.RDS_MASTER_PASSWORD` cua env `development`.
- Push vao branch `production` -> GitHub Environment `production` -> `secrets.RDS_MASTER_PASSWORD` cua env `production` (gia tri KHAC).

Khong can thay doi logic chon environment trong workflow.

---

## Sub-tasks

- [x] S03-T01 - Sua `modules/rds/main.tf`: bo `random_password`, bo `aws_secretsmanager_secret_version`, doi password source sang `var.master_password`, doi secret name
  - Assignee: iac-builder
  - Inputs / preconditions: `modules/rds/main.tf` hien tai
  - Outputs / artifacts: `modules/rds/main.tf` sau khi sua:
    - Xoa toan bo resource `random_password "master"`
    - Xoa toan bo resource `aws_secretsmanager_secret_version "db"`
    - `aws_secretsmanager_secret.db`: doi `name` sang `/3-tiers-app/${var.environment}/rds/credentials`; giu `description`, `kms_key_id`, `tags`; giu `lifecycle { prevent_destroy = true }`
    - `aws_db_instance.this`: doi `password = random_password.master.result` sang `password = var.master_password`; them `ignore_changes = [password]` vao lifecycle block; giu `prevent_destroy = true`
    - Khong cham `aws_security_group.this`, `aws_db_subnet_group.this`, cac data source, cac resource khac
  - Depends on: none
  - Notes: `ignore_changes = [password]` va `prevent_destroy = true` phai cung ton tai trong lifecycle block cua `aws_db_instance.this`. Neu hien tai block lifecycle chua co, tao moi voi ca 2 field.

- [x] S03-T02 - Sua `modules/rds/variables.tf`: them variable `master_password`; bo variable `master_password_length` (neu co)
  - Assignee: iac-builder
  - Inputs / preconditions: `modules/rds/variables.tf` hien tai; S03-T01 done
  - Outputs / artifacts: `modules/rds/variables.tf` sau khi sua:
    - Them variable `master_password` voi `type = string`, `sensitive = true`, `nullable = false`, description ro rang
    - Xoa variable `master_password_length` neu co (vi `random_password` da bi xoa)
    - Giu cac variable khac nguyen ven
  - Depends on: S03-T01
  - Notes: Khong dat `default` cho `master_password` --- khong co gia tri mac dinh an toan cho password.

- [x] S03-T03 - Sua `envs/_shared/variables.tf` va `envs/_shared/main.tf`: them `rds_master_password`, wiring module rds, uncomment modules
  - Assignee: iac-builder
  - Inputs / preconditions: S03-T02 done; `envs/_shared/main.tf` co 2 module dang comment voi marker `# S02-TEMP`
  - Outputs / artifacts:
    - `envs/_shared/variables.tf`: them variable `rds_master_password` voi `type = string`, `sensitive = true`, `nullable = false`
    - `envs/_shared/main.tf`: uncomment `module "rds"` va `module "iam_app_roles"`; xoa marker `# S02-TEMP`; them `master_password = var.rds_master_password` vao block `module "rds"`; giu cac comment tam thoi da co (`ingress_security_group_ids = [] # S03: temporary empty list, restored in S04` va `frontend_bucket_arn = null # S03: temporary null, restored in S04`)
    - `envs/_shared/outputs.tf`: uncomment `output "rds_endpoint"` neu dang comment
  - Depends on: S03-T02
  - Notes: Khong uncomment cac module khac (`ecs_service`, `frontend_cdn`, `observability`) --- cac module nay thuoc Sprint S04 cua ke hoach phased-deploy.

- [x] S03-T04 - Sua `envs/development/variables.tf` va `envs/production/variables.tf`: them variable `rds_master_password`
  - Assignee: iac-builder
  - Inputs / preconditions: S03-T03 done
  - Outputs / artifacts:
    - `envs/development/variables.tf`: them variable `rds_master_password` voi `type = string`, `sensitive = true`, `nullable = false`
    - `envs/production/variables.tf`: them variable `rds_master_password` voi `type = string`, `sensitive = true`, `nullable = false`
    - `envs/development/terraform.tfvars` va `envs/production/terraform.tfvars`: KHONG them gia tri `rds_master_password` (gia tri den tu `TF_VAR_rds_master_password` trong workflow, KHONG commit vao file)
  - Depends on: S03-T03
  - Notes: Hai file variables.tf phai giong het nhau cho variable nay (bat buoc: `scripts/verify-envs-in-sync.sh` kiem tra byte-identical). Tuyet doi KHONG them password vao tfvars hay bat ky file nao khac.

- [x] S03-T05 - Sua `.github/workflows/terraform-apply.yaml`: them `TF_VAR_rds_master_password` env var va post-apply `put-secret-value` step
  - Assignee: github-action-builder
  - Inputs / preconditions: S03-T04 done; `terraform-apply.yaml` hien tai
  - Outputs / artifacts: `.github/workflows/terraform-apply.yaml` sau khi sua:
    - Them env var `TF_VAR_rds_master_password: ${{ secrets.RDS_MASTER_PASSWORD }}` vao job apply (o muc `env:` cua job, cung level voi cac TF_VAR khac neu co, hoac them env block moi cho job apply)
    - Them step moi sau buoc `terraform apply` (chi chay neu apply thanh cong, khong dung `continue-on-error: true`):
      ```yaml
      - name: Inject RDS secret value
        run: |
          SECRET_ARN=$(terraform -chdir=envs/${{ env.TF_WORKING_DIR || 'development' }} output -raw rds_secret_arn)
          aws secretsmanager put-secret-value \
            --secret-id "$SECRET_ARN" \
            --secret-string "{\"username\":\"app_admin\",\"password\":\"$TF_VAR_rds_master_password\",\"dbname\":\"appdb\",\"port\":5432}"
      ```
      (gia tri chinh xac cua `chdir` phu thuoc vao cau truc hien tai cua workflow --- github-action-builder phai doc workflow truoc khi sua)
    - Khong thay doi cac phan khac cua workflow (plan job, environment selection, OIDC setup, cac step khac)
  - Depends on: S03-T04
  - Notes: |
      Step `Inject RDS secret value` PHAI fail workflow neu `put-secret-value` tra ve loi (khong dung `|| true`, khong dung `continue-on-error`). Ly do: neu step nay fail, secret rong va app khong doc duoc credentials -> workflow MUST fail de user biet va rerun.
      `terraform output -raw rds_secret_arn` lay ARN tu Terraform output cua module rds --- iac-builder phai dam bao output `rds_secret_arn` ton tai trong `envs/_shared/outputs.tf` (neu chua co, add vao S03-T03).

- [x] S03-T06 - Audit IaC diff (T01 den T04)
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S03-T01, T02, T03, T04
  - Outputs / artifacts: tick checkbox tung sub-task; bao cao findings co severity tag; reassign neu co van de
  - Depends on: S03-T04
  - Notes: |
      Kiem tra dac biet:
      (1) `modules/rds/main.tf`: khong con `random_password`, khong con `aws_secretsmanager_secret_version`; `aws_db_instance.this.password = var.master_password`; lifecycle co ca `ignore_changes = [password]` va `prevent_destroy = true`.
      (2) `modules/rds/variables.tf`: co `master_password` voi `sensitive = true` va `nullable = false`; khong co default.
      (3) `envs/_shared/variables.tf`, `envs/development/variables.tf`, `envs/production/variables.tf`: ca 3 co variable `rds_master_password` giong het nhau (sensitive, nullable = false, no default).
      (4) `envs/development/terraform.tfvars` va `envs/production/terraform.tfvars`: KHONG co dong `rds_master_password` (phai vang mat).
      (5) `envs/_shared/main.tf`: module rds co `master_password = var.rds_master_password`; 2 module uncomment, marker S02-TEMP da xoa; comment tam thoi S03 van con.
      (6) `scripts/verify-envs-in-sync.sh` pass.
      (7) `terraform fmt -check -recursive` pass.
      (8) Khong co hardcode password, ARN account, secret value trong bat ky file.

- [x] S03-T07 - Audit workflow diff (T05)
  - Assignee: github-actions-reviewer
  - Inputs / preconditions: diff cua S03-T05
  - Outputs / artifacts: tick checkbox; bao cao findings; reassign neu co van de
  - Depends on: S03-T05
  - Notes: |
      Kiem tra dac biet:
      (1) `TF_VAR_rds_master_password` duoc set o muc `env:` cua job apply, lay tu `secrets.RDS_MASTER_PASSWORD` --- KHONG echo, KHONG log ra stdout.
      (2) Step `Inject RDS secret value` khong co `continue-on-error: true`.
      (3) Step nay chi chay sau `terraform apply` thanh cong (khong co `if: always()`).
      (4) `terraform output -raw rds_secret_arn` tro den dung output name.
      (5) JSON trong `--secret-string` co du 4 field: username, password, dbname, port.
      (6) SKIP chay `act` locally vi step nay goi AWS API that (put-secret-value) --- ghi ro trong review log: "SKIP act: step requires real AWS credentials and live secret ARN".
      (7) Xac nhan workflow khong thay doi logic chon environment, OIDC, plan job, cac step khac.

- [ ] S03-T08 - User: add GitHub Environment Secret `RDS_MASTER_PASSWORD` cho env `development` (va `production` neu can)
  - Assignee: user
  - Inputs / preconditions: S03-T06 va S03-T07 da approve; PR S03 chua duoc merge
  - Outputs / artifacts: GitHub Environment `development` co secret `RDS_MASTER_PASSWORD` duoc set; (tuy chon: GitHub Environment `production` co secret `RDS_MASTER_PASSWORD` rieng)
  - Depends on: S03-T06, S03-T07
  - Notes: |
      Cach tao password an toan (chay tren may local, KHONG commit ket qua):
        openssl rand -base64 32
      Vao GitHub repo > Settings > Environments > development > Environment secrets > Add secret:
        Name: RDS_MASTER_PASSWORD
        Value: <ket qua cua openssl>
      Lam tuong tu cho `production` (gia tri KHAC voi dev).
      KHONG luu password nay vao file nao trong repo. KHONG paste vao terraform.tfvars, CLAUDE.md, hay bat ky note nao.

- [ ] S03-T09 - User: commit + push + tao PR + merge + verify apply + verify bomb duoc pha
  - Assignee: user
  - Inputs / preconditions: S03-T08 hoan thanh (GitHub Secret da set); PR S03 san sang merge
  - Outputs / artifacts: apply thanh cong; RDS instance trang thai `available`; secret `/3-tiers-app/development/rds/credentials` ton tai; plan workflow cua PR test pass ma KHONG co `AccessDeniedException`
  - Depends on: S03-T08
  - Notes: |
      Quy trinh:
      1. Commit tat ca thay doi S03 (T01-T05) vao branch `feature/phased-deploy-s03-rds-iam`.
      2. Push va tao PR vao `development`.
      3. Doi plan workflow pass (phai pass vi secret metadata khong goi GetSecretValue).
      4. Merge. Approve apply workflow trong GitHub Actions Environment `development`.
      5. Doi apply thanh cong (RDS instance tao mat ~10-15 phut).
      6. Verify tren AWS Console:
         - RDS instance `development-postgres` trang thai `available`.
         - Secret `/3-tiers-app/development/rds/credentials` ton tai va co value (khong rong).
         - IAM roles `3-tiers-app-development-task*` ton tai.
         - secret cu `/3-tiers-app/development/rds/master` van dang "scheduled deletion" (se tu xoa ~2026-05-25) --- binh thuong.
      7. Verify bomb duoc pha vinh vien:
         - Tao 1 PR test nho (sua comment trong terraform.tfvars).
         - Plan workflow phai pass HOAN TOAN: khong co dong `AccessDeniedException` trong log.
         - Xac nhan trong AWS CloudTrail hoac plan log: chi thay goi `DescribeSecret`, khong thay `GetSecretValue` cho secret nay.
      8. Sau khi xac nhan step 7: bao cao cho team -> keo sang S04 (mandatory cleanup inline policy).

---

## Acceptance criteria

- `modules/rds/main.tf`: khong co `random_password`, khong co `aws_secretsmanager_secret_version`; `aws_db_instance` co `password = var.master_password` va `lifecycle { ignore_changes = [password]; prevent_destroy = true }`.
- `modules/rds/variables.tf`: co variable `master_password` voi `sensitive = true`, `nullable = false`, khong co `default`.
- `envs/_shared/variables.tf`, `envs/development/variables.tf`, `envs/production/variables.tf`: ca 3 co variable `rds_master_password` giong het nhau.
- `terraform.tfvars` (ca 2 env): KHONG co `rds_master_password`.
- `envs/_shared/main.tf`: 2 module uncomment, marker S02-TEMP da xoa.
- `.github/workflows/terraform-apply.yaml`: co `TF_VAR_rds_master_password` env var va step `Inject RDS secret value` sau apply, khong co `continue-on-error`.
- `scripts/verify-envs-in-sync.sh` pass.
- `terraform fmt -check -recursive` pass.
- Apply thanh cong: RDS instance `available`, secret `/3-tiers-app/development/rds/credentials` co value, IAM roles ton tai.
- PR test sau apply: plan workflow pass, khong co `AccessDeniedException`.

---

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

### 2026-05-18 - github-actions-reviewer
- Verdict: approve
- Sub-tasks ticked: S03-T05, S03-T07
- Sub-tasks reassigned to github-action-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- act exit code: SKIPPED (per Sprint plan: step requires real AWS credentials and live secret ARN created by terraform apply earlier in the same workflow run)
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0
- Evidence:
  - `.github/workflows/terraform-apply.yaml:35` - `TF_VAR_rds_master_password: ${{ secrets.RDS_MASTER_PASSWORD }}` o job-level env cua job `apply`.
  - `.github/workflows/terraform-apply.yaml:72-86` - step `Inject RDS secret value` dat ngay sau `Terraform apply` (line 69-70), khong `continue-on-error`, khong `if: always()`, khong echo password.
  - JSON build qua `jq -nc --arg pw ...` -> safe escape, password khong xuat hien tren command line cua `aws secretsmanager put-secret-value`.

### 2026-05-18 - iac-reviewer
- Verdict: approve with comments
- Sub-tasks ticked: S03-T01, S03-T02, S03-T03, S03-T04, S03-T06
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: `envs/development/terraform.tfvars` hien tai dat `rds_storage_gb = 15` (< 20GB minimum cua PostgreSQL tren gp3). Commit fix `9ff2855` (`rds_storage_gb` -> 20) KHONG nam trong nhanh `fix/secret-version-refresh-bomb-s03-rev2` cung nhu `origin/development`. README S03 ghi nhan "Ngoai pham vi" voi gia dinh fix da co; thuc te chua co. Truoc khi merge S03 va apply: user can cherry-pick `9ff2855` hoac tach PR fix storage, neu khong apply RDS se fail (ValidationError: gp3 minimum 20GB).
- Findings count: BLOCKER 0, HIGH 1, MEDIUM 0, LOW 1, NIT 0
- Evidence:
  - `modules/rds/main.tf:24-34` - `aws_secretsmanager_secret.db` chi quan ly metadata, name moi `/3-tiers-app/${var.environment}/rds/credentials`, `lifecycle { prevent_destroy = true }` co commentary.
  - `modules/rds/main.tf:36-79` - `aws_db_instance.this`: `password = var.master_password` (line 51), `lifecycle { prevent_destroy = true; ignore_changes = [final_snapshot_identifier, password] }` (line 74-78).
  - `modules/rds/main.tf` - `random_password.master` va `aws_secretsmanager_secret_version.db` da xoa hoan toan (grep `random_password|secret_string` trong `modules/` -> no matches).
  - `modules/rds/variables.tf:70-75` - `master_password` co `type = string`, `sensitive = true`, `nullable = false`, khong co `default`, description ro nguon goc. Khong con `master_password_length` (xac nhan vi variable da khong co tu truoc).
  - `envs/_shared/variables.tf:60-65` - `rds_master_password` (sensitive, nullable=false, no default).
  - `envs/_shared/main.tf:44-69` - 2 module uncomment, marker `# S02-TEMP` xoa, `master_password = var.rds_master_password`, comment tam thoi S03 (`ingress_security_group_ids = []`, `frontend_bucket_arn = null`) van giu.
  - `envs/_shared/outputs.tf:65-74` - `rds_endpoint` uncomment + output moi `rds_secret_arn = module.rds.secret_arn` (su dung output sẵn co cua `modules/rds/outputs.tf:26-29`).
  - `envs/development/variables.tf` vs `envs/production/variables.tf` byte-identical (`cmp -s` pass).
  - `envs/development/main.tf` vs `envs/production/main.tf` byte-identical (`cmp -s` pass), ca 2 deu co `rds_master_password = var.rds_master_password` trong wrapper `module "stack"`.
  - `envs/development/terraform.tfvars` va `envs/production/terraform.tfvars` khong chua `rds_master_password` (`Grep` no matches).
  - `modules/iam-app-roles/main.tf` khong bi cham trong diff; van tham chieu `var.rds_secret_arn` -> wiring qua `module.rds.secret_arn`.
  - `terraform fmt -check -recursive` exit 0.
  - `terraform -chdir=envs/development validate` & `terraform -chdir=envs/production validate` ca 2 success.
  - `scripts/verify-envs-in-sync.sh` exit 0, "OK: envs/development and envs/production are in sync.".
  - Grep workspace/state-mutation/provider-in-modules pattern: chi match `.claude/` docs va `notes/` plans (rules + audit history), khong match source code.
- Quality gates:
  - terraform fmt: PASS
  - terraform validate (dev + prod): PASS
  - tflint: SKIPPED (tool khong co tren PATH; theo CLAUDE.md install gate, reviewer khong cai dat. Bao cao LOW de user chay thu cong sau).
  - envs in sync: PASS
- Structural / branch-model: provider blocks trong modules/ KHONG co; terraform workspaces KHONG dung; top-level layout giu nguyen; envs dev/prod parity PASS; workflow file `.github/workflows/terraform-apply.yaml` thay doi nam ngoai scope (dispatch github-actions-reviewer - da hoan thanh: entry 2026-05-18 phia tren).
- State preservation: KHONG co refactor (state dev da sach sau S02 - README boi canh). Secret cu `master` da scheduled deletion; secret moi `credentials` ten KHAC nen khong cap nhat ten -> khong can `moved`. `random_password` va `aws_secretsmanager_secret_version` cung khong con trong state dev sau S02 -> khong can `removed`. `prevent_destroy = true` co tren `aws_db_instance.this` (line 76) va `aws_secretsmanager_secret.db` (line 32). Khong co CLI state mutation (`terraform state mv/rm/import`) trong source.
  - Guard `if [ -z "$SECRET_ARN" ]` -> fail som neu output thieu.
  - `bootstrap/03-github-oidc-roles.yaml:88-90` - `gha-infra-apply` co `AdministratorAccess` -> bao gom `secretsmanager:PutSecretValue`, khong can them IAM permission.
  - YAML parse OK qua `python -c "yaml.safe_load(...)"`.
  - Scope guardrail: chi `.github/workflows/terraform-apply.yaml` thay doi (+17 dong), khong dung `terraform-plan.yaml`, `bootstrap.yaml`, drift workflows, hay `.github/actions/`.
  - Branch-based env-isolation giu nguyen: `environment:` (line 30), `ENV_DIR` va `ACCOUNT_ID` (line 32-33) deu derive theo `github.ref`, khong co workspace/cross-account logic.
  - Permissions block (line 11-13) giu least-privilege: `id-token: write` + `contents: read`.
  - OIDC giu nguyen: `aws-actions/configure-aws-credentials@v4` voi `role-to-assume` (line 46-49), khong introduce static keys.

---

## Last updated

2026-05-18 by task-planner (Sprint S03 v2: rewrite hoan toan tu secret_string_wo sang cicd-inject Pattern C)
