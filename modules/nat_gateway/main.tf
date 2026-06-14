# NAT Gateway Module - Creates a single NAT gateway for private subnet internet access
# Cost optimization: 1 NAT Gateway instead of 3 (saves $66/mo)
# Production: Set var.nat_gateway_count = 3 for high availability

resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-nat-eip-${count.index + 1}"
    },
    var.additional_tags
  )
}

resource "aws_nat_gateway" "main" {
  count         = var.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = var.public_subnet_ids[count.index]

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-nat-gw-${count.index + 1}"
    },
    var.additional_tags
  )
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_ids)
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    # All private subnets route through the first (and possibly only) NAT Gateway
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-private-rt-${count.index + 1}"
    },
    var.additional_tags
  )
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_ids)
  subnet_id      = var.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}
