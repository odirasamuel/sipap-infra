# ElastiCache Module - Supports both Serverless and standard instances
# Toggle with var.use_serverless (false = cost-optimized, true = serverless)

# ============================================================================
# SHARED RESOURCES (used by both Serverless and standard)
# ============================================================================

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.cache_name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = var.additional_tags
}

# ============================================================================
# ELASTICACHE SERVERLESS (when use_serverless = true)
# ============================================================================

resource "aws_elasticache_serverless_cache" "this" {
  count = var.use_serverless ? 1 : 0

  engine               = var.engine
  name                 = var.cache_name
  description          = var.description
  major_engine_version = var.major_engine_version

  # Cache usage limits
  cache_usage_limits {
    data_storage {
      maximum = var.cache_usage_limits.data_storage.maximum
      unit    = var.cache_usage_limits.data_storage.unit
    }
    ecpu_per_second {
      maximum = var.cache_usage_limits.ecpu_per_second.maximum
    }
  }

  # Daily snapshot configuration
  daily_snapshot_time      = var.daily_snapshot_time
  snapshot_retention_limit = var.snapshot_retention_limit

  # KMS encryption
  kms_key_id = var.kms_key_id

  # Security groups
  security_group_ids = var.security_group_ids

  # Subnet group
  subnet_ids = var.subnet_ids

  # User group for IAM authentication
  user_group_id = var.user_group_id

  tags = merge(
    {
      Mode = "Serverless"
    },
    var.additional_tags
  )

  depends_on = [
    aws_elasticache_subnet_group.this
  ]
}

# ============================================================================
# STANDARD ELASTICACHE INSTANCE (when use_serverless = false) - Cost Optimized
# ============================================================================

resource "aws_elasticache_cluster" "this" {
  count = var.use_serverless ? 0 : 1

  cluster_id           = var.cache_name
  engine               = var.engine == "valkey" ? "redis" : var.engine  # Valkey uses Redis engine for instances
  engine_version       = var.engine == "redis" || var.engine == "valkey" ? "7.1" : "1.6.17"  # Redis 7.1 or Memcached 1.6
  node_type            = var.node_type
  num_cache_nodes      = var.num_cache_nodes
  parameter_group_name = var.parameter_group_name
  port                 = var.engine == "redis" || var.engine == "valkey" ? 6379 : 11211

  # Networking
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = var.security_group_ids

  # Backups (Redis only)
  snapshot_retention_limit = var.engine == "redis" || var.engine == "valkey" ? var.snapshot_retention_limit : 0
  snapshot_window          = var.engine == "redis" || var.engine == "valkey" ? "${var.daily_snapshot_time}-04:00" : null

  # Maintenance
  maintenance_window       = "sun:05:00-sun:06:00"
  auto_minor_version_upgrade = true

  tags = merge(
    {
      Mode = "Standard Instance"
    },
    var.additional_tags
  )

  depends_on = [
    aws_elasticache_subnet_group.this
  ]
}
