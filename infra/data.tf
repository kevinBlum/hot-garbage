data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket               = "effigy-analytics-terraform-state"
    key                  = "terraform.tfstate"
    workspace_key_prefix = "network-foundation"
    region               = "us-east-1"
  }
  workspace = terraform.workspace
}

locals {
  env         = terraform.workspace
  name_prefix = "hot-garbage-${local.env}"

  vpc_id            = data.terraform_remote_state.network.outputs.environment_vpc_id
  public_subnet_ids = data.terraform_remote_state.network.outputs.public_subnet_ids
}
