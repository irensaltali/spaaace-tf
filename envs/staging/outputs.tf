#==============================================================================
# VPC Outputs
#==============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

#==============================================================================
# ECR Outputs (ECR created by bootstrap environment)
#==============================================================================

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = module.ecr.repository_name
}

#==============================================================================
# ACM Certificate Outputs
#==============================================================================

output "certificate_arn" {
  description = "ARN of the ACM certificate (ALB)"
  value       = local.certificate_arn
}

output "cloudfront_certificate_arn" {
  description = "ARN of the CloudFront certificate (us-east-1)"
  value       = local.cloudfront_certificate_arn
}

output "certificate_domain" {
  description = "Domain name of the certificate"
  value       = "*.spaaace.online"
}

#==============================================================================
# ALB Outputs
#==============================================================================

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB"
  value       = module.alb.alb_zone_id
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = module.alb.target_group_arn
}

#==============================================================================
# ECS Cluster Outputs
#==============================================================================

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  value       = module.ecs_cluster.cluster_id
}

output "ecs_cloudwatch_log_group" {
  description = "CloudWatch log group for ECS"
  value       = module.ecs_cluster.cloudwatch_log_group_name
}

#==============================================================================
# ECS Service Outputs
#==============================================================================

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs_service.service_name
}

output "game_cloudwatch_log_group" {
  description = "CloudWatch log group for game server"
  value       = module.ecs_service.cloudwatch_log_group_name
}

#==============================================================================
# Website Outputs
#==============================================================================

output "website_bucket_name" {
  description = "Name of the S3 bucket for website"
  value       = module.website.bucket_id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = module.website.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.website.cloudfront_distribution_id
}

output "cloudfront_zone_id" {
  description = "CloudFront hosted zone ID"
  value       = module.website.cloudfront_zone_id
}

#==============================================================================
# Route53 Outputs
#==============================================================================

output "route53_zone_id" {
  description = "Route53 zone ID"
  value       = local.route53_zone_id
}

output "route53_nameservers" {
  description = "Route53 nameservers (add to domain registrar)"
  value       = var.create_hosted_zone ? aws_route53_zone.this[0].name_servers : []
}

output "game_server_domain" {
  description = "Domain name for game server"
  value       = "game.${var.domain_name}"
}

output "website_domain" {
  description = "Domain name for website"
  value       = var.domain_name
}

#==============================================================================
# Important Endpoints
#==============================================================================

output "game_server_endpoint" {
  description = "Game server HTTPS endpoint"
  value       = "https://game.${var.domain_name}"
}

output "game_server_websocket" {
  description = "Game server WebSocket endpoint (wss)"
  value       = "wss://game.${var.domain_name}"
}

output "website_endpoint" {
  description = "Website HTTPS endpoint"
  value       = "https://${var.domain_name}"
}

output "deploy_commands" {
  description = "Commands to deploy the game server"
  value       = <<-EOT
    # Build and push Docker image:
    cd ../spaaace
    docker build -t spaaace-game .
    docker tag spaaace-game:latest ${local.ecr_repository_url}:staging
    aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin ${local.ecr_repository_url}
    docker push ${local.ecr_repository_url}:staging
    
    # Update ECS service:
    aws ecs update-service --cluster ${module.ecs_cluster.cluster_name} --service ${module.ecs_service.service_name} --force-new-deployment
    
    # Deploy website to S3:
    aws s3 sync ../spaaace/dist/ s3://${module.website.bucket_id}/ --delete
    
    # Invalidate CloudFront cache:
    aws cloudfront create-invalidation --distribution-id ${module.website.cloudfront_distribution_id} --paths "/*"
  EOT
}

output "important_endpoints" {
  description = "Important endpoints for the staging environment"
  value       = <<-EOT
    
    ============================================
    STAGING ENVIRONMENT ENDPOINTS
    ============================================
    
    🎮 Game Server:    https://game.${var.domain_name}
    🌐 Website:        https://${var.domain_name}
    🔧 ALB (Direct):   ${module.alb.alb_dns_name}
    📦 CloudFront:     ${module.website.cloudfront_domain_name}
    
    ============================================
    
  EOT
}
