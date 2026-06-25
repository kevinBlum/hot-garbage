provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "hot-garbage"
      Environment = terraform.workspace
      ManagedBy   = "terraform"
    }
  }
}
