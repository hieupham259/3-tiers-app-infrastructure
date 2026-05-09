# Sprint S05 - Migrate Account IDs sang GitHub Actions Variables

## Goal

Xoa bo toan bo hardcode `'111111111111'` va `'222222222222'` trong 5 workflow files bang cach chuyen sang Repository Variables `vars.DEV_ACCOUNT_ID` va `vars.PROD_ACCOUNT_ID`. Day la fix cho finding HIGH tu reviewer S02: CLAUDE.md phan loai AWS account IDs la sensitive data bi cam hardcode trong bat ky file nao trong repo.

## Definition of done

- Grep `'111111111111'` va `'222222222222'` tren `.github/workflows/*.yaml` tra ve rong.
- `vars.DEV_ACCOUNT_ID` va `vars.PROD_ACCOUNT_ID` duoc dung nhat quan trong toan bo 5 workflow files thay cho gia tri hardcode.
- Co it nhat mot comment hoac step trong workflow huong dan user set 2 bien nay trong GitHub Settings.
- `github-actions-reviewer` chay `act` va tat ca workflows pass (hoac fail vi ly do hop le nhu thieu AWS credential trong local env, khong phai vi syntax sai).
- `bootstrap/03-github-oidc-roles.yaml` duoc xac nhan la khong hardcode account ID (dung `${AWS::AccountId}` - CFN pseudo parameter).

## Danh sach thay doi cu the

| File | Dong | Hien tai | Sau khi sua |
|------|------|----------|-------------|
| `.github/workflows/bootstrap.yaml` | 22 | `${{ inputs.account == 'production' && '222222222222' \|\| '111111111111' }}` | `${{ inputs.account == 'production' && vars.PROD_ACCOUNT_ID \|\| vars.DEV_ACCOUNT_ID }}` |
| `.github/workflows/terraform-plan.yaml` | 31 | `{ env: development, account_id: '111111111111' }` | `{ env: development, account_id: '${{ vars.DEV_ACCOUNT_ID }}' }` |
| `.github/workflows/terraform-plan.yaml` | 32 | `{ env: production, account_id: '222222222222' }` | `{ env: production, account_id: '${{ vars.PROD_ACCOUNT_ID }}' }` |
| `.github/workflows/terraform-apply.yaml` | 33 | `${{ github.ref == 'refs/heads/production' && '222222222222' \|\| '111111111111' }}` | `${{ github.ref == 'refs/heads/production' && vars.PROD_ACCOUNT_ID \|\| vars.DEV_ACCOUNT_ID }}` |
| `.github/workflows/terraform-drift.yaml` | 18 | `{ env: development, ref: development, account_id: '111111111111' }` | `{ env: development, ref: development, account_id: '${{ vars.DEV_ACCOUNT_ID }}' }` |
| `.github/workflows/terraform-drift.yaml` | 19 | `{ env: production, ref: production, account_id: '222222222222' }` | `{ env: production, ref: production, account_id: '${{ vars.PROD_ACCOUNT_ID }}' }` |
| `.github/workflows/cfn-drift-detect.yaml` | 18 | `{ account: development, account_id: '111111111111' }` | `{ account: development, account_id: '${{ vars.DEV_ACCOUNT_ID }}' }` |
| `.github/workflows/cfn-drift-detect.yaml` | 19 | `{ account: production, account_id: '222222222222' }` | `{ account: production, account_id: '${{ vars.PROD_ACCOUNT_ID }}' }` |

Tong: 8 vi tri trong 5 files.

## Luu y ve ky thuat

### GitHub Actions Variables vs Secrets

`vars.DEV_ACCOUNT_ID` va `vars.PROD_ACCOUNT_ID` la **Repository Variables** (khong phai Secrets), vi:
- Account ID khong phai credential - no khong the duoc dung de authenticate.
- Variables hien thi ro trong logs (khong bi mask), giup debug OIDC assume-role failures de hon.
- CLAUDE.md cam "AWS account IDs" nhung gia thiet la cam vi tiet lo thong tin nay trong file code, khong phai vi account ID la credential. GitHub Variables la co che dung de externalize configuration nhu the nay.

De set variables: GitHub Settings -> Secrets and variables -> Actions -> Variables tab -> New repository variable.

### Pattern ternary trong matrix

Trong `terraform-plan.yaml`, `terraform-drift.yaml`, `cfn-drift-detect.yaml`, gia tri `account_id` nam trong matrix `include`. GitHub Actions expression `${{ vars.X }}` duoc expand tai runtime, khong tai parse time. Do do pattern nhu:

```yaml
- { env: development, account_id: '${{ vars.DEV_ACCOUNT_ID }}' }
```

la hop le - GitHub Actions se expand bien truoc khi chay step dung `matrix.account_id`.

### Verify bootstrap/03-github-oidc-roles.yaml

CFN file nay dung `${AWS::AccountId}` (CloudFormation pseudo parameter) - khong phai hardcode. Sub-task S05-T01 phai doc va xac nhan dieu nay, ghi nhan la OK trong log.

## Sub-tasks

- [x] S05-T01 - Xac nhan bootstrap/03-github-oidc-roles.yaml khong hardcode account ID
  - Assignee: github-action-builder
  - Inputs / preconditions: none. File: `bootstrap/03-github-oidc-roles.yaml`.
  - Outputs / artifacts: Ghi nhan la file dung `${AWS::AccountId}` (CFN pseudo parameter), khong co gia tri account ID cu the nao. Khong can thay doi file nay.
  - Depends on: none
  - Notes: Day la verify buoc, khong phai build buoc. Neu phat hien hardcode account ID bat ky, reassign ve iac-builder de sua truoc khi tiep tuc.

- [x] S05-T02 - Migrate 8 hardcode account ID sang vars trong 5 workflow files
  - Assignee: github-action-builder
  - Inputs / preconditions: S05-T01 hoan thanh. Danh sach thay doi trong bang tren. S04-T04 hoan thanh (S04 da xong, workflows da sach ve region).
  - Outputs / artifacts: 5 workflow files duoc edit. Khong con string `'111111111111'` hay `'222222222222'` nao.
  - Depends on: S05-T01, S04-T04 (tranh merge conflict voi S03/S04 dang cham vao workflow files)
  - Notes: Doi tung file mot. Khong thay doi gi ngoai account ID strings. Giu nguyen toan bo logic, spacing, comments.

- [x] S05-T03 - Them comment huong dan set GitHub Variables vao it nhat 1 workflow
  - Assignee: github-action-builder
  - Inputs / preconditions: S05-T02 hoan thanh.
  - Outputs / artifacts: Comment trong `terraform-plan.yaml` (hoac `terraform-apply.yaml`) noi ro `vars.DEV_ACCOUNT_ID` va `vars.PROD_ACCOUNT_ID` phai duoc set trong GitHub Settings -> Actions Variables truoc khi workflow chay. Comment nam ngoai `jobs:` block, gan dau file, de de tim.
  - Depends on: S05-T02
  - Notes: Comment phai viet bang tieng Anh (English-only rule cho files trong repo). Khong them comment vao ca 5 files - 1 file duy nhat la du.

- [x] S05-T04 - Review S05 (github-actions-reviewer chay act)
  - Assignee: github-actions-reviewer
  - Inputs / preconditions: S05-T01, S05-T02, S05-T03 hoan thanh. Chay `act` locally.
  - Outputs / artifacts: Xac nhan grep `'111111111111'`/`'222222222222'` trong `.github/workflows/*.yaml` tra ve rong. `act` pass (hoac fail vi ly do hop le). Findings severity-tagged. Log luu vao `.act-logs/`.
  - Depends on: S05-T03

## Review checklist

- [ ] S05-T01: Xac nhan `bootstrap/03-github-oidc-roles.yaml` dung `${AWS::AccountId}`, khong hardcode
- [ ] S05-T02: Grep `'111111111111'` va `'222222222222'` trong `.github/workflows/*.yaml` tra ve rong
- [ ] S05-T03: Co comment huong dan set GitHub Variables trong it nhat 1 workflow file
- [ ] S05-T04: `act` chay thanh cong; khong co syntax error moi; OIDC role ARN van dung (dung `vars.X` thay vi hardcode)
- [ ] Khong co thay doi nao ngoai `.github/workflows/`

## Review log

(Reviewer append findings vao day sau khi chay review)

### 2026-05-10 - github-actions-reviewer
- Verdict: approve
- Sub-tasks ticked: S05-T01, S05-T02, S05-T03, S05-T04
- Sub-tasks reassigned to github-action-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- act exit code: 1 (act-skip - third-party action git clone fails on Windows host; matrix expansion + ternary expression resolve correctly in dryrun parse)
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0
- Verify: grep `'111111111111'`/`'222222222222'` o `.github/` -> 0 hit. bootstrap/03-github-oidc-roles.yaml dung `${AWS::AccountId}` (CFN pseudo parameter), khong hardcode. Comment 4 dong dau terraform-plan.yaml (line 3-8) huong dan set 2 Repository Variables. Pattern matrix `account_id: '${{ vars.X }}'` parse OK, act dryrun expand thanh `plan-1`/`plan-2`, `drift-1`/`drift-2`. Bootstrap workflow ternary `inputs.account == 'production' ? vars.PROD_ACCOUNT_ID : vars.DEV_ACCOUNT_ID` resolve dung. Apply workflow ternary `github.ref == 'refs/heads/production' ? vars.PROD_ACCOUNT_ID : vars.DEV_ACCOUNT_ID` resolve dung.
- act logs: `.act-logs/terraform-plan-S05S06-20260510-043830.log`, `.act-logs/terraform-drift-S05S06-20260510-043846.log`, `.act-logs/cfn-drift-detect-S05S06-20260510-043847.log`, `.act-logs/bootstrap-S05S06-20260510-043900.log`, `.act-logs/terraform-apply-S05S06-20260510-043901.log`

## Open questions

- (none - design da du ro de github-action-builder thuc hien)

## Last updated

2026-05-10 by task-planner
