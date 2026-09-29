terraform {
  backend "s3" {
    bucket         = "terraform-state-async-worker-lab-489947827123"
    key            = "asynchronous-worker/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock-async-worker-lab-489947827123"
    encrypt        = true
    profile        = "tn-playground"
  }
}
