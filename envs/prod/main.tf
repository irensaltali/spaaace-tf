# Spaaace Game - Production Environment
# Region: eu-north-1 (Stockholm)
# Domain: spaaace.online
#
# High Availability Architecture: ECS + Redis (ElastiCache) Multi-AZ

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Terraform Cloud Configuration (recommended for production)
  # cloud {
  #   organization = "your-org-name"
  #   workspaces {
  #     name = "spaaace-prod"
  #   }
  # }

  # Local backend for now - migrate to remote for production
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

  single_nat_gateway = false # Use multiple NAT gateways for production
  enable_flow_logs   = true  # Enable for production

  tags = local.common_tags
}

#==============================================================================
# ECR - Container Registry for Game Server (Created by bootstrap)
#==============================================================================
# ECR is created separately in envs/bootstrap to allow:
# 1. ECR creation first
# 2. Docker image push via GitHub Actions
# 3. Then this environment's resources
data "aws_ecr_repository" "game" {
  name = "${local.prefix}-game"
}

locals {
  ecr_repository_url = data.aws_ecr_repository.game.repository_url
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
  enable_https = false # Enable after ACM certificate is ready

  target_port          = 3000
  idle_timeout         = 120
  health_check_path    = "/health"
  deregistration_delay = 30

  enable_stickiness   = true
  stickiness_duration = 86400

  enable_deletion_protection = true # Enable for production

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
#==============================================================================
module "redis" {
  source = "../../modules/elasticache"

  name = local.prefix

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.ecs_cluster.instance_security_group_id

  multi_az_enabled           = true
  automatic_failover_enabled = true
  num_cache_clusters         = 3 # 1 Primary + 2 Replicas for production

  node_type = "cache.t4g.medium" # Larger instance for production

  at_rest_encryption_enabled = true  # Enable for production
  transit_encryption_enabled = false # Enable with auth token if needed

  snapshot_retention_limit = 14 # 2 weeks of backups
  snapshot_window          = "03:00-04:00"

  enable_alarms = false # Set to true with SNS topic for production

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

  container_image = "${local.ecr_repository_url}:latest"
  container_port  = 3000

  cpu    = 512  # More CPU for production
  memory = 1024 # More memory for production

  desired_count = var.game_desired_count

  execution_role_arn = module.ecs_cluster.task_execution_role_arn

  environment_variables = {
    PORT                   = "3000"
    NODE_ENV               = "production"
    REDIS_URL              = module.redis.connection_string
    REDIS_ENABLED          = "true"
    GAME_HYDRATION_ENABLED = "true"
    ENVIRONMENT            = "production"
  }

  aws_region = data.aws_region.current.name

  target_group_arn = module.alb.target_group_arn

  enable_deployment_circuit_breaker = true
  enable_deployment_rollback        = true
  health_check_grace_period_seconds = 120 # Longer for production

  health_check_enabled = true
  health_check_command = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]

  enable_autoscaling = var.enable_autoscaling
  min_count          = var.game_min_count
  max_count          = var.game_max_count

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
  error_document = "index.html"

  cloudfront_comment = "${local.prefix} website"
  price_class        = "PriceClass_All" # Global for production

  tags = local.common_tags
}
