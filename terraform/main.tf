terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket         = "namegen-terraform-state-1712"
    key            = "state/terraform.tfstate"
    region         = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "namegen-vpc"
  cidr            = "10.0.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags  = { 
    "kubernetes.io/role/elb"                      = "1" 
    "kubernetes.io/cluster/namegen-cluster"       = "shared" 
  }
  private_subnet_tags = { 
    "kubernetes.io/role/internal-elb"             = "1" 
    "kubernetes.io/cluster/namegen-cluster"       = "shared" 
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "namegen-cluster"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  create_iam_role = false
  iam_role_arn    = data.aws_iam_role.lab_role.arn

  cluster_compute_config = {
    enabled = false
  }

  eks_managed_node_groups = {
    default_node_group = {
      instance_types = ["t3.micro"]
      
      min_size     = 1
      max_size     = 2
      desired_size = 1

      create_iam_role = false
      iam_role_arn    = data.aws_iam_role.lab_role.arn
    }
  }

  authentication_mode = "API_AND_CONFIG_MAP"

  enable_cluster_creator_admin_permissions = true
}

resource "aws_ecr_repository" "namegen" {
  name                 = "namegen"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}
