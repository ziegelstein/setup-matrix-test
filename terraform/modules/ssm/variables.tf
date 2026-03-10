variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

# Database Secrets
variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "postgres_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "synapse"
}

variable "postgres_db" {
  description = "PostgreSQL database name"
  type        = string
  default     = "synapse"
}

# Synapse Configuration
variable "synapse_server_name" {
  description = "Matrix Synapse server name (domain)"
  type        = string
}

variable "synapse_registration_shared_secret" {
  description = "Matrix Synapse registration shared secret"
  type        = string
  sensitive   = true
}

variable "synapse_macaroon_secret_key" {
  description = "Matrix Synapse macaroon secret key"
  type        = string
  sensitive   = true
}
