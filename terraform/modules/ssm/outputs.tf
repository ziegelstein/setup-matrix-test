output "kms_key_id" {
  description = "KMS key ID for SSM encryption"
  value       = aws_kms_key.ssm.id
}

output "kms_key_arn" {
  description = "KMS key ARN for SSM encryption"
  value       = aws_kms_key.ssm.arn
}

output "ssm_policy_arn" {
  description = "IAM policy ARN for reading SSM parameters"
  value       = aws_iam_policy.ssm_read.arn
}

# Parameter names for reference
output "postgres_password_parameter" {
  description = "SSM parameter name for PostgreSQL password"
  value       = aws_ssm_parameter.postgres_password.name
}

output "postgres_user_parameter" {
  description = "SSM parameter name for PostgreSQL user"
  value       = aws_ssm_parameter.postgres_user.name
}

output "postgres_db_parameter" {
  description = "SSM parameter name for PostgreSQL database"
  value       = aws_ssm_parameter.postgres_db.name
}

output "synapse_server_name_parameter" {
  description = "SSM parameter name for Synapse server name"
  value       = aws_ssm_parameter.synapse_server_name.name
}

output "synapse_registration_secret_parameter" {
  description = "SSM parameter name for Synapse registration secret"
  value       = aws_ssm_parameter.synapse_registration_shared_secret.name
}

output "synapse_macaroon_secret_parameter" {
  description = "SSM parameter name for Synapse macaroon secret"
  value       = aws_ssm_parameter.synapse_macaroon_secret_key.name
}
