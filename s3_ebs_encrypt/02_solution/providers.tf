terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.43.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_region" "current" {}

data "terraform_remote_state" "example" {
  backend = "local"

  config = {
    path = "../01_preconfiguration/terraform.tfstate"
  }
}
