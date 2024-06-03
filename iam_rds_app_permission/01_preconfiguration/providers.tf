terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.49.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

variable "availability" {

  default = {
    zone1 = "ap-southeast-1a"
    zone2 = "ap-southeast-1b"
  }
}
