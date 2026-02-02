#==============================================================================
# General Variables
#==============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "aws_profile" {
  description = "AWS profile to use for authentication"
  type        = string
  default     = "irensaltali"
}

variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "spaaace.online"
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
  default     = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
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
