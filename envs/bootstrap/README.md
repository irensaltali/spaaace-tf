# Spaaace Bootstrap Environment

This environment creates only the ECR repositories needed before other infrastructure can be deployed.

## Why Bootstrap?

The deployment has a circular dependency:
1. **ECR repos** must exist before GitHub Actions can push images
2. **Docker images** must exist in ECR before ECS services can pull them
3. **ECS services** are created by staging/prod Terraform

By separating ECR into a bootstrap step, we break this cycle.

## Order of Operations

```
1. Apply Bootstrap     →  Creates ECR repos in both regions
2. Push Docker Image   →  GitHub Actions builds and pushes to ECR
3. Apply Staging/Prod  →  Creates all other infrastructure (ECS, ALB, etc.)
```

## Usage

### First-Time Setup

```bash
cd spaaace-tf/envs/bootstrap

# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Create ECR repos
terraform apply
```

### Outputs

After applying, you'll see:
- `staging_ecr_repository_url` - ECR URL for staging (eu-west-1)
- `prod_ecr_repository_url` - ECR URL for production (eu-north-1)

### Next Steps

After bootstrap is applied:

1. **Push a Docker image** - Trigger the GitHub Actions workflow by pushing to `develop` (staging) or `master` (prod)

2. **Apply staging environment**:
   ```bash
   cd ../staging
   terraform init
   terraform apply
   ```

3. **Apply production environment**:
   ```bash
   cd ../prod
   terraform init
   terraform apply
   ```

## Multi-Region

This bootstrap creates ECR repos in two regions:

| Environment | Region      | Repository Name        |
|------------|-------------|------------------------|
| Staging    | eu-west-1   | spaaace-staging-game   |
| Production | eu-north-1  | spaaace-prod-game      |

## Terraform State

The bootstrap uses local state by default. For team environments, consider migrating to:
- **Terraform Cloud** (recommended)
- **S3 + DynamoDB** for remote state with locking
