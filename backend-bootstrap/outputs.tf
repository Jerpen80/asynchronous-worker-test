output "bucket_name" {
  description = "S3 bucket used by the application Terraform backend."
  value       = module.terraform_backend.terraform_backend_s3_id
}

output "dynamodb_table_name" {
  description = "DynamoDB table used for Terraform state locking."
  value       = module.terraform_backend.terraform_backend_dynamodb_name
}
