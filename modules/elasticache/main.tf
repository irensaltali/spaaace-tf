# ElastiCache Redis Module - Multi-AZ for Game State Persistence
# This module provides Redis for game state storage to survive node crashes

locals {
  common_tags = merge(var.tags, {
    Module = "elasticache"
  })
}

# Subnet group for Redis - uses private subnets across multiple AZs
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = local.common_tags
}

# Security Group for Redis
resource "aws_security_group" "redis" {
  name_prefix = "${var.name}-redis-"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.name}-redis-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Allow inbound Redis traffic from ECS instances
resource "aws_security_group_rule" "redis_from_ecs" {
  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = var.ecs_security_group_id
  security_group_id        = aws_security_group.redis.id
  description              = "Allow Redis traffic from ECS instances"
}

# Allow all outbound from Redis (for updates, etc.)
resource "aws_security_group_rule" "redis_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis.id
  description       = "Allow all outbound traffic"
}

# ElastiCache Parameter Group
resource "aws_elasticache_parameter_group" "this" {
  family = "redis7"
  name   = "${var.name}-redis-params"

  # Note: AWS ElastiCache manages AOF settings internally for Redis 7
  # The default configuration already provides good durability.
  # appendonly and appendfsync cannot be modified directly.

  # Enable keyspace notifications for game events (optional)
  parameter {
    name  = "notify-keyspace-events"
    value = var.enable_keyspace_notifications ? "Ex" : ""
  }

  tags = local.common_tags
}

# ElastiCache Replication Group (Redis with Multi-AZ)
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-redis"
  description          = "Redis cluster for ${var.name} game state persistence"

  # Engine configuration
  engine               = "redis"
  engine_version       = var.engine_version
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.this.name

  # Node configuration
  node_type = var.node_type

  # Cluster mode configuration
  num_cache_clusters = var.num_cache_clusters

  # Multi-AZ and failover
  multi_az_enabled           = var.multi_az_enabled
  automatic_failover_enabled = var.automatic_failover_enabled

  # Subnet and security
  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  # Encryption (recommended for production)
  at_rest_encryption_enabled  = var.at_rest_encryption_enabled
  transit_encryption_enabled  = var.transit_encryption_enabled
  auth_token                  = var.auth_token != "" ? var.auth_token : null

  # Backup configuration
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  maintenance_window       = var.maintenance_window

  # Performance improvements
  apply_immediately = var.apply_immediately

  tags = merge(local.common_tags, {
    Name = "${var.name}-redis"
  })
}

# CloudWatch Alarms for Redis
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.name}-redis-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis CPU utilization is high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.this.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.name}-redis-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory usage is high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.this.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_connections" {
  count = var.enable_alarms ? 1 : 0

  alarm_name          = "${var.name}-redis-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CurrConnections"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = var.max_connections_threshold
  alarm_description   = "Redis connection count is high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    CacheClusterId = aws_elasticache_replication_group.this.id
  }

  tags = local.common_tags
}
