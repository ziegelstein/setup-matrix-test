#!/bin/bash
# Script to rotate a secret in AWS SSM Parameter Store
# Usage: ./scripts/rotate-secret.sh <parameter-name> [new-value]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}Error: Missing parameter name${NC}"
    echo ""
    echo "Usage: $0 <parameter-name> [new-value]"
    echo ""
    echo "Available parameters:"
    echo "  - postgres_password"
    echo "  - synapse_registration_shared_secret"
    echo "  - synapse_macaroon_secret_key"
    echo ""
    echo "Examples:"
    echo "  $0 postgres_password"
    echo "  $0 postgres_password 'my-new-password'"
    exit 1
fi

PARAM_NAME=$1
NEW_VALUE=$2

# Default values
CLUSTER_NAME="${TF_VAR_cluster_name:-matrix-eks-cluster}"
ENVIRONMENT="${TF_VAR_environment:-dev}"
AWS_REGION="${TF_VAR_aws_region:-us-east-1}"

# Map short names to full SSM paths
case $PARAM_NAME in
    postgres_password)
        SSM_PATH="/${CLUSTER_NAME}/${ENVIRONMENT}/database/postgres_password"
        RESTART_PODS="postgres synapse"
        ;;
    synapse_registration_shared_secret)
        SSM_PATH="/${CLUSTER_NAME}/${ENVIRONMENT}/synapse/registration_shared_secret"
        RESTART_PODS="synapse"
        ;;
    synapse_macaroon_secret_key)
        SSM_PATH="/${CLUSTER_NAME}/${ENVIRONMENT}/synapse/macaroon_secret_key"
        RESTART_PODS="synapse"
        ;;
    *)
        # Assume it's a full path
        SSM_PATH=$PARAM_NAME
        RESTART_PODS=""
        ;;
esac

echo -e "${GREEN}=== Secret Rotation Tool ===${NC}"
echo ""
echo "Parameter: ${SSM_PATH}"
echo "Region: ${AWS_REGION}"
echo ""

# Generate new value if not provided
if [ -z "$NEW_VALUE" ]; then
    echo "Generating new random secret..."
    NEW_VALUE=$(openssl rand -base64 32)
fi

# Confirm rotation
echo -e "${YELLOW}Warning: This will update the secret in AWS SSM Parameter Store${NC}"
read -p "Do you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Update SSM parameter
echo "Updating SSM parameter..."
aws ssm put-parameter \
    --name "${SSM_PATH}" \
    --value "${NEW_VALUE}" \
    --type SecureString \
    --overwrite \
    --region "${AWS_REGION}"

echo -e "${GREEN}✓ Secret updated in SSM Parameter Store${NC}"

# Restart affected pods
if [ -n "$RESTART_PODS" ]; then
    echo ""
    echo "Restarting affected pods..."
    for pod in $RESTART_PODS; do
        echo "  - Restarting ${pod}..."
        kubectl rollout restart deployment/${pod} -n matrix 2>/dev/null || echo "    (deployment not found, skipping)"
    done
    echo -e "${GREEN}✓ Pods restarted${NC}"
fi

echo ""
echo -e "${GREEN}Secret rotation completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Update your local .SECRETS_ENV file if needed"
echo "  2. Monitor pod logs: kubectl logs -n matrix -l app=${RESTART_PODS%% *} -f"
echo "  3. Verify application functionality"
echo ""
