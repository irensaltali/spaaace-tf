# Spaaace Game - Staging Environment
# Region: eu-west-1
# Domain: staging.spaaace.online
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

  # Terraform Cloud Configuration (recommended for staging)
  # cloud {
  #   organization = "your-org-name"
  #   workspaces {
  #     name = "spaaace-staging"
  #   }
  # }

  # Local backend for now
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

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
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

  single_nat_gateway = true # Cost-saving for staging
  enable_flow_logs   = false

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
  keep_images_count    = 20

  tags = local.common_tags
}

locals {
  ecr_repository_url = module.ecr.repository_url
}

#==============================================================================
# Use Existing ACM Certificate for HTTPS
#==============================================================================

# Find existing wildcard certificate in eu-west-1 (for ALB)
# Only look up certificate if HTTPS is enabled and no ARN is provided
data "aws_acm_certificate" "alb" {
  count       = var.enable_https && var.alb_certificate_arn == "" ? 1 : 0
  domain      = "*.spaaace.online"
  most_recent = true
  statuses    = ["ISSUED"]
}

# Create the Route53 hosted zone for staging
data "aws_route53_zone" "parent" {
  count = var.create_hosted_zone ? 0 : 1

  # Look up the existing hosted zone (parent zone for subdomain)
  # For staging.spaaace.online, look up spaaace.online
  name         = "spaaace.online"
  private_zone = false
}

resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0

  name = var.domain_name

  tags = local.common_tags
}

locals {
  route53_zone_id = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.parent[0].zone_id
  # Use provided certificate ARN, or look it up, or null if HTTPS is disabled
  certificate_arn = var.enable_https ? (var.alb_certificate_arn != "" ? var.alb_certificate_arn : try(data.aws_acm_certificate.alb[0].arn, null)) : null
}

#==============================================================================
# ALB - WebSocket-ready Application Load Balancer with Stickiness
#==============================================================================
module "alb" {
  source = "../../modules/alb"

  name              = "${local.prefix}-alb"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids

  enable_http     = true
  enable_https    = var.enable_https
  certificate_arn = local.certificate_arn

  target_port          = 3000
  idle_timeout         = 120
  health_check_path    = "/health"
  deregistration_delay = 30

  enable_stickiness   = true
  stickiness_duration = 86400

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
#==============================================================================
module "redis" {
  source = "../../modules/elasticache"

  name = local.prefix

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.ecs_cluster.instance_security_group_id

  multi_az_enabled           = true
  automatic_failover_enabled = true
  num_cache_clusters         = 2

  node_type = "cache.t4g.small"

  at_rest_encryption_enabled = false
  transit_encryption_enabled = false

  snapshot_retention_limit = 7
  snapshot_window          = "03:00-04:00"

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

  container_image = "${local.ecr_repository_url}:staging"
  container_port  = 3000

  cpu    = 256
  memory = 512

  desired_count = var.game_desired_count

  execution_role_arn = module.ecs_cluster.task_execution_role_arn

  environment_variables = {
    PORT                   = "3000"
    NODE_ENV               = "production"
    REDIS_URL              = module.redis.connection_string
    REDIS_ENABLED          = "true"
    GAME_HYDRATION_ENABLED = "true"
    ENVIRONMENT            = "staging"
  }

  aws_region = data.aws_region.current.name

  target_group_arn = module.alb.target_group_arn

  enable_deployment_circuit_breaker = true
  enable_deployment_rollback        = true
  health_check_grace_period_seconds = 60

  health_check_enabled = true
  health_check_command = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]

  enable_autoscaling = var.enable_autoscaling
  min_count          = var.game_min_count
  max_count          = var.game_max_count

  enable_alarms = false

  tags = local.common_tags

  depends_on = [module.ecs_cluster, module.redis]
}

# Note: CloudFront requires ACM certificate from us-east-1
# Using existing wildcard certificate: *.spaaace.online

# Use existing wildcard certificate from us-east-1 (only if custom domain is enabled)
data "aws_acm_certificate" "cloudfront" {
  provider    = aws.us_east_1
  count       = var.enable_cloudfront_custom_domain && var.cloudfront_certificate_arn == "" ? 1 : 0
  domain      = "*.spaaace.online"
  most_recent = true
  statuses    = ["ISSUED"]
}

locals {
  cloudfront_certificate_arn = var.enable_cloudfront_custom_domain ? (var.cloudfront_certificate_arn != "" ? var.cloudfront_certificate_arn : try(data.aws_acm_certificate.cloudfront[0].arn, null)) : null
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
  price_class        = "PriceClass_100"

  # Custom domain configuration (only if enabled)
  aliases         = var.enable_cloudfront_custom_domain ? [var.domain_name] : []
  certificate_arn = local.cloudfront_certificate_arn

  # Route53 integration for DNS
  route53_zone_id = var.enable_cloudfront_custom_domain ? local.route53_zone_id : null

  tags = local.common_tags
}

#==============================================================================
# Route53 - DNS Records
#==============================================================================

# Game server record (ALB) - game.staging.spaaace.online
resource "aws_route53_record" "game" {
  zone_id = local.route53_zone_id
  name    = "game.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# Website A record (CloudFront) - staging.spaaace.online
# NOTE: The s3-website module creates A and AAAA records via route53_zone_id

# WWW redirect record - www.staging.spaaace.online -> staging.spaaace.online
resource "aws_route53_record" "www" {
  zone_id = local.route53_zone_id
  name    = "www.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_name]
}
