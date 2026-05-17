resource "aws_security_group" "alb" {
  name        = "${var.environment}-alb-sg"
  description = "ALB security group - ingress 443 from the internet"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.environment}-alb-sg" })
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_ingress_http_redirect" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_lb" "this" {
  name               = "${var.environment}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  enable_deletion_protection = true
  drop_invalid_header_fields = true

  tags = merge(var.tags, { Name = "${var.environment}-alb" })
}

resource "aws_lb_target_group" "this" {
  name        = "${var.environment}-tg"
  port        = var.target_port
  protocol    = "HTTP"
  target_type = "ip" # for Fargate, EKS pods, on-prem servers, etc.
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = var.tags
}

# --- HTTP listener ---
# When existing_acm_cert_arn is set, port 80 returns a 301 redirect to 443
# (the typical production posture: clients follow the redirect and all real
# traffic is encrypted over HTTPS).
# When no cert is provided yet (first-deploy bootstrap before ACM is ready,
# e.g. the development environment), port 80 forwards directly to the target
# group so the application is reachable over plain HTTP. This lets the app be
# exercised end-to-end before a certificate exists, without standing up an
# HTTPS listener that has no cert to serve.
# Resource label kept as http_redirect for state stability; the actual action
# is selected dynamically below based on whether the cert is provided, so the
# label is a historical name rather than a literal description of the action.
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.existing_acm_cert_arn != null ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.existing_acm_cert_arn == null ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this.arn
    }
  }
}

# --- HTTPS listener ---
# Conditional: only created once an ACM cert ARN is provided. The frontend
# CloudFront and the public DNS records should not be flipped to this ALB
# until the HTTPS listener exists.
resource "aws_lb_listener" "https" {
  count             = var.existing_acm_cert_arn != null ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.existing_acm_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
