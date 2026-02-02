variable "domain_name" {
  description = "Root domain name (e.g., spaaace.online)"
  type        = string
}

variable "create_hosted_zone" {
  description = "Create a new Route53 hosted zone (if false, uses existing)"
  type        = bool
  default     = false
}

variable "game_subdomain" {
  description = "Subdomain for game server (e.g., game)"
  type        = string
  default     = "game"
}

variable "www_subdomain" {
  description = "Subdomain for website (e.g., www)"
  type        = string
  default     = "www"
}

variable "game_alb_dns_name" {
  description = "DNS name of the game ALB"
  type        = string
  default     = null
}

variable "game_alb_zone_id" {
  description = "Zone ID of the game ALB"
  type        = string
  default     = null
}

variable "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  type        = string
  default     = null
}

variable "cloudfront_zone_id" {
  description = "Zone ID of the CloudFront distribution"
  type        = string
  default     = "Z2FDTNDATAQYW2"  # CloudFront zone ID is always this
}

variable "create_apex_record" {
  description = "Create apex domain record pointing to CloudFront"
  type        = bool
  default     = true
}

variable "create_health_check" {
  description = "Create Route53 health check for game server"
  type        = bool
  default     = false
}

variable "health_check_path" {
  description = "Path for health check"
  type        = string
  default     = "/"
}

variable "create_certificate" {
  description = "Create ACM certificate for the domain"
  type        = bool
  default     = false
}

variable "certificate_subject_alternative_names" {
  description = "SANs for the certificate"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
