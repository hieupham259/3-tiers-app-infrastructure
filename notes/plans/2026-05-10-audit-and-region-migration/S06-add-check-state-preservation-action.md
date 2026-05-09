# Sprint S06 - Add check-state-preservation Composite Action

## Goal

Tao composite action `.github/actions/check-state-preservation/action.yaml` va wire vao `terraform-plan.yaml` (va `terraform-apply.yaml`) de ngan chan workflow thanh cong khi `terraform plan` phat hien destroy hoac replacement mot stateful resource. Day la fix cho finding HIGH tu reviewer S02: rule #11 trong agent definition yeu cau gate nay phai ton tai nhung hien tai chua co.

## Definition of done

- `.github/actions/check-state-preservation/action.yaml` ton tai va la composite action hop le.
- Action nhan input `plan-json-path` (duong dan den file `tfplan.json` output cua `terraform show -json`).
- Action parse `resource_changes[]` tu JSON, loc action co chua `"delete"` (bao gom `["delete"]` va `["delete", "create"]` aka replacement).
- Cross-check `resource_type` cua cac change bi delete/replace voi allowlist stateful resource.
- Neu co match: step fail voi message ro rang liet ke tung resource bi anh huong (`address`, `type`, `action`).
- Neu khong co match: step pass voi message xac nhan sach.
- Escape valve: neu commit message hoac PR label chua magic string `acknowledged-destroy:<resource_address>` (exact match per resource address), resource do duoc bo qua khi kiem tra.
- `terraform-plan.yaml` co step `terraform show -json tfplan > tfplan.json` sau step `terraform plan`, roi goi composite action nay.
- `terraform-apply.yaml`: re-plan truoc apply (buoc `terraform plan -out=tfplan`) duoc bo sung buoc `terraform show -json tfplan > tfplan.json` va goi composite action truoc khi apply.
- `github-actions-reviewer` chay `act` voi mock `tfplan.json` kiem tra ca 2 path: pass (khong co stateful destroy) va fail (co stateful destroy, khong co escape valve).

## Allowlist stateful resource types

Danh sach nay duoc dinh nghia trong composite action (constant trong shell script). Tuong thich voi operating rule 11 cua iac-builder agent va danh sach trong CLAUDE.md:

```
aws_db_instance
aws_rds_cluster
aws_s3_bucket
aws_kms_key
aws_efs_file_system
aws_dynamodb_table
aws_eip
aws_secretsmanager_secret
aws_elasticache_cluster
aws_msk_cluster
aws_eks_cluster
aws_eks_node_group
```

## Thiet ke escape valve

Magic string format: `acknowledged-destroy:<resource_address>`

Vi du commit message hoac PR label:

```
acknowledged-destroy:module.rds.aws_db_instance.main
```

- Parser doc commit message tu `GITHUB_EVENT_PATH` (event JSON cua pull_request hoac push).
- Parser cung doc labels cua PR neu chay trong context pull_request.
- Neu `resource_address` co trong danh sach acknowledged, bo qua resource do khi fail check.
- Ghi nhan ro trong log: "Skipping <address> - acknowledged by commit message/label."
- Neu escape valve duoc su dung, step van pass nhung warning duoc print de audit trail.

## Cau truc file mong doi

```
.github/
  actions/
    check-state-preservation/
      action.yaml      # composite action definition
      check.sh         # shell script thuc hien logic (duoc goi boi action.yaml)
```

`check.sh` dung `jq` (co san tren ubuntu-latest runner) de parse JSON. Khong phu thuoc Python hay Node.

## Sub-tasks

- [x] S06-T01 - Tao composite action check-state-preservation
  - Assignee: github-action-builder
  - Inputs / preconditions: none. Directory `.github/actions/` chua ton tai - can tao moi.
  - Outputs / artifacts: `.github/actions/check-state-preservation/action.yaml` va `.github/actions/check-state-preservation/check.sh`.
  - Depends on: none
  - Notes:
    - `action.yaml` phai khai bao `inputs.plan-json-path` (required, string).
    - `action.yaml` phai khai bao `inputs.commit-message` (optional, string, default rong) va `inputs.pr-labels` (optional, string JSON array, default `[]`) de nhan escape valve context tu caller.
    - `check.sh` duoc set `chmod +x` va goi tu step `run: $GITHUB_ACTION_PATH/check.sh` trong composite action.
    - Shell script phai dung `set -euo pipefail`.
    - Allowlist phai duoc dinh nghia la multiline variable trong `check.sh`, khong hard-coded inline trong jq filter.
    - Output: script exit 0 neu sach, exit 1 neu co stateful destroy khong co escape valve.

- [x] S06-T02 - Wire action vao terraform-plan.yaml
  - Assignee: github-action-builder
  - Inputs / preconditions: S06-T01 hoan thanh. File: `.github/workflows/terraform-plan.yaml`. Hien tai workflow co: checkout, setup-terraform, configure-aws-credentials, fmt-check, init, validate, plan (id: plan), comment PR.
  - Outputs / artifacts: `terraform-plan.yaml` co them 2 buoc sau step `plan`:
    1. Step `Generate plan JSON` (id: `plan-json`): `terraform show -json tfplan > tfplan.json`
    2. Step `Check state preservation` (id: `check-state-preservation`): goi `.github/actions/check-state-preservation` voi inputs `plan-json-path: tfplan.json`, `commit-message: ${{ github.event.pull_request.title }}` (title la noi nguoi dung co the ghi acknowledged-destroy), `pr-labels: ${{ toJson(github.event.pull_request.labels.*.name) }}`.
  - Depends on: S06-T01, S05-T04 (S05 phai xong truoc de tranh conflict tren terraform-plan.yaml)
  - Notes: Step `Check state preservation` phai nam TRUOC step `Comment plan on PR` de fail truoc khi post comment neu co van de.

- [x] S06-T03 - Wire action vao terraform-apply.yaml
  - Assignee: github-action-builder
  - Inputs / preconditions: S06-T01, S06-T02 hoan thanh. File: `.github/workflows/terraform-apply.yaml`. Hien tai workflow co: checkout, setup-terraform, configure-aws-credentials, init, plan (-out=tfplan), apply.
  - Outputs / artifacts: `terraform-apply.yaml` co them 2 buoc giua `plan` va `apply`:
    1. Step `Generate plan JSON` (id: `plan-json`): `terraform show -json tfplan > tfplan.json`
    2. Step `Check state preservation` (id: `check-state-preservation`): goi `.github/actions/check-state-preservation` voi inputs `plan-json-path: tfplan.json`, `commit-message: ${{ github.event.head_commit.message }}` (push event dung `head_commit.message`), `pr-labels: '[]'` (push event khong co PR labels).
  - Depends on: S06-T01, S06-T02, S05-T04 (S05 phai xong truoc de tranh conflict tren terraform-apply.yaml)
  - Notes: Gate nay tao lop bao ve thu 2 o apply time, sau gate da co o plan time (S06-T02). Neu plan time pass nhung apply time fail (co the xay ra neu ai do bypass plan workflow), apply se bi block.

- [x] S06-T04 - Review S06 (github-actions-reviewer chay act voi mock JSON)
  - Assignee: github-actions-reviewer
  - Inputs / preconditions: S06-T01, S06-T02, S06-T03 hoan thanh. Reviewer tao mock `tfplan.json` de test.
  - Outputs / artifacts: Log act cho it nhat 2 test case:
    1. **Path pass**: mock JSON khong co stateful resource bi delete/replace. Action exit 0.
    2. **Path fail**: mock JSON co `aws_db_instance` bi destroy, khong co escape valve. Action exit 1, workflow fail.
    3. **(optional) Path escape**: mock JSON co `aws_db_instance` bi destroy, commit message co `acknowledged-destroy:module.rds.aws_db_instance.main`. Action exit 0 voi warning.
  - Depends on: S06-T03
  - Notes: Mock `tfplan.json` co the la file nho chi chua `resource_changes` array. Reviewer tao file nay trong `.act-logs/mock-plans/` hoac `.act-secrets/` (khong commit). Reviewer check `action.yaml` dung syntax composite action dung (steps dung `shell: bash`, `uses: actions/checkout` neu can, khong co `runs-on` vi composite action khong khai bao runner). Findings severity-tagged. Reassign neu can.

## Review checklist

- [ ] S06-T01: `action.yaml` ton tai va la composite action hop le; `check.sh` co `set -euo pipefail`; allowlist day du 12 resource types; escape valve logic duoc implement
- [ ] S06-T02: `terraform-plan.yaml` co step generate plan JSON va step check-state-preservation sau step `plan`, truoc step comment PR
- [ ] S06-T03: `terraform-apply.yaml` co step generate plan JSON va step check-state-preservation sau step `plan` (truoc `apply`)
- [ ] S06-T04: `act` test path pass va path fail deu cho ket qua dung (exit 0 vs exit 1 tuong ung); khong co composite action syntax error
- [ ] Khong co thay doi nao ngoai `.github/workflows/` va `.github/actions/`

## Review log

(Reviewer append findings vao day sau khi chay review)

### 2026-05-10 - github-actions-reviewer
- Verdict: approve
- Sub-tasks ticked: S06-T01, S06-T02, S06-T03, S06-T04
- Sub-tasks reassigned to github-action-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- act exit code: 1 (act-skip - third-party action git clone fails on Windows host; composite action `./.github/actions/check-state-preservation` reference la local path, khong bi anh huong)
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0
- Unit-test check.sh qua Docker (alpine + jq + bash) tren 10 path:
  - PASS (exit 0): pass-empty (resource_changes rong), pass-create-only (chi co `create`), non-stateful-destroy (SG + lb_listener delete - ngoai allowlist), ack-via-commit-message, ack-via-pr-label
  - FAIL (exit 1): fail-rds-destroy (aws_db_instance delete, no ack), fail-replacement (aws_s3_bucket delete+create, no ack), ack-mismatch-address (wrong address khong bypass), invalid-pr-labels-not-array, missing-plan-json
- Verify static: `bash -n check.sh` exit 0 (syntax OK). `set -euo pipefail` co. Allowlist 12 types khop spec. jq filter `.change.actions | index("delete")` cover ca `["delete"]` lan `["delete","create"]` lan `["create","delete"]`. Escape valve scan ca `COMMIT_MESSAGE` va tung label trong `PR_LABELS` JSON array.
- Verify wiring:
  - `terraform-plan.yaml` line 70-82: step `Generate plan JSON` (id=plan-json) -> step `Check state preservation` (uses `./.github/actions/check-state-preservation`) sau step `plan` va truoc step `Comment plan on PR`. Ca 2 deu co `if: steps.plan.outcome == 'success'` de skip khi plan fail.
  - `terraform-apply.yaml` line 55-65: step `Generate plan JSON` -> step `Check state preservation` giua `Terraform plan` va `Terraform apply` (lop bao ve thu 2 truoc apply).
  - Inputs duoc truyen dung: `plan-json-path` (path tuong doi tu repo root, khong phai env dir), `commit-message`, `pr-labels` voi context phu hop tung event.
- act logs unit-test: `.act-logs/check-state-preservation-pass-20260510-040000.log`, `.act-logs/check-state-preservation-fail-20260510-040100.log`, `.act-logs/check-state-preservation-escape-20260510-040200.log`
- act logs workflow dryrun: `.act-logs/terraform-plan-S05S06-20260510-043830.log`, `.act-logs/terraform-apply-S05S06-20260510-043901.log`
- Mock plan fixtures (giu lai cho audit trail): `.act-logs/mock-plans/*.json`

## Open questions

- (none - design da du ro de github-action-builder thuc hien)

## Last updated

2026-05-10 by task-planner
