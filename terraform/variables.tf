# Input variables for the Matrix EKS infrastructure

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "matrix-eks-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  # Best Practice: Use RFC1918 private address space
}

variable "instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
  # t3.small: 2 vCPU, 2GB RAM - smallest viable for running Kubernetes + Matrix
  # Cheaper alternatives like t3.micro (1GB) would cause OOM issues
}

variable "desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
  # Running 2 nodes for basic HA and pod distribution
}

variable "min_capacity" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
  # Allow scaling to 3 for handling traffic spikes
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for Matrix applications"
  type        = string
  default     = "matrix"
}

# Secrets Management Variables
# These should be provided via environment variables (TF_VAR_*) or .SECRETS_ENV file
# NEVER commit actual secret values to version control

variable "postgres_password" {
  description = "PostgreSQL password for Matrix Synapse database"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.postgres_password) >= 16
    error_message = "PostgreSQL password must be at least 16 characters long."
  }
}

variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "synapse"
  sensitive   = true
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
  default     = "synapse"
}

variable "synapse_server_name" {
  description = "Matrix Synapse server name (your domain, e.g., matrix.example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.synapse_server_name))
    error_message = "Server name must be a valid domain name."
  }
}

variable "synapse_registration_shared_secret" {
  description = "Shared secret for Matrix Synapse user registration"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.synapse_registration_shared_secret) >= 32
    error_message = "Registration shared secret must be at least 32 characters long."
  }
}

variable "synapse_macaroon_secret_key" {
  description = "Secret key for Matrix Synapse macaroon generation"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.synapse_macaroon_secret_key) >= 32
    error_message = "Macaroon secret key must be at least 32 characters long."
  }
}
