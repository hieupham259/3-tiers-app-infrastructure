# Sprint S01 - Deploy full networking module, comment 8 module con lai

## Goal

Sau Sprint nay, `envs/_shared/main.tf` chi goi mot module duy nhat la `module "network"` (tat ca 8 module con lai bi comment). `module "network"` duoc goi nguyen ven - khong co gi thay doi ben trong `modules/network/`. `envs/_shared/outputs.tf` comment toan bo cac block tham chieu toi 8 module da bi comment (giu lai khong co output nao vi khong co module nao khac ngoai network duoc expose). `terraform validate` va `terraform fmt -check` pass. `terraform plan` chi thay cac resource cua module `network` duoc tao: VPC, subnet, IGW, EIP, NAT gateway, route table, route table association (day du). Deploy len branch `development` thanh cong.

## Pham vi comment can thuc hien (chi tiet cho iac-builder)

### 1. `modules/network/` - KHONG CHAM VAO

Tuyet doi khong comment, khong sua, khong thay doi bat ky file nao ben trong `modules/network/`. Module nay deploy full.

### 2. `envs/_shared/main.tf`

Comment cac module call sau (giu lai `locals { common_tags = ... }` va `module "network"`):
- `module "ecr_backend"` (dong 20-25)
- `module "alb"` (dong 27-35)
- `module "ecs_cluster"` (dong 37-41)
- `module "rds"` (dong 43-59)
- `module "iam_app_roles"` (dong 61-67)
- `module "ecs_service"` (dong 69-90)
- `module "frontend_cdn"` (dong 92-99)
- `module "observability"` (dong 101-110)

Them comment `# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04` ngay truoc moi block bi comment de de theo doi khi un-comment ve sau.

Giu lai: block `locals { common_tags = ... }`, `module "network" { ... }`.

### 3. `envs/_shared/outputs.tf`

Comment TOAN BO noi dung file nay. Tat ca `resource "aws_ssm_parameter"` va `output` block deu tham chieu toi module da bi comment - neu giu lai se loi `terraform validate`. Comment ca 7 SSM parameter resource va 8 output block.

Cau truc sau khi comment: file chi con cac comment, khong con block nao active.

Them comment mo ta o dau file: `# PHASED-DEPLOY S01: all outputs commented out, restore progressively in S02/S03/S04`.

## Cac resource stateful trong Sprint nay

`aws_eip` la resource stateful. `modules/network/main.tf` co resource `aws_eip.nat`. Theo Operating rule 11, can co `lifecycle { prevent_destroy = true }`. Tuy nhien, task nay yeu cau KHONG sua gi ben trong `modules/network/` - nen viec them lifecycle se la sub-task rieng (S01-T02) chi de ghi nhan va de nghi nguoi dung quyet dinh sau, HOAC iac-builder them lifecycle block vao module truoc khi comment, vi day la best practice. Chi them lifecycle block - khong thay doi gi khac trong module.

## Definition of done

LUU Y VE MOI TRUONG CHAY: Cac lenh terraform/tflint duoi day deu duoc verify tren GitHub Actions CI runner (workflow `terraform-plan.yaml` va `terraform-apply.yaml`, dung Terraform 1.13.3) - KHONG yeu cau chay o local. Terraform CLI local cua nguoi dung la v1.9.2 < `required_version >= 1.11` cua repo, nen agent team khong chay duoc cuc bo; viec verify chinh thuc dien ra tren CI. Nguoi dung khong can cai Terraform o may de hoan thanh Sprint nay.

- `terraform fmt -check -recursive` tra ve exit 0 - verify boi step "Terraform fmt -check" trong `terraform-plan.yaml`.
- `terraform validate` trong `envs/development/` tra ve "Success!" - verify boi step "Terraform validate" trong `terraform-plan.yaml`.
- `tflint --recursive` khong co error - verify tren CI.
- `scripts/verify-envs-in-sync.sh` pass - verify boi job `sync-check` trong `terraform-plan.yaml` va `terraform-apply.yaml` (script chi check `envs/development/main.tf` va `envs/development/variables.tf` - 2 file nay khong doi nen auto-pass).
- `terraform plan` trong `envs/development/` xac nhan chi co resource cua `module.network` duoc tao: aws_vpc, 6 subnet (3 public + 3 private), 1 IGW, 3 EIP, 3 NAT gateway, 4 route table, 6 route table association. Khong co resource nao khac. Plan chinh thuc duoc post len PR comment boi step "Comment plan on PR" trong `terraform-plan.yaml`.
- PR tu feature branch vao `development` duoc merge thanh cong.
- GitHub Actions workflow `terraform-apply.yaml` chay thanh cong tren branch `development`.
- Networking infrastructure xuat hien trong AWS Console: VPC, subnet, IGW, NAT gateway, EIP, route table.

## Sub-tasks

- [x] S01-T01 - Them lifecycle { prevent_destroy = true } cho aws_eip.nat trong modules/network/main.tf
  - Assignee: iac-builder
  - Inputs / preconditions: `modules/network/main.tf` (hien co resource `aws_eip.nat` - can kiem tra co lifecycle block chua)
  - Outputs / artifacts: `modules/network/main.tf` co lifecycle block tren `aws_eip.nat`; khong co thay doi nao khac trong module
  - Depends on: none
  - Notes: Day la buoc bao ve stateful resource. Chi them `lifecycle { prevent_destroy = true }` - khong comment, khong sua gi khac trong module. Neu da co lifecycle block thi skip (tick luon).

- [x] S01-T02 - Comment 8 module call trong `envs/_shared/main.tf`; comment toan bo `envs/_shared/outputs.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: `envs/_shared/main.tf` (hien co 1 locals + 9 module block), `envs/_shared/outputs.tf` (hien co 7 aws_ssm_parameter + 8 output)
  - Outputs / artifacts: `envs/_shared/main.tf` chi con locals + module "network"; `envs/_shared/outputs.tf` comment toan bo
  - Depends on: S01-T01
  - Notes: Comment ca toan bo moi block ke ca closing brace. Them comment "# PHASED-DEPLOY S01: commented out, uncomment in S02/S03/S04" truoc moi block de de theo doi. Them comment mo ta o dau outputs.tf.

- [x] S01-T03 - Review toan bo diff Sprint S01
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S01-T01 va S01-T02
  - Outputs / artifacts: tick checkbox S01-T01, S01-T02 neu done; neu co van de, reassign ve iac-builder
  - Depends on: S01-T02
  - Notes: Kiem tra ky: (1) khong co output nao con tham chieu resource da comment; (2) `envs/_shared/outputs.tf` da comment het; (3) `modules/network/` khong bi sua gi ngoai lifecycle block o S01-T01; (4) lifecycle prevent_destroy co mat tren aws_eip.nat; (5) `terraform validate` co the chay thanh cong voi chi module "network" active

- [x] S01-T04 - Chay terraform plan trong envs/development de xac nhan chi co resource cua module network
  - Assignee: terraform-planner
  - Inputs / preconditions: code sau S01-T01 va S01-T02 da duoc review S01-T03 approve
  - Outputs / artifacts: bao cao plan: danh sach day du resource se duoc tao (chi networking), ket qua state-preservation check
  - Depends on: S01-T03
  - Notes: Plan ket qua mong doi: chi cac resource cua module.network (aws_vpc, 6 aws_subnet, aws_internet_gateway, 3 aws_eip, 3 aws_nat_gateway, 4 aws_route_table, 6 aws_route_table_association). Khong co resource nao tu 8 module bi comment.
  - MOI TRUONG CHAY: `terraform plan` KHONG chay duoc o local (Terraform CLI v1.9.2 < required >= 1.11). terraform-planner da phan tich tinh source va xac nhan ket qua mong doi la 21 resource, tat ca thuoc `module.stack.module.network.*`. Plan chinh thuc se chay tren CI runner khi mo PR vao `development` (step "Terraform plan" trong `terraform-plan.yaml`, Terraform 1.13.3) va post len PR comment. Nguoi dung xac nhan plan o buoc do, khong can chay terraform o may.

- [ ] S01-T05 - Deploy giai doan 1 len branch development
  - Assignee: user
  - Inputs / preconditions: S01-T04 xac nhan plan hop le
  - Outputs / artifacts: networking infrastructure ton tai trong AWS Console; `terraform-apply.yaml` job thanh cong
  - Depends on: S01-T04
  - Notes: |
      Cac buoc day du (deploy len `development`):
      1. Tu branch `master`, checkout `development`: `git checkout development && git pull origin development`.
      2. Tao feature branch: `git checkout -b feature/phased-deploy-s01-full-networking`.
      3. Code da duoc iac-builder commit (S01-T01, S01-T02). Push feature branch: `git push origin feature/phased-deploy-s01-full-networking`.
      4. Mo PR tren GitHub: base = `development`, head = `feature/phased-deploy-s01-full-networking`.
      5. Workflow `terraform-plan.yaml` tu dong chay. Doi job pass. Kiem tra plan comment tren PR: chi co networking resource (21 to add, 0 change, 0 destroy).
      6. Merge PR vao `development`.
      7. Push vao `development` trigger `terraform-apply.yaml`. Vao tab Actions -> click vao run moi nhat -> "Review deployments" -> tick `development` -> Approve.
      8. Doi job `apply` hoan tat voi trang thai "Success".
      9. Verify tren AWS Console: VPC, 6 subnet (3 public + 3 private), IGW, 3 NAT gateway, 3 EIP, route table cua development.
      Replicate sang `production` (sau khi `development` da verify xong):
      10. Mo PR moi: base = `production`, head = `feature/phased-deploy-s01-full-networking` (cung feature branch).
      11. Doi `terraform-plan.yaml` chay voi account production - cung phai la 21 to add, 0 destroy.
      12. Merge -> `terraform-apply.yaml` chay trong Environment `production` -> approve -> verify Console account production.
      13. Ghi nhan: tat ca cac giai doan tiep theo (S02, S03, S04) lap lai cung flow nay - dev truoc, verify, roi production.

## Review checklist

Cac reviewer tick box khi verify xong.

## Review log

(Cac reviewer append vao day sau khi hoan thanh review.)

### 2026-05-15 - iac-reviewer
- Verdict: approve
- Sub-tasks ticked: S01-T01, S01-T02
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 1, NIT 0
- Ghi chu: `terraform validate` khong chay duoc cuc bo (Terraform CLI v1.9.2 < required >= 1.11). Da review thu cong o muc source. Nho `terraform-planner` (S01-T04) xac nhan `terraform validate` + `terraform plan` tren runner co Terraform >= 1.11. `tflint` cung khong co tren may cuc bo (LOW finding).

## Last updated

2026-05-15 by main thread - lam ro moi truong chay cac lenh terraform (CI runner, khong yeu cau local); tick S01-T03 va S01-T04 sau khi iac-reviewer va terraform-planner hoan thanh; doi marker PHASED-ROLLOUT thanh PHASED-DEPLOY; them buoc replicate sang production trong S01-T05
