# Matrix Synapse + Element on AWS EKS

This Terraform configuration deploys a complete Matrix homeserver (Synapse) and Element web client on AWS EKS with self-managed EC2 worker nodes.

## Architecture Overview

- **EKS Cluster**: Kubernetes 1.28 control plane
- **Worker Nodes**: 2x t3.small EC2 instances (2 vCPU, 2GB RAM each)
- **Networking**: Multi-AZ VPC with public/private subnets
- **Applications**:
  - Matrix Synapse (homeserver)
  - Element Web (client)
  - PostgreSQL (database)

## Instance Size Rationale

**t3.small** is the smallest viable instance type for this setup:

- **2 vCPU, 2GB RAM** per instance
- Kubernetes system components: ~400MB
- Synapse: ~1GB RAM
- Element: ~256MB RAM
- PostgreSQL: ~512MB RAM
- Total: ~2.2GB across 2 nodes with pod distribution

Smaller instances (t3.micro with 1GB) would cause OOM issues.

## Configuration Choices

### Best Practices Followed

✓ Multi-AZ deployment for high availability
✓ Private subnets for worker nodes (security)
✓ Separate public/private subnet architecture
✓ NAT gateways for secure outbound access
✓ EBS encryption enabled
✓ IMDSv2 required on EC2 instances
✓ Control plane logging enabled
✓ Resource limits on all pods
✓ Health checks for all services
✓ Kubernetes namespaces for isolation

### Deviations (with reasons)

⚠ **Self-managed nodes** instead of managed node groups

- Reason: Explicit control over exact instance count (2 as requested)
  
⚠ **Public cluster endpoint** enabled

- Reason: Easier management for dev/demo
- Production: Restrict to VPN/bastion access
  
⚠ **PostgreSQL in-cluster** instead of RDS

- Reason: Cost optimization for dev/demo
- Production: Use RDS for managed backups and HA
  
⚠ **EmptyDir volumes** instead of EBS PersistentVolumes

- Reason: Simplified demo setup
- Production: Use EBS volumes with snapshots
  
⚠ **LoadBalancer services** without SSL/TLS

- Reason: Simplified initial setup
- Production: Use Ingress with cert-manager for HTTPS

### Security Features Implemented

✓ **AWS SSM Parameter Store** for secrets management with KMS encryption
✓ **IAM least privilege** for secret access
✓ **Secret validation** in Terraform
✓ **Audit logging** via CloudTrail
✓ **No hardcoded secrets** in code or version control

## Prerequisites

1. **AWS CLI** configured with appropriate credentials

   ```bash
   aws configure
   ```

2. **Terraform** >= 1.0

   ```bash
   terraform version
   ```

3. **kubectl** for Kubernetes management

   ```bash
   kubectl version --client
   ```

4. **IAM Permissions**: Your AWS user/role needs permissions to create:
   - VPC, subnets, route tables, NAT gateways
   - EKS clusters
   - EC2 instances, security groups, launch templates
   - IAM roles and policies
   - ELB load balancers

## Deployment Steps

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Configure Variables

Copy the example variables file and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your preferences:

```hcl
aws_region       = "us-east-1"
cluster_name     = "matrix-eks-cluster"
environment      = "dev"
instance_type    = "t3.small"
desired_capacity = 2
```

### 3. Configure Secrets

**IMPORTANT**: Set up secrets before deploying!

```bash
# Copy the example secrets file
cp .SECRETS_ENV.example .SECRETS_ENV

# Edit .SECRETS_ENV with your actual secrets
# Generate strong passwords using: openssl rand -base64 32
nano .SECRETS_ENV

# Load secrets into environment
source .SECRETS_ENV
```

See [SECRETS_MANAGEMENT.md](./SECRETS_MANAGEMENT.md) for detailed information about secrets management, best practices, and alternative approaches.

### 4. Review the Plan

```bash
terraform plan
```

Review the resources that will be created (~60 resources including SSM parameters).

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 15-20 minutes.

### 6. Configure kubectl

After deployment completes, configure kubectl to access your cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name matrix-eks-cluster
```

Verify connectivity:

```bash
kubectl get nodes
kubectl get pods -n matrix
```

### 7. Access the Applications

Get the LoadBalancer URLs:

```bash
# Synapse homeserver
kubectl get svc synapse -n matrix -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Element web client
kubectl get svc element -n matrix -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Wait a few minutes for the LoadBalancers to provision, then access:

- **Element**: http://[element-lb-hostname]
- **Synapse**: http://[synapse-lb-hostname]:8008

## Post-Deployment Configuration

### Create Synapse Admin User

```bash
# Get the Synapse pod name
SYNAPSE_POD=$(kubectl get pod -n matrix -l app=synapse -o jsonpath='{.items[0].metadata.name}')

# Create admin user
kubectl exec -n matrix $SYNAPSE_POD -- register_new_matrix_user \
  -u admin \
  -p your_password \
  -a \
  -c /data/homeserver.yaml \
  http://localhost:8008
```

### Configure Element to Use Your Synapse

Element needs to be configured to point to your Synapse homeserver. You can:

1. Use the Element UI to specify your homeserver URL
2. Or create a custom Element config (requires rebuilding the container)

## Monitoring and Troubleshooting

### Check Cluster Status

```bash
kubectl get nodes
kubectl cluster-info
```

### Check Application Logs

```bash
# Synapse logs
kubectl logs -n matrix -l app=synapse -f

# Element logs
kubectl logs -n matrix -l app=element -f

# PostgreSQL logs
kubectl logs -n matrix -l app=postgres -f
```

### Check Pod Status

```bash
kubectl get pods -n matrix
kubectl describe pod -n matrix [pod-name]
```

### Common Issues

**Pods stuck in Pending**: Check if nodes are ready

```bash
kubectl get nodes
kubectl describe node [node-name]
```

**OOM errors**: Increase instance size or reduce resource requests

```bash
kubectl top pods -n matrix
```

**LoadBalancer not accessible**: Check security groups

```bash
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=*matrix*"
```

## Cost Estimation

Approximate monthly costs (us-east-1):

- **EKS Control Plane**: $73/month
- **2x t3.small instances**: ~$30/month
- **2x NAT Gateways**: ~$65/month
- **EBS volumes**: ~$4/month
- **Load Balancers**: ~$33/month
- **Data transfer**: Variable

**Total**: ~$205/month

### Cost Optimization Tips

- Use single NAT gateway for dev: ~$32/month savings
- Use t3.micro for very light workloads (may cause issues)
- Stop cluster when not in use
- Use Fargate instead of EC2 (different pricing model)

## Scaling

### Scale Worker Nodes

```bash
# Via Terraform
# Edit terraform.tfvars: desired_capacity = 3
terraform apply

# Or via AWS CLI
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name matrix-eks-cluster-worker-asg \
  --desired-capacity 3
```

### Scale Application Pods

```bash
kubectl scale deployment synapse -n matrix --replicas=2
kubectl scale deployment element -n matrix --replicas=2
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

Type `yes` when prompted. This will delete:

- All Kubernetes resources
- EKS cluster
- EC2 instances
- VPC and networking components
- IAM roles

**Note**: Ensure LoadBalancers are deleted before destroying (Terraform should handle this).

## Security Hardening for Production

1. **Migrate to AWS Secrets Manager** with automatic rotation
2. **Enable private cluster endpoint only**
3. **Implement network policies** in Kubernetes
4. **Add WAF** in front of LoadBalancers
5. **Enable Pod Security Standards**
6. **Use RDS** with encryption and automated backups
7. **Implement HTTPS** with ACM certificates
8. **Enable VPC Flow Logs** for network monitoring
9. **Implement RBAC** for Kubernetes access control
10. **Set up secret rotation schedule**

See [SECRETS_MANAGEMENT.md](./SECRETS_MANAGEMENT.md) for detailed security recommendations.

## Future Improvements

- [ ] Migrate to AWS Secrets Manager for production (see SECRETS_COMPARISON.md)
- [ ] Implement automatic secret rotation
- [ ] Add Ingress controller (nginx/ALB) with TLS
- [ ] Implement horizontal pod autoscaling
- [ ] Add Prometheus/Grafana monitoring
- [ ] Use Helm charts for easier management
- [ ] Implement GitOps with ArgoCD/Flux
- [ ] Add backup solution for PostgreSQL
- [ ] Implement disaster recovery procedures
- [ ] Add CI/CD pipeline integration
- [ ] Use EFS for shared persistent storage
- [ ] Implement multi-region deployment

## Documentation

- [README.md](./README.md) - Main documentation
- [SECRETS_MANAGEMENT.md](./SECRETS_MANAGEMENT.md) - Comprehensive secrets management guide
- [SECRETS_COMPARISON.md](./SECRETS_COMPARISON.md) - Comparison of different secrets management approaches
- [QUICKSTART_SECRETS.md](./QUICKSTART_SECRETS.md) - Quick reference for secrets setup
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Architecture overview
- [QUICKSTART.md](./QUICKSTART.md) - Quick start guide

## Support

For issues with:

- **Terraform**: Check AWS provider documentation
- **EKS**: AWS EKS documentation
- **Matrix Synapse**: <https://matrix-org.github.io/synapse/>
- **Element**: <https://element.io/help>

## License

This configuration is provided as-is for educational and demonstration purposes.
