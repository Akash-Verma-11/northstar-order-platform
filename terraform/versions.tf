terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Local state is fine for a solo practice project.
  # For a team or real production, move to an S3 backend with locking.
}

provider "aws" {
  region = var.aws_region
}
