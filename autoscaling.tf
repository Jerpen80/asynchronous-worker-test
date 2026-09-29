resource "aws_appautoscaling_target" "consumer" {
  max_capacity       = var.consumer_max_capacity
  min_capacity       = var.consumer_min_capacity
  resource_id        = local.service_resource_id
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "scale_out" {
  name               = "${var.name}-queue-scale-out"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.consumer.resource_id
  scalable_dimension = aws_appautoscaling_target.consumer.scalable_dimension
  service_namespace  = aws_appautoscaling_target.consumer.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_lower_bound = 0
      metric_interval_upper_bound = 40
      scaling_adjustment          = 1
    }
    step_adjustment {
      metric_interval_lower_bound = 40
      metric_interval_upper_bound = 90
      scaling_adjustment          = 2
    }
    step_adjustment {
      metric_interval_lower_bound = 90
      scaling_adjustment          = 4
    }
  }
}

resource "aws_appautoscaling_policy" "scale_in" {
  name               = "${var.name}-queue-scale-in"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.consumer.resource_id
  scalable_dimension = aws_appautoscaling_target.consumer.scalable_dimension
  service_namespace  = aws_appautoscaling_target.consumer.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 120
    metric_aggregation_type = "Maximum"
    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "queue_high" {
  alarm_name          = "${var.name}-queue-depth-high"
  alarm_description   = "Scale the consumer out as visible SQS messages exceed 10"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 10
  alarm_actions       = [aws_appautoscaling_policy.scale_out.arn]
  dimensions          = { QueueName = aws_sqs_queue.jobs.name }
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "queue_empty" {
  alarm_name          = "${var.name}-queue-empty"
  alarm_description   = "Scale the consumer in one task at a time while the queue is empty"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_appautoscaling_policy.scale_in.arn]
  dimensions          = { QueueName = aws_sqs_queue.jobs.name }
  tags                = local.tags
}
