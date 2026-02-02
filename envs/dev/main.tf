# Spaaace Game - Dev Environment
# High Availability Architecture: ECS + Redis (ElastiCache) Multi-AZ
# 
# This architecture ensures game state survives:
# - Node (Container) crashes: ECS auto-restarts, Redis hydrates state
# - EC2 failures: ASG replaces instances, Redis retains state
# - AZ outages: Multi-AZ failover, ALB routes to healthy AZs

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Terraform Cloud Configuration
  # Uncomment and configure after creating workspace:
  # cloud {
  #   organization = "your-org-name"
  #   workspaces {
  #     name = "spaaace-dev"
  #   }
  # }

  # Local backend for initial development
  # Replace with Terraform Cloud for production
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "spaaace"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Locals
locals {
  common_tags = {
    Project     = "spaaace"
    Environment = var.environment
  }
  prefix = "spaaace-${var.environment}"
}

#==============================================================================
# VPC - 3 AZs for High Availability
#==============================================================================
module "vpc" {
  source = "../../modules/vpc"

  name = local.prefix

  vpc_cidr        = var.vpc_cidr
  azs             = var.availability_zones
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets

  single_nat_gateway = true  # Cost-saving for dev (use false for prod)
  enable_flow_logs   = false # Disable for dev (cost)

  tags = local.common_tags
}

#==============================================================================
# ECR - Container Registry for Game Server
#==============================================================================
module "ecr" {
  source = "../../modules/ecr"

  name = "${local.prefix}-game"

  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
  keep_images_count    = 10

  tags = local.common_tags
}

#==============================================================================
# ALB - WebSocket-ready Application Load Balancer with Stickiness
#==============================================================================
module "alb" {
  source = "../../modules/alb"

  name              = "${local.prefix}-alb"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  enable_http  = true
  enable_https = false # Start with HTTP for dev, enable HTTPS with certificate later

  target_port          = 3000
  idle_timeout         = 120       # Important for WebSockets - long-lived connections
  health_check_path    = "/health" # Dedicated health endpoint for game server
  deregistration_delay = 30        # Quick deregistration for faster failover

  enable_stickiness   = true  # CRITICAL: WebSocket connections must stick to same instance
  stickiness_duration = 86400 # 24 hours

  enable_deletion_protection = false

  tags = local.common_tags
}

#==============================================================================
# ECS Cluster - EC2-backed with Capacity Provider for resilience
#==============================================================================
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name                  = local.prefix
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id

  instance_type    = var.ecs_instance_type
  min_size         = var.ecs_min_size
  max_size         = var.ecs_max_size
  desired_capacity = var.ecs_desired_capacity

  use_spot_instances = var.use_spot_instances
  spot_max_price     = var.spot_max_price

  enable_container_insights = true

  tags = local.common_tags
}

#==============================================================================
# ElastiCache (Redis) - Multi-AZ for Game State Persistence
# 
# CRITICAL: This is what allows game state to survive node crashes.
# When a node crashes, players disconnect briefly, then reconnect to
# a new node which hydrates game state from Redis.
#==============================================================================
module "redis" {
  source = "../../modules/elasticache"

  name = local.prefix

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.ecs_cluster.instance_security_group_id

  # Multi-AZ configuration for HA
  multi_az_enabled           = true
  automatic_failover_enabled = true
  num_cache_clusters         = 2 # Primary + Replica across different AZs

  # Node configuration (cache.t4g.micro is free tier eligible)
  node_type = "cache.t4g.micro"

  # Persistence for game state durability
  at_rest_encryption_enabled = false # Set to true for production
  transit_encryption_enabled = false # Set to true for production with auth_token

  # Backup configuration
  snapshot_retention_limit = 3 # Keep 3 days of backups for dev
  snapshot_window          = "03:00-04:00"

  # Alarms disabled for dev
  enable_alarms = false

  tags = local.common_tags
}

#==============================================================================
# ECS Service - Game Server with Redis Integration
#==============================================================================
module "ecs_service" {
  source = "../../modules/ecs-service"

  name                   = "${local.prefix}-game"
  cluster_id             = module.ecs_cluster.cluster_id
  cluster_name           = module.ecs_cluster.cluster_name
  capacity_provider_name = module.ecs_cluster.capacity_provider_name

  container_image = "${module.ecr.repository_url}:latest"
  container_port  = 3000

  cpu    = 256 # 0.25 vCPU
  memory = 512 # 512 MB

  desired_count = var.game_desired_count

  execution_role_arn = module.ecs_cluster.task_execution_role_arn

  # Environment variables for game server
  # REDIS_URL allows the game server to persist/restore game state
  environment_variables = {
    PORT                   = "3000"
    NODE_ENV               = "production"
    REDIS_URL              = module.redis.connection_string
    REDIS_ENABLED          = "true"
    GAME_HYDRATION_ENABLED = "true" # Enable state hydration on startup
  }

  aws_region = data.aws_region.current.name

  target_group_arn = module.alb.target_group_arn

  # Deployment settings
  enable_deployment_circuit_breaker = true
  enable_deployment_rollback        = true
  health_check_grace_period_seconds = 60

  # Container health check - must match ALB health check path
  health_check_enabled = true
  health_check_command = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]

  # Auto-scaling (disabled for dev, enable for production)
  enable_autoscaling = var.enable_autoscaling
  min_count          = var.game_min_count
  max_count          = var.game_max_count

  # Alarms (disabled for dev)
  enable_alarms = false

  tags = local.common_tags

  depends_on = [module.ecs_cluster, module.redis]
}

#==============================================================================
# S3 + CloudFront - Static Website
#==============================================================================
module "website" {
  source = "../../modules/s3-website"

  bucket_name = "${local.prefix}-website-${data.aws_caller_identity.current.account_id}"

  index_document = "index.html"
  error_document = "index.html" # SPA pattern - serve index.html for all routes

  cloudfront_comment = "${local.prefix} website"
  price_class        = "PriceClass_100" # North America and Europe only (cost-saving)

  # Custom domain (when ready)
  # aliases = ["www.${var.domain_name}"]
  # certificate_arn = module.route53.certificate_validation_arn

  # Route53 integration (when ready)
  # route53_zone_id = module.route53.zone_id

  tags = local.common_tags
}

#==============================================================================
# Route53 - DNS Management
#==============================================================================
# Uncomment when domain is ready:
# module "route53" {
#   source = "../../modules/route53"
#
#   domain_name = var.domain_name
#   create_hosted_zone = false  # Use existing zone
#
#   game_subdomain = "game"
#   www_subdomain  = "www"
#
#   game_alb_dns_name = module.alb.alb_dns_name
#   game_alb_zone_id  = module.alb.alb_zone_id
#
#   cloudfront_domain_name = module.website.cloudfront_domain_name
#
#   create_apex_record = true
#   create_health_check = false
#
#   tags = local.common_tags
# }
