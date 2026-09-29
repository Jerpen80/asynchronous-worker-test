terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.74.0"
    }
  }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

module "asynchronous_worker" {
  source = "../.."

  name           = "async-worker-lab"
  vpc_id         = data.aws_vpc.default.id
  subnet_ids     = data.aws_subnets.default.ids
  connection_arn = var.connection_arn
  repository_id  = var.repository_id
  branch_name    = var.branch_name

  consumer_min_capacity = 1
  consumer_max_capacity = 10
  processing_seconds    = 5

  tags = {
    Project     = "asynchronous-worker-lab"
    Environment = "learning"
  }
}
