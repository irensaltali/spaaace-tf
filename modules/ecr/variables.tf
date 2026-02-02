variable "name" {
  description = "Name of the ECR repository"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability (MUTABLE or IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Force delete repository even if it contains images"
  type        = bool
  default     = true
}

variable "keep_images_count" {
  description = "Number of images to keep"
  type        = number
  default     = 10
}

variable "repository_policy" {
  description = "Repository policy JSON"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
