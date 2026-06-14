# RDS Module - Supports both Aurora Serverless v2 and standard RDS instances
# Toggle with var.use_serverless (false = cost-optimized, true = serverless)

# ============================================================================
# SHARED RESOURCES (used by both Aurora and standard RDS)
# ============================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.stack_name}-${var.env}-db-password"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-db-password"
    },
    var.additional_tags
  )
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.stack_name}-${var.env}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-db-subnet-group"
    },
    var.additional_tags
  )
}

resource "aws_security_group" "main" {
  name        = "${var.stack_name}-${var.env}-db-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-db-sg"
    },
    var.additional_tags
  )
}

# ============================================================================
# AURORA SERVERLESS V2 RESOURCES (when use_serverless = true)
# ============================================================================

resource "aws_rds_cluster" "aurora" {
  count = var.use_serverless ? 1 : 0

  cluster_identifier     = "${var.stack_name}-${var.env}-aurora"
  engine                 = "aurora-postgresql"
  engine_mode            = "provisioned"
  engine_version         = "15.17"
  database_name          = var.database_name
  master_username        = var.master_username
  master_password        = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.main.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  backup_retention_period   = 7
  preferred_backup_window   = "03:00-04:00"
  skip_final_snapshot       = var.env == "dev" ? true : false
  final_snapshot_identifier = var.env == "dev" ? null : "${var.stack_name}-${var.env}-aurora-final-snapshot"

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-aurora"
      Mode = "Serverless v2"
    },
    var.additional_tags
  )
}

resource "aws_rds_cluster_instance" "aurora" {
  count = var.use_serverless ? 1 : 0

  identifier         = "${var.stack_name}-${var.env}-aurora-instance"
  cluster_identifier = aws_rds_cluster.aurora[0].id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora[0].engine
  engine_version     = aws_rds_cluster.aurora[0].engine_version

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-aurora-instance"
      Mode = "Serverless v2"
    },
    var.additional_tags
  )
}

# ============================================================================
# STANDARD RDS INSTANCE (when use_serverless = false) - Cost Optimized
# ============================================================================

resource "aws_db_instance" "standard" {
  count = var.use_serverless ? 0 : 1

  identifier             = "${var.stack_name}-${var.env}-rds"
  engine                 = "postgres"
  engine_version         = var.engine_version_standard
  instance_class         = var.instance_class
  allocated_storage      = 20
  max_allocated_storage  = 100  # Enable storage autoscaling up to 100 GB
  storage_type           = "gp3"
  storage_encrypted      = true

  db_name  = var.database_name
  username = var.master_username
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.main.id]
  publicly_accessible    = false

  backup_retention_period   = 7
  backup_window             = "03:00-04:00"
  maintenance_window        = "sun:04:00-sun:05:00"
  skip_final_snapshot       = var.env == "dev" ? true : false
  final_snapshot_identifier = var.env == "dev" ? null : "${var.stack_name}-${var.env}-rds-final-snapshot"

  # Performance Insights (free for t4g.micro)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Auto minor version upgrades
  auto_minor_version_upgrade = true

  tags = merge(
    {
      Name = "${var.stack_name}-${var.env}-rds"
      Mode = "Standard Instance"
    },
    var.additional_tags
  )
}
