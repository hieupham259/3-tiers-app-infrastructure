# How Terraform works in this repo

## 1. Init bắt đầu từ đâu?

Terraform luôn init từ **một thư mục "root module"** - là thư mục bạn `cd` vào và chạy `terraform init`. Trong repo này, root module là một trong hai env directories:

- `envs/development/` - root module cho account dev
- `envs/production/` - root module cho account prod
- `global/route53/` - root module riêng cho tài nguyên global (Route53 hosted zone)

`envs/_shared/` và `modules/` **không phải** root module - không bao giờ chạy `terraform init` trực tiếp ở đó. Chúng chỉ là module được gọi từ root.

Theo branch-per-environment model (xem `CLAUDE.md`): branch `development` deploy `envs/development`, branch `production` deploy `envs/production`. Không có workspace.

## 2. Thứ tự file Terraform đọc khi `terraform init` trong `envs/development/`

Terraform không quan tâm tên file - nó load **tất cả `*.tf` trong root module cùng lúc**. Thứ tự "logic" của init:

1. **Đọc toàn bộ `.tf` ở root** - `envs/development/`:
   - `backend.tf` -> khai báo `backend "s3"` (bucket `3-tiers-app-infrastructure-tfstate-<account-id>`, key `3-tiers-app/development/terraform.tfstate`, KMS `alias/tfstate`, lockfile S3-native).
   - `providers.tf` -> 2 AWS provider: default theo `var.region` + alias `us_east_1` (cho CloudFront ACM).
   - `variables.tf` -> khai báo biến input của root.
   - `main.tf` -> 1 module duy nhất `module "stack" { source = "../_shared" ... }`.
2. **Khởi tạo backend S3** - kết nối bucket tfstate, kiểm tra quyền, set lock.
3. **Resolve `module.stack`** - đi vào `envs/_shared/`, đọc:
   - `versions.tf` -> pin `aws ~> 5.70`, `random ~> 3.6`, `terraform >= 1.11`.
   - `main.tf` -> gọi tiếp 9 child module: `network`, `ecr_backend`, `alb`, `ecs_cluster`, `rds`, `iam_app_roles`, `ecs_service`, `frontend_cdn`, `observability` - đều `source = "../../modules/<name>"`.
   - `outputs.tf` -> SSM parameters + outputs.
   - `variables.tf`.
4. **Resolve child module** - đi vào từng `modules/<name>/` - chỉ load `*.tf`, **không** cần init riêng vì là local module.
5. **Download providers** từ registry vào `.terraform/providers/` (AWS, random).
6. **Tạo `.terraform.lock.hcl`** ở root (provider checksum).

Tóm tắt: file "đầu tiên" được parse là tập hợp `*.tf` trong `envs/development/`, nhưng **trigger init** là `backend.tf` (vì nó quyết định nơi state lưu - Terraform phải config backend trước khi làm gì khác).

## 3. Cấu trúc và nhiệm vụ từng folder

### `envs/_shared/` - "stack definition" dùng chung

- Là module **root-stack chung** cho mọi env. Chứa toàn bộ topology: VPC + ALB + ECS + RDS + ECR + CloudFront + IAM + Observability + SSM publishing.
- Được call từ `envs/development/main.tf` và `envs/production/main.tf` qua `source = "../_shared"`.
- Mục đích: đảm bảo dev và prod **chạy cùng một stack** - khác biệt duy nhất là giá trị `.tfvars`. Đây là cách CLAUDE.md ép "envs/development và envs/production phải identical".

### `envs/development/` và `envs/production/` - root modules per-env

Mỗi env chỉ chứa 4 file, và theo CLAUDE.md hai env phải **byte-identical** trừ 3 file:

- `backend.tf` - **khác nhau**: state key (`/development/` vs `/production/`), có thể khác bucket/account.
- `providers.tf` - **khác nhau**: region + default tags theo env.
- `terraform.tfvars` - **khác nhau**: giá trị input (CIDR, instance class, multi_az, domain...).
- `main.tf` + `variables.tf` - **giống hệt** prod, chỉ làm 1 việc: forward tất cả `var.*` xuống `module "stack" { source = "../_shared" }`.

Script `scripts/verify-envs-in-sync.sh` (theo CLAUDE.md) enforce invariant này.

### `global/` - tài nguyên không thuộc env nào

- `global/route53/` là root module **độc lập** (có `versions.tf` + `main.tf` riêng, init/apply riêng).
- Dùng cho tài nguyên "singleton" toàn project - ví dụ Route53 hosted zone primary mà cả dev và prod đều trỏ NS record vào.
- State riêng (sẽ có backend.tf riêng), apply ngoài luồng env.

### `modules/` - reusable building blocks

- 9 module: `network`, `alb`, `ecs-cluster`, `ecs-service`, `ecr`, `rds`, `iam-app-roles`, `iam-github-oidc`, `frontend-cdn`, `observability`.
- Mỗi module có file layout chuẩn `main.tf / variables.tf / outputs.tf / versions.tf` (theo CLAUDE.md convention).
- Không bao giờ là root - chỉ được gọi qua `module "..." { source = "../../modules/<name>" }` từ `envs/_shared/main.tf`.
- Naming convention: `${var.environment}-<resource>-<role>`.

## 4. Các folder work với nhau như thế nào

```
GitHub Actions (branch development)
        |
        v
   cd envs/development          <-- root module thật sự (chạy init/plan/apply ở đây)
        | backend.tf  ---> S3 tfstate (key /development/)
        | providers.tf ---> AWS account dev
        | variables.tf + terraform.tfvars
        | main.tf
        v
   module "stack" -> envs/_shared/   <-- 1 stack chung cho mọi env
        |
        +-- module "network"        -> modules/network/
        +-- module "alb"            -> modules/alb/
        +-- module "ecs_cluster"    -> modules/ecs-cluster/
        +-- module "ecs_service"    -> modules/ecs-service/
        +-- module "rds"            -> modules/rds/
        +-- module "ecr_backend"    -> modules/ecr/
        +-- module "iam_app_roles"  -> modules/iam-app-roles/
        +-- module "frontend_cdn"   -> modules/frontend-cdn/
        +-- module "observability"  -> modules/observability/

   (tách bạch hoàn toàn)

GitHub Actions (workflow global)
        |
        v
   cd global/route53           <-- root module riêng, state riêng
```

**Luồng dữ liệu giữa các module** (trong cùng env, do `envs/_shared/main.tf` wire):

- `network` xuất `vpc_id`, `public_subnet_ids`, `private_subnet_ids` -> cho `alb`, `rds`, `ecs_service` tiêu thụ.
- `alb` xuất `target_group_arn`, `security_group_id` -> cho `ecs_service`.
- `ecs_cluster` xuất `cluster_name` -> cho `ecs_service`, `observability`.
- `rds` xuất `secret_arn`, `endpoint`, `db_instance_id` -> cho `iam_app_roles`, `ecs_service`, `observability`.
- `frontend_cdn` xuất `bucket_arn`, `bucket_name`, `distribution_id` -> cho `iam_app_roles`, `observability`, SSM.
- `ecs_service` xuất `security_group_id` -> quay ngược lại làm `ingress_security_group_ids` của `rds`.
- Cuối cùng `envs/_shared/outputs.tf` publish các giá trị runtime ra **SSM Parameter Store** (`/3-tiers-app/<env>/...`) để các repo app khác (frontend, backend pipeline) đọc lúc deploy.

**Tách biệt env** đạt được hoàn toàn bằng:

1. Hai thư mục root khác nhau => hai `terraform init` riêng => hai `.terraform/` riêng.
2. Hai backend key khác nhau => hai state file riêng.
3. Hai branch git khác nhau => hai pipeline OIDC role khác nhau => hai AWS account khác nhau.
4. Không workspace, không cross-env reference - `global/` cũng là root riêng để không bị kéo vào state env.

## 5. Cơ chế: tại sao root module gọi được sang `envs/_shared/`, và `envs/_shared/` gọi được sang child module?

Phần này đi sâu vào **mechanism** của Terraform - không có "magic", chỉ là 3 thứ rất cụ thể: `module` block, `source` attribute, và cách Terraform build một **resource graph** duy nhất.

### 5.1. `module` block là gì

Một `module "X" { source = "..." }` block làm 3 việc:

1. **Khai báo một "module instance"** với địa chỉ `module.X` trong namespace của caller. Đây là cái Terraform dùng làm tiền tố cho mọi resource bên trong: ví dụ `aws_vpc.this` định nghĩa trong `modules/network/main.tf` sẽ có resource address `module.stack.module.network.aws_vpc.this[0]` khi nhìn từ root `envs/development/`.
2. **Inline toàn bộ `.tf` file** ở thư mục `source` vào graph - không phải "import" theo nghĩa lập trình. Terraform parse tất cả `*.tf` trong thư mục đó như một sub-graph riêng, có local variables/locals/data/resource riêng.
3. **Map arguments** trong `module` block thành giá trị của `variable` blocks trong sub-module. Mỗi key sau `source =` phải khớp với một `variable` đã khai báo trong sub-module - nếu không khớp sẽ là lỗi `Unsupported argument`.

### 5.2. `source` attribute - các loại path

Trong repo này dùng **local path source** - chỉ là đường dẫn tương đối từ thư mục chứa `module` block:

- `envs/development/main.tf` có `source = "../_shared"` -> path tương đối = `envs/development/../_shared` = `envs/_shared/`.
- `envs/_shared/main.tf` có `source = "../../modules/network"` -> path tương đối = `envs/_shared/../../modules/network` = `modules/network/`.

Local path source là cơ chế đơn giản nhất - Terraform không download, không cache vào `.terraform/modules/` từ remote, chỉ đọc thẳng file ở đường dẫn đó. Đó là lý do tại sao chỉ cần `terraform init` ở root là toàn bộ chuỗi module được nối liền: Terraform follow các `source =` đệ quy cho tới khi không còn `module` block nào nữa.

(Còn các loại source khác: `registry` như `terraform-aws-modules/vpc/aws`, `git::https://...`, `s3::...`, etc. Repo này không dùng.)

### 5.3. Variable passing - "argument" thành "var"

Trong `envs/development/main.tf`:

```hcl
module "stack" {
  source = "../_shared"

  environment = var.environment
  region      = var.region
  vpc_cidr    = var.vpc_cidr
  ...
}
```

- Phía caller (`envs/development/`): `var.environment` là biến của root module, lấy giá trị từ `terraform.tfvars` (hoặc CLI `-var`, env `TF_VAR_*`).
- Phía callee (`envs/_shared/`): `environment = var.environment` ở dòng trên gán argument tên `environment` cho module instance `stack`. Bên trong `envs/_shared/variables.tf` phải tồn tại một `variable "environment"` - nếu không có sẽ lỗi.
- Bên trong `envs/_shared/main.tf`, biểu thức `var.environment` reference vào chính biến đó - **không liên quan** đến `var.environment` của root, dù tên trùng. Chúng nằm trong scope khác nhau.

Tương tự, `envs/_shared/main.tf` gọi xuống module `network`:

```hcl
module "network" {
  source                      = "../../modules/network"
  environment                 = var.environment           # var ở scope _shared
  vpc_cidr                    = var.vpc_cidr              # var ở scope _shared
  existing_vpc_id             = var.existing_vpc_id
  existing_private_subnet_ids = var.existing_private_subnet_ids
  existing_public_subnet_ids  = var.existing_public_subnet_ids
  tags                        = local.common_tags
}
```

Bên trong `modules/network/variables.tf` có `variable "environment"`, `variable "vpc_cidr"`, etc. - đó là các "input port" của module này. Module hoàn toàn không biết caller là ai, chỉ thấy `var.environment`, `var.vpc_cidr` trong scope của chính nó.

Như vậy giá trị `environment = "development"` ở `envs/development/terraform.tfvars` đi qua **3 lớp scope**:

```
terraform.tfvars                        -> envs/development/var.environment   (root scope)
envs/development/main.tf                -> module "stack" { environment = ... }
envs/_shared/var.environment            -> envs/_shared scope
envs/_shared/main.tf                    -> module "network" { environment = var.environment }
modules/network/var.environment         -> modules/network scope
modules/network/main.tf                 -> tag Name = "${var.environment}-vpc"
```

Mỗi bước chỉ là một "argument assignment" trong `module` block. Không có pointer, không có shared state - giá trị được copy theo từng lớp.

### 5.4. Output passing - cách module trả giá trị về caller

Hướng ngược lại: trong sub-module có `output` blocks. Caller truy cập bằng `module.<name>.<output>`.

- `modules/network/outputs.tf` khai báo `output "vpc_id"`.
- `envs/_shared/main.tf` đọc bằng `module.network.vpc_id` và đưa làm argument cho `module.alb`:

```hcl
module "alb" {
  source = "../../modules/alb"
  ...
  vpc_id = module.network.vpc_id
  ...
}
```

- Root module `envs/development/` có thể đọc tiếp `module.stack.<output>` nếu `envs/_shared/outputs.tf` tái-export. Repo này có một số `output` ở `envs/_shared/outputs.tf` (chẳng hạn `ecs_cluster_name`) để tiện debug.

Output không phải là "return value chạy sau". Terraform build toàn bộ graph trước, rồi tính giá trị output theo dependency order: `module.alb` không thể đánh giá `vpc_id = module.network.vpc_id` nếu `aws_vpc.this[0].id` của module `network` chưa biết -> Terraform tự động tạo edge `module.alb` depends on `module.network`. Đây là lý do bạn không bao giờ phải viết `depends_on` giữa các module trong repo này.

### 5.5. Provider passing - tại sao child module dùng được AWS provider của root

Một câu hỏi tinh tế: `modules/network/main.tf` viết `resource "aws_vpc" "this"` nhưng **không** có `provider` block ở đâu cả trong `modules/network/`. Tại sao biết dùng AWS provider region nào?

- Provider được khai báo **chỉ một lần** ở root module (`envs/development/providers.tf` - region từ `var.region`, plus alias `us_east_1`).
- Khi sub-module có `required_providers` trong `versions.tf` nhưng **không** có `provider` block, Terraform **tự động inherit** provider mặc định của parent. Đây là quy tắc "default provider inheritance".
- Vì vậy `module.stack.module.network.aws_vpc.this` chạy bằng AWS provider được cấu hình tại root - tức là region của development env.
- Nếu cần provider khác (ví dụ CloudFront ACM cert phải tạo ở `us-east-1` bất kể env region), caller phải truyền explicit qua `providers = { aws = aws.us_east_1 }` trong `module` block. Repo này có alias `us_east_1` sẵn ở `envs/development/providers.tf` để dùng cho mục đích đó.

### 5.6. Tổng kết cơ chế

Tổng hợp lại - tại sao `envs/development/` "gọi được" sang `envs/_shared/` và `envs/_shared/` "gọi được" sang `modules/network/`:

1. `module "stack" { source = "../_shared" }` trong `envs/development/main.tf` ra lệnh cho Terraform parse mọi `.tf` trong `envs/_shared/` và đưa vào graph dưới tiền tố `module.stack.*`.
2. Argument `environment = var.environment` (và 20+ argument khác) gán giá trị từ scope root vào `variable "environment"` của `envs/_shared/`.
3. Bên trong `envs/_shared/main.tf`, mỗi `module "X" { source = "../../modules/X" }` lặp lại đúng cơ chế đó với child module thật - parse `modules/X/*.tf`, đưa vào graph dưới tiền tố `module.stack.module.X.*`, map arguments thành biến của child.
4. Provider config từ root được kế thừa xuống tất cả các tầng nếu không override.
5. Output đi ngược: child `output` -> `module.X.<output>` trong scope của parent -> tiếp tục `module.stack.<output>` nếu được tái-export.

Đó là tất cả. Không có "import" runtime, không có loader, không có dependency injection - chỉ là Terraform parse tĩnh các file `.tf` theo `source` tree.

## 6. Ví dụ chi tiết: VPC resource được tạo như thế nào trong môi trường development

Phần này trace cụ thể một resource - `aws_vpc.this` của module `network` - từ giá trị `vpc_cidr = "10.10.0.0/16"` trong `terraform.tfvars` cho tới khi AWS API `CreateVpc` được gọi và state được ghi vào S3.

### 6.1. Khởi đầu: `terraform.tfvars`

File `envs/development/terraform.tfvars`:

```hcl
environment = "development"
region      = "us-east-1"
vpc_cidr    = "10.10.0.0/16"
# existing_vpc_id = null  (default)
tags = {
  Owner      = "platform-team@myorg.com"
  CostCenter = "CC-12345"
}
```

Đây là input dạng plain text. Khi chạy `terraform plan` hoặc `terraform apply` từ thư mục `envs/development/`, Terraform tự động đọc file này (vì nó tên là `terraform.tfvars`) và gán giá trị vào các `variable` của root module.

### 6.2. Lớp 1: Root module `envs/development/`

`envs/development/variables.tf` khai báo:

```hcl
variable "environment"     { type = string }
variable "region"          { type = string }
variable "vpc_cidr"        { type = string, default = "10.0.0.0/16" }
variable "existing_vpc_id" { type = string, default = null }
variable "tags"            { type = map(string), default = {} }
...
```

Sau khi đọc tfvars:

- `var.environment = "development"`
- `var.region = "us-east-1"`
- `var.vpc_cidr = "10.10.0.0/16"`
- `var.existing_vpc_id = null` (không có trong tfvars -> dùng default)
- `var.tags = { Owner = "...", CostCenter = "..." }`

`envs/development/providers.tf` cấu hình AWS provider:

```hcl
provider "aws" {
  region = var.region                # -> "us-east-1"
  default_tags {
    tags = {
      Environment = var.environment  # -> "development"
      Project     = "3-tiers-app"
      ManagedBy   = "terraform"
    }
  }
}
```

Provider này từ giờ là **default provider** của toàn bộ graph, trừ khi có alias.

`envs/development/main.tf` chỉ có một module call:

```hcl
module "stack" {
  source                      = "../_shared"
  environment                 = var.environment            # "development"
  region                      = var.region                 # "us-east-1"
  vpc_cidr                    = var.vpc_cidr               # "10.10.0.0/16"
  existing_vpc_id             = var.existing_vpc_id        # null
  existing_private_subnet_ids = var.existing_private_subnet_ids
  existing_public_subnet_ids  = var.existing_public_subnet_ids
  ...
  tags = var.tags                                          # { Owner=..., CostCenter=... }
}
```

Terraform thấy `source = "../_shared"`, đi tới thư mục `envs/_shared/`, parse mọi `.tf`.

### 6.3. Lớp 2: Shared stack `envs/_shared/`

`envs/_shared/variables.tf` khai báo:

```hcl
variable "environment"     { type = string }
variable "region"          { type = string }
variable "vpc_cidr"        { type = string, default = "10.0.0.0/16" }
variable "existing_vpc_id" { type = string, default = null }
variable "tags"            { type = map(string), default = {} }
...
```

Giá trị nhận vào (do `module "stack"` ở root đã map):

- `var.environment = "development"` (scope `_shared`)
- `var.vpc_cidr = "10.10.0.0/16"`
- `var.existing_vpc_id = null`
- `var.tags = { Owner = "...", CostCenter = "..." }`

`envs/_shared/main.tf` định nghĩa local `common_tags`:

```hcl
locals {
  common_tags = merge(var.tags, {
    Environment = var.environment   # "development"
    Project     = "3-tiers-app"
    ManagedBy   = "terraform"
  })
}
```

-> `local.common_tags = { Owner = "platform-team@myorg.com", CostCenter = "CC-12345", Environment = "development", Project = "3-tiers-app", ManagedBy = "terraform" }`.

Tiếp đó:

```hcl
module "network" {
  source                      = "../../modules/network"
  environment                 = var.environment                  # "development"
  vpc_cidr                    = var.vpc_cidr                     # "10.10.0.0/16"
  existing_vpc_id             = var.existing_vpc_id              # null
  existing_private_subnet_ids = var.existing_private_subnet_ids  # null
  existing_public_subnet_ids  = var.existing_public_subnet_ids   # null
  tags                        = local.common_tags                # merged map
}
```

Terraform follow `source = "../../modules/network"`, đi tới `modules/network/`.

### 6.4. Lớp 3: Child module `modules/network/`

`modules/network/variables.tf` khai báo input port:

```hcl
variable "environment"     { type = string }
variable "vpc_cidr"        { type = string, default = "10.0.0.0/16" }
variable "az_count"        { type = number, default = 3 }
variable "existing_vpc_id" { type = string, default = null }
variable "tags"            { type = map(string), default = {} }
...
```

Giá trị nhận:

- `var.environment = "development"` (scope `modules/network/`)
- `var.vpc_cidr = "10.10.0.0/16"`
- `var.az_count = 3` (caller không truyền -> dùng default)
- `var.existing_vpc_id = null`
- `var.tags = local.common_tags` từ tầng trên -> map gồm 5 key.

`modules/network/main.tf` định nghĩa local `create_vpc`:

```hcl
locals {
  create_vpc = var.existing_vpc_id == null   # -> true
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}
```

-> `local.create_vpc = true` (vì tfvars không set `existing_vpc_id`). Đây là switch giữa **create mode** và **BYO mode** của module.

### 6.5. Resource `aws_vpc.this` trong module `network`

```hcl
resource "aws_vpc" "this" {
  count                = local.create_vpc ? 1 : 0          # -> 1
  cidr_block           = var.vpc_cidr                       # -> "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(var.tags, { Name = "${var.environment}-vpc" })
}
```

Sau khi đánh giá:

- `count = 1` -> Terraform tạo đúng 1 instance, địa chỉ đầy đủ `module.stack.module.network.aws_vpc.this[0]`.
- `cidr_block = "10.10.0.0/16"`.
- `tags = merge(local.common_tags_passed_in, { Name = "development-vpc" })` = `{ Owner = "...", CostCenter = "...", Environment = "development", Project = "3-tiers-app", ManagedBy = "terraform", Name = "development-vpc" }`.

Provider lookup: `aws_vpc` thuộc provider `aws`. Module `modules/network/` không có `provider` block và `versions.tf` chỉ khai báo `required_providers`, nên Terraform dùng provider mặc định kế thừa từ root - tức provider `aws` ở `envs/development/providers.tf` với `region = "us-east-1"`.

### 6.6. Build graph và plan

Terraform parse toàn bộ chuỗi trên một lần duy nhất, build resource graph. Một số node liên quan đến VPC:

```
module.stack.module.network.data.aws_availability_zones.available
module.stack.module.network.aws_vpc.this[0]
module.stack.module.network.aws_subnet.public[0]
module.stack.module.network.aws_subnet.public[1]
module.stack.module.network.aws_subnet.public[2]
module.stack.module.network.aws_subnet.private[0..2]
module.stack.module.network.aws_internet_gateway.this[0]
module.stack.module.network.aws_eip.nat[0..2]
module.stack.module.network.aws_nat_gateway.this[0..2]
module.stack.module.network.aws_route_table.public[0]
module.stack.module.network.aws_route_table.private[0..2]
module.stack.module.network.aws_route_table_association.public[0..2]
module.stack.module.network.aws_route_table_association.private[0..2]
```

Edges chính trong graph:

- `aws_subnet.public[i]` depends on `aws_vpc.this[0]` (qua `vpc_id = aws_vpc.this[0].id`).
- `aws_subnet.public[i]` depends on `data.aws_availability_zones.available` (qua `local.azs`).
- `aws_internet_gateway.this[0]` depends on `aws_vpc.this[0]`.
- `aws_nat_gateway.this[i]` depends on `aws_eip.nat[i]` và `aws_subnet.public[i]`, plus explicit `depends_on = [aws_internet_gateway.this]`.
- `aws_route_table.public[0]` depends on `aws_internet_gateway.this[0]`.
- `aws_route_table.private[i]` depends on `aws_nat_gateway.this[i]`.

Khi chạy `terraform plan`, Terraform:

1. Refresh state hiện có từ S3 (key `3-tiers-app/development/terraform.tfstate`).
2. So sánh state với resource graph mới.
3. Lần đầu (state rỗng) -> tất cả node liệt kê ở trên đều là `+ create`.

Output plan cho VPC nhìn như:

```
# module.stack.module.network.aws_vpc.this[0] will be created
+ resource "aws_vpc" "this" {
    + cidr_block           = "10.10.0.0/16"
    + enable_dns_hostnames = true
    + enable_dns_support   = true
    + id                   = (known after apply)
    + tags                 = {
        + "CostCenter"  = "CC-12345"
        + "Environment" = "development"
        + "ManagedBy"   = "terraform"
        + "Name"        = "development-vpc"
        + "Owner"       = "platform-team@myorg.com"
        + "Project"     = "3-tiers-app"
      }
    + tags_all             = (same as above, từ default_tags + tags)
  }
```

### 6.7. Apply: AWS API thật sự được gọi

Khi `terraform apply` chạy (qua workflow `terraform-apply.yaml` của branch `development`):

1. Terraform giữ S3 lock (S3-native locking vì `use_lockfile = true` trong `backend.tf`).
2. Tạo các resource theo dependency order. VPC là root của subgraph nên tạo đầu tiên trong cụm network.
3. Đối với `aws_vpc.this[0]`, AWS provider gọi API `EC2.CreateVpc` với body đại loại:
   ```
   POST https://ec2.us-east-1.amazonaws.com/
   Action=CreateVpc
   CidrBlock=10.10.0.0/16
   InstanceTenancy=default
   TagSpecifications.1.ResourceType=vpc
   TagSpecifications.1.Tag.1.Key=Name
   TagSpecifications.1.Tag.1.Value=development-vpc
   TagSpecifications.1.Tag.2.Key=Environment
   TagSpecifications.1.Tag.2.Value=development
   ... (các tag còn lại)
   ```
4. AWS trả về `VpcId` (ví dụ `vpc-0abc123def456`). Provider gọi tiếp `ModifyVpcAttribute` để set `EnableDnsHostnames = true` và `EnableDnsSupport = true`.
5. Terraform ghi resource state mới vào file state in-memory: `module.stack.module.network.aws_vpc.this[0]` có `id = "vpc-0abc123def456"`, đầy đủ attributes.
6. Các resource phụ thuộc (subnet, IGW, NAT, route table, association) chạy tiếp theo, mỗi resource lại là một API call EC2 riêng.
7. Khi cụm network xong, các module khác (`alb`, `rds`, `ecs_service`, ...) bắt đầu chạy vì chúng depends on `module.network.vpc_id` thông qua output:

   ```hcl
   # envs/_shared/main.tf
   module "alb" {
     vpc_id            = module.network.vpc_id            # "vpc-0abc123def456"
     public_subnet_ids = module.network.public_subnet_ids # ["subnet-..."]
     ...
   }
   ```

8. Cuối cùng Terraform serialize toàn bộ state thành JSON và `PutObject` lên S3:
   - Bucket: `3-tiers-app-infrastructure-tfstate-<account-id>`
   - Key: `3-tiers-app/development/terraform.tfstate`
   - Encryption: KMS qua `alias/tfstate`
9. Release lock.

### 6.8. Output đi ngược lên trên

Sau apply, các giá trị output được "bubble" ngược:

- `modules/network/outputs.tf` -> `output "vpc_id" { value = aws_vpc.this[0].id }` -> giá trị `"vpc-0abc123def456"`.
- `envs/_shared/main.tf` truy cập `module.network.vpc_id` để truyền cho các module khác (`alb`, `rds`, `ecs_service`).
- `envs/_shared/outputs.tf` **không** re-export trực tiếp `vpc_id` ra root, nhưng có re-export `alb_dns_name`, `ecs_cluster_name`, etc.
- Root `envs/development/` không có `outputs.tf` riêng, nên người dùng chỉ thấy outputs do `envs/_shared/outputs.tf` re-export, nhìn dưới dạng `module.stack.<output>` khi chạy `terraform output`.

### 6.9. Tóm tắt đường đi giá trị `vpc_cidr = "10.10.0.0/16"`

```
envs/development/terraform.tfvars
   vpc_cidr = "10.10.0.0/16"
       |
       v
envs/development/variables.tf
   var.vpc_cidr  (string)
       |
       v
envs/development/main.tf
   module "stack" { vpc_cidr = var.vpc_cidr }
       |
       v
envs/_shared/variables.tf
   var.vpc_cidr  (string)
       |
       v
envs/_shared/main.tf
   module "network" { vpc_cidr = var.vpc_cidr }
       |
       v
modules/network/variables.tf
   var.vpc_cidr  (string)
       |
       v
modules/network/main.tf
   resource "aws_vpc" "this" { cidr_block = var.vpc_cidr }
       |
       v
AWS EC2 API: CreateVpc(CidrBlock="10.10.0.0/16")
       |
       v
Real VPC vpc-0abc123def456 trong AWS account development, region us-east-1
       |
       v
State ghi xuống s3://3-tiers-app-infrastructure-tfstate-<acct>/3-tiers-app/development/terraform.tfstate
```

Cùng một dòng `vpc_cidr = "10.10.0.0/16"` đi qua 3 module instance, 3 scope `var.vpc_cidr` khác nhau, rồi cuối cùng trở thành một field trong API request gửi tới EC2. Đó là toàn bộ "magic" của module composition trong Terraform.
