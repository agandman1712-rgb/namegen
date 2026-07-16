terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket         = "namegen-terraform-state-1712"
    key            = "ecr/terraform.tfstate"
    region         = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_ecr_repository" "namegen" {
  name                 = "namegen-v2"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}
