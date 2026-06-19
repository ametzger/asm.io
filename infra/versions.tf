terraform {
  required_version = ">= 0.13"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.49.0"
    }
  }
}
