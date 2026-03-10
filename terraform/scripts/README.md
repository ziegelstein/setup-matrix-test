# Secrets Management Scripts

Helper scripts for managing secrets in the Matrix EKS deployment.

## Available Scripts

### 1. generate-secrets.sh

Generates secure random secrets and creates the `.SECRETS_ENV` file.

**Usage:**

```bash
./scripts/generate-secrets.sh [domain]
```

**Examples:**

```bash
# Generate with default domain
./scripts/generate-secrets.sh

# Generate with custom domain
./scripts/generate-secrets.sh matrix.mycompany.com
```

**What it does:**

- Generates strong random passwords (32 characters)
- Creates `.SECRETS_ENV` file with all required secrets
- Backs up existing `.SECRETS_ENV` if present
- Uses OpenSSL for cryptographically secure random generation

**Output:**

- `.SECRETS_ENV` - Environment file with all secrets
- `.SECRETS_ENV.backup` - Backup of previous file (if exists)

---

### 2. rotate-secret.sh

Rotates a secret in AWS SSM Parameter Store and restarts affected pods.

**Usage:**

```bash
./scripts/rotate-secret.sh <parameter-name> [new-value]
```

**Parameters:**

- `parameter-name` - Short name or full SSM path
- `new-value` - (Optional) New secret value. If not provided, generates random value

**Available short names:**

- `postgres_password` - PostgreSQL database password
- `synapse_registration_shared_secret` - Synapse registration secret
- `synapse_macaroon_secret_key` - Synapse macaroon secret

**Examples:**

```bash
# Rotate with auto-generated value
./scripts/rotate-secret.sh postgres_password

# Rotate with specific value
./scripts/rotate-secret.sh postgres_password 'my-new-secure-password'

# Rotate using full SSM path
./scripts/rotate-secret.sh /matrix-eks-cluster/dev/database/postgres_password
```

**What it does:**

1. Validates the parameter name
2. Generates new random value (if not provided)
3. Updates the secret in AWS SSM Parameter Store
4. Restarts affected Kubernetes pods
5. Provides next steps for verification

**Requirements:**

- AWS CLI configured with appropriate credentials
- kubectl configured for the cluster
- IAM permissions to update SSM parameters
- Kubernetes permissions to restart deployments

---

## Prerequisites

### AWS CLI

```bash
# Install
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure
aws configure
```

### kubectl

```bash
# Install
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Configure for EKS
aws eks update-kubeconfig --region us-east-1 --name matrix-eks-cluster
```

### OpenSSL

Usually pre-installed on Linux/macOS. Verify:

```bash
openssl version
```

---

## Common Workflows

### Initial Setup

```bash
# 1. Generate secrets
./scripts/generate-secrets.sh matrix.example.com

# 2. Review and edit if needed
nano .SECRETS_ENV

# 3. Load secrets
source .SECRETS_ENV

# 4. Deploy infrastructure
terraform apply
```

### Regular Secret Rotation

```bash
# Rotate database password (recommended every 90 days)
./scripts/rotate-secret.sh postgres_password

# Rotate Synapse secrets (recommended every 180 days)
./scripts/rotate-secret.sh synapse_registration_shared_secret
./scripts/rotate-secret.sh synapse_macaroon_secret_key

# Update local .SECRETS_ENV file
# (Get new values from AWS SSM)
aws ssm get-parameter \
  --name "/matrix-eks-cluster/dev/database/postgres_password" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

### Emergency Secret Rotation (Compromised Secret)

```bash
# 1. Immediately rotate the compromised secret
./scripts/rotate-secret.sh postgres_password

# 2. Check pod status
kubectl get pods -n matrix

# 3. Verify pods are running with new secret
kubectl logs -n matrix deployment/postgres
kubectl logs -n matrix deployment/synapse

# 4. Review CloudTrail logs for unauthorized access
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=/matrix-eks-cluster/dev/database/postgres_password \
  --max-results 50

# 5. Update incident response documentation
```

---

## Troubleshooting

### Script Permission Denied

```bash
chmod +x scripts/*.sh
```

### AWS CLI Not Found

```bash
# Check if AWS CLI is installed
which aws

# If not, install it
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### kubectl Not Configured

```bash
# Configure kubectl for your cluster
aws eks update-kubeconfig --region us-east-1 --name matrix-eks-cluster

# Verify
kubectl get nodes
```

### SSM Parameter Not Found

```bash
# List all parameters
aws ssm get-parameters-by-path \
  --path "/matrix-eks-cluster/dev/" \
  --recursive

# Check if Terraform has been applied
terraform state list | grep ssm_parameter
```

### Pod Restart Failed

```bash
# Check if deployment exists
kubectl get deployments -n matrix

# Manually restart
kubectl rollout restart deployment/postgres -n matrix
kubectl rollout restart deployment/synapse -n matrix

# Check status
kubectl rollout status deployment/postgres -n matrix
```

---

## Security Best Practices

1. **Never commit secrets to Git**
   - `.SECRETS_ENV` is in `.gitignore`
   - Always verify before committing

2. **Use strong secrets**
   - Minimum 32 characters for shared secrets
   - Use the scripts to generate cryptographically secure values

3. **Rotate regularly**
   - Database passwords: Every 90 days
   - Application secrets: Every 180 days
   - Immediately if compromised

4. **Limit access**
   - Only authorized personnel should run these scripts
   - Use IAM policies to restrict SSM access
   - Enable MFA for AWS accounts

5. **Audit access**
   - Monitor CloudTrail for SSM parameter access
   - Set up CloudWatch alarms for unauthorized access
   - Review logs regularly

6. **Backup secrets**
   - Store encrypted backups in a secure location
   - Document recovery procedures
   - Test recovery process

---

## Additional Resources

- [SECRETS_MANAGEMENT.md](../SECRETS_MANAGEMENT.md) - Comprehensive guide
- [SECRETS_COMPARISON.md](../SECRETS_COMPARISON.md) - Compare different approaches
- [QUICKSTART_SECRETS.md](../QUICKSTART_SECRETS.md) - Quick reference
- [AWS SSM Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
