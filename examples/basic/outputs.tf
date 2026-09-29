output "pipeline_name" {
  value = module.asynchronous_worker.pipeline_name
}

output "queue_url" {
  value = module.asynchronous_worker.queue_url
}

output "production_health_url" {
  value = module.asynchronous_worker.production_health_url
}
