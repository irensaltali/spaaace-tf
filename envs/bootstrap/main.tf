# Bootstrap Environment
# Creates shared resources needed before other environments:
# - ECR repositories for Docker images
# - Route53 hosted zones

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Provider for staging (eu-west-1)
provider "aws" {
  alias  = "staging"
  region = "eu-west-1"

  default_tags {
    tags = {
      Project     = "spaaace"
      Environment = "bootstrap"
      ManagedBy   = "terraform"
    }
  }
}

# Provider for production (eu-north-1)
provider "aws" {
  alias  = "prod"
  region = "eu-north-1"

  default_tags {
    tags = {
      Project     = "spaaace"
      Environment = "bootstrap"
      ManagedBy   = "terraform"
    }
  }
}

#==============================================================================
# ECR Repositories
#==============================================================================

# Staging ECR (eu-west-1)
module "ecr_staging" {
  source = "../../modules/ecr"
  providers = {
    aws = aws.staging
  }

  name = "spaaace-staging-game"

  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
  keep_images_count    = 20

  tags = {
    Environment = "staging"
  }
}

# Production ECR (eu-north-1)
module "ecr_prod" {
  source = "../../modules/ecr"
  providers = {
    aws = aws.prod
  }

  name = "spaaace-prod-game"

  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  keep_images_count    = 30

  tags = {
    Environment = "prod"
  }
}

#==============================================================================
# Route53 Hosted Zones
#==============================================================================

# Staging hosted zone (eu-west-1)
resource "aws_route53_zone" "staging" {
  provider = aws.staging

  name = "staging.spaaace.online"

  tags = {
    Environment = "staging"
  }
}

# Production hosted zone (eu-north-1)
resource "aws_route53_zone" "prod" {
  provider = aws.prod

  name = "spaaace.online"

  tags = {
    Environment = "prod"
  }
}

#==============================================================================
# Outputs
#==============================================================================

output "staging_ecr_repository_url" {
  description = "Staging ECR repository URL"
  value       = module.ecr_staging.repository_url
}

output "prod_ecr_repository_url" {
  description = "Production ECR repository URL"
  value       = module.ecr_prod.repository_url
}

output "staging_route53_zone_id" {
  description = "Staging Route53 zone ID"
  value       = aws_route53_zone.staging.zone_id
}

output "staging_route53_nameservers" {
  description = "Staging Route53 nameservers (add these to your domain registrar)"
  value       = aws_route53_zone.staging.name_servers
}

output "prod_route53_zone_id" {
  description = "Production Route53 zone ID"
  value       = aws_route53_zone.prod.zone_id
}

output "prod_route53_nameservers" {
  description = "Production Route53 nameservers (add these to your domain registrar)"
  value       = aws_route53_zone.prod.name_servers
}

output "nameserver_instructions" {
  description = "Instructions for setting up DNS"
  value       = <<-EOT
    
    ============================================
    DNS SETUP INSTRUCTIONS
    ============================================
    
    1. STAGING (staging.spaaace.online)
       Add these nameservers to your domain registrar:
       ${join("\n       ", aws_route53_zone.staging.name_servers)}
    
    2. PRODUCTION (spaaace.online)
       Add these nameservers to your domain registrar:
       ${join("\n       ", aws_route53_zone.prod.name_servers)}
    
    ============================================
    
  EOT
}
