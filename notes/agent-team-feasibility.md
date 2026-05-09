# Đánh giá khả thi: Agent team & skills cho Terraform IaC

Tài liệu phân tích nội bộ về agent team trong `.claude/agents/` và skill `.claude/skills/research-iac-resource/`. Đánh giá những gì team sẽ đạt được trong dự án Terraform thực tế và những gap có thể bỏ sót.

Ngày tạo: 2026-05-09
Phạm vi: agent team v1 (`iac-builder`, `iac-reviewer`, `terraform-planner`, `github-actions-reviewer`) + skill `research-iac-resource`.

---

## Verdict ngắn

**Khả thi và chất lượng cao** cho phạm vi mà nó nhắm đến: viết Terraform mới/sửa, audit theo convention repo, sinh plan có cấu trúc, validate workflows. Có **separation of concerns rõ ràng**: builder không tự review, planner không apply, reviewer không viết - đúng pattern ngăn "marking own homework".

Tuy nhiên team này phủ **pre-merge / pre-apply**. Nó **không phủ runtime, drift thực, cost, policy-as-code, testing, và post-apply**. Một số gap thuộc loại sẽ âm thầm gây sự cố nếu không bù bằng tooling khác.

---

## Những gì team sẽ đạt được

### 1. Code Terraform đúng và idiomatic

- `research-iac-resource` đọc docs vendor + Terraform registry **trước khi viết** -> diệt 90% lỗi "Claude bịa attribute".
- Builder bắt buộc check provider chính thức tồn tại (registry namespace verified) -> tránh community fork không kiểm chứng.
- `simplify` skill tự rà code thừa.

### 2. Convention và cấu trúc repo được giữ nguyên

- Reviewer dimension 5 (BLOCKER cho workspace, provider trong `modules/`, divergence env, promotion path lệch git-merge) -> **bảo vệ deployment model** branch-per-env, đây là phần dễ vỡ nhất nếu để Claude tự do.
- `scripts/verify-envs-in-sync.sh` được audit ở 2 layer (builder self-check + reviewer).

### 3. Bảo mật baseline

- 3 lớp enforce secrets (builder ngăn viết, reviewer audit, gha-reviewer audit workflow).
- OIDC-only cho AWS auth, no static keys -> BLOCKER nếu reintroduce.
- `sensitive = true` được kiểm tra.

### 4. Plan có cấu trúc, đọc được

- `terraform plan -out` + `terraform show -json` + parse `resource_changes` -> output có `replace_paths`, `before_sensitive`, downtime risk theo loại resource, IAM scope changes tách riêng.
- Tốt hơn dán raw `terraform plan` vì người duyệt PR đọc được.

### 5. Workflow CI thực sự được chạy

- `gha-reviewer` dùng `act` chạy workflow cục bộ -> bắt lỗi YAML thực, không chỉ static lint. Phân loại `act-skip` / `env-required` / real bug -> giảm false positive.

### 6. Hand-off tường minh giữa các agent

- Builder báo "files changed + line ranges" -> reviewer biết quét gì -> planner sanity-check `iac-builder` claim vs `tfplan.json` (nếu plan đụng address mà builder không claim -> flag `UNEXPECTED`).

---

## Những gap có thể bỏ sót

Sắp xếp theo mức tác động trong 1 dự án Terraform thực tế.

### A. Cost và FinOps - gap lớn

- Reviewer chỉ flag định tính ("multi-AZ, NAT count cao"). Không có **Infracost / cost-estimator agent** -> không có con số $/tháng trong PR.
- Không pre-flight Service Quotas (VPC/region, NAT/AZ, EIP, RDS storage). Apply chết giữa chừng vì quota là trải nghiệm phổ biến mà team này không bắt được.

### B. Policy-as-code và static security scan - gap lớn

- Không có **tfsec / checkov / trivy / OPA-Conftest** layer. Reviewer enforce convention bằng prose, không có rule engine để áp dụng nhất quán cross-PR.
- Không có CIS benchmark check (S3 public block, RDS encryption, root MFA, ...).
- Không có Sentinel/OPA cho rule repo-specific kiểu "không cho 0.0.0.0/0 ingress trừ port 443".

### C. State management và refactor - gap nguy hiểm

- **Không có agent cho `terraform state mv` / `import`**. Khi refactor module (đổi tên, split), planner sẽ báo "replace toàn bộ" -> nếu user gật -> **mất data RDS / S3**. Không agent nào dạy user soạn import/state-mv plan.
- Không phân biệt được "replace có chủ đích" vs "replace do thiếu state move" - cả 2 hiện ra như nhau trong plan.

### D. Plan-to-apply gap - subtle bug

- Plan reviewed trong PR != plan applied khi merge (apply job re-plan). Nếu base branch nhảy giữa lúc duyệt và lúc merge -> apply có thể khác. Không agent / workflow nào **upload `tfplan` artifact rồi apply chính tfplan đó**. Đây là một deviation từ best practice "saved plan apply".
- Hệ quả: phê duyệt 1 plan, áp dụng 1 plan khác. Audit trail yếu cho compliance.

### E. Concurrency trong apply workflow - đã thấy lỗi cụ thể

- File `terraform-apply.yaml` hiện tại **không có `concurrency:` block**. 2 push liên tiếp vào `development` -> 2 job đua state lock -> 1 job fail. `gha-reviewer` lẽ ra phải BLOCKER cái này nhưng nó chỉ là MEDIUM trong rule. Có thể nâng severity.

### F. Drift thực - gap functional

- Repo có `terraform-drift.yaml` cron, nhưng **không có agent** chuyên reasoning drift. Khi cron báo drift, ai phân tích "console edit hợp lệ" vs "tấn công" vs "Terraform sai schema"? Không có drift-triage agent.
- `cfn-drift-detect.yaml` cũng vậy với CFN bootstrap.

### G. Testing - gap hoàn toàn

- Không có **module unit test** (Terratest / `terraform test` / kitchen-terraform). Correctness chỉ dựa vào plan + review.
- Không có `examples/` per module để test invocation thực.
- Module thay đổi behavior (ví dụ subnet logic) chỉ phát hiện ở plan của env caller - quá muộn.

### H. CloudFormation bootstrap chỉ được phủ một nửa

- Builder dùng `cfn-resource-research` skill, nhưng **`iac-reviewer` scope mặc định cho Terraform**. Không có `cfn-reviewer` agent.
- Bootstrap stacks (`01-trust-anchor.yaml`, `02-tfstate-backend.yaml`, `03-github-oidc-roles.yaml`) là phần security-critical nhất (root trust, OIDC trust policy) nhưng review nhẹ nhất.

### I. terraform-docs / README drift

- Mỗi module có `README.md` nhưng **không agent verify nó match `variables.tf` + `outputs.tf` thực tế**. Không chạy `terraform-docs`. README sẽ rot dần.

### J. Lockfile và supply chain

- Không thấy `.terraform.lock.hcl` trong cây file -> nếu thật sự không commit thì supply-chain attack khả thi (provider bị swap).
- Không agent chạy `terraform providers lock -platform=linux_amd64,darwin_arm64,windows_amd64` để CI cross-platform reproducible.
- Không Renovate/Dependabot cho action versions hay provider versions -> các SHA pinned đứng yên mãi.

### K. Cross-region / cross-account hazards

- ACM cert cho CloudFront **bắt buộc us-east-1**. Reviewer không có check provider-alias cụ thể này. Đây là loại lỗi "code chạy ở local, fail ở apply" rất phổ biến.
- `global/` chứa resource cross-region/cross-env nhưng review không có dimension ordering / eventual consistency cho cross-region.

### L. Network correctness ở mức graph

- Reviewer check SG/subnet/port chính xác. Nhưng:
  - Không kiểm **NACL** (NACL âm thầm chặn traffic mà SG cho phép).
  - Không kiểm **VPC endpoints** (thiếu S3/ECR endpoint -> cost NAT cao + chậm).
  - Không kiểm **route table** (subnet có route ra NAT không).
  - Không có "blast radius" agent đếm bao nhiêu resource phụ thuộc input thay đổi (`terraform graph`).

### M. Observability completeness

- Module `observability` tồn tại nhưng **không agent enforce** rằng resource mới phải có alarm/log group/dashboard. Một RDS mới được merge mà không có alarm cũng pass.

### N. Operational / post-apply

- Plan flag "replacement của RDS = data loss" nhưng **không sinh runbook rollback / snapshot procedure**. Approver thấy cảnh báo nhưng không thấy bước thực hiện.
- Không có agent verify post-apply (smoke test, CloudWatch metric check, health endpoint).
- Không có rollback agent khi apply fail nửa chừng.

### O. Tag schema và governance

- "Merge `var.tags` + Name tag" được enforce. **Tag schema (CostCenter, Owner, DataClassification, Compliance) không enforce.** FinOps và ownership tracing yếu.

### P. Secret rotation

- Secrets phải qua Secrets Manager/SSM by ARN - tốt. Nhưng **rotation Lambda / rotation schedule không được audit**. Secret 5 năm không xoay vẫn pass.

### Q. UX gate fatigue

- `research-iac-resource` bắt user confirm cho **mọi** task IaC. Skill cố loại trừ "cosmetic" nhưng ranh giới mờ. Hệ quả thực tế: user rubber-stamp -> gate mất giá trị.
- Không có "approve class of similar tasks" hay "skip research khi resource đã được research trong cùng session".

### R. Module discoverability và onboarding

- User mới gõ "tôi muốn thêm Lambda" - không agent giúp xem **catalog module hiện có**. Builder được dặn "read neighbouring modules" nhưng đó là sau khi đã quyết định viết mới.
- Không có `module-catalog` agent.

### S. Compliance / audit trail

- Cho SOC2/ISO/PCI: không có log liên kết "ai approved cái plan nào, plan đó có khớp plan applied không". Chỉ có git history chung.

### T. Plan ở local thiếu credentials

- Planner agent stop nếu `terraform init` fail vì thiếu creds. Dev local không có AWS creds -> planner luôn block. Không có dry-mode / mock backend cho trường hợp này.

---

## Tóm tắt impact của các gap

| Gap | Tần suất gặp | Mức nguy hiểm | Bù bằng cách nào |
|-----|--------------|---------------|------------------|
| State mv / import | Mỗi lần refactor module | Mất data | Thêm agent `terraform-state-refactor` |
| Cost estimation | Mọi PR | Cao về tài chính | Tích hợp Infracost trong workflow |
| Policy-as-code | Mọi PR | Cao về security | Thêm `tfsec` + `checkov` step |
| Plan-to-apply gap | Mọi merge | Trung bình | Đổi sang saved-plan apply |
| Concurrency apply | Push dồn | Trung bình | Thêm `concurrency:` block |
| Testing modules | Mọi module change | Cao | Thêm `terraform test` |
| CFN bootstrap review | Hiếm nhưng critical | Rất cao | Mở rộng reviewer hoặc thêm `cfn-reviewer` |
| Drift triage | Định kỳ | Trung bình | Thêm `drift-triage` agent |
| README drift | Liên tục | Thấp | `terraform-docs` pre-commit |
| ACM us-east-1 | Hiếm nhưng đau | Trung bình | Thêm dimension trong reviewer |

---

## Khuyến nghị ưu tiên

1. **Saved-plan apply** + **`concurrency:` block** trong `terraform-apply.yaml` (1 buổi).
2. **Infracost + tfsec/checkov** vào `terraform-plan.yaml` (1 buổi).
3. **Agent state-refactor** chuyên thiết kế import/state-mv plan trước replace nguy hiểm.
4. **`terraform test` + `examples/`** cho mỗi module.
5. **Tag schema enforcement** trong reviewer.
6. **`terraform-docs` pre-commit** + check `.terraform.lock.hcl` được commit.

Phần còn lại (drift triage, post-apply, module catalog, compliance audit) có thể thêm dần khi team scale.
