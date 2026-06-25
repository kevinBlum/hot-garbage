resource "aws_lb" "server" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  # Prevent accidental deletion in prod
  enable_deletion_protection = local.env == "prod"

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "server" {
  name        = "${local.name_prefix}-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  # Stickiness ensures WebSocket reconnects land on the same task.
  # Required when desired_count > 1; harmless at count = 1.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = { Name = "${local.name_prefix}-tg" }
}

# HTTP listener — forward directly for now.
# TODO: Replace with HTTP→HTTPS redirect once an ACM cert is provisioned for a custom domain.
# Update network_manager.gd SERVER_URL to ws://<alb_dns_name> after first deploy.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.server.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.server.arn
  }
}
