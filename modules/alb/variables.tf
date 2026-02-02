variable "name" {
  description = "Name of the ALB"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB"
  type        = list(string)
}

variable "enable_http" {
  description = "Enable HTTP listener"
  type        = bool
  default     = true
}

variable "enable_https" {
  description = "Enable HTTPS listener"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS"
  type        = string
  default     = null
}

variable "target_port" {
  description = "Port of the target service"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/"
}

variable "idle_timeout" {
  description = "Idle timeout in seconds (important for WebSockets)"
  type        = number
  default     = 120
}

variable "deregistration_delay" {
  description = "Deregistration delay in seconds"
  type        = number
  default     = 30
}

variable "enable_stickiness" {
  description = "Enable session stickiness (useful for WebSockets)"
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Stickiness cookie duration in seconds"
  type        = number
  default     = 86400
}

variable "websocket_ports" {
  description = "Additional WebSocket ports to open"
  type        = list(number)
  default     = []
}

variable "enable_access_logs" {
  description = "Enable access logs"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for access logs"
  type        = string
  default     = null
}

variable "access_logs_prefix" {
  description = "Prefix for access logs"
  type        = string
  default     = "alb-access-logs"
}

variable "enable_connection_logs" {
  description = "Enable connection logs"
  type        = bool
  default     = false
}

variable "connection_logs_bucket" {
  description = "S3 bucket for connection logs"
  type        = string
  default     = null
}

variable "connection_logs_prefix" {
  description = "Prefix for connection logs"
  type        = string
  default     = "alb-connection-logs"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
