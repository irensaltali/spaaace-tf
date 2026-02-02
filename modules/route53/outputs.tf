output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.zone_id
}

output "zone_name_servers" {
  description = "Name servers for the hosted zone"
  value       = local.zone_name_servers
}

output "game_record_fqdn" {
  description = "FQDN of the game server record"
  value       = var.game_alb_dns_name != null ? aws_route53_record.game[0].fqdn : null
}

output "www_record_fqdn" {
  description = "FQDN of the www record"
  value       = var.cloudfront_domain_name != null ? aws_route53_record.www[0].fqdn : null
}

output "certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = var.create_certificate && var.create_hosted_zone == false ? aws_acm_certificate.this[0].arn : null
}

output "certificate_validation_arn" {
  description = "ARN of the validated ACM certificate"
  value       = var.create_certificate && var.create_hosted_zone == false ? aws_acm_certificate_validation.this[0].certificate_arn : null
}
