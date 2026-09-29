output "queue_url" {
  description = "URL of the work queue."
  value       = aws_sqs_queue.jobs.url
}

output "dead_letter_queue_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dead_letter.url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "consumer_service_name" {
  description = "Name of the autoscaled consumer ECS service."
  value       = aws_ecs_service.consumer.name
}

output "producer_task_definition_arn" {
  description = "Task definition ARN to run when manually generating load."
  value       = aws_ecs_task_definition.producer.arn
}

output "producer_repository_url" {
  description = "ECR repository URL for the producer image."
  value       = aws_ecr_repository.producer.repository_url
}

output "consumer_repository_url" {
  description = "ECR repository URL for the consumer image."
  value       = aws_ecr_repository.consumer.repository_url
}

output "pipeline_name" {
  description = "Name of the application CodePipeline."
  value       = aws_codepipeline.this.name
}

output "production_health_url" {
  description = "Production listener health URL."
  value       = "http://${aws_lb.this.dns_name}/health"
}

output "test_health_url" {
  description = "CodeDeploy test listener health URL."
  value       = "http://${aws_lb.this.dns_name}:8080/health"
}
