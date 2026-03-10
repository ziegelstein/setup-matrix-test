variable "namespace" {
  description = "Kubernetes namespace for Matrix applications"
  type        = string
  default     = "matrix"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# SSM Parameter names
variable "postgres_password_parameter" {
  description = "SSM parameter name for PostgreSQL password"
  type        = string
}

variable "postgres_user_parameter" {
  description = "SSM parameter name for PostgreSQL user"
  type        = string
}

variable "postgres_db_parameter" {
  description = "SSM parameter name for PostgreSQL database"
  type        = string
}

variable "synapse_server_name_parameter" {
  description = "SSM parameter name for Synapse server name"
  type        = string
}

variable "synapse_registration_secret_parameter" {
  description = "SSM parameter name for Synapse registration secret"
  type        = string
}

variable "synapse_macaroon_secret_parameter" {
  description = "SSM parameter name for Synapse macaroon secret"
  type        = string
}
