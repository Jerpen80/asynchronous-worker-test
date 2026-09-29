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

variable "tags" {
  description = "Tags applied by default to every taggable backend resource."
  type        = map(string)
  default     = {}
}
