resource "aws_iam_role" "role" {
  name               = "${var.stack_name}-${var.env}-${var.stack_tool}-role"
  description        = var.role_description
  assume_role_policy = var.assume_role_policy

  tags = merge({
    Name = "${var.stack_name}-${var.env}-${var.stack_tool}-role"
  }, var.additional_tags)
}

resource "aws_iam_role_policy" "inline_policies" {
  for_each = {
    for pol in var.inline_policies : pol.name => pol
  }

  name   = each.key
  role   = aws_iam_role.role.name
  policy = each.value.policy
}

resource "aws_iam_role_policy_attachment" "managed_policies" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.role.name
  policy_arn = each.value
}