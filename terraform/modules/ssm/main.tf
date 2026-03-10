# AWS SSM Parameter Store Module for Secrets Management
# Best Practice: Store secrets in AWS SSM Parameter Store with KMS encryption
# This provides centralized secrets management, audit logging, and rotation capabilities

# KMS key for encrypting SSM parameters
resource "aws_kms_key" "ssm" {
  description             = "KMS key for SSM Parameter Store encryption - ${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name        = "${var.cluster_name}-ssm-key"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "ssm" {
  name          = "alias/${var.cluster_name}-ssm"
  target_key_id = aws_kms_key.ssm.key_id
}

# Database Secrets
resource "aws_ssm_parameter" "postgres_password" {
  name        = "/${var.cluster_name}/${var.environment}/database/postgres_password"
  description = "PostgreSQL password for Matrix Synapse"
  type        = "SecureString"
  value       = var.postgres_password
  key_id      = aws_kms_key.ssm.key_id

  tags = {
    Environment = var.environment
    Application = "matrix"
  }
}

resource "aws_ssm_parameter" "postgres_user" {
  name        = "/${var.cluster_name}/${var.environment}/database/postgres_user"
  description = "PostgreSQL username for Matrix Synapse"
  type        = "SecureString"
  value       = var.postgres_user
  key_id      = aws_kms_key.ssm.key_id

  tags = {
    Environment = var.environment
    Application = "matrix"
  }
}

resource "aws_ssm_parameter" "postgres_db" {
  name        = "/${var.cluster_name}/${var.environment}/database/postgres_db"
  description = "PostgreSQL database name for Matrix Synapse"
  type        = "String"
  value       = var.postgres_db

  tags = {
    Environment = var.environment
    Application = "matrix"
  }
}

# Synapse Configuration Secrets
resource "aws_ssm_parameter" "synapse_server_name" {
  name        = "/${var.cluster_name}/${var.environment}/synapse/server_name"
  description = "Matrix Synapse server name (domain)"
  type        = "String"
  value       = var.synapse_server_name

  tags = {
    Environment = var.environment
    Application = "matrix"
  }
}

resource "aws_ssm_parameter" "synapse_registration_shared_secret" {
  name        = "/${var.cluster_name}/${var.environment}/synapse/registration_shared_secret"
  description = "Matrix Synapse registration shared secret"
  type        = "SecureString"
  value       = var.synapse_registration_shared_secret
  key_id      = aws_kms_key.ssm.key_id

  tags = {
    Environment = var.environment
    Application = "matrix"
  }
}

resource "aws_ssm_parameter" "synapse_macaroon_secret_key" {
  name        = "/${var.cluster_name}/${var.environment}/synapse/macaroon_secret_key"
  description = "Matrix Synapse macaroon secret key"
  type        = "SecureString"
  value       = var.synapse_macaroon_secret_key
  key_id      = aws_kms_key.ssm.key_id

  tags = {
    Environment = var.environment
    Application = "matrix"
  }
}

# IAM Policy for EKS nodes to read SSM parameters
resource "aws_iam_policy" "ssm_read" {
  name        = "${var.cluster_name}-ssm-read-policy"
  description = "Allow EKS nodes to read SSM parameters for Matrix secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_name}/${var.environment}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          aws_kms_key.ssm.arn
        ]
      }
    ]
  })
}
