variable "aws_profile" {
  description = "Shared AWS config profile used to deploy this stack."
  type        = string
  default     = "tn-playground"
}

variable "aws_region" {
  description = "AWS region in which to deploy this stack."
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Name prefix for resources created by this module."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.name))
    error_message = "name must contain 3-30 lowercase letters, numbers, or hyphens."
  }
}

variable "vpc_id" {
  description = "VPC in which to run the ALB and Fargate tasks."
  type        = string
}

variable "subnet_ids" {
  description = "At least two subnets in different Availability Zones. Public subnets are suitable for this learning lab."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least two subnet IDs are required by the Application Load Balancer."
  }
}

variable "connection_arn" {
  description = "ARN of an existing, AVAILABLE CodeStar Connections connection to GitHub."
  type        = string
}

variable "repository_id" {
  description = "GitHub repository in owner/name form used by the CodePipeline source action."
  type        = string
}

variable "branch_name" {
  description = "Git branch monitored by CodePipeline."
  type        = string
  default     = "main"
}

variable "assign_public_ip" {
  description = "Assign public IPs to tasks. Set false only when private subnets have NAT or the required VPC endpoints."
  type        = bool
  default     = true
}

variable "consumer_min_capacity" {
  description = "Minimum number of consumer tasks."
  type        = number
  default     = 1
}

variable "consumer_max_capacity" {
  description = "Maximum number of consumer tasks."
  type        = number
  default     = 10
}

variable "processing_seconds" {
  description = "Artificial processing time per message, making autoscaling visible."
  type        = number
  default     = 5
}

variable "failure_rate" {
  description = "Intentional consumer failure probability from 0 to 1. Failed messages are retried and may reach the DLQ."
  type        = number
  default     = 0

  validation {
    condition     = var.failure_rate >= 0 && var.failure_rate <= 1
    error_message = "failure_rate must be between 0 and 1."
  }
}

variable "producer_messages_per_burst" {
  description = "Number of SQS messages sent in each producer burst."
  type        = number
  default     = 100
}

variable "producer_burst_count" {
  description = "Number of bursts sent by one producer task run."
  type        = number
  default     = 1
}

variable "producer_burst_interval_seconds" {
  description = "Seconds the producer waits between bursts."
  type        = number
  default     = 60
}

variable "producer_batch_delay_seconds" {
  description = "Delay between SQS SendMessageBatch calls within a burst."
  type        = number
  default     = 0.1
}

variable "visibility_timeout_seconds" {
  description = "SQS visibility timeout. Keep this longer than processing_seconds."
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "Failed receives before SQS moves a message to the dead-letter queue."
  type        = number
  default     = 3
}

variable "deployment_config_name" {
  description = "CodeDeploy ECS deployment configuration controlling the production traffic shift."
  type        = string
  default     = "CodeDeployDefault.ECSCanary10Percent5Minutes"
}

variable "termination_wait_minutes" {
  description = "Minutes CodeDeploy retains the blue task set after a successful deployment."
  type        = number
  default     = 5
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to apply to resources managed by this module."
  type        = map(string)
  default     = {}
}
