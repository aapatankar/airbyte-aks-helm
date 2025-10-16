# Airbyte AKS Helm Chart - Quick Start Guide

This guide will help you quickly deploy Airbyte to Azure Kubernetes Service (AKS) using our Helm chart.

## Prerequisites

- Azure CLI installed and logged in
- kubectl installed
- Helm 3.x installed
- An Azure subscription with appropriate permissions

## Quick Deploy (Development)

For a quick development setup:

```bash
# 1. Clone or navigate to the chart directory
cd airbyte-aks-helm

# 2. Deploy everything with one command
./deploy.sh install -e development

# 3. Access Airbyte
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80
# Open http://localhost:8080 in your browser
```

## Production Setup

### Step 1: Set up Azure Resources

```bash
# Set your configuration
export RESOURCE_GROUP="airbyte-prod-rg"
export AKS_CLUSTER="airbyte-prod-aks"
export POSTGRES_SERVER="airbyte-prod-postgres"
export STORAGE_ACCOUNT="airbyteprodstorage"  # Must be globally unique
export KEY_VAULT="airbyte-prod-kv"

# Create all Azure resources
./setup-azure.sh \
  -g "$RESOURCE_GROUP" \
  -c "$AKS_CLUSTER" \
  -p "$POSTGRES_SERVER" \
  -s "$STORAGE_ACCOUNT" \
  -k "$KEY_VAULT" \
  --create-all
```

### Step 2: Configure Secrets

```bash
# Create Kubernetes secrets with your actual values
kubectl create secret generic airbyte-config-secrets \
  --from-literal=database-user='airbyte_admin' \
  --from-literal=database-password='YOUR_DB_PASSWORD' \
  --from-literal=azure-storage-key='YOUR_STORAGE_KEY' \
  --from-literal=azure-client-secret='YOUR_CLIENT_SECRET' \
  --namespace=airbyte
```

### Step 3: Update Configuration

Edit `values-production.yaml` with your specific values:

```yaml
global:
  airbyteUrl: "https://airbyte.yourdomain.com"
  database:
    host: "airbyte-prod-postgres.postgres.database.azure.com"
  storage:
    azure:
      storageAccountName: "airbyteprodstorage"
  secretsManager:
    azureKeyVault:
      vaultUrl: "https://airbyte-prod-kv.vault.azure.net/"
      tenantId: "your-tenant-id"
      clientId: "your-client-id"
```

### Step 4: Deploy to Production

```bash
./deploy.sh install -e production --wait
```

## Common Commands

```bash
# Check deployment status
./deploy.sh status

# Upgrade deployment
./deploy.sh upgrade -e production

# Create backup
./deploy.sh backup

# Validate configuration
./deploy.sh validate -e production

# Access logs
kubectl logs -n airbyte -l app.kubernetes.io/component=server

# Port forward for testing
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80
```

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n airbyte
kubectl describe pod <pod-name> -n airbyte
```

### Check Logs
```bash
kubectl logs -n airbyte deployment/airbyte-server
kubectl logs -n airbyte deployment/airbyte-worker
```

### Verify Configuration
```bash
helm get values airbyte -n airbyte
kubectl get secrets -n airbyte
kubectl get configmaps -n airbyte
```

## Next Steps

1. **Configure DNS**: Point your domain to the ingress load balancer
2. **Set up SSL**: The chart includes cert-manager integration for Let's Encrypt
3. **Configure monitoring**: Enable Azure Monitor integration
4. **Set up backups**: Configure automated database backups
5. **Review security**: Ensure network policies and RBAC are properly configured

For detailed configuration options, see the main [README.md](README.md).
