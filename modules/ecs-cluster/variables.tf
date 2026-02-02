variable "name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS instances"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB to allow traffic from"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for ECS nodes"
  type        = string
  default     = "t3.small"
}

variable "min_size" {
  description = "Minimum number of ECS instances"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of ECS instances"
  type        = number
  default     = 3
}

variable "desired_capacity" {
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

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
