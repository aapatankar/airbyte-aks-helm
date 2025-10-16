# Airbyte AKS Deployment - Complete Helm Chart

This is a comprehensive, production-ready Helm chart for deploying Airbyte to Azure Kubernetes Service (AKS). The chart includes Azure-native integrations, security best practices, monitoring, backup solutions, and both development and production configurations.

## 🎯 Key Features

- **Production-Ready**: Includes high availability, auto-scaling, and monitoring
- **Azure Native**: Integrates with Azure Database for PostgreSQL, Blob Storage, Key Vault, and Workload Identity
- **Security Focused**: Network policies, RBAC, pod security standards, and secrets management
- **Multi-Environment**: Separate configurations for development, staging, and production
- **Automated Scripts**: Complete automation for Azure resource creation and deployment
- **Comprehensive Testing**: Health checks, validation, and testing frameworks
- **Backup & Recovery**: Automated backup solutions with retention policies
- **Monitoring**: Integration with Azure Monitor and Prometheus metrics

## 🎯 Latest Updates

### ✅ **HEARTBEAT TIMEOUT CONFIGURATION COMPLETED** (October 14, 2025)
- **Implemented 96-hour heartbeat timeout** (345,600 seconds) for long-running sync operations
- **Multiple configuration methods** for comprehensive coverage:
  - Airbyte feature flags (`flags.yml`) - primary method
  - Environment variables for all components - fallback method
  - Applied to Server, Worker, Workload Launcher, and Webapp
- **Updated all environment configurations**: Default, Development, and Production
- **Created comprehensive documentation** in `HEARTBEAT_CONFIGURATION.md`
- **Validated implementation** with 9 environment variable instances across components
- **Chart passes all validation tests** with new heartbeat configuration

### Previous Completions

## 📁 Project Structure

```
airbyte-aks-helm/
├── Chart.yaml                    # Helm chart metadata
├── values.yaml                   # Default values
├── values-development.yaml       # Development environment values
├── values-production.yaml        # Production environment values
├── README.md                     # Comprehensive documentation
├── QUICKSTART.md                 # Quick deployment guide
├── TESTING.md                    # Testing documentation
├── .gitignore                    # Git ignore file
├── charts/                       # Chart dependencies
│   └── airbyte-2.0.7.tgz        # Airbyte chart dependency
├── templates/                    # Kubernetes templates
│   ├── _helpers.tpl              # Template helpers
│   ├── serviceaccount.yaml       # Service account with Workload Identity
│   ├── networkpolicy.yaml        # Network security policies
│   ├── secretproviderclass.yaml  # Azure Key Vault CSI driver
│   ├── monitoring-configmap.yaml # Monitoring configuration
│   ├── backup-cronjob.yaml       # Automated backup job
│   └── development-tools.yaml    # Development utilities
├── deploy.sh                     # Main deployment script
├── setup-azure.sh               # Azure resources setup script
└── health-check.sh              # Health monitoring script
```

## 🚀 Quick Start

### Development Deployment (5 minutes)

```bash
# Clone the repository
git clone <repository-url>
cd airbyte-aks-helm

# Deploy to development
./deploy.sh install -e development

# Access Airbyte
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80
# Open http://localhost:8080
```

### Production Deployment

```bash
# 1. Set up Azure resources
./setup-azure.sh \
  -g "airbyte-prod-rg" \
  -c "airbyte-prod-aks" \
  -p "airbyte-prod-postgres" \
  -s "airbyteprodstorage" \
  -k "airbyte-prod-kv" \
  --create-all

# 2. Configure secrets (update with your values)
kubectl create secret generic airbyte-config-secrets \
  --from-literal=database-user='airbyte_admin' \
  --from-literal=database-password='YOUR_PASSWORD' \
  --from-literal=azure-storage-key='YOUR_STORAGE_KEY' \
  --from-literal=azure-client-secret='YOUR_CLIENT_SECRET' \
  --namespace=airbyte

# 3. Update production values (edit values-production.yaml)
# 4. Deploy
./deploy.sh install -e production --wait
```

## 🔧 Configuration

### Environment-Specific Values

- **Development** (`values-development.yaml`): Minimal resources, internal database, no SSL
- **Production** (`values-production.yaml`): External database, Azure integrations, SSL, HA

### Azure Integrations

- **Azure Database for PostgreSQL**: External managed database
- **Azure Blob Storage**: For logs, state, and workload outputs
- **Azure Key Vault**: Centralized secrets management
- **Azure Workload Identity**: Secure access to Azure resources
- **Azure Monitor**: Logging and monitoring integration
- **Azure Application Gateway**: Advanced ingress (optional)

### Security Features

- **Network Policies**: Pod-to-pod communication control
- **RBAC**: Role-based access control
- **Pod Security Standards**: Security contexts and constraints
- **Workload Identity**: Passwordless authentication to Azure
- **Secrets Management**: Azure Key Vault CSI driver integration

## 📊 Monitoring & Observability

- **Health Checks**: Automated health monitoring with `health-check.sh`
- **Prometheus Metrics**: Application and infrastructure metrics
- **Azure Monitor**: Integration with Azure logging and monitoring
- **Resource Usage**: CPU, memory, and storage monitoring
- **Alerting**: Ready for integration with Azure Monitor alerts

## 🔄 Backup & Recovery

- **Automated Backups**: CronJob-based PostgreSQL backups
- **Retention Policies**: Configurable backup retention
- **Azure Storage Integration**: Backups stored in Azure Blob Storage
- **Point-in-Time Recovery**: Database-level backup strategies

## 🛠 Management Scripts

### `deploy.sh` - Main Deployment Script
```bash
./deploy.sh install -e production     # Install
./deploy.sh upgrade -e production     # Upgrade
./deploy.sh status                    # Check status
./deploy.sh backup                    # Create backup
./deploy.sh uninstall                 # Remove installation
```

### `setup-azure.sh` - Azure Resources Setup
```bash
./setup-azure.sh --create-all         # Create all resources
./setup-azure.sh --create-aks         # Create AKS only
./setup-azure.sh --create-postgres    # Create PostgreSQL only
```

### `health-check.sh` - Health Monitoring
```bash
./health-check.sh                     # Run health checks
./health-check.sh -n custom-namespace # Custom namespace
```

## 🧪 Testing

Comprehensive testing framework including:

- **Unit Tests**: Helm chart linting and template validation
- **Integration Tests**: Kind/Minikube deployment testing
- **Functional Tests**: Health endpoint and connectivity testing
- **Load Tests**: Performance and stress testing
- **Security Tests**: Network policy and RBAC validation

Run tests with:
```bash
# Lint charts
helm lint . --values values-development.yaml

# Template validation
helm template airbyte . --values values-production.yaml

# Full test suite (see TESTING.md)
```

## 📚 Documentation

- **[README.md](README.md)**: Complete documentation and configuration guide
- **[QUICKSTART.md](QUICKSTART.md)**: Fast deployment guide
- **[TESTING.md](TESTING.md)**: Comprehensive testing documentation

## 🏗 Architecture

### High-Level Architecture
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Azure App     │    │       AKS        │    │  Azure Services │
│    Gateway      │───▶│     Cluster      │◀───│                 │
│  (Ingress)      │    │                  │    │ • PostgreSQL    │
└─────────────────┘    │  ┌─────────────┐ │    │ • Blob Storage  │
                       │  │   Airbyte   │ │    │ • Key Vault     │
┌─────────────────┐    │  │   Pods      │ │    │ • Monitor       │
│     Users       │───▶│  │             │ │    │                 │
│                 │    │  │ • Server    │ │    └─────────────────┘
│                 │    │  │ • Worker    │ │
└─────────────────┘    │  │ • Launcher  │ │
                       │  └─────────────┘ │
                       └──────────────────┘
```

### Security Architecture
- Network policies control pod-to-pod communication
- Workload Identity provides secure Azure access
- Azure Key Vault manages all secrets
- RBAC controls Kubernetes access

## 🎛 Customization

### Resource Requirements
- **Development**: ~2GB RAM, 1 CPU core
- **Production**: ~8GB RAM, 4 CPU cores (auto-scaling enabled)

### Storage Options
- **Development**: Internal MinIO or PostgreSQL
- **Production**: Azure Blob Storage + Azure Database for PostgreSQL

### Networking Options
- **NGINX Ingress Controller** (default)
- **Azure Application Gateway Ingress Controller** (AGIC)

## 🔒 Security Best Practices

1. **Use external PostgreSQL database** in production
2. **Enable Azure Workload Identity** for passwordless auth
3. **Configure network policies** to restrict pod communication
4. **Use Azure Key Vault** for secrets management
5. **Enable pod security standards** for runtime security
6. **Regular security updates** and vulnerability scanning

## 🚨 Troubleshooting

### Common Issues

1. **Database Connection Issues**
   ```bash
   kubectl logs -n airbyte deployment/airbyte-server
   # Check PostgreSQL firewall rules and SSL configuration
   ```

2. **Storage Access Issues**
   ```bash
   ./health-check.sh
   # Verify Azure storage account keys and permissions
   ```

3. **Pod Not Starting**
   ```bash
   kubectl describe pod <pod-name> -n airbyte
   # Check resource limits and image pull policies
   ```

### Debug Commands
```bash
# Get all resources
kubectl get all -n airbyte

# Check events
kubectl get events -n airbyte --sort-by=.metadata.creationTimestamp

# Health check
./health-check.sh

# Port forward for debugging
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test with `helm lint`
4. Update documentation
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

- **Issues**: Create GitHub issues for bugs or feature requests
- **Documentation**: Check the comprehensive docs in this repository
- **Community**: Join the Airbyte community discussions

---

## 🎉 What's Included

This Helm chart provides everything needed for a production Airbyte deployment:

✅ **Production-ready Airbyte deployment**  
✅ **Azure-native integrations**  
✅ **Security hardening**  
✅ **High availability configuration**  
✅ **Auto-scaling capabilities**  
✅ **Comprehensive monitoring**  
✅ **Automated backup solutions**  
✅ **Multi-environment support**  
✅ **Complete documentation**  
✅ **Testing framework**  
✅ **Management scripts**  
✅ **Health checking**  

Ready to deploy Airbyte to your AKS cluster with enterprise-grade reliability and security!
