# main.tf
# Configures the AWS Provider and Terraform Version

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Using local state for simplicity in this demo.
  # For real production, use S3 backend with DynamoDB locking.
  # backend "s3" { ... }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "K8s-AutoScaling-Cluster"
      Environment = "Production"
      ManagedBy   = "Terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "k3s-demo-cluster"
}
