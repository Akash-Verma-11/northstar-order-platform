variable "aws_region" { type = string, default = "ap-south-1" }
variable "project" { type = string, default = "northstar" }
variable "environment" { type = string, default = "prod" }
variable "vpc_cidr" { type = string, default = "10.40.0.0/16" }
variable "db_password" { type = string, sensitive = true }
