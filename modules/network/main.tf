locals {
  create_vpc = var.existing_vpc_id == null
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

data "aws_availability_zones" "available" {
  state = "available"
}

# --- Create mode: VPC + subnets + NAT ---
resource "aws_vpc" "this" {
  count                = local.create_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(var.tags, { Name = "${var.environment}-vpc" })
}

resource "aws_subnet" "public" {
  count                   = local.create_vpc ? var.az_count : 0
  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(var.tags, { Name = "${var.environment}-public-${local.azs[count.index]}" })
}

resource "aws_subnet" "private" {
  count             = local.create_vpc ? var.az_count : 0
  vpc_id            = aws_vpc.this[0].id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + var.az_count)
  availability_zone = local.azs[count.index]
  tags              = merge(var.tags, { Name = "${var.environment}-private-${local.azs[count.index]}" })
}

resource "aws_internet_gateway" "this" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  tags   = merge(var.tags, { Name = "${var.environment}-igw" })
}

resource "aws_eip" "nat" {
  count  = local.create_vpc ? var.az_count : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.environment}-nat-eip-${count.index}" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_nat_gateway" "this" {
  count         = local.create_vpc ? var.az_count : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.tags, { Name = "${var.environment}-nat-${local.azs[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.this[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }
  tags = merge(var.tags, { Name = "${var.environment}-rt-public" })
}

resource "aws_route_table" "private" {
  count  = local.create_vpc ? var.az_count : 0
  vpc_id = aws_vpc.this[0].id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }
  tags = merge(var.tags, { Name = "${var.environment}-rt-private-${local.azs[count.index]}" })
}

resource "aws_route_table_association" "public" {
  count          = local.create_vpc ? var.az_count : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "private" {
  count          = local.create_vpc ? var.az_count : 0
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --- BYO mode: lookup existing VPC ---
data "aws_vpc" "existing" {
  count = local.create_vpc ? 0 : 1
  id    = var.existing_vpc_id
}
