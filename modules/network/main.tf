# Network module: VPC, public/private subnets across N AZs, IGW, NAT, routing
# Game servers / ALB live in public subnets the app + data tier live private

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.env}-skybound-vpc" }
}

# --- Public subnets: ALB / anything that must reach the internet directly -----
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.env}-public-${count.index}", Tier = "public" }
}

# --- Private subnets: ECS tasks, DynamoDB access, matchmaking, no public IPs --
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]
  tags              = { Name = "${var.env}-private-${count.index}", Tier = "private" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.env}-skybound-igw" }
}

# --- NAT: one in dev to save cost, one-per-AZ in prod (var.nat_gateway_count) --
resource "aws_eip" "nat" {
  count      = var.nat_gateway_count
  domain     = "vpc"
  tags       = { Name = "${var.env}-nat-eip-${count.index}" }
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = var.nat_gateway_count
  subnet_id     = aws_subnet.public[count.index].id
  allocation_id = aws_eip.nat[count.index].id
  tags          = { Name = "${var.env}-nat-${count.index}" }
  depends_on    = [aws_internet_gateway.this]
}

# --- Public routing: one shared table -> IGW --------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.env}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Private routing: one table per private subnet -> a NAT gateway ----------
# With nat_gateway_count = 1, every private subnet shares the single NAT
# With nat_gateway_count >= AZ count, each subnet uses the NAT in its own AZ
resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[min(count.index, var.nat_gateway_count - 1)].id
  }
  tags = { Name = "${var.env}-private-rt-${count.index}" }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
