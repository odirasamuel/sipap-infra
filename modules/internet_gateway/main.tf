# Internet Gateway Module - Creates IGW and configures route tables
resource "aws_internet_gateway" "main" {
  vpc_id = var.vpc_id

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-igw"
    },
    var.additional_tags
  )
}

resource "aws_route_table" "public" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-public-rt"
    },
    var.additional_tags
  )
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_ids)
  subnet_id      = var.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}
