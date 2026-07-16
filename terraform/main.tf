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

data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name            = "namegen-vpc-v2"
  cidr            = "10.10.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  
  private_subnets = []
  public_subnets  = ["10.10.1.0/24", "10.10.2.0/24"]

  enable_nat_gateway = false 
  single_nat_gateway = false

  public_subnet_tags  = { 
    "kubernetes.io/role/elb"                   = "1" 
    "kubernetes.io/cluster/namegen-cluster-v2" = "shared" 
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "namegen-cluster-v2"
  cluster_version = "1.30"  
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnets

  cluster_endpoint_public_access = true
  create_iam_role                = true

  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 1

  eks_managed_node_groups = {
    default_node_group = {
      instance_types = ["t2.micro"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      
      assign_public_ip = true
    }
  }

  authentication_mode = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true
}

resource "aws_ecr_repository" "namegen" {
  name                 = "namegen-v2"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}
