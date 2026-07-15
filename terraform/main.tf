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

resource "aws_security_group" "app_sg" {
  name        = "namegen-app-sg"
  description = "Allow web traffic"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app_server" {
  ami                    = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS ב-us-east-1
  instance_type          = "t3.micro"               # חסכוני וכלול ב-Free Tier
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              EOF

  tags = {
    Name = "namegen-app-server"
  }
}

output "server_public_ip" {
  value = aws_instance.app_server.public_ip
}
