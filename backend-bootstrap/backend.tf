terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The pinned backend module generates a policy containing a null value
      # that AWS provider v6 rejects. Use the provider version it was built for.
      version = "= 4.57.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      ManagedBy = "Terraform"
      Project   = "${var.name}-terraform-backend"
    })
  }
}

module "terraform_backend" {
  source = "git::ssh://git@github.com/wearetechnative/terraform-aws-module-terraform-backend.git?ref=59f17d5e6480e1347e5dd6ea83f200036e4242d8"

  name                        = var.name
  use_fixed_name              = "true"
  add_name_prefix_to_dynamodb = true
}
