terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
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

  name            = "namegen-vpc"
  cidr            = "10.0.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "namegen-cluster"
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  # הפעלת EKS Auto Mode
  cluster_compute_config = {
    enabled       = true
    node_pool_ids = ["general-purpose"]
  }

  access_config = {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  enable_cluster_creator_admin_permissions = true
}

resource "aws_ecr_repository" "namegen" {
  name                 = "namegen"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

data "tls_certificate" "github" {
  url = "https://githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://githubusercontent.com"
  client_id_list  = ["://amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates.sha1_fingerprint]
}

resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-eks-deployment-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "://githubusercontent.com:aud" = "://amazonaws.com"
          }
          StringLike = {
            "://githubusercontent.com:sub" = "repo:agandman1712-rgb/namegen:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_ecr" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "github_eks" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_actions_role.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_admin" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:aws:iam::aws:policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_iam_role.github_actions_role.arn

  access_scope { type = "cluster" }
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "ה-ARN של התפקיד עבור ה-Pipeline"
}
