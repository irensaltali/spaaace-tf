# ECR Module - Container Registry for game server images

locals {
  common_tags = merge(var.tags, {
    Module = "ecr"
  })
}

# ECR Repository
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  force_delete = var.force_delete

  tags = local.common_tags
}

# Lifecycle policy to cleanup old images
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.keep_images_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_images_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Repository policy (for cross-account access if needed)
resource "aws_ecr_repository_policy" "this" {
  count = var.repository_policy != null ? 1 : 0

  repository = aws_ecr_repository.this.name
  policy     = var.repository_policy
}
