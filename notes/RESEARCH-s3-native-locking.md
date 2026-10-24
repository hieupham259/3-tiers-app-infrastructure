# Research: S3 Native State Locking (không cần DynamoDB)

> Câu hỏi: Có thể dùng **chỉ S3** làm state locking thay vì **S3 + DynamoDB** không?
> Trả lời ngắn: **CÓ — và đây là cách được khuyến nghị từ Terraform 1.11+ (2025).** DynamoDB locking đã bị **deprecated**.

---

## 1. Tóm tắt kết quả research

| Mốc | Phiên bản Terraform | Sự kiện |
|-----|---------------------|---------|
| 22/12/2024 | **1.10** | Giới thiệu `use_lockfile` (experimental) — S3 native state locking |
| 27/02/2025 | **1.11** | Bỏ nhãn experimental, **deprecated** `dynamodb_table` / `dynamodb_endpoint` / `endpoints.dynamodb` |
| Hiện tại (05/2026) | **>= 1.11** | S3-only locking là **stable** và là cách khuyến nghị |

**Kết luận:** Cho dự án mới khởi tạo (như repo `3-tiers-app-infrastructure` này), nên dùng **S3 native locking** ngay từ đầu. Không cần tạo DynamoDB table.

---

## 2. Cơ chế hoạt động

S3 native locking dựa trên **S3 conditional writes** (tính năng GA 11/2024 trên toàn S3):

1. Khi Terraform bắt đầu một operation (`plan`, `apply`, `destroy`...), nó gọi `PutObject` với header `If-None-Match: *` để tạo file lock.
2. S3 chỉ ghi nếu object chưa tồn tại — đây là **atomic compare-and-swap** ở tầng storage.
3. Lock file đặt cùng path với state, đuôi `.tflock`. Ví dụ:
   - State: `s3://bucket/3-tiers-app/development/terraform.tfstate`
   - Lock:  `s3://bucket/3-tiers-app/development/terraform.tfstate.tflock`
4. Nội dung lock file là JSON metadata (operation ID, who, when).
5. Khi xong, Terraform `DeleteObject` để giải phóng lock.

Đây là **optimistic locking** — Terraform delegate hoàn toàn việc quản lý lock cho S3, không cần một service phụ.

---

## 3. Cấu hình mới (so sánh)

### Trước (S3 + DynamoDB — deprecated)

```hcl
terraform {
  backend "s3" {
    bucket         = "myorg-tfstate-111111111111"
    key            = "3-tiers-app/development/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "myorg-tfstate-locks"   # ← DEPRECATED
  }
}
```

### Sau (S3-only — khuyến nghị)

```hcl
terraform {
  required_version = ">= 1.11"

  backend "s3" {
    bucket       = "myorg-tfstate-111111111111"
    key          = "3-tiers-app/development/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true                       # ← ĐỦ rồi, không cần DynamoDB
    # kms_key_id = "arn:aws:kms:..."          # nên có cho production
  }
}
```

---

## 4. IAM permissions cần thiết

Khi dùng `use_lockfile = true`, role cần thêm quyền trên path lock file:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ],
  "Resource": [
    "arn:aws:s3:::myorg-tfstate-111111111111/3-tiers-app/*/terraform.tfstate",
    "arn:aws:s3:::myorg-tfstate-111111111111/3-tiers-app/*/terraform.tfstate.tflock"
  ]
}
```

So với approach cũ:
- ❌ Bỏ: `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem` trên table lock
- ✅ Thêm: `s3:DeleteObject` trên path `*.tflock` (nếu trước đây policy chỉ có GetObject/PutObject)

---

## 5. Lợi ích

| Tiêu chí | S3 + DynamoDB (cũ) | S3 only (mới) |
|----------|--------------------|--------------------|
| Số AWS resource cần dựng | 2 (S3 bucket + DynamoDB table) | 1 (S3 bucket) |
| Bootstrap phức tạp | Cao hơn | Thấp hơn |
| Chi phí | DynamoDB ~$0.25/tháng (PAY_PER_REQUEST, traffic thấp) | $0 thêm (chỉ vài requests) |
| IAM policy | Phải cấp quyền chéo S3 + DynamoDB | Chỉ S3 |
| Cross-region replication state | Phải replicate cả 2 | Chỉ replicate S3 |
| Phụ thuộc dịch vụ | 2 dịch vụ | 1 dịch vụ → ít điểm fail hơn |
| Atomicity | DynamoDB conditional write | S3 conditional write (`If-None-Match`) |
| Hỗ trợ chính thức | **Deprecated** từ 1.11 | **Stable** & khuyến nghị |

---

## 6. Caveats / lưu ý

1. **Yêu cầu Terraform >= 1.11** để có trạng thái stable. Nếu team có người vẫn xài < 1.10, sẽ không lock được → **bắt buộc pin version** qua `.terraform-version` (tfenv) và `required_version` trong code.
2. **S3 Object Lock buckets**: bug 1.10.0 với `skip_checksum` đã được fix ở 1.10.1 — không vấn đề trên 1.11+.
3. **Versioning bucket**: vẫn nên bật để rollback state khi cần — không liên quan đến locking.
4. **Lock file bị "kẹt"**: nếu CI bị giết giữa chừng và không kịp `DeleteObject`, lock file vẫn còn — phải `terraform force-unlock <ID>` hoặc xóa thủ công file `.tflock`. Hành vi này **giống hệt** DynamoDB approach (cũng có thể bị stuck lock).
5. **Migration từ cấu hình cũ**: có thể chạy **đồng thời** cả `dynamodb_table` và `use_lockfile` trong giai đoạn chuyển đổi → an toàn để cutover dần. Sau khi xác nhận, bỏ `dynamodb_table` và destroy DynamoDB table.
6. **OpenTofu**: nếu dự án dùng OpenTofu thay vì Terraform, kiểm tra version — OpenTofu cũng đã port feature này (từ OpenTofu 1.10) nhưng cần verify với version đang dùng.

---

## 7. Khuyến nghị cho dự án này

### Áp dụng ngay từ bootstrap

Vì đây là dự án **mới khởi tạo** (chưa có state nào), không có gánh nặng migration:

1. **Bỏ hoàn toàn** thư mục/module DynamoDB trong `global/tf-state-bootstrap/`.
2. Bootstrap chỉ cần tạo:
   - 1 S3 bucket cho tfstate (versioning + SSE-KMS + block public access + lifecycle xóa noncurrent versions sau 90 ngày)
   - (Optional) 1 KMS key riêng cho encryption
3. Pin `required_version = ">= 1.11"` ở mọi env.
4. IAM role OIDC chỉ cần cấp quyền S3 (bỏ DynamoDB).

### Ví dụ `global/tf-state-bootstrap/main.tf` rút gọn

```hcl
terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "myorg-tfstate-111111111111"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tfstate.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

resource "aws_kms_key" "tfstate" {
  description             = "KMS for Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

# KHÔNG còn aws_dynamodb_table cho lock nữa
```

### Backend config trong mỗi env

```hcl
# envs/development/backend.tf
terraform {
  required_version = ">= 1.11"
  backend "s3" {
    bucket       = "myorg-tfstate-111111111111"
    key          = "3-tiers-app/development/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    kms_key_id   = "alias/tfstate"
    use_lockfile = true
  }
}
```

---

## 8. Action items áp dụng vào ARCHITECTURE.md

- [ ] Cập nhật mục **3.1 State management**: bỏ DynamoDB, dùng `use_lockfile = true`.
- [ ] Cập nhật **Roadmap bước 1** (`global/tf-state-bootstrap`): chỉ tạo S3 + KMS.
- [ ] Cập nhật IAM policy mẫu: bỏ permissions DynamoDB.
- [ ] Thêm `required_version = ">= 1.11"` thành policy bắt buộc; `.terraform-version` pin version cụ thể (vd `1.13.x`).
- [ ] Thêm vào checklist quality gates: CI verify Terraform version >= 1.11.

---

## Sources

- [Terraform S3 Backend (official docs)](https://developer.hashicorp.com/terraform/language/backend/s3) — `use_lockfile` stable, `dynamodb_table` marked Deprecated
- [S3 native state locking — Bruno Schaatsbergen](https://www.bschaatsbergen.com/s3-native-state-locking) — kỹ thuật chi tiết, lịch sử PR
- [Goodbye DynamoDB — Terraform S3 Backend Now Supports Native Locking (Medium)](https://rafaelmedeiros94.medium.com/goodbye-dynamodb-terraform-s3-backend-now-supports-native-locking-06f74037ad39)
- [Terraform state with native s3 locking (DEV.to)](https://dev.to/drewmullen/terraform-state-with-native-s3-locking-1fck)
- [State Locking with S3 Without DynamoDB in Terraform (CloudThat)](https://www.cloudthat.com/resources/blog/state-locking-with-s3-without-dynamodb-in-terraform)
- [HashiCorp Discuss feature request thread](https://discuss.hashicorp.com/t/feature-request-terraform-state-locking-in-aws-with-s3-strong-consistency-no-dynamodb/18456)
