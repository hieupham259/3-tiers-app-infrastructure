# Sprint S03 - Khoi phuc prevent_destroy sau khi destroy xong (PR2)

## Goal

Sau khi DB instance development da bi destroy thanh cong (PR1 gom S01+S02 da merge va
workflow da chay), khoi phuc `lifecycle { prevent_destroy = true }` tren `aws_db_instance.this`
trong `modules/rds/main.tf` de bao ve lai ca 2 environment (development va production) khoi
cac destroy vo tinh trong tuong lai.

Day la buoc 2 (PR2) cua staged 2-PR convention. Sprint nay phai duoc dispatch CHI SAU KHI:
1. PR1 (S01+S02) da duoc merge vao `development`.
2. Workflow targeted destroy da duoc chay thanh cong (DB dev da bi xoa).
3. Nguoi dung xac nhan rang destroy da hoan tat.

## Definition of done

- `modules/rds/main.tf`: block `lifecycle` cua `aws_db_instance.this` duoc khoi phuc voi
  `prevent_destroy = true` va `ignore_changes = [final_snapshot_identifier, password]`.
- Comment mo ta rui ro trong lifecycle block duoc khoi phuc (hoac viet lai) tuong duong voi
  comment goc (giai thich ly do prevent_destroy).
- `terraform fmt -check -recursive` sach.
- `terraform validate` sach tren ca `envs/development` va `envs/production`.
- `tflint --recursive` sach.
- `scripts/verify-envs-in-sync.sh` sach.
- `iac-reviewer` da verify va tick checkbox S03-T01.

## Dieu kien tien quyet truoc khi dispatch Sprint nay

Sprint nay KHONG duoc dispatch dong thoi voi S01/S02. Thu tu bat buoc:
1. S01 hoan tat + S02 hoan tat (cac checkbox da tick).
2. Nguoi dung commit + push PR1 (nhanh `development`).
3. Nguoi dung chay workflow targeted destroy tren GitHub Actions.
4. Nguoi dung xac nhan destroy thanh cong (DB dev khong con trong AWS Console).
5. Nguoi dung yeu cau dispatch Sprint S03.

## Sub-tasks

- [ ] S03-T01 - Khoi phuc prevent_destroy = true tren aws_db_instance.this
  - Assignee: iac-builder
  - Inputs / preconditions:
    - File `modules/rds/main.tf` o trang thai sau PR1 (lifecycle block chi co `ignore_changes`).
    - Nguoi dung da xac nhan destroy dev DB thanh cong.
    - Them lai `prevent_destroy = true` vao lifecycle block cua `aws_db_instance.this`.
    - Giu nguyen `ignore_changes = [final_snapshot_identifier, password]`.
    - Giu nguyen lifecycle block cua `aws_secretsmanager_secret.db` (khong cham vao).
  - Outputs / artifacts:
    - File sua: `modules/rds/main.tf` - lifecycle block cua `aws_db_instance.this` khoi phuc
      dung `prevent_destroy = true` va `ignore_changes`.
  - Depends on: none (Sprint S01 va S02 da hoan tat truoc khi Sprint nay duoc dispatch)
  - Notes: |
      Day la buoc mirror cua S01-T01: add lai `prevent_destroy = true` ma S01-T01 da xoa.
      Comment giac thich ly do nen ghi ro: "Prevent accidental destroy: this is the primary
      application database; recovery requires a snapshot restore and incurs full app downtime."
      hoac tuong duong. Giu dung cau truc lifecycle block nhu truoc PR1.

- [ ] S03-T02 - Review viec khoi phuc prevent_destroy
  - Assignee: iac-reviewer
  - Inputs / preconditions:
    - File `modules/rds/main.tf` sau khi S03-T01 hoan tat.
    - Sprint plan nay (doi chieu voi Definition of done).
  - Outputs / artifacts:
    - Checkbox S03-T01 duoc tick neu verified.
    - `## Review log` duoc append vao cuoi file Sprint nay.
    - Neu co finding BLOCKER hoac NOT DONE, reassign S03-T01 ve `iac-builder`.
  - Depends on: S03-T01
  - Notes: |
      Reviewer xac nhan:
      - `prevent_destroy = true` da duoc khoi phuc trong lifecycle block cua `aws_db_instance.this`.
      - `ignore_changes` van con nguyen.
      - `prevent_destroy` tren `aws_secretsmanager_secret.db` van con nguyen (khong bi anh huong).
      - Quality gates sach.
      Viec THEM LAI `prevent_destroy` tren stateful resource la hanh dong bao ve - khong co
      reason gi de block, reviewer nen approve nhanh.

## Review checklist

(iac-reviewer se tick cac box sau khi verify)

- [ ] S03-T01: `modules/rds/main.tf` da khoi phuc `prevent_destroy = true` tren
      `aws_db_instance.this`, `ignore_changes` van con, `aws_secretsmanager_secret.db` khong bi anh huong.

## Open questions

- Khong co.

## Ghi chu thuoc tinh trang thai

Sprint nay KHONG CAN `terraform-state-refactor` vi khong co resource address nao thay doi.
Viec them/xoa `prevent_destroy` chi anh huong lifecycle policy trong Terraform, khong anh huong
state address hay remote state tren AWS.

## Last updated

2026-06-11 by task-planner
