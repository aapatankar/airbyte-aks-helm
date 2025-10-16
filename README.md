# Airbyte on Azure Kubernetes Service (AKS) - Helm Chart

> **Production-Ready Helm Chart for Airbyte 2.0 on Azure Kubernetes Service**

[![Helm Version](https://img.shields.io/badge/Helm-v3.8+-blue.svg)](https://helm.sh/)
[![Airbyte Version](https://img.shields.io/badge/Airbyte-v2.0.0-green.svg)](https://airbyte.com/)
[![Azure AKS](https://img.shields.io/badge/Azure-AKS-0078d4.svg)](https://azure.microsoft.com/en-us/services/kubernetes-service/)

## 🚀 Quick Start

### Development Setup (5 minutes)
```bash
# Clone and deploy to development
git clone <repository-url> && cd airbyte-aks-helm
./deploy.sh install -e development

# Access Airbyte
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80
# Open http://localhost:8080
```

### Production Setup (30 minutes)
```bash
# Set up Azure resources and deploy
export RESOURCE_GROUP="airbyte-prod-rg"
./setup-azure.sh --create-all
./deploy.sh install -e production
./health-check.sh
```

## 📖 Complete Documentation

For comprehensive documentation, see **[DOCUMENTATION.md](./DOCUMENTATION.md)** which includes:

- **Installation Guide** - Step-by-step setup instructions
- **Configuration** - Environment-specific configurations
- **Security** - Security hardening and best practices  
- **Performance** - Optimization strategies
- **Testing** - Testing procedures and validation
- **Troubleshooting** - Common issues and solutions
- **Advanced Features** - Enterprise features and integrations

## ✨ Key Features

- **🏗️ Production-Ready**: HA, auto-scaling, monitoring, backup & recovery
- **☁️ Azure Native**: Database, Storage, Key Vault, Workload Identity integration  
- **🔒 Security Focused**: Network policies, RBAC, pod security standards
- **🎯 Multi-Environment**: Development, staging, and production configurations
- **🤖 Automated**: Complete Azure setup and deployment automation
- **📊 Observability**: Health checks, monitoring, and alerting
- **⏱️ Extended Operations**: 96-hour heartbeat timeout for long-running syncs

## 🏗️ Architecture

```
Azure Subscription
├── AKS Cluster (Private)
│   ├── Airbyte Components (Auto-scaled)
│   ├── Network Policies
│   └── Workload Identity
├── Azure Database for PostgreSQL
├── Azure Blob Storage
├── Azure Key Vault
└── Azure Monitor
```

## 📋 Prerequisites

- **Azure CLI** - Latest version
- **kubectl** - Configured for your AKS cluster  
- **Helm 3.8+** - Package manager
- **Azure Subscription** - With appropriate permissions

## 🎯 What's Included

| Component | Description |
|-----------|-------------|
| **Helm Chart** | Production-ready chart with Airbyte 2.0.0 |
| **Azure Integration** | Database, Storage, Key Vault, Workload Identity |
| **Security** | Network policies, RBAC, pod security standards |
| **Automation** | Deployment scripts, Azure setup, health checks |
| **Monitoring** | Azure Monitor, Prometheus metrics, health checks |
| **Backup** | Automated PostgreSQL backups with retention |

## 🔧 Quick Commands

```bash
# Health check
./health-check.sh

# Upgrade deployment  
./deploy.sh upgrade -e production

# Backup database
./migrate.sh backup

# Test chart
./test-chart.sh --environment development
```

## 📞 Support

- **📖 Documentation**: See [DOCUMENTATION.md](./DOCUMENTATION.md)
- **🐛 Issues**: Create GitHub issues for bugs
- **💬 Discussions**: Use GitHub Discussions for questions  
- **🔗 Airbyte Docs**: [Official Documentation](https://docs.airbyte.com/)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
  --namespace airbyte \
  --values values.yaml
```

## Configuration

### Basic Configuration

Update the `values.yaml` file with your specific configuration:

```yaml
global:
  airbyteUrl: "https://airbyte.yourdomain.com"
  database:
    host: "your-postgres-server.postgres.database.azure.com"
  storage:
    azure:
      storageAccountName: "yourstorageaccount"
```

### Azure Database for PostgreSQL

1. Create an Azure Database for PostgreSQL server
2. Create a database named `airbyte`
3. Create a user and grant permissions:

```sql
CREATE USER airbyte_user WITH PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE airbyte TO airbyte_user;
```

4. Update the values.yaml:

```yaml
global:
  database:
    type: external
    host: "your-postgres-server.postgres.database.azure.com"
    port: "5432"
    name: "airbyte"
    sslMode: "require"
```

### Azure Storage Account

1. Create an Azure Storage Account
2. Create containers for:
   - `airbyte-logs`
   - `airbyte-state`
   - `airbyte-workload-output`
   - `airbyte-activity-payload`

3. Update values.yaml:

```yaml
global:
  storage:
    type: "azure"
    azure:
      storageAccountName: "yourstorageaccount"
      containerName: "airbyte"
```

### Ingress Configuration

#### Option 1: NGINX Ingress Controller

```bash
# Install NGINX Ingress Controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

#### Option 2: Azure Application Gateway Ingress Controller (AGIC)

```yaml
ingress:
  className: "azure-application-gateway"
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
```

### SSL/TLS Configuration

#### Using cert-manager with Let's Encrypt

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

Create a ClusterIssuer:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

Update ingress annotations:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

### Azure Workload Identity (Recommended)

1. Enable OIDC Issuer on your AKS cluster:

```bash
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-oidc-issuer \
  --enable-workload-identity
```

2. Create Azure AD Application and Federated Identity Credential
3. Assign necessary permissions (Key Vault, Storage, etc.)
4. Update values.yaml:

```yaml
security:
  serviceAccount:
    annotations:
      azure.workload.identity/client-id: "your-client-id"

azure:
  workloadIdentity:
    enabled: true
```

### Monitoring with Azure Monitor

```yaml
monitoring:
  azureMonitor:
    enabled: true
    workspaceId: "your-log-analytics-workspace-id"
```

## Scaling and High Availability

### Horizontal Pod Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### Multiple Replicas

```yaml
highAvailability:
  enabled: true
  replicaCount:
    server: 2
    worker: 3
    workloadLauncher: 2
```

## Security Best Practices

### Network Policies

```yaml
security:
  networkPolicies:
    enabled: true
```

### Pod Security Standards

```yaml
security:
  podSecurityStandards:
    enabled: true
```

### Azure Key Vault Integration

```yaml
global:
  secretsManager:
    type: "AZURE_KEY_VAULT"
    azureKeyVault:
      vaultUrl: "https://your-keyvault.vault.azure.net/"
      tenantId: "your-tenant-id"
      clientId: "your-client-id"
```

## Backup and Disaster Recovery

### Database Backup

Configure automated backups for Azure Database for PostgreSQL:

```bash
az postgres server configuration set \
  --resource-group myResourceGroup \
  --server-name myserver \
  --name backup_retention_days \
  --value 35
```

### Application Backup

```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"  # Daily at 2 AM
  retention: "30d"
```

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n airbyte
kubectl describe pod <pod-name> -n airbyte
kubectl logs <pod-name> -n airbyte
```

### Check Ingress

```bash
kubectl get ingress -n airbyte
kubectl describe ingress airbyte-ingress -n airbyte
```

### Check Secrets

```bash
kubectl get secrets -n airbyte
kubectl describe secret airbyte-config-secrets -n airbyte
```

### Common Issues

1. **Database Connection Issues**
   - Verify PostgreSQL server firewall rules
   - Check SSL certificate configuration
   - Verify user permissions

2. **Storage Access Issues**
   - Verify Azure Storage Account access keys
   - Check container permissions
   - Verify Azure Workload Identity configuration

3. **Ingress Issues**
   - Verify DNS configuration
   - Check SSL certificate status
   - Verify ingress controller logs

## Upgrading

```bash
# Update Helm repository
helm repo update

# Upgrade Airbyte
helm upgrade airbyte ./airbyte-aks-helm \
  --namespace airbyte \
  --values values.yaml
```

## Uninstalling

```bash
helm uninstall airbyte --namespace airbyte
kubectl delete namespace airbyte
```

## Production Considerations

1. **Use external PostgreSQL database** for data persistence
2. **Configure proper resource limits** based on your workload
3. **Set up monitoring and alerting**
4. **Implement proper backup strategy**
5. **Use Azure Workload Identity** for secure access to Azure resources
6. **Configure network policies** for security
7. **Set up proper SSL/TLS certificates**
8. **Consider using Azure Application Gateway** for advanced routing

## Support

For issues and questions:
1. Check the [Airbyte Documentation](https://docs.airbyte.com/)
2. Review AKS best practices
3. Check Azure service health status
4. Review Kubernetes logs and events

## License

This Helm chart is licensed under the same license as Airbyte.
