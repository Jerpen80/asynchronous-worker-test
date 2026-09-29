provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      ManagedBy = "Terraform"
      Project   = var.name
    })
  }
}
