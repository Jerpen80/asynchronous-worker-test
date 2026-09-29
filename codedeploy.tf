data "archive_file" "validation" {
  type        = "zip"
  output_path = "${path.root}/.terraform/${var.name}-validation-hook.zip"

  source {
    filename = "index.py"
    content  = <<-PYTHON
      import json
      import os
      import urllib.request
      import boto3

      def handler(event, _context):
          status = "Failed"
          try:
              with urllib.request.urlopen(os.environ["TEST_URL"], timeout=10) as response:
                  body = response.read().decode()
                  if response.status == 200 and body == "ok":
                      status = "Succeeded"
          except Exception as exc:
              print(json.dumps({"validation_error": str(exc)}))

          boto3.client("codedeploy").put_lifecycle_event_hook_execution_status(
              deploymentId=event["DeploymentId"],
              lifecycleEventHookExecutionId=event["LifecycleEventHookExecutionId"],
              status=status,
          )
          return {"status": status}
    PYTHON
  }
}

resource "aws_lambda_function" "validation" {
  function_name    = "${var.name}-deployment-validation"
  role             = aws_iam_role.validation.arn
  handler          = "index.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.validation.output_path
  source_code_hash = data.archive_file.validation.output_base64sha256
  timeout          = 30
  environment { variables = { TEST_URL = "http://${aws_lb.this.dns_name}:8080/health" } }
  tags = local.tags
}

resource "aws_codedeploy_app" "consumer" {
  compute_platform = "ECS"
  name             = "${var.name}-consumer"
  tags             = local.tags
}

resource "aws_codedeploy_deployment_group" "consumer" {
  app_name               = aws_codedeploy_app.consumer.name
  deployment_group_name  = "${var.name}-consumer"
  service_role_arn       = aws_iam_role.codedeploy.arn
  deployment_config_name = var.deployment_config_name

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }
  alarm_configuration {
    enabled                   = true
    ignore_poll_alarm_failure = false
    alarms                    = [aws_cloudwatch_metric_alarm.dlq.alarm_name]
  }
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout    = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes = 0
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_minutes
    }
  }
  ecs_service {
    cluster_name = aws_ecs_cluster.this.name
    service_name = aws_ecs_service.consumer.name
  }
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route { listener_arns = [aws_lb_listener.production.arn] }
      test_traffic_route { listener_arns = [aws_lb_listener.test.arn] }
      target_group { name = aws_lb_target_group.blue.name }
      target_group { name = aws_lb_target_group.green.name }
    }
  }
  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name          = "${var.name}-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  dimensions          = { QueueName = aws_sqs_queue.dead_letter.name }
  tags                = local.tags
}
