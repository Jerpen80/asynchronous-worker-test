variable "aws_profile" {
  description = "Shared AWS config profile used to create the backend."
  type        = string
  default     = "tn-playground"
}

variable "aws_region" {
  description = "AWS region in which to create the backend."
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Account-specific suffix for the backend bucket and lock table."
  type        = string
  default     = "async-worker-lab-489947827123"
}

variable "kms_key_arn" {
  description = "ARN of the existing customer-managed KMS key used for state and lock-table encryption."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key ARN."
  }
}

variable "tags" {
  description = "Tags applied by default to every taggable backend resource."
  type        = map(string)
  default     = {}
}
