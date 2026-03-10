# Main Terraform configuration for Matrix Synapse/Element on EKS
# This setup uses t3.small instances (smallest viable for EKS worker nodes)
# Best Practice: Modular design for maintainability and reusability
# Deviation: Using self-managed nodes instead of managed node groups for explicit control

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }

  # Best Practice: Use remote state for team collaboration
  # Uncomment and configure for production use
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "matrix-eks/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  # Best Practice: Tag all resources for cost tracking and management
  default_tags {
    tags = {
      Project     = "Matrix-EKS"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# SSM Module - Manages secrets in AWS Parameter Store
module "ssm" {
  source = "./modules/ssm"

  cluster_name                       = var.cluster_name
  environment                        = var.environment
  aws_region                         = var.aws_region
  postgres_password                  = var.postgres_password
  postgres_user                      = var.postgres_user
  postgres_db                        = var.postgres_db
  synapse_server_name                = var.synapse_server_name
  synapse_registration_shared_secret = var.synapse_registration_shared_secret
  synapse_macaroon_secret_key        = var.synapse_macaroon_secret_key
}

# VPC Module - Creates isolated network infrastructure
module "vpc" {
  source = "./modules/vpc"

  cluster_name = var.cluster_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
}

# EKS Module - Creates Kubernetes cluster with self-managed nodes
module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  environment     = var.environment
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets
  public_subnets  = module.vpc.public_subnets

  # t3.small: 2 vCPU, 2GB RAM - minimum for EKS worker nodes
  # Synapse needs ~1GB RAM, Element needs ~512MB, leaving room for system overhead
  instance_type = var.instance_type
  desired_size  = var.desired_capacity
  min_size      = var.min_capacity
  max_size      = var.max_capacity

  # Attach SSM read policy to worker nodes
  ssm_policy_arn    = module.ssm.ssm_policy_arn
  enable_ssm_policy = true
}

# Configure Kubernetes provider after EKS cluster is created
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name
    ]
  }
}

# aws-auth ConfigMap - Required for self-managed nodes to join the cluster
# Maps the worker node IAM role to Kubernetes RBAC groups
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = module.eks.worker_node_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ])
  }

  depends_on = [module.eks]
}

# Wait for worker nodes to join the cluster and become Ready
# This ensures k8s workloads aren't deployed before nodes are available
resource "null_resource" "wait_for_nodes" {
  depends_on = [kubernetes_config_map.aws_auth]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Configuring kubectl..."
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}
      
      echo "Waiting for EKS nodes to join and become Ready..."
      for i in $(seq 1 60); do
        echo "--- Attempt $i ---"
        echo "All nodes:"
        kubectl get nodes 2>&1 || true
        
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo 0)
        echo "$READY_NODES nodes ready (need ${var.desired_capacity})"
        
        if [ "$READY_NODES" -ge ${var.desired_capacity} ]; then
          echo "All nodes are ready!"
          exit 0
        fi
        sleep 15
      done
      echo "Timeout waiting for nodes" && exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# Kubernetes Module - Deploys Matrix Synapse and Element
module "k8s" {
  source = "./modules/k8s"

  # Wait for nodes to be ready before deploying workloads
  depends_on = [null_resource.wait_for_nodes]

  namespace    = var.k8s_namespace
  aws_region   = var.aws_region
  cluster_name = var.cluster_name
  environment  = var.environment

  # SSM parameter names for secrets
  postgres_password_parameter           = module.ssm.postgres_password_parameter
  postgres_user_parameter               = module.ssm.postgres_user_parameter
  postgres_db_parameter                 = module.ssm.postgres_db_parameter
  synapse_server_name_parameter         = module.ssm.synapse_server_name_parameter
  synapse_registration_secret_parameter = module.ssm.synapse_registration_secret_parameter
  synapse_macaroon_secret_parameter     = module.ssm.synapse_macaroon_secret_parameter
}
