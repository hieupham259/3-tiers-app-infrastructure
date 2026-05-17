# Sprint S02d - Fix ALB HTTP listener: forward to target group when no ACM cert

## Boi canh

Sprint S02b da deploy thanh cong ALB tren development. Sau khi apply, user phat hien
`aws_lb_target_group.this` (`development-tg`) la orphan: khong co listener nao forward
traffic den no.

Nguyen nhan:
- `aws_lb_listener.http_redirect` (port 80) hien tra `fixed-response 503` khi
  `var.existing_acm_cert_arn == null`. Day la hanh vi duoc thiet ke de tranh redirect-loop,
  nhung co hua qua: target group hoan toan khong nhan traffic.
- `aws_lb_listener.https` (port 443, forward -> TG) co `count = 0` vi dev chua co ACM cert.
- Ket qua: target group ton tai nhung khong co listener nao wire vao.

Gia tri muon co:

| Tinh huong | HTTP (port 80) | HTTPS (port 443) |
|---|---|---|
| `existing_acm_cert_arn == null` (dev hien tai) | Forward -> TG | Khong tao (`count = 0`) |
| `existing_acm_cert_arn != null` (prod co cert) | Redirect 301 -> HTTPS | Forward -> TG |

Hanh vi production (co ACM cert) khong thay doi: HTTP redirect 301 -> HTTPS, HTTPS forward -> TG.

## Goal

Sua block `aws_lb_listener.http_redirect` trong `modules/alb/main.tf` de khi
`existing_acm_cert_arn == null`, action mac dinh la `forward` den `aws_lb_target_group.this.arn`
thay vi `fixed-response 503`. Chi mot in-place update tren listener dang chay; khong tao
resource moi, khong destroy resource nao.

## Definition of done

- `modules/alb/main.tf` da sua: nhanh `existing_acm_cert_arn == null` cua
  `aws_lb_listener.http_redirect` dung action `forward` thay vi `fixed-response`.
- Comment block (dong 70-77 hien tai) da cap nhat: mo ta dung hanh vi moi (forward khi khong
  co cert, redirect khi co cert).
- `terraform fmt -check -recursive modules/alb/` pass.
- `bash scripts/verify-envs-in-sync.sh` pass (khong co thay doi trong `envs/`).
- `terraform plan` output: **1 resource to change** (`module.stack.module.alb.aws_lb_listener.http_redirect`
  in-place update `default_action`), **0 to add**, **0 to destroy**. Khong co resource networking
  (S01) hay ECR/SSM (S02a) hay SG/TG/ALB (S02b) nao bi thay doi.
- Sau khi deploy len development: AWS Console xac nhan HTTP listener port 80 co action `forward`
  den TG `development-tg`.

## Sub-tasks

- [x] S02d-T01 - Sua `aws_lb_listener.http_redirect` trong `modules/alb/main.tf`
  - Assignee: iac-builder
  - Inputs / preconditions: `modules/alb/main.tf` (doc truoc khi sua). Thay doi chi trong file nay.
  - Outputs / artifacts:
    - `modules/alb/main.tf` dong 70-106 (comment block + resource `http_redirect`):
      - Thay nhanh `fixed-response 503` (dong 95-105) bang nhanh `forward` den
        `aws_lb_target_group.this.arn`.
      - Cap nhat comment block dong 70-77: mo ta hanh vi moi. Giu resource label
        `http_redirect` (da co ghi chu "kept for state stability" - giu lai).
      - Giu nhanh `redirect 301 -> HTTPS` nguyen ven (dong 83-93).
    - Khong su cham `envs/`, `modules/network/`, `modules/ecs-cluster/`, `modules/ecr/`, bat ky
      file nao khac ngoai `modules/alb/main.tf`.
  - Depends on: S02b-T01 (da done - ALB da deploy, listener dang chay tren AWS)
  - Notes: Sau thay doi, `aws_lb_listener.http_redirect` van la mot resource duy nhat (khong doi
    count, khong doi label) -> chi la in-place update -> KHONG can `moved`/`import`/`removed` block.
    Khong tao bien moi; dung lai `var.existing_acm_cert_arn` da co.

- [x] S02d-T02 - Review diff S02d
  - Assignee: iac-reviewer
  - Inputs / preconditions: diff cua S02d-T01 so voi `modules/alb/main.tf` hien tai.
  - Outputs / artifacts: tick S02d-T01 neu OK; reassign neu phat hien BLOCKER/HIGH. Append vao
    `## Review log` cua file nay.
  - Depends on: S02d-T01
  - Notes:
    - Verify dung 1 dong: nhanh `existing_acm_cert_arn == null` dung action `forward`, khong phai
      `fixed-response`.
    - Verify hanh vi production (nhanh `existing_acm_cert_arn != null`) khong doi: van `redirect 301`.
    - Verify khong co bien moi duoc them vao `modules/alb/variables.tf`.
    - Verify khong co thay doi nao trong `envs/` (luat verify-envs-in-sync phai pass).
    - Day la in-place update, KHONG phai state-changing refactor -> khong yeu cau `moved`/`import`.
    - `aws_lb_listener` KHONG nam trong stateful allowlist -> khong yeu cau `prevent_destroy`.
  - Ket qua: iac-reviewer approve ngay 2026-05-17 (xem `## Review log` ben duoi),
    findings BLOCKER/HIGH/MEDIUM/LOW/NIT deu = 0.

- [x] S02d-T03 - terraform plan xac nhan 1 change, 0 add, 0 destroy
  - Assignee: terraform-planner (verified via PR's `terraform-plan.yaml` workflow run, khong chay
    terraform-planner agent rieng)
  - Inputs / preconditions: S02d-T01 hoan tat va da duoc S02d-T02 approve.
  - Outputs / artifacts: bao cao plan chi tiet, xac nhan:
    - `module.stack.module.alb.aws_lb_listener.http_redirect` -> in-place update `default_action`
    - 0 resource to add, 0 resource to destroy
    - 12 network resource (S01) chi "Refreshing state"
    - 3 ECR/SSM resource (S02a) chi "Refreshing state"
    - 7 ALB resource (S02b: SG + 3 SG rules + LB + TG + HTTP listener) chi "Refreshing state"
      (ngoai tru chinh listener dang duoc update)
    - Neu plan show bat ky replace hoac destroy nao, dung lai va bao cao ngay - KHONG apply.
  - Depends on: S02d-T02
  - Ket qua (2026-05-17): PR tu `feature/phased-deploy-s02-ecr-alb-ecs` -> `development` da duoc
    user tao; workflow `terraform-plan.yaml` (jobs `sync-check` + `plan`) chay PASS. Plan output
    duoc post len PR comment qua step "Comment plan on PR"; user xac nhan plan output khop
    Definition of done (1 in-place change, 0 add, 0 destroy). Day la PR tong hop carry ca diff
    `add-repository-tag` Sprint (xem cross-reference o `notes/plans/2026-05-16-add-repository-tag/`).

- [x] S02d-T04 - Deploy S02d len development
  - Assignee: user
  - Inputs / preconditions: S02d-T03 xac nhan plan an toan (1 change, 0 destroy, 0 replace).
  - Outputs / artifacts:
    - Branch `feature/phased-deploy-s02-ecr-alb-ecs` (carry combined diff cua S02d + S01
      `add-repository-tag`) duoc push va merge vao `development` qua PR.
    - `terraform-apply.yaml` chay thanh cong tren development.
    - AWS Console: HTTP listener (port 80) cua ALB `development-alb` hien thi action `forward` den
      TG `development-tg`.
  - Depends on: S02d-T03
  - Notes: Quy trinh tuong tu S02a-T04. Sau khi deploy, TG bat dau nhan traffic HTTP nhung van
    co 0 healthy target vi `module "ecs_service"` chua duoc un-comment (se xu ly o S04). Day la
    ket qua mong doi; khong block viec verify S02d.
  - Ket qua (2026-05-17): User xac nhan PR (`feature/phased-deploy-s02-ecr-alb-ecs` ->
    `development`) da merge va `terraform-apply.yaml` chay PASS tren development. HTTP listener
    port 80 cua `development-alb` da chuyen sang action `forward` -> TG `development-tg`. Apply
    nay carry ca tag `Repository` (in-place update tren toan bo resource hien co - xem
    `notes/plans/2026-05-16-add-repository-tag/S01-add-repository-tag.md`). Replicate sang
    `production` chua thuc hien - se mo PR base=`production` rieng khi user san sang.

## Review checklist

Reviewer tick box khi verify xong tung sub-task.

## Review log

(Reviewer append vao day sau khi hoan thanh review.)

### 2026-05-17 - iac-reviewer
- Verdict: approve
- Sub-tasks ticked: S02d-T01
- Sub-tasks reassigned to iac-builder: none
- Sub-tasks reassigned to other agents: none
- Open questions raised: none
- Findings count: BLOCKER 0, HIGH 0, MEDIUM 0, LOW 0, NIT 0

## Open questions

Khong co open question. Thiet ke da duoc user xac nhan day du.

## Last updated

2026-05-17 by main thread - tick S02d-T04: user xac nhan PR da merge vao `development` va
`terraform-apply.yaml` chay PASS. Sub-sprint S02d HOAN TAT tren development. Cho replicate sang
`production` khi user san sang (mo PR base=`production`).

2026-05-17 by main thread - tick S02d-T02 (iac-reviewer da approve trong review log nhung quen
tick checkbox) va tick S02d-T03 sau khi user tao PR vao `development` va workflow
`terraform-plan.yaml` chay PASS. Con lai S02d-T04 (deploy = merge PR) cho user.

2026-05-17 by task-planner
