variable "aws_region" {
  description = "AWS region in which to create the lab."
  type        = string
  default     = "eu-central-1"
}

variable "aws_profile" {
  description = "Shared AWS config profile used to deploy the lab."
  type        = string
  default     = "tn-playground"
}

variable "connection_arn" {
  description = "ARN of an existing CodeStar Connections GitHub connection."
  type        = string
}

variable "repository_id" {
  description = "GitHub repository in owner/name form."
  type        = string
}

variable "branch_name" {
  description = "Git branch monitored by the pipeline."
  type        = string
  default     = "main"
}
