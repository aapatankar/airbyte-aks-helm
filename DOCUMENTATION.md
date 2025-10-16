# Airbyte on Azure Kubernetes Service (AKS) - Complete Documentation

> **Production-Ready Helm Chart for Airbyte 2.0 on Azure Kubernetes Service**

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Security](#security)
7. [Performance Optimization](#performance-optimization)
8. [Testing](#testing)
9. [Deployment Checklist](#deployment-checklist)
10. [Monitoring & Maintenance](#monitoring--maintenance)
11. [Troubleshooting](#troubleshooting)
12. [Advanced Features](#advanced-features)

---

## Overview

This Helm chart deploys **Airbyte 2.0** on Azure Kubernetes Service (AKS) with enterprise-grade features, Azure-native integrations, and production-ready configurations.

### 🎯 Key Features

- **Production-Ready**: High availability, auto-scaling, and comprehensive monitoring
- **Azure Native**: Integrates with Azure Database, Blob Storage, Key Vault, and Workload Identity
- **Security Focused**: Network policies, RBAC, pod security standards, and secrets management
- **Multi-Environment**: Separate configurations for development, staging, and production
- **Automated**: Complete automation for Azure resource creation and deployment
- **Comprehensive Testing**: Health checks, validation, and testing frameworks
- **Backup & Recovery**: Automated backup solutions with retention policies
- **96-Hour Heartbeat**: Extended timeout for long-running sync operations

### Latest Updates

- **Helm Chart V2**: Updated to use Airbyte chart version 2.0.18 with app version 2.0.0
- **Extended Heartbeat**: 96-hour timeout (345,600 seconds) for long-running operations
- **Enhanced Security**: Comprehensive security hardening and best practices
- **Azure Integration**: Full integration with Azure services for enterprise deployment

---

## Quick Start

### Development Setup (5 minutes)

```bash
# 1. Clone the repository
git clone <repository-url>
cd airbyte-aks-helm

# 2. Quick deploy to development
./deploy.sh install -e development

# 3. Access Airbyte
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80
# Open http://localhost:8080
```

### Production Setup (30 minutes)

```bash
# 1. Set up Azure resources
export RESOURCE_GROUP="airbyte-prod-rg"
export AKS_CLUSTER="airbyte-prod-aks"
./setup-azure.sh --create-all

# 2. Deploy to production
./deploy.sh install -e production

# 3. Verify deployment
./health-check.sh
```

---

## Prerequisites

### Required Tools
- **Azure CLI**: Latest version, logged in to your subscription
- **kubectl**: Configured to connect to your AKS cluster
- **Helm 3.x**: Version 3.8 or later
- **Git**: For cloning the repository

### Azure Resources

#### Required for Production
1. **Azure Kubernetes Service (AKS)**
   - Azure CNI networking
   - Azure Key Vault CSI driver add-on
   - Azure Workload Identity enabled
   - System-assigned managed identity

2. **Azure Database for PostgreSQL Flexible Server**
   - SKU: Standard_D2ds_v4 or higher
   - Storage: 128GB+ with auto-grow enabled
   - SSL enforcement enabled

3. **Azure Storage Account**
   - Standard_LRS or Premium_LRS
   - Containers: `airbyte-logs`, `airbyte-state`, `airbyte-workload-output`, `airbyte-activity-payload`

4. **Azure Key Vault**
   - Soft delete enabled
   - Purge protection enabled (recommended)

#### Optional but Recommended
- **Azure Container Registry**: For custom images
- **Azure Application Gateway**: For ingress with WAF
- **Azure Monitor**: For centralized logging and monitoring
- **Azure DNS**: For custom domain management

---

## Installation

### Automated Installation

#### Option 1: One-Command Deploy
```bash
# Development environment
./deploy.sh install -e development

# Production environment with Azure setup
./setup-azure.sh --create-all && ./deploy.sh install -e production
```

#### Option 2: Step-by-Step Installation

1. **Prepare Azure Resources**
   ```bash
   # Customize these values
   export RESOURCE_GROUP="airbyte-rg"
   export AKS_CLUSTER="airbyte-aks"
   export POSTGRES_SERVER="airbyte-postgres"
   export STORAGE_ACCOUNT="airbytestore$(date +%s)"
   export KEY_VAULT="airbyte-kv-$(date +%s)"

   # Create resources
   ./setup-azure.sh \
     -g "$RESOURCE_GROUP" \
     -c "$AKS_CLUSTER" \
     -p "$POSTGRES_SERVER" \
     -s "$STORAGE_ACCOUNT" \
     -k "$KEY_VAULT" \
     --create-all
   ```

2. **Install Helm Chart**
   ```bash
   # Add Airbyte repository
   helm repo add airbyte https://airbytehq.github.io/charts
   helm repo update

   # Install chart
   helm install airbyte . \
     --namespace airbyte \
     --create-namespace \
     --values values-production.yaml
   ```

3. **Verify Installation**
   ```bash
   # Check deployment status
   kubectl get pods -n airbyte
   
   # Run health checks
   ./health-check.sh
   ```

### Manual Installation

If you prefer manual setup:

1. **Create Namespace**
   ```bash
   kubectl create namespace airbyte
   ```

2. **Create Secrets**
   ```bash
   kubectl create secret generic airbyte-config-secrets \
     --from-literal=database-user='airbyte_user' \
     --from-literal=database-password='your-secure-password' \
     --from-literal=azure-storage-key='your-storage-key' \
     --namespace airbyte
   ```

3. **Deploy Chart**
   ```bash
   helm install airbyte . --namespace airbyte --values values-production.yaml
   ```

---

## Configuration

### Environment-Specific Values

#### Development (`values-development.yaml`)
- Single replica for most components
- Resource limits optimized for local development
- In-memory database option available
- Debug logging enabled

#### Production (`values-production.yaml`)
- High availability with multiple replicas
- Production resource limits and requests
- External PostgreSQL database required
- Azure integrations enabled
- Monitoring and alerting configured

### Key Configuration Sections

#### Database Configuration
```yaml
postgresql:
  enabled: false  # Use external Azure PostgreSQL

externalDatabase:
  host: "your-postgres-server.postgres.database.azure.com"
  port: 5432
  database: "airbyte"
  user: "airbyte_user"
  existingSecret: "airbyte-config-secrets"
  existingSecretPasswordKey: "database-password"
```

#### Storage Configuration
```yaml
global:
  storage:
    type: "azure"
    azure:
      storageAccountName: "your-storage-account"
      containerName: "airbyte-logs"
      existingSecret: "airbyte-config-secrets"
      existingSecretKey: "azure-storage-key"
```

#### Ingress Configuration
```yaml
ingress:
  enabled: true
  className: "azure-application-gateway"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: airbyte.yourdomain.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: airbyte-tls
      hosts:
        - airbyte.yourdomain.com
```

#### Heartbeat Configuration (96 Hours)
```yaml
# Extended heartbeat timeout for long-running syncs
global:
  env_vars:
    HEARTBEAT_MAX_SECONDS_BETWEEN_MESSAGES: "345600"  # 96 hours
    HEARTBEAT_FAIL_SYNC: "true"
```

---

## Security

### Infrastructure Security

#### AKS Cluster Security
```bash
# Create secure AKS cluster
az aks create \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-private-cluster \
  --network-plugin azure \
  --network-policy calico \
  --enable-managed-identity \
  --enable-azure-rbac \
  --enable-encryption-at-host \
  --enable-workload-identity \
  --enable-oidc-issuer
```

#### Network Security
- **Network Policies**: Pod-to-pod communication control
- **Private Endpoints**: For database and storage access
- **Ingress Security**: WAF protection via Application Gateway

#### Authentication & Authorization
- **Azure Workload Identity**: Passwordless authentication to Azure services
- **RBAC**: Minimal permissions principle
- **Pod Security Standards**: Security contexts and constraints

#### Secrets Management
- **Azure Key Vault**: Centralized secrets storage
- **CSI Driver**: Secure secret mounting
- **Rotation**: Automated secret rotation capabilities

### Security Checklist

- [ ] Enable private AKS cluster
- [ ] Configure network policies
- [ ] Set up Azure Key Vault integration
- [ ] Enable Azure Workload Identity
- [ ] Configure pod security standards
- [ ] Set up private endpoints for Azure services
- [ ] Enable Azure Defender for Kubernetes
- [ ] Configure SSL/TLS for all communications
- [ ] Implement backup encryption
- [ ] Set up monitoring and alerting

---

## Performance Optimization

### Infrastructure Optimization

#### Node Pool Configuration
```bash
# Optimized node pools for Airbyte workloads
az aks nodepool add \
  --resource-group myResourceGroup \
  --cluster-name myAKSCluster \
  --name airbyte-workers \
  --node-count 3 \
  --min-count 2 \
  --max-count 10 \
  --enable-cluster-autoscaler \
  --node-vm-size Standard_D4s_v3 \
  --os-disk-size-gb 100 \
  --os-disk-type Premium_LRS
```

#### Database Performance
```bash
# PostgreSQL optimization
az postgres flexible-server parameter set \
  --resource-group myResourceGroup \
  --server-name myPostgreSQLServer \
  --name shared_preload_libraries \
  --value 'pg_stat_statements'

az postgres flexible-server parameter set \
  --name max_connections \
  --value 200
```

### Application Optimization

#### Resource Allocation
```yaml
# Optimized resource allocation
worker:
  replicaCount: 3
  resources:
    requests:
      cpu: "1000m"
      memory: "2Gi"
    limits:
      cpu: "2000m"
      memory: "4Gi"

server:
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
```

#### Auto-scaling Configuration
```yaml
# Horizontal Pod Autoscaler
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

---

## Testing

### Automated Testing

#### Chart Validation
```bash
# Lint the chart
helm lint . --values values-development.yaml
helm lint . --values values-production.yaml

# Template validation
helm template airbyte . --values values-production.yaml --output-dir ./test-output

# Schema validation
./validate-chart.sh
```

#### Integration Testing
```bash
# Test deployment
./test-chart.sh --environment development

# Health checks
./health-check.sh --verbose

# Performance testing
kubectl run -it --rm load-test --image=busybox --restart=Never -- /bin/sh
```

### Manual Testing

#### Connectivity Tests
```bash
# Test database connectivity
kubectl exec -it deployment/airbyte-server -n airbyte -- \
  psql -h your-postgres-server.postgres.database.azure.com -U airbyte_user -d airbyte

# Test storage connectivity
kubectl exec -it deployment/airbyte-server -n airbyte -- \
  az storage blob list --account-name your-storage-account --container-name airbyte-logs
```

#### Functional Tests
1. **Web UI Access**: Verify Airbyte web interface loads correctly
2. **Connection Creation**: Test creating source and destination connections
3. **Sync Execution**: Run a test sync operation
4. **Log Collection**: Verify logs are stored in Azure Blob Storage
5. **Backup Verification**: Confirm automated backups are working

---

## Deployment Checklist

### Pre-Deployment

#### Azure Resources
- [ ] Azure subscription with sufficient quotas
- [ ] Resource group created
- [ ] AKS cluster provisioned with required features
- [ ] Azure Database for PostgreSQL created
- [ ] Azure Storage Account with containers
- [ ] Azure Key Vault with secrets
- [ ] DNS configuration (if using custom domain)
- [ ] SSL certificates (if using HTTPS)

#### Local Setup
- [ ] kubectl configured and connected
- [ ] Helm 3.x installed
- [ ] Azure CLI logged in
- [ ] Repository cloned and configured

### Deployment Steps

1. **Environment Setup**
   ```bash
   ./setup-azure.sh --create-all
   ```

2. **Chart Installation**
   ```bash
   ./deploy.sh install -e production
   ```

3. **Post-Deployment Verification**
   ```bash
   ./health-check.sh
   ```

### Post-Deployment

- [ ] Verify all pods are running
- [ ] Test web UI accessibility
- [ ] Confirm database connectivity
- [ ] Validate storage integration
- [ ] Check monitoring and logging
- [ ] Test backup functionality
- [ ] Verify security configurations
- [ ] Document access credentials
- [ ] Set up monitoring alerts

---

## Monitoring & Maintenance

### Health Monitoring

#### Automated Health Checks
```bash
# Run comprehensive health check
./health-check.sh --all

# Component-specific checks
./health-check.sh --component webapp
./health-check.sh --component server
./health-check.sh --component worker
```

#### Monitoring Integration
- **Azure Monitor**: Centralized logging and metrics
- **Prometheus**: Application metrics collection
- **Grafana**: Monitoring dashboards
- **Azure Application Insights**: APM and performance monitoring

### Backup & Recovery

#### Automated Backups
```yaml
# Backup CronJob configuration
backup:
  enabled: true
  schedule: "0 2 * * *"  # Daily at 2 AM
  retention: "7d"
  storageClass: "managed-premium"
```

#### Backup Verification
```bash
# Verify backup job
kubectl get cronjobs -n airbyte
kubectl logs -l job-name=airbyte-backup -n airbyte
```

### Maintenance Tasks

#### Regular Maintenance
- **Weekly**: Review resource utilization and scaling
- **Monthly**: Update Helm chart and security patches
- **Quarterly**: Review and rotate secrets
- **Annually**: Review and update disaster recovery procedures

#### Upgrade Procedures
```bash
# Backup current state
./migrate.sh backup

# Upgrade chart
helm upgrade airbyte . --values values-production.yaml

# Verify upgrade
./health-check.sh

# Rollback if needed
helm rollback airbyte
```

---

## Troubleshooting

### Common Issues

#### Pod Startup Issues
```bash
# Check pod status
kubectl get pods -n airbyte

# View pod logs
kubectl logs -f deployment/airbyte-server -n airbyte

# Describe pod for events
kubectl describe pod <pod-name> -n airbyte
```

#### Database Connection Issues
```bash
# Test database connectivity
kubectl exec -it deployment/airbyte-server -n airbyte -- \
  nc -zv your-postgres-server.postgres.database.azure.com 5432
```

#### Storage Issues
```bash
# Check storage account connectivity
kubectl exec -it deployment/airbyte-server -n airbyte -- \
  curl -I "https://your-storage-account.blob.core.windows.net/airbyte-logs"
```

### Debug Commands

#### Resource Investigation
```bash
# Check resource usage
kubectl top pods -n airbyte
kubectl top nodes

# View events
kubectl get events -n airbyte --sort-by=.metadata.creationTimestamp
```

#### Network Debugging
```bash
# Test internal connectivity
kubectl exec -it deployment/airbyte-webapp -n airbyte -- \
  curl -I http://airbyte-server:8001/api/v1/health
```

---

## Advanced Features

### Custom Resource Management

#### Resource Constraints
```yaml
# Custom resource constraints template
resources:
  requests:
    cpu: "{{ .Values.resources.requests.cpu }}"
    memory: "{{ .Values.resources.requests.memory }}"
  limits:
    cpu: "{{ .Values.resources.limits.cpu }}"
    memory: "{{ .Values.resources.limits.memory }}"
```

#### Horizontal Pod Autoscaler
```yaml
# Advanced HPA configuration
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80
```

### Azure Workload Identity Integration

```yaml
# Workload Identity configuration
azure:
  workloadIdentity:
    enabled: true
    clientId: "your-managed-identity-client-id"
    tenantId: "your-tenant-id"
```

### Development Tools

#### Local Development
```yaml
# Development tools configuration
development:
  enabled: true
  tools:
    - name: "kubectl-debug"
    - name: "helm-unittest"
    - name: "azure-cli"
```

---

## Project Structure

```
airbyte-aks-helm/
├── Chart.yaml                    # Helm chart metadata (v2.0.0, app v2.0.0)
├── Chart.lock                    # Dependency lock file
├── values.yaml                   # Default values
├── values-development.yaml       # Development environment
├── values-production.yaml        # Production environment
├── DOCUMENTATION.md              # This consolidated documentation
├── deploy.sh                     # Main deployment script
├── setup-azure.sh               # Azure resource setup
├── health-check.sh              # Health monitoring script
├── migrate.sh                    # Migration and backup script
├── test-chart.sh                # Testing framework
├── validate-chart.sh            # Chart validation
├── charts/                       # Chart dependencies
│   ├── airbyte-2.0.18.tgz       # Airbyte chart (v2.0.18)
│   └── airbyte/                  # Extracted chart
├── templates/                    # Kubernetes templates
│   ├── _helpers.tpl              # Template helpers
│   ├── serviceaccount.yaml       # Service account with Workload Identity
│   ├── networkpolicy.yaml        # Network security policies
│   ├── secretproviderclass.yaml  # Azure Key Vault CSI driver
│   ├── monitoring-configmap.yaml # Monitoring configuration
│   ├── backup-cronjob.yaml       # Automated backup job
│   ├── flags-configmap.yaml      # Airbyte feature flags (96h heartbeat)
│   ├── hpa.yaml                  # Horizontal Pod Autoscaler
│   ├── resource-constraints.yaml # Resource management
│   └── development-tools.yaml    # Development utilities
└── .github/                      # GitHub Actions workflows
    └── workflows/
        └── ci.yml                # CI/CD pipeline
```

---

## Support & Contribution

### Getting Help
- **Issues**: Create GitHub issues for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Documentation**: Refer to official Airbyte documentation

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### License
This project is licensed under the MIT License. See LICENSE file for details.

---

**Ready for Production Deployment** ✨

This comprehensive Helm chart provides everything needed for a production-ready Airbyte deployment on Azure Kubernetes Service with enterprise features, security hardening, and operational excellence.
