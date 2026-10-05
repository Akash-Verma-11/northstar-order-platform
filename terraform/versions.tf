# versions.tf — add local backend explicitly + gitignore reminder
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {source = "hashicorp/aws", version = "~> 6.0"}
  }
  # Local state for practice — for real production, use an S3 backend
  # with DynamoDB locking instead. Revisit once this is beyond a solo project.
}
provider "aws" {
  region = var.aws_region
}