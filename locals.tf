data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  tags = merge(var.tags, {
    ManagedBy = "Terraform"
    Module    = "asynchronous-worker"
  })

  consumer_container_name = "consumer"
  consumer_port           = 8080
  service_resource_id     = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.consumer.name}"
}
