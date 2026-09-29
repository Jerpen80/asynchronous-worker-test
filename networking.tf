resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Public production and test listeners for the learning deployment"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "${var.name}-alb" })

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "consumer" {
  name_prefix = "${var.name}-consumer-"
  description = "Consumer ingress only from the ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = local.consumer_port
    to_port         = local.consumer_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.tags, { Name = "${var.name}-consumer" })

  lifecycle { create_before_destroy = true }
}

resource "aws_lb" "this" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  tags               = local.tags
}

resource "aws_lb_target_group" "blue" {
  name        = substr("${var.name}-blue", 0, 32)
  port        = local.consumer_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
  }
  tags = local.tags
}

resource "aws_lb_target_group" "green" {
  name        = substr("${var.name}-green", 0, 32)
  port        = local.consumer_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
  }
  tags = local.tags
}

resource "aws_lb_listener" "production" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
}

resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.this.arn
  port              = 8080
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }
}
