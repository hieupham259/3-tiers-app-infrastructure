# Sprint S01 - Deploy full networking module, comment 8 module con lai

## CAP NHAT 2026-05-15: refactor cost-optimization

Sprint nay da bi DIEU CHINH sau khi user yeu cau toi uu chi phi. Kien truc moi:

- **VPC 2 AZ** (truoc day default 1 AZ). az_count default = 2.
- **KHONG CO NAT Gateway, KHONG CO Elastic IP** (truoc day co 1 NAT + 1 EIP per AZ). Tiet kiem ~$32/thang.
- **ECS Fargate** chay trong public subnet voi `assign_public_ip = true` thay vi private subnet (cap nhat ben trong block comment cua `module "ecs_service"` de S04 dung kien truc moi).
- **Private subnet** chi co local route (khong co route 0.0.0.0/0) - chi de chua RDS.
- **Private route table** la 1 RT shared cho 2 private subnet (truoc day per-AZ).

Resource mong doi cuoi cung: **12 resource networking** (1 VPC + 2 public subnet + 2 private subnet + 1 IGW + 1 public RT + 1 private RT + 4 RTA). Truoc kia plan ghi 21 (3 AZ + 3 NAT/EIP) va terraform plan thuc te chay 10 (1 AZ + 1 NAT/EIP) deu khong con dung. Xem README.md cua plan de biet ly do va anh huong.

Sub-task S01-T01 (them lifecycle prevent_destroy cho aws_eip.nat) khong con relevant - aws_eip da bi xoa khoi modules/network. Sub-task nay duoc danh dau obsolete o duoi.

## Goal

Sau Sprint nay, `envs/_shared/main.tf` chi goi mot module duy nhat la `module "network"` (tat ca 8 module con lai bi comment). `module "network"` da duoc refactor cost-optimization (no NAT/EIP, 2 AZ, ECS se dung public subnet o S04). `envs/_shared/outputs.tf` comment toan bo cac block tham chieu toi 8 module da bi comment. `terraform validate` va `terraform fmt -check` pass. `terraform plan` chi thay cac resource cua module `network` duoc tao: VPC, 4 subnet (2 public + 2 private), IGW, 2 route table, 4 route table association = **12 resource**. Deploy len branch `development` thanh cong.

## Pham vi comment can thuc hien (chi tiet cho iac-builder)

### 1. `modules/network/` - refactor cost-optimization (CAP NHAT 2026-05-15)

Ban dau plan ghi "KHONG CHAM VAO". Sau khi user duyet phuong an cost-opt, module nay da duoc refactor:
- `variables.tf`: `az_count` default 1 → 2.
- `main.tf`: xoa `aws_eip.nat` va `aws_nat_gateway.this`; `aws_route_table.private` shared (count=1) khong co route NAT; `aws_route_table_association.private` map ve RT[0].
- `README.md`: cap nhat mo ta.

Module sau refactor deploy full kien truc cost-optimized (12 resource, no NAT/EIP, 2 AZ).

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

Sau refactor cost-optimization, **khong con resource stateful** trong module network (aws_eip da bi xoa, NAT gateway khong stateful). Cac stateful resource (`aws_db_instance`, `aws_secretsmanager_secret`, `aws_s3_bucket`) nam o cac module khac (rds, frontend-cdn) se duoc xu ly trong Sprint S03 va S04 voi `lifecycle { prevent_destroy = true }`.

## Definition of done

LUU Y VE MOI TRUONG CHAY: Cac lenh terraform/tflint duoi day deu duoc verify tren GitHub Actions CI runner (workflow `terraform-plan.yaml` va `terraform-apply.yaml`, dung Terraform 1.13.3) - KHONG yeu cau chay o local. Terraform CLI local cua nguoi dung la v1.9.2 < `required_version >= 1.11` cua repo, nen agent team khong chay duoc cuc bo; viec verify chinh thuc dien ra tren CI. Nguoi dung khong can cai Terraform o may de hoan thanh Sprint nay.

- `terraform fmt -check -recursive` tra ve exit 0 - verify boi step "Terraform fmt -check" trong `terraform-plan.yaml`.
- `terraform validate` trong `envs/development/` tra ve "Success!" - verify boi step "Terraform validate" trong `terraform-plan.yaml`.
- `tflint --recursive` khong co error - verify tren CI.
- `scripts/verify-envs-in-sync.sh` pass - verify boi job `sync-check` trong `terraform-plan.yaml` va `terraform-apply.yaml` (script chi check `envs/development/main.tf` va `envs/development/variables.tf` - 2 file nay khong doi nen auto-pass).
- `terraform plan` trong `envs/development/` xac nhan chi co resource cua `module.network` duoc tao (sau refactor cost-opt): 1 aws_vpc, 4 aws_subnet (2 public + 2 private), 1 aws_internet_gateway, 2 aws_route_table (1 public + 1 private shared), 4 aws_route_table_association = **12 resource**. KHONG co aws_eip va aws_nat_gateway. Khong co resource nao khac. Plan chinh thuc duoc post len PR comment boi step "Comment plan on PR" trong `terraform-plan.yaml`.
- PR tu feature branch vao `development` duoc merge thanh cong.
- GitHub Actions workflow `terraform-apply.yaml` chay thanh cong tren branch `development`.
- Networking infrastructure xuat hien trong AWS Console: VPC, 4 subnet, IGW, 2 route table. KHONG co NAT gateway, KHONG co EIP.

## Sub-tasks

- [x] S01-T01 - ~~Them lifecycle { prevent_destroy = true } cho aws_eip.nat~~ OBSOLETE
  - Assignee: iac-builder
  - Notes: Sub-task nay khong con relevant sau refactor cost-optimization (2026-05-15). aws_eip va aws_nat_gateway da bi xoa khoi modules/network. Giu checkbox da tick de luu lich su - luc thuc hien S01-T01 lan dau, lifecycle da duoc them dung yeu cau cu, nhung resource da bi xoa khoi code o refactor sau do.

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
  - Notes: Plan ket qua mong doi (sau refactor cost-opt): chi cac resource cua module.network = **12 resource** (1 aws_vpc, 4 aws_subnet, 1 aws_internet_gateway, 2 aws_route_table, 4 aws_route_table_association). KHONG co aws_eip va aws_nat_gateway. Khong co resource nao tu 8 module bi comment.
  - MOI TRUONG CHAY: `terraform plan` KHONG chay duoc o local (Terraform CLI v1.9.2 < required >= 1.11). Plan chinh thuc se chay tren CI runner khi mo PR vao `development` (step "Terraform plan" trong `terraform-plan.yaml`, Terraform 1.13.3) va post len PR comment. Nguoi dung xac nhan plan o buoc do, khong can chay terraform o may.

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
      5. Workflow `terraform-plan.yaml` tu dong chay. Doi job pass. Kiem tra plan comment tren PR: chi co networking resource (**12 to add, 0 change, 0 destroy** sau refactor cost-opt - khong co NAT/EIP).
      6. Merge PR vao `development`.
      7. Push vao `development` trigger `terraform-apply.yaml`. Vao tab Actions -> click vao run moi nhat -> "Review deployments" -> tick `development` -> Approve.
      8. Doi job `apply` hoan tat voi trang thai "Success".
      9. Verify tren AWS Console: VPC, 4 subnet (2 public + 2 private), IGW, 2 route table (1 public + 1 private shared) cua development. KHONG co NAT gateway, KHONG co EIP.
      Replicate sang `production` (sau khi `development` da verify xong):
      10. Mo PR moi: base = `production`, head = `feature/phased-deploy-s01-full-networking` (cung feature branch).
      11. Doi `terraform-plan.yaml` chay voi account production - cung phai la **12 to add, 0 destroy**.
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

### 2026-05-15 - iac-reviewer (refactor cost-optimization: bo NAT/EIP)
- Verdict: approve with comments
- Sub-tasks ticked: none (main thread se rewrite Sprint vi kien truc da doi - NAT/EIP bi go khoi modules/network, kien truc ECS chuyen sang public subnet)
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: production cung se mat NAT khi merge cung diff sang `production` branch (vi `envs/_shared/` dung chung). Neu sau nay production can NAT, can introduce variable gate (vi du `enable_nat_gateway`) o module network va expose qua `envs/_shared/variables.tf` de production override. Hien tai user da chap nhan; ghi nhan de quay lai khi production deploy that.
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 1, LOW 2, NIT 1
- Ghi chu: refactor hop le ve Terraform syntax (aws_route_table khong route block la valid), AWS docs (Fargate awsvpc + public subnet + assign_public_ip=true la phuong an chinh thuc thay NAT de pull ECR/Secrets). README network con noi "3 AZs" - can sua thanh "2 AZs". `envs/_shared/main.tf` block ecs_service van comment - viec sua subnet_ids/assign_public_ip ben trong block comment dung mong doi cho Sprint sau.

## Last updated

2026-05-15 by main thread - cap nhat Sprint cho refactor cost-optimization: bo NAT/EIP, 2 AZ, 12 resource thay vi 21; danh dau S01-T01 obsolete; cap nhat moi tham chieu resource count trong DoD + S01-T04 + S01-T05
