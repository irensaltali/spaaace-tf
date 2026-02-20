#==============================================================================
# General Variables
#==============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "staging"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS profile to use for authentication (null to use default credentials)"
  type        = string
  default     = null
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair to associate with EC2 instances"
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "staging.spaaace.online"
}

variable "parent_zone_name" {
  description = "Parent Route53 public zone used for DNS records (when create_hosted_zone is false and route53_zone_id is not set)"
  type        = string
  default     = "spaaace.online"
}

variable "route53_zone_id" {
  description = "Existing Route53 zone ID to use for DNS records (recommended in CI to avoid ambiguous hosted zone lookups)"
  type        = string
  default     = ""
}

#==============================================================================
# VPC Variables
#==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

#==============================================================================
# ECS Cluster Variables
#==============================================================================

variable "ecs_instance_type" {
  description = "EC2 instance type for ECS nodes"
  type        = string
  default     = "t3.small"
}

variable "ecs_min_size" {
  description = "Minimum number of ECS instances"
  type        = number
  default     = 1
}

variable "ecs_max_size" {
  description = "Maximum number of ECS instances"
  type        = number
  default     = 3
}

variable "ecs_desired_capacity" {
  description = "Desired number of ECS instances"
  type        = number
  default     = 1
}

variable "use_spot_instances" {
  description = "Use Spot instances for cost savings"
  type        = bool
  default     = false
}

variable "spot_max_price" {
  description = "Maximum price for Spot instances"
  type        = string
  default     = null
}

#==============================================================================
# Game Service Variables
#==============================================================================

variable "game_desired_count" {
  description = "Desired number of game server tasks"
  type        = number
  default     = 1
}

variable "game_min_count" {
  description = "Minimum number of game server tasks"
  type        = number
  default     = 1
}

variable "game_max_count" {
  description = "Maximum number of game server tasks"
  type        = number
  default     = 3
}

variable "enable_autoscaling" {
  description = "Enable auto-scaling for game service"
  type        = bool
  default     = false
}

variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate for ALB (in eu-west-1)"
  type        = string
  default     = "" # Set in terraform.tfvars or via CLI
}

variable "cloudfront_certificate_arn" {
  description = "ARN of the ACM certificate for CloudFront (in us-east-1)"
  type        = string
  default     = "" # Set in terraform.tfvars or via CLI
}

variable "enable_https" {
  description = "Enable HTTPS on ALB (requires ACM certificate)"
  type        = bool
  default     = false
}

variable "enable_cloudfront_custom_domain" {
  description = "Enable custom domain on CloudFront (requires ACM certificate in us-east-1)"
  type        = bool
  default     = false
}
