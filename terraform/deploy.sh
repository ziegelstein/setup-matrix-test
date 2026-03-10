#!/bin/bash
# Quick deployment script for Matrix EKS cluster

set -e

echo "=== Matrix Synapse + Element on EKS Deployment ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install Terraform >= 1.0"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install and configure AWS CLI"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl"
    exit 1
fi

echo "✓ All prerequisites found"
echo ""

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Run 'aws configure'"
    exit 1
fi
echo "✓ AWS credentials configured"
echo ""

# Check for terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    echo "⚠ terraform.tfvars not found. Creating from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "✓ Created terraform.tfvars - please review and customize if needed"
    echo ""
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init
echo ""

# Plan
echo "Creating deployment plan..."
terraform plan -out=tfplan
echo ""

# Confirm
read -p "Do you want to proceed with deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

# Apply
echo ""
echo "Deploying infrastructure (this will take 15-20 minutes)..."
terraform apply tfplan
echo ""

# Get cluster name from output
CLUSTER_NAME=$(terraform output -raw cluster_name)
AWS_REGION=$(grep aws_region terraform.tfvars | cut -d'"' -f2 || echo "us-east-1")

# Configure kubectl
echo "Configuring kubectl..."
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
echo ""

# Wait for nodes
echo "Waiting for worker nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo ""

# Check pods
echo "Checking pod status..."
kubectl get pods -n matrix
echo ""

# Get service URLs
echo "=== Deployment Complete ==="
echo ""
echo "Getting service URLs (may take a few minutes for LoadBalancers to provision)..."
echo ""

SYNAPSE_LB=$(kubectl get svc synapse -n matrix -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")
ELEMENT_LB=$(kubectl get svc element -n matrix -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending...")

echo "Synapse Homeserver: http://$SYNAPSE_LB:8008"
echo "Element Web Client: http://$ELEMENT_LB"
echo ""
echo "Note: LoadBalancer URLs may take 2-3 minutes to become active"
echo ""
echo "Next steps:"
echo "1. Wait for all pods to be Running: kubectl get pods -n matrix"
echo "2. Create admin user (see README.md)"
echo "3. Access Element and configure homeserver URL"
echo ""
echo "For more information, see README.md"
