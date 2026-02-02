# ALB Module - WebSocket-ready Application Load Balancer

locals {
  common_tags = merge(var.tags, {
    Module = "alb"
  })
}

# Application Load Balancer
resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  # Access logs (optional)
  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  # Connection logs for debugging WebSocket issues
  dynamic "connection_logs" {
    for_each = var.enable_connection_logs ? [1] : []
    content {
      bucket  = var.connection_logs_bucket
      prefix  = var.connection_logs_prefix
      enabled = true
    }
  }

  # WebSocket-friendly idle timeout (default is 60s, increase for long-lived connections)
  idle_timeout = var.idle_timeout

  # Cross-zone load balancing for better distribution
  enable_cross_zone_load_balancing = true

  # Deletion protection for production
  enable_deletion_protection = var.enable_deletion_protection

  tags = local.common_tags
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id

  # HTTP - will redirect to HTTPS
  dynamic "ingress" {
    for_each = var.enable_http ? [1] : []
    content {
      description = "HTTP from Internet"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # HTTPS
  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []
    content {
      description = "HTTPS from Internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # WebSocket ports (if different from HTTP/HTTPS)
  dynamic "ingress" {
    for_each = var.websocket_ports
    content {
      description = "WebSocket port"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP Listener -> Redirect to HTTPS
resource "aws_lb_listener" "http" {
  count = var.enable_http ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "fixed-response"

    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = var.enable_https ? [] : [1]
      content {
        content_type = "text/plain"
        message_body = "OK"
        status_code  = "200"
      }
    }
  }
}

# HTTPS Listener (if certificate provided)
resource "aws_lb_listener" "https" {
  count = var.enable_https && var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "No target group configured"
      status_code  = "404"
    }
  }
}

# Target Group for Game Server (WebSocket ready)
resource "aws_lb_target_group" "this" {
  name     = "${var.name}-tg"
  port     = var.target_port
  protocol = var.enable_https ? "HTTPS" : "HTTP"
  vpc_id   = var.vpc_id

  # Target type: instance for EC2-backed ECS
  target_type = "instance"

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = var.enable_https ? "HTTPS" : "HTTP"
    matcher             = "200"
  }

  # Deregistration delay - how long to wait before removing instance
  # Set lower for faster deployments, higher for WebSocket connections to drain
  deregistration_delay = var.deregistration_delay

  # Stickiness - useful for WebSocket connections
  dynamic "stickiness" {
    for_each = var.enable_stickiness ? [1] : []
    content {
      type            = "lb_cookie"
      cookie_duration = var.stickiness_duration
      enabled         = true
    }
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Listener rule to forward to target group
resource "aws_lb_listener_rule" "game" {
  count = var.enable_https && var.certificate_arn != null ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# HTTP listener rule (if no HTTPS)
resource "aws_lb_listener_rule" "game_http" {
  count = var.enable_http && !var.enable_https ? 1 : 0

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}
