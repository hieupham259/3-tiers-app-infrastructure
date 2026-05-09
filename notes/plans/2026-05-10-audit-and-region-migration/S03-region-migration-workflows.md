# Sprint S03 - Region Migration: GitHub Actions workflows

## Goal

Doi toan bo reference `ap-southeast-1` thanh `us-east-1` trong 5 workflow files `.github/workflows/`. Day la Sprint don gian nhat trong region migration vi chi lien quan den text substitution, khong co state impact. Chay sau S02 (audit workflows) de tranh lam viec tren file chua sach.

## Definition of done

- Khong con chuoi `ap-southeast-1` nao trong bat ky file `.github/workflows/*.yaml` nao.
- `github-actions-reviewer` da chay `act` va workflows chay dung (hoac fail voi ly do hop le nhu thieu AWS secret trong local env, khong phai vi sai region string).
- `scripts/verify-envs-in-sync.sh` van sach (workflows khong phai scope cua script nay nhung chay de dam bao cac thay doi khong anh huong den env sync check).

## Danh sach thay doi cu the

| File | Dong | Hien tai | Sau khi sua |
|------|------|----------|-------------|
| `.github/workflows/bootstrap.yaml` | 21 | `AWS_REGION: ap-southeast-1` | `AWS_REGION: us-east-1` |
| `.github/workflows/terraform-plan.yaml` | 47 | `aws-region: ap-southeast-1` | `aws-region: us-east-1` |
| `.github/workflows/terraform-apply.yaml` | 35 | `aws-region: ap-southeast-1` | `aws-region: us-east-1` |
| `.github/workflows/terraform-drift.yaml` | 36 | `aws-region: ap-southeast-1` | `aws-region: us-east-1` |
| `.github/workflows/cfn-drift-detect.yaml` | 25 | `aws-region: ap-southeast-1` | `aws-region: us-east-1` |

Tong: 5 vi tri trong 5 files.

## Luu y quan trong

- `aws-region` trong `configure-aws-credentials` la region ma GitHub Actions dung de assume role va goi AWS API. Doi sang `us-east-1` co nghia la Terraform init/plan/apply se khi tao provider config, se goi S3 endpoint tai `us-east-1`. Neu S3 tfstate bucket van o `ap-southeast-1`, Terraform init se van hoat dong (S3 la global namespace) nhung se co latency va co the gap issue voi `region` trong `backend.tf`. S05 xu ly state backend migration de dong bo hoan toan.
- Noi chung: doi region trong workflow truoc, doi `backend.tf` trong S04, migrate state trong S05. Neu lam nguoc lai se gap window bi inconsistent.

## Sub-tasks

- [x] S03-T01 - Doi region trong 5 workflow files
  - Assignee: github-action-builder
  - Inputs / preconditions: S02-T04 da duoc iac-reviewer approved. Danh sach thay doi trong bang tren.
  - Outputs / artifacts: 5 files duoc edit, moi file dung 1 Edit call.
  - Depends on: S02-T04 (S02 phai hoan thanh truoc)
  - Notes: Chi doi string `ap-southeast-1` -> `us-east-1`. Khong doi bat ky gi khac. Khong cham vao logic, version, hay dieu kien.

- [x] S03-T02 - Review va chay act kiem tra sau khi doi region
  - Assignee: github-actions-reviewer
  - Inputs / preconditions: S03-T01 hoan thanh.
  - Outputs / artifacts: `act` output log. Xac nhan khong con string `ap-southeast-1` nao. Findings (neu co) duoc reassign ve github-action-builder.
  - Depends on: S03-T01

## Review checklist

- [x] S03-T01: 5 file da duoc sua, grep ket qua `ap-southeast-1` trong `.github/workflows/` tra ve rong
- [x] S03-T02: `act` chay thanh cong (hoac fail vi ly do hop le)
- [x] Khong co thay doi nao ngoai `.github/workflows/`

## Review log

(Reviewer append findings vao day sau khi chay review)

### 2026-05-10 - github-actions-reviewer
- Verdict: approve
- Sub-tasks ticked: S03-T01, S03-T02
- Sub-tasks reassigned to github-action-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- act exit code: 0 (5/5 workflows, --dryrun mode, tat ca "Job succeeded")
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0

## Last updated

2026-05-10 by task-planner
