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
  alias   = "staging"
  region  = "eu-west-1"
  profile = "irensaltali"

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
  alias   = "prod"
  region  = "eu-north-1"
  profile = "irensaltali"

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

# Route 53 zones are pre-existing and managed externally.
#==============================================================================
# Terraform State Backend Resources
#==============================================================================

# Staging State Bucket
resource "aws_s3_bucket" "terraform_state_staging" {
  provider = aws.staging
  bucket   = "spaaace-terraform-state-staging"

  tags = {
    Name        = "Terraform State Store Staging"
    Environment = "staging"
  }
}

resource "aws_s3_bucket_versioning" "staging_versioning" {
  provider = aws.staging
  bucket   = aws_s3_bucket.terraform_state_staging.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "staging_encryption" {
  provider = aws.staging
  bucket   = aws_s3_bucket.terraform_state_staging.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Staging State Lock Table
resource "aws_dynamodb_table" "terraform_locks_staging" {
  provider     = aws.staging
  name         = "terraform-state-locks-staging"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    Name        = "Terraform State Lock Table Staging"
    Environment = "staging"
  }
}

# Production State Bucket
resource "aws_s3_bucket" "terraform_state_prod" {
  provider = aws.prod
  bucket   = "spaaace-terraform-state-prod"

  tags = {
    Name        = "Terraform State Store Production"
    Environment = "prod"
  }
}

resource "aws_s3_bucket_versioning" "prod_versioning" {
  provider = aws.prod
  bucket   = aws_s3_bucket.terraform_state_prod.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prod_encryption" {
  provider = aws.prod
  bucket   = aws_s3_bucket.terraform_state_prod.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Production State Lock Table
resource "aws_dynamodb_table" "terraform_locks_prod" {
  provider     = aws.prod
  name         = "terraform-state-locks-prod"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    Name        = "Terraform State Lock Table Production"
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

