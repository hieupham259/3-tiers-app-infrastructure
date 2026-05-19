# Greenfield apply va luong cross-module reference RDS <-> ECS

Tai lieu noi bo phan tich chi tiet cau hoi:

**"Neu chua tao bat ky resource nao tren AWS truoc do, lieu mot lan `terraform apply` co the tao ca `module.rds` lan `module.ecs_service` cung mot luc khong, khi dong code `ingress_security_group_ids = [module.ecs_service.security_group_id]` o `envs/_shared/main.tf:58` duoc set ngay tu dau?"**

## 1. Cau tra loi ngan

Co. `terraform apply` lan dau tren AWS account hoan toan trong se thanh cong, du `module "rds".ingress_security_group_ids = [module.ecs_service.security_group_id]` duoc set ngay tu dau. Day chinh la kieu apply ma code nay duoc thiet ke de chay.

Phased deploy cua Sprint S01-S04 trong project nay khong ton tai vi co cycle - no ton tai vi ly do van hanh: verify tung tang truoc khi dap tang tiep theo, giam blast radius khi loi config, dap IAM/networking tung lop de xac nhan.

## 2. Resource "cau noi" giua hai module

Tai nguyen dong vai tro cau noi giua `rds` va `ecs_service`:

### `aws_security_group.task` (so huu boi module ecs-service)

Dinh nghia tai `modules/ecs-service/main.tf:6-11`:

```hcl
resource "aws_security_group" "task" {
  name        = "${local.family}-sg"
  description = "ECS task ENI security group - ingress only from ALB"
  vpc_id      = var.vpc_id     # CHI phu thuoc vpc_id, KHONG phu thuoc RDS
  tags        = merge(var.tags, { Name = "${local.family}-sg" })
}
```

**ID cua resource nay duoc tieu thu o hai noi**:

| Noi tieu thu | Reference path | Muc dich |
|---|---|---|
| `modules/ecs-service/main.tf:101` | `aws_security_group.task.id` (internal) | Gan SG cho ECS task ENI trong `network_configuration` cua `aws_ecs_service` |
| `modules/rds/main.tf:20` | `var.ingress_security_group_ids[count.index]` - duoc truyen tu root qua `module.ecs_service.security_group_id` | Lam `source_security_group_id` cho ingress rule cua RDS SG (cho phep Postgres 5432 tu ECS task) |

Output expose ID nay: `modules/ecs-service/outputs.tf:16-19`:
```hcl
output "security_group_id" {
  description = "Task ENI security group ID (RDS must allow ingress from this SG)"
  value       = aws_security_group.task.id
}
```

**Diem chia khoa**: Resource nay chi phu thuoc `var.vpc_id` - khong phu thuoc bat ky thuoc tinh nao cua RDS. Day la ly do no co the duoc tao SOM trong DAG, truoc cac resource cua ca hai module rds va ecs_service ma can ID cua no.

## 3. Trace luong code file-to-file (cuc ky chi tiet)

Khi Terraform gap dong code `ingress_security_group_ids = [module.ecs_service.security_group_id]` o `envs/_shared/main.tf:58`, no follow chain qua 6 buoc, di qua 5 file de xay dung edge trong DAG. Hieu duoc trace nay la chia khoa de "doc" duoc bat ky cross-module reference nao trong Terraform.

### Buoc 1: User chay `terraform apply` o `envs/development/`

**File**: `envs/development/main.tf:1-31`
```hcl
module "stack" {
  source = "../_shared"

  environment                 = var.environment
  region                      = var.region
  vpc_cidr                    = var.vpc_cidr
  # ... pass-through cac variable khac
}
```

Terraform load source tu `envs/_shared/`. Day la lop bao boc shared giua development va production (chi khac nhau terraform.tfvars, backend.tf, providers.tf).

### Buoc 2: Trong `envs/_shared/main.tf`, module rds duoc khai bao voi gia tri cross-reference

**File**: `envs/_shared/main.tf:44-61`
```hcl
module "rds" {
  source            = "../../modules/rds"
  environment       = var.environment
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.private_subnet_ids
  instance_class    = var.rds_instance_class
  multi_az          = var.rds_multi_az
  allocated_storage = var.rds_storage_gb
  master_password   = var.rds_master_password

  backup_retention_days = var.rds_backup_retention_days
  deletion_protection   = var.rds_deletion_protection
  skip_final_snapshot   = var.environment != "production"

  ingress_security_group_ids = [module.ecs_service.security_group_id]   # <-- DONG 58
  #                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  #                             tham chieu output cua module ecs_service

  tags = local.common_tags
}
```

Lan dau parse, Terraform chua biet `module.ecs_service.security_group_id` la gi. No chi note:
```
edge can ket: module.rds.<resource X> -> module.ecs_service.<resource Y>
(chua biet X va Y la gi)
```
va tiep tuc parse phan con lai cua file.

### Buoc 3: Terraform doc khai bao module ecs_service

**File**: `envs/_shared/main.tf:71-93`
```hcl
module "ecs_service" {
  source                = "../../modules/ecs-service"
  environment           = var.environment
  cluster_name          = module.ecs_cluster.cluster_name
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.public_subnet_ids
  assign_public_ip      = true
  alb_target_group_arn  = module.alb.target_group_arn
  alb_security_group_id = module.alb.security_group_id
  ecr_repository_url    = module.ecr_backend.repository_url

  rds_endpoint   = module.rds.endpoint
  rds_secret_arn = module.rds.secret_arn

  task_cpu      = var.ecs_task_cpu
  task_memory   = var.ecs_task_memory
  desired_count = var.ecs_desired_count

  existing_task_exec_role_arn = module.iam_app_roles.task_exec_role_arn
  existing_task_role_arn      = module.iam_app_roles.task_role_arn

  tags = local.common_tags
}
```

Module ecs_service duoc load tu `modules/ecs-service/`. Luc nay Terraform da co the biet trong module ecs-service co nhung output gi.

### Buoc 4: Terraform doc khai bao output `security_group_id` cua module ecs-service

**File**: `modules/ecs-service/outputs.tf:16-19`
```hcl
output "security_group_id" {
  description = "Task ENI security group ID (RDS must allow ingress from this SG)"
  value       = aws_security_group.task.id
}
```

Bay gio Terraform biet: `module.ecs_service.security_group_id` chinh la `aws_security_group.task.id` cua module ecs-service. Edge cu the trong DAG bay gio la:

```
module.rds.<resource dung bien ingress_security_group_ids>
        -> module.ecs_service.aws_security_group.task
```

(Terraform chua biet "resource nao dung bien" - se khám phá o buoc 6.)

### Buoc 5: Terraform load source resource `aws_security_group.task`

**File**: `modules/ecs-service/main.tf:6-11`
```hcl
resource "aws_security_group" "task" {
  name        = "${local.family}-sg"
  description = "ECS task ENI security group - ingress only from ALB"
  vpc_id      = var.vpc_id     # CHI phu thuoc vpc_id, KHONG phu thuoc RDS
  tags        = merge(var.tags, { Name = "${local.family}-sg" })
}
```

**Quan trong**: resource nay khong inline ingress/egress rule. No la "SG rong" - tao xong la co ID ngay, khong can resource khac. Cac rule (ingress_from_alb, egress_all) duoc tach ra `aws_security_group_rule` rieng:

```hcl
# modules/ecs-service/main.tf:13-29
resource "aws_security_group_rule" "ingress_from_alb" {
  type                     = "ingress"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = var.alb_security_group_id
  security_group_id        = aws_security_group.task.id
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.task.id
}
```

Cac rule nay tao SAU SG, dung sau khi SG da co ID.

### Buoc 6: Terraform truyen gia tri vao bien cua module rds

**File**: `modules/rds/variables.tf:16-20`
```hcl
variable "ingress_security_group_ids" {
  type        = list(string)
  default     = []
  description = "Security groups allowed to ingress on 5432 (e.g. ECS task SG)"
}
```

Gia tri `[module.ecs_service.security_group_id]` duoc binding vao `var.ingress_security_group_ids` (mot list[string]) o thoi diem evaluation.

### Buoc 7: Bien duoc tieu thu trong resource `aws_security_group_rule.ingress_from_ecs`

**File**: `modules/rds/main.tf:14-22`
```hcl
resource "aws_security_group_rule" "ingress_from_ecs" {
  count                    = length(var.ingress_security_group_ids)
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.ingress_security_group_ids[count.index]
  #                          ^^^ chinh la ECS task SG ID
  security_group_id        = aws_security_group.this.id
  #                          ^^^ rds SG (cung trong module nay)
}
```

Den day Terraform da khám phá xong edge cu the:
```
module.rds.aws_security_group_rule.ingress_from_ecs
        -> module.ecs_service.aws_security_group.task   (qua source_security_group_id)
        -> module.rds.aws_security_group.this           (qua security_group_id, cung module)
```

## 4. Tom tat chain file dang diagram

```
envs/development/main.tf:1
        | module "stack" { source = "../_shared" }
        v
envs/_shared/main.tf:58
        | module "rds" {
        |   ingress_security_group_ids = [module.ecs_service.security_group_id]
        | }
        v
envs/_shared/main.tf:71
        | module "ecs_service" { source = "../../modules/ecs-service" }
        v
modules/ecs-service/outputs.tf:16
        | output "security_group_id" {
        |   value = aws_security_group.task.id
        | }
        v
modules/ecs-service/main.tf:6
        | resource "aws_security_group" "task" {
        |   vpc_id = var.vpc_id         <-- KHONG phu thuoc RDS
        | }
        |
        | [Terraform tao resource nay -> AWS tra ve ID -> output co value]
        |
        v (gia tri list[string] duoc inject vao module rds)
modules/rds/variables.tf:16
        | variable "ingress_security_group_ids" {
        |   type = list(string)
        | }
        v
modules/rds/main.tf:14
        | resource "aws_security_group_rule" "ingress_from_ecs" {
        |   count                    = length(var.ingress_security_group_ids)
        |   source_security_group_id = var.ingress_security_group_ids[count.index]
        |   security_group_id        = aws_security_group.this.id
        | }
```

## 5. DAG cuoi cung Terraform xay duoc

```
                  +-----------------------------+
                  | module.network.aws_vpc.this |
                  +--------------+--------------+
                                 |
                                 | vpc_id
                                 v
                  +-----------------------------+
                  | module.ecs_service.         |
                  | aws_security_group.task     |
                  | (chi can vpc_id, KHONG can  |
                  |  bat ky thu gi tu RDS)      |
                  +--------------+--------------+
                                 |
                                 | .id qua output security_group_id
                                 |
                  +--------------v--------------+
                  | module.rds.                 |
                  | aws_security_group_rule.    |
                  | ingress_from_ecs            |
                  |                             |
                  | source_security_group_id =  |
                  |   var.ingress_security_     |
                  |   group_ids[count.index]    |
                  | security_group_id =         |
                  |   aws_security_group.this.id|
                  +--------------+--------------+
                                 |
                                 | (rule da gan vao rds SG)
                                 v
                  +-----------------------------+
                  | module.rds.aws_db_instance  |
                  | .this                       |
                  | (can rds SG da co rule)     |
                  +-----------------------------+
```

## 6. Vi sao khong vong - phan tich edge

Co the nghi: "module.rds can ECS task SG ID, module.ecs_service can rds endpoint -> cycle". **Sai**. Terraform khong xay DAG o muc module - DAG la o muc resource. Hai chieu cross-module thuc ra noi cac cap resource khac nhau:

```
Chieu 1 (rds can gi tu ecs_service):
  module.rds.aws_security_group_rule.ingress_from_ecs
      <-- can ID cua --
  module.ecs_service.aws_security_group.task

Chieu 2 (ecs_service can gi tu rds):
  module.ecs_service.aws_ecs_task_definition.this
      <-- can endpoint + secret_arn cua --
  module.rds.aws_db_instance.this
  module.rds.aws_secretsmanager_secret.db
```

Tu Chieu 1 di nguoc lai khong cham `aws_db_instance.this` hay `aws_secretsmanager_secret.db`.
Tu Chieu 2 di nguoc lai khong cham `aws_security_group.task`.

Hai chieu noi cac cap **disjoint** -> DAG van acyclic.

## 7. Wave-by-wave order khi greenfield apply

Khi `terraform apply` chay tren AWS account trong (parallelism mac dinh = 10):

```
Wave 1  (song song, ~few seconds):
        aws_vpc.this              (module.network)
        aws_subnet.*              (module.network)
        aws_internet_gateway.this (module.network)
        aws_route_table.*         (module.network)

Wave 2  (song song, ~5-10 seconds):  <-- DAY LA NOI "CAU NOI" DUOC TAO
        aws_security_group.alb        (module.alb)
        aws_security_group.this       (module.rds)         <- SG rong, deps: vpc_id
        aws_security_group.task       (module.ecs_service) <- SG rong, deps: vpc_id  ★ CAU NOI
        aws_db_subnet_group.this      (module.rds)
        aws_secretsmanager_secret.db  (module.rds)
        aws_cloudwatch_log_group.this (module.ecs_service)
        aws_lb.this                   (module.alb)
        aws_lb_target_group.this      (module.alb)
        aws_iam_role.*                (module.iam_app_roles)

Wave 3  (song song, ~few seconds):  <-- RULE DUOC TAO SAU SG
        aws_security_group_rule.ingress_from_ecs (module.rds)
            <- can ECS task SG ID (Wave 2)
        aws_security_group_rule.ingress_from_alb (module.ecs_service)
            <- can ALB SG ID (Wave 2)
        aws_security_group_rule.egress_all (module.ecs_service)
        aws_lb_listener.this (module.alb)
        aws_iam_role_policy_attachment.* (module.iam_app_roles)

Wave 4  (cham nhat, 5-15 phut):
        aws_db_instance.this          (module.rds)         <- 5-8 phut tao Postgres
        aws_s3_bucket.frontend        (module.frontend_cdn)
        aws_cloudfront_distribution   (module.frontend_cdn) <- 10-15 phut

Wave 5  (~few seconds):
        aws_ecs_task_definition.this  (module.ecs_service)
            <- can rds endpoint + secret_arn (Wave 4)

Wave 6  (~30s - 2 phut):
        aws_ecs_service.this          (module.ecs_service)
        aws_cloudwatch_metric_alarm.* (module.observability)
        aws_ssm_parameter.*           (envs/_shared/outputs.tf)
```

**Quan sat quan trong**:
- `module.ecs_service` bat dau o Wave 2 (cung Wave voi `module.rds`), nhung chi "xong han" o Wave 6.
- `module.rds` cung trai dai tu Wave 2 den Wave 4.
- Khong module nao chay nguyen khoi - moi resource di theo nhip cua DAG.
- "Cau noi" `aws_security_group.task` o Wave 2, ngay tu som, vi the rule cua module rds (Wave 3) co the dap len.

## 8. Cach viet SAI - se gay cycle

De thay ro vi sao pattern hien tai an toan, day la cach viet SAI gia su nguoi viet code khong tach rule ra:

```hcl
# SAI - dat inline ingress vao SG resource
# modules/ecs-service/main.tf
resource "aws_security_group" "task" {
  vpc_id = var.vpc_id

  egress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.rds_security_group_id]   # can RDS SG ID
  }
}

# modules/rds/main.tf
resource "aws_security_group" "this" {
  vpc_id = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_task_security_group_id]   # can ECS task SG ID
  }
}
```

Edge bay gio tro thanh:
```
module.ecs_service.aws_security_group.task <----+
        |                                       |
        v                                       |
module.rds.aws_security_group.this -------------+
```

`terraform validate` se bao:
```
Error: Cycle: module.ecs_service.aws_security_group.task,
              module.rds.aws_security_group.this
```

**Pattern dung**: tach rule ra khoi SG (chinh la cach `modules/ecs-service/main.tf` va `modules/rds/main.tf` hien tai dang lam).

## 9. Loi khuyen rut ra

1. **Trace cross-module reference qua chain**: `module.<name>.<output>` -> `outputs.tf` cua module do -> resource cu the trong `main.tf`. Day la cach duy nhat de biet edge thuc cua DAG.

2. **DAG la o muc resource, khong phai muc module**. Cycle khong xay ra giua cac module, ma xay ra giua cap resource cu the. Doc edge o muc resource khi nghi ngo.

3. **Khi viet module, luon de cac SG/route table o dang "rong"** (chi vpc_id) va tach rule ra `aws_security_group_rule`/`aws_route` rieng. Cho phep module duoc tao song song voi module khac trong cung wave dau tien.

4. **`terraform graph` la cong cu xac thuc cuoi cung**. `terraform validate` xong, neu khong cycle thi an toan apply mot lan.

## 10. Tom tat 1 dong

`ingress_security_group_ids = [module.ecs_service.security_group_id]` an toan o lan apply dau tien tren greenfield vi: (a) DAG cua Terraform la resource-level, khong module-level; (b) `aws_security_group.task` chi can `vpc_id`, khong can RDS; (c) rule cua RDS (`aws_security_group_rule.ingress_from_ecs`) duoc tach ra khoi SG cha, nen no chi can ID cua RDS SG va ECS task SG (ca hai da co o Wave 2), tao o Wave 3, khong gay vong.

## Lich su tai lieu

- 2026-05-19: tao file. Phan tich greenfield apply + trace luong code file-to-file cho cross-module reference `ingress_security_group_ids = [module.ecs_service.security_group_id]` o `envs/_shared/main.tf:58`. Tach ra khoi file `terraform-dependency-reading-guide.md` de focus rieng vao topic nay.
