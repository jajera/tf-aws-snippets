terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.55.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

variable "availability" {

  default = {
    zone1 = "ap-southeast-1a"
    zone2 = "ap-southeast-1b"
  }
}
