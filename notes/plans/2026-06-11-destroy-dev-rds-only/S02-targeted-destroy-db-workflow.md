# Sprint S02 - Sua workflow targeted destroy DB

## Goal

Sua `.github/workflows/terraform-destroy.yaml` de thay lenh `terraform destroy` toan bo
thanh targeted destroy co dinh vao dung 1 resource address:
`module.stack.module.rds.aws_db_instance.this`. Workflow se chi xoa DB instance, khong
cham den bat ky resource nao khac (Secret, S3, ECS, ALB, VPC, v.v.).

Giu nguyen toan bo co che an toan hien co: `workflow_dispatch`, `confirm_destroy` gate,
GitHub Environment gate, OIDC `gha-infra-apply`, `concurrency` block.

Sau Sprint nay, nguoi dung co the dispatch workflow chon `environment=development`, go
"destroy" de xac nhan, va chi DB instance dev bi xoa.

Dong thoi, Sprint nay cung bao gom `terraform-planner` chay plan de xac nhan rang
targeted destroy chi anh huong dung 1 resource.

## Definition of done

- `.github/workflows/terraform-destroy.yaml`: buoc "Terraform destroy" dung:
  `terraform destroy -target=module.stack.module.rds.aws_db_instance.this -no-color -auto-approve -input=false`
  (thay vi `terraform destroy -no-color -auto-approve -input=false`).
- Khong co thay doi nao khac trong workflow ngoai dong lenhnh destroy.
- Comment trong workflow duoc cap nhat (hoac them) de ghi ro scope la targeted destroy
  vao DB instance, khong phai full destroy.
- `github-actions-reviewer` da verify syntax YAML hop le.
- `terraform-planner` da chay `terraform plan -destroy -target=module.stack.module.rds.aws_db_instance.this`
  cho `envs/development` o JSON mode va xac nhan:
  - Dung 1 resource bi destroy: `module.stack.module.rds.aws_db_instance.this`.
  - Khong co resource nao khac bi destroy ngoai y muon.
  - Cross-check state-preservation: `aws_secretsmanager_secret.db`, `aws_s3_bucket.frontend`,
    ECS service, ALB, VPC, v.v. deu KHONG xuyen trong plan.

## Sub-tasks

- [x] S02-T01 - Sua buoc "Terraform destroy" trong workflow thanh targeted destroy
  - Assignee: github-action-builder
  - Inputs / preconditions:
    - File `.github/workflows/terraform-destroy.yaml` hien tai (da duoc doc truoc, dong 95-96).
    - Resource address can target: `module.stack.module.rds.aws_db_instance.this`
      (xac nhan tu `envs/development` state; dieu nay duoc nguoi dung chot).
    - S01-T01 phai hoan tat truoc (prevent_destroy da bi xoa); neu khong, targeted destroy van
      that bai voi lifecycle error.
    - Chi sua dung 1 dong lenh: them flag `-target=module.stack.module.rds.aws_db_instance.this`
      vao buoc "Terraform destroy".
  - Outputs / artifacts:
    - File sua: `.github/workflows/terraform-destroy.yaml` - dong 96 duoc sua.
    - Comment header cua workflow (dong 1-27) duoc cap nhat de phan anh scope targeted destroy.
  - Depends on: S01-T01
  - Notes: |
      Chi thay doi toi thieu:
      Dong cu (dong 96):
        run: terraform destroy -no-color -auto-approve -input=false
      Dong moi:
        run: terraform destroy -target=module.stack.module.rds.aws_db_instance.this -no-color -auto-approve -input=false
      Cap nhat comment header: doi "destroy all Terraform-managed resources" thanh
      "destroy the RDS DB instance for the selected environment". Giu nguyen toan bo
      co che an toan, inputs, OIDC setup, concurrency, environment gate.

- [ ] S02-T02 - Review workflow sau khi sua
  - Assignee: github-actions-reviewer
  - Inputs / preconditions:
    - File `.github/workflows/terraform-destroy.yaml` sau khi S02-T01 hoan tat.
    - Sprint plan nay (doi chieu voi Definition of done).
  - Outputs / artifacts:
    - Checkbox S02-T01 duoc tick neu verified.
    - `## Review log` duoc append vao cuoi file Sprint nay.
    - Neu co finding BLOCKER hoac NOT DONE, reassign S02-T01 ve `github-action-builder`.
  - Depends on: S02-T01
  - Notes: |
      Kiem tra:
      - Flag `-target=module.stack.module.rds.aws_db_instance.this` co mat trong lenh destroy.
      - Khong co `-target` nao khac duoc them (chi destroy dung 1 resource).
      - Khong co thay doi nao o cac co che an toan: confirm_destroy gate, environment gate,
        concurrency block, OIDC setup.
      - YAML syntax hop le.
      - Khong co secret nao bi hardcode.
      Neu `act` khong the chay vi thieu OIDC token, chi kiem tra YAML syntax va logic la du.

- [ ] S02-T03 - Chay terraform plan targeted destroy cho envs/development
  - Assignee: terraform-planner
  - Inputs / preconditions:
    - S01-T01 phai hoan tat (prevent_destroy da bi xoa khoi `aws_db_instance.this`).
    - Authorization tu nguoi dung de chay `terraform plan` cho `envs/development`.
    - Lenh plan: `terraform plan -destroy -target=module.stack.module.rds.aws_db_instance.this
      -no-color -input=false` (JSON mode hoac text mode).
    - `TF_VAR_rds_master_password` can duoc set (du la placeholder) de Terraform load config.
  - Outputs / artifacts:
    - Danh sach change chinh xac: resource nao bi destroy, resource nao khong bi anh huong.
    - Cross-check state-preservation: xac nhan `aws_secretsmanager_secret.db`,
      `aws_s3_bucket.frontend`, ECS, ALB, VPC, KMS khong nam trong plan.
    - Bao cao xuat hien trong `## Review log` cua file Sprint nay.
    - Artifact `tfplan` / `tfplan.json` duoc don dep sau khi bao cao xong.
  - Depends on: S01-T01
  - Notes: |
      Muc tieu chinh cua sub-task nay la XACHH NHAN scope targeted destroy dung 1 resource.
      Neu plan hien thi bat ky resource nao khac ngoai `module.stack.module.rds.aws_db_instance.this`
      trong danh sach destroy, day la BLOCKER - bao cao ngay cho nguoi dung truoc khi deploy.

## Review checklist

(reviewer se tick cac box sau khi verify)

- [x] S02-T01: workflow da co `-target=module.stack.module.rds.aws_db_instance.this`,
      co che an toan khong thay doi.
- [ ] S02-T03: terraform plan xac nhan chi 1 resource bi destroy, khong co ngoai y muon.

## Open questions

- Khong co.

## Last updated

2026-06-11 by task-planner

## Review log

### 2026-06-11 - github-actions-reviewer
- Verdict: approve
- Sub-tasks ticked: S02-T01
- Sub-tasks reassigned to github-action-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- act exit code: 1 (positive path - fail tai configure-aws-credentials do thieu OIDC token duoi act, day la ky vong); 1 (negative path - fail tai Validate confirmation input nhu thiet ke khi confirm_destroy != "destroy")
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0
- Ghi chu: Lenh destroy da dung `terraform destroy -target=module.stack.module.rds.aws_db_instance.this -no-color -auto-approve -input=false`. Resource address xac nhan ton tai (module "stack" -> module "rds" trong envs/_shared -> aws_db_instance.this trong modules/rds). Khong co `-target` thua. Toan bo co che an toan giu nguyen: workflow_dispatch only, confirm_destroy gate, environment binding, concurrency cancel-in-progress=false, OIDC gha-infra-apply (khong static key), khong hardcode secret/account ID, khong dung terraform workspace. Log act: .act-logs/terraform-destroy-20260611-023020.log (positive), .act-logs/terraform-destroy-negative-20260611-023046.log (negative).
