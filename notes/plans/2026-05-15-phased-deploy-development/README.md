# Phased Deploy for Development Environment

## Context

Day la trien khai ha tang LAN DAU (chua co resource nao duoc tao tru cac stack trong `bootstrap/`). Day KHONG phai rollout/cap nhat ha tang dang chay.

Nguoi dung muon deploy ha tang theo tung module mot (phased deploy) cho moi truong `development` thay vi deploy toan bo stack cung luc, voi muc dich hieu cau truc va cach hoat dong cua Terraform. Cach thuc hien: comment phan code chua can thiet de moi lan `terraform apply` chi tao dung cac resource cua giai doan hien tai. Sau moi giai doan, un-comment them module cua giai doan ke tiep va deploy lai.

Sau khi moi giai doan chay tot tren `development`, nguoi dung se merge cung thay doi do sang `production` (tung module hoac vai module mot lan).

Module `modules/network/` duoc giu nguyen hoan toan - khong comment, khong sua gi ben trong. Sprint 1 deploy full networking (VPC + subnet + IGW + NAT + EIP + route table + route table association). Chi comment/uncomment cac module call trong `envs/_shared/main.tf` va cac block tuong ung trong `envs/_shared/outputs.tf`.

## Cap nhat

Plan nay da duoc sua lai vao 2026-05-15 (ban dau tao cung ngay). Thay doi chinh: S01 cu (comment ben trong modules/network) va S02 cu (uncomment full networking) da duoc gop/loai bo. Thay vao do la 4 Sprint moi, khong dong cham vao `modules/network/`.

## Deployment model

Apply KHONG chay tu local. Theo CLAUDE.md, apply chi xay ra qua GitHub Actions pipeline khi push. Luong deploy cho moi giai doan:

1. Tao feature branch tu `development`.
2. Commit va push code (da comment/uncomment dung giai doan).
3. Mo PR vao `development` -> `terraform-plan.yaml` chay, kiem tra plan.
4. Merge PR vao `development` -> `terraform-apply.yaml` chay, duyet va apply.

## Sprints

| ID | Title | Status | Owner of last update |
|----|-------|--------|----------------------|
| S01 | deploy-full-networking | planned | task-planner |
| S02 | uncomment-ecr-alb-ecs-cluster | planned | task-planner |
| S03 | uncomment-rds-iam | planned | task-planner |
| S04 | uncomment-ecs-service-cdn-observability | planned | task-planner |

## Chuoi phu thuoc giua Sprint

S01 -> S02 -> S03 -> S04. Moi Sprint mo khoa giai doan truoc khi bat dau giai doan tiep theo.

## Open questions

- Khong co open question. Tat ca quyet dinh co the dat ra da duoc nguoi dung trinh bay ro trong yeu cau.

## Out-of-scope

- Thay doi ben trong `modules/network/` - module nay duoc giu nguyen hoan toan trong suot qua trinh.
- Thay doi `envs/development/` va `envs/production/` ngoai viec deploy.
- Thay doi cac workflow `.github/workflows/`.
- Luat "byte-identical" cua `scripts/verify-envs-in-sync.sh` khong bi vi pham vi script chi kiem tra `envs/development/main.tf` va `envs/development/variables.tf` - khong kiem tra `envs/_shared/`.

## Production

Code comment/uncomment nam o `envs/_shared/` (dung chung cho ca hai env). Vi chua co resource nao duoc tao tren ca `development` lan `production`, viec deploy sang `production` la AN TOAN - moi giai doan chi THEM resource (0 destroy).

Luong lam viec:
- Moi Sprint = mot feature branch chua dung mot diff. Merge vao `development` truoc -> deploy + verify tren account development.
- Sau khi `development` chay tot, merge cung feature branch do sang `production` -> deploy + verify tren account production.
- Co the gom vai Sprint roi merge sang `production` mot lan (vai module mot luc) thay vi tung Sprint mot.
- Khong co rang buoc thu tu cung-nhip giua hai env; `development` co the di truoc `production` bao nhieu giai doan tuy y.

## Last updated

2026-05-15 by main thread - doi ten thu muc tu phased-rollout sang phased-deploy; lam ro day la deploy lan dau (khong phai rollout); cap nhat huong dan deploy sang production cho dung y dinh nguoi dung
