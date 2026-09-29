resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/ecs/${var.name}/consumer"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "producer" {
  name              = "/ecs/${var.name}/producer"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = local.tags
}

resource "aws_ecs_task_definition" "consumer" {
  family                   = "${var.name}-consumer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.consumer.arn
  container_definitions = jsonencode([{
    name         = local.consumer_container_name
    image        = "public.ecr.aws/docker/library/python:3.13-slim"
    essential    = true
    command      = ["python", "-m", "http.server", tostring(local.consumer_port)]
    portMappings = [{ containerPort = local.consumer_port, protocol = "tcp" }]
    environment = [
      { name = "QUEUE_URL", value = aws_sqs_queue.jobs.url },
      { name = "PROCESSING_SECONDS", value = tostring(var.processing_seconds) },
      { name = "FAILURE_RATE", value = tostring(var.failure_rate) }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.consumer.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "consumer"
      }
    }
  }])
  tags = local.tags
}

resource "aws_ecs_task_definition" "producer" {
  family                   = "${var.name}-producer"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.producer.arn
  container_definitions = jsonencode([{
    name      = "producer"
    image     = "${aws_ecr_repository.producer.repository_url}:latest"
    essential = true
    environment = [
      { name = "QUEUE_URL", value = aws_sqs_queue.jobs.url },
      { name = "MESSAGE_COUNT", value = "100" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.producer.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "producer"
      }
    }
  }])
  tags = local.tags
}

resource "aws_ecs_service" "consumer" {
  name            = "${var.name}-consumer"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.consumer.arn
  desired_count   = var.consumer_min_capacity
  launch_type     = "FARGATE"

  deployment_controller { type = "CODE_DEPLOY" }
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.consumer.id]
    assign_public_ip = var.assign_public_ip
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = local.consumer_container_name
    container_port   = local.consumer_port
  }
  health_check_grace_period_seconds = 30
  propagate_tags                    = "SERVICE"
  tags                              = local.tags

  lifecycle {
    ignore_changes = [desired_count, task_definition, load_balancer]
  }

  depends_on = [aws_lb_listener.production, aws_iam_role_policy_attachment.ecs_execution]
}
