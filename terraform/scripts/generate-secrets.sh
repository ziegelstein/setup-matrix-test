#!/bin/bash
# Script to generate secure secrets for Matrix EKS deployment
# Usage: ./scripts/generate-secrets.sh [domain]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default domain
DOMAIN="${1:-matrix.example.com}"

echo -e "${GREEN}=== Matrix EKS Secrets Generator ===${NC}"
echo ""

# Check if .SECRETS_ENV already exists
if [ -f ".SECRETS_ENV" ]; then
    echo -e "${YELLOW}Warning: .SECRETS_ENV already exists!${NC}"
    read -p "Do you want to overwrite it? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Aborted. Existing .SECRETS_ENV file preserved."
        exit 0
    fi
    # Backup existing file
    cp .SECRETS_ENV .SECRETS_ENV.backup
    echo -e "${GREEN}Backed up existing file to .SECRETS_ENV.backup${NC}"
fi

# Generate secrets
echo "Generating secure random secrets..."
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REGISTRATION_SECRET=$(openssl rand -base64 32)
MACAROON_SECRET=$(openssl rand -base64 32)

# Create .SECRETS_ENV file
cat > .SECRETS_ENV << EOF
# Secrets Environment File
# Generated on: $(date)
# IMPORTANT: Never commit this file to version control!

# Database Secrets
export TF_VAR_postgres_password="${POSTGRES_PASSWORD}"
export TF_VAR_postgres_user="synapse"
export TF_VAR_postgres_db="synapse"

# Matrix Synapse Configuration
export TF_VAR_synapse_server_name="${DOMAIN}"
export TF_VAR_synapse_registration_shared_secret="${REGISTRATION_SECRET}"
export TF_VAR_synapse_macaroon_secret_key="${MACAROON_SECRET}"
EOF

echo -e "${GREEN}✓ Secrets generated successfully!${NC}"
echo ""
echo "Configuration:"
echo "  - Domain: ${DOMAIN}"
echo "  - PostgreSQL password: [generated - 32 chars]"
echo "  - Registration secret: [generated - 32 chars]"
echo "  - Macaroon secret: [generated - 32 chars]"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Review .SECRETS_ENV and update the domain if needed"
echo "  2. Load secrets: source .SECRETS_ENV"
echo "  3. Deploy: terraform apply"
echo ""
echo -e "${RED}IMPORTANT: .SECRETS_ENV contains sensitive data!${NC}"
echo "  - Never commit it to version control"
echo "  - Store a backup in a secure location"
echo "  - Use different secrets for each environment"
echo ""
