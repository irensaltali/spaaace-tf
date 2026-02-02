# Route53 Module - DNS management

locals {
  common_tags = merge(var.tags, {
    Module = "route53"
  })
}

# Data source for existing hosted zone
data "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 0 : 1

  name         = var.domain_name
  private_zone = false
}

# Create new hosted zone (if needed)
resource "aws_route53_zone" "this" {
  count = var.create_hosted_zone ? 1 : 0

  name = var.domain_name

  tags = local.common_tags
}

locals {
  zone_id = var.create_hosted_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.this[0].zone_id
  zone_name_servers = var.create_hosted_zone ? aws_route53_zone.this[0].name_servers : data.aws_route53_zone.this[0].name_servers
}

# Game server record (ALB)
resource "aws_route53_record" "game" {
  count = var.game_alb_dns_name != null ? 1 : 0

  zone_id = local.zone_id
  name    = var.game_subdomain
  type    = "A"

  alias {
    name                   = var.game_alb_dns_name
    zone_id                = var.game_alb_zone_id
    evaluate_target_health = true
  }
}

# Website record (CloudFront)
resource "aws_route53_record" "www" {
  count = var.cloudfront_domain_name != null ? 1 : 0

  zone_id = local.zone_id
  name    = var.www_subdomain
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# Apex domain record (optional - can point to CloudFront)
resource "aws_route53_record" "apex" {
  count = var.cloudfront_domain_name != null && var.create_apex_record ? 1 : 0

  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_zone_id
    evaluate_target_health = false
  }
}

# Health check for game server (optional)
resource "aws_route53_health_check" "game" {
  count = var.create_health_check && var.game_alb_dns_name != null ? 1 : 0

  fqdn              = "${var.game_subdomain}.${var.domain_name}"
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 30

  tags = merge(local.common_tags, {
    Name = "${var.domain_name}-game-health"
  })
}

# SSL Certificate (if creating)
resource "aws_acm_certificate" "this" {
  count = var.create_certificate && var.create_hosted_zone == false ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = var.certificate_subject_alternative_names
  validation_method         = "DNS"

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Certificate validation records
resource "aws_route53_record" "cert_validation" {
  for_each = var.create_certificate && var.create_hosted_zone == false ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "this" {
  count = var.create_certificate && var.create_hosted_zone == false ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
