# Sprint S01 - Create terraform-destroy workflow

## Goal

Tao file `.github/workflows/terraform-destroy.yaml` cho phep nguoi co quyen tren repo kich hoat destroy toan bo Terraform resources cua mot environment (development hoac production) qua GitHub UI. Workflow chi co `workflow_dispatch` trigger, co input chon environment, dung GitHub Environment de co manual approval gate (dac biet quan trong voi production), va dung OIDC de xac thuc vao AWS giong cac workflow hien co. Sau khi Sprint nay hoan tat, nguoi dung co the: chon environment tren GitHub UI -> duoc yeu cau approve (voi production) -> workflow chay `terraform destroy`.

## Definition of done

- File `.github/workflows/terraform-destroy.yaml` ton tai va co duy nhat trigger `workflow_dispatch` (khong co `push`, `pull_request`, `schedule`).
- Workflow co input `environment` kieu `choice` voi options `development` va `production`, va input `confirm_destroy` kieu `string` yeu cau nguoi dung go chu "destroy" de xac nhan y dinh.
- Job `destroy` duoc gan vao GitHub Environment tuong ung (`development` hoac `production`) qua bien `environment:` trong job, cho phep repo admin cau hinh required reviewers tren moi environment de co manual approval gate.
- Workflow dung `aws-actions/configure-aws-credentials@v4` voi role `arn:aws:iam::${{ env.ACCOUNT_ID }}:role/gha-infra-apply` va `aws-region: us-east-1`, giong het `terraform-apply.yaml`.
- `ACCOUNT_ID` duoc suy ra tu `vars.DEV_ACCOUNT_ID` hoac `vars.PROD_ACCOUNT_ID` theo input `environment`.
- `TF_VAR_rds_master_password` duoc inject tu `secrets.RDS_MASTER_PASSWORD` (giong apply workflow), hoac dung gia tri placeholder hop le neu secret khong can cho destroy. Ghi chu ro trong file.
- `TF_VAR_repository` duoc set tu `github.event.repository.name`.
- `working-directory` la `envs/${{ env.ENV_DIR }}` (ENV_DIR = gia tri input `environment`).
- `hashicorp/setup-terraform@v3` voi `terraform_version: 1.13.3`.
- Cac buoc chay theo thu tu: `terraform init` -> `terraform plan -destroy` (de nguoi dung thay plan truoc) -> mot buoc `echo` / `run` check lai gia tri `confirm_destroy` == "destroy", exit 1 neu sai -> `terraform destroy -auto-approve -input=false`.
- Workflow co `concurrency` group rieng (vi du `terraform-destroy-${{ github.event.inputs.environment }}`) voi `cancel-in-progress: false` de tranh 2 run chay cung mot luc tren cung environment.
- `permissions` block co `id-token: write` va `contents: read`.
- Khong co secret nao duoc hardcode; khong co AWS account ID nao duoc hardcode.
- `terraform fmt -check` pass tren file YAML (YAML format, khong phai terraform fmt; agent tu kiem tra YAML syntax hop le).
- Comment trong file giai thich ro muc dich cua tung phan an toan (confirm gate, environment gate).

## Sub-tasks

- [ ] S01-T01 - Viet file `.github/workflows/terraform-destroy.yaml`
  - Assignee: github-action-builder
  - Inputs / preconditions:
    - Noi dung `terraform-apply.yaml` (da doc o tren): dung lam tham chieu cho OIDC setup, role ARN pattern, env var pattern, terraform_version, aws-region.
    - Noi dung `terraform-plan.yaml`: tham chieu cho terraform init / plan pattern.
    - Terraform variable `rds_master_password` la `sensitive = true, nullable = false`: can inject gia tri (dung placeholder "destroy-not-used" la ok vi destroy khong update secret, nhung can ghi chu).
    - GitHub Environment `development` va `production` da ton tai (dung trong `terraform-apply.yaml`).
    - Repository Variables: `vars.DEV_ACCOUNT_ID`, `vars.PROD_ACCOUNT_ID`.
    - Repository Secret: `secrets.RDS_MASTER_PASSWORD`.
  - Outputs / artifacts:
    - File moi: `.github/workflows/terraform-destroy.yaml`
  - Depends on: none
  - Notes: |
      Thiet ke luong workflow nhu sau:
      1. Trigger: `workflow_dispatch` voi inputs:
         - `environment`: choice [development, production], required, description "Target environment to destroy"
         - `confirm_destroy`: string, required, description "Type 'destroy' to confirm. This action is irreversible."
      2. Job `destroy` (runs-on: ubuntu-latest):
         - `environment: ${{ github.event.inputs.environment }}` -> kich hoat GitHub Environment protection rules (manual approval cho production neu repo admin da cau hinh).
         - `concurrency: group: terraform-destroy-${{ github.event.inputs.environment }}, cancel-in-progress: false`
         - env:
           - `ENV_DIR: ${{ github.event.inputs.environment }}`
           - `ACCOUNT_ID: ${{ github.event.inputs.environment == 'production' && vars.PROD_ACCOUNT_ID || vars.DEV_ACCOUNT_ID }}`
           - `TF_VAR_repository: ${{ github.event.repository.name }}`
           - `TF_VAR_rds_master_password: ${{ secrets.RDS_MASTER_PASSWORD }}` (inject that de tranh Terraform loi vi variable khong co default; destroy khong dung gia tri nay nhung Terraform van yeu cau no khi load configuration)
         - `defaults.run.working-directory: envs/${{ env.ENV_DIR }}`
         - Steps:
           a. `actions/checkout@v4`
           b. `hashicorp/setup-terraform@v3` voi `terraform_version: 1.13.3`
           c. `aws-actions/configure-aws-credentials@v4` voi role va region
           d. "Validate confirmation input" - `run: if [ "${{ github.event.inputs.confirm_destroy }}" != "destroy" ]; then echo "ERROR: confirm_destroy must be exactly 'destroy'"; exit 1; fi`
           e. `terraform init -no-color`
           f. `terraform plan -destroy -no-color -out=tfplan -input=false`
           g. `terraform destroy -auto-approve -input=false` (dung plan file neu muon, hoac chay lai destroy truc tiep)
      3. Khong co `sync-check` job (destroy khong can check env sync vi chi chay tren mot env).
      4. Khong goi `.github/actions/sync-secret-value` sau destroy (resources khong con nua).
      Luu y quan trong ve production safety: viec gating production phu thuoc vao GitHub Environment "production" co "Required reviewers" duoc cau hinh boi repo admin. Workflow thuc hien dung co che nay bang cach gan `environment: production`. Them comment trong YAML giai thich dieu nay.

- [ ] S01-T02 - Review workflow file vua tao
  - Assignee: github-actions-reviewer
  - Inputs / preconditions:
    - File `.github/workflows/terraform-destroy.yaml` da duoc tao boi S01-T01.
    - Sprint plan nay (kiem tra doi chieu voi Definition of done).
  - Outputs / artifacts:
    - Cac checkbox trong Sprint file duoc tich neu verified.
    - `## Review log` duoc append vao cuoi file nay voi cac findings (neu co).
    - Neu co finding BLOCKER hoac NOT DONE, reassign S01-T01 ve `github-action-builder`.
  - Depends on: S01-T01
  - Notes: |
      Kiem tra cac diem sau (ngoai checklist DoD):
      - Khong co secret nao duoc hardcode trong YAML (BLOCKER neu vi pham).
      - Khong co AWS account ID nao duoc hardcode (BLOCKER neu vi pham).
      - `workflow_dispatch` la trigger duy nhat.
      - `confirm_destroy` check duoc chay TRUOC `terraform init` va TRUOC `terraform destroy` (hoac it nhat truoc destroy).
      - `concurrency.cancel-in-progress: false` de tranh huy run dang chay.
      - `environment:` duoc set dung ten input (khong phai hardcode).
      - `TF_VAR_rds_master_password` duoc set (du la placeholder) de tranh Terraform error.
      - Neu `act` khong the chay vi thieu AWS credential, chi can kiem tra YAML syntax va logic, khong can AWS call that.

## Review checklist

(github-actions-reviewer se tick cac box sau khi verify)

- [ ] S01-T01: `.github/workflows/terraform-destroy.yaml` da ton tai va dung spec.

## Open questions

- Khong co.

## Last updated

2026-06-10 by task-planner
