terraform {
  backend "s3" {
    bucket               = "effigy-analytics-terraform-state"
    key                  = "terraform.tfstate"
    workspace_key_prefix = "hot-garbage"
    region               = "us-east-1"
    encrypt              = true
    use_lockfile         = true
  }

  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
