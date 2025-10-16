# 🚀 Airbyte AKS Deployment Checklist

Use this checklist to ensure a successful deployment of Airbyte on Azure Kubernetes Service (AKS).

## Pre-Deployment Checklist

### ✅ Azure Resources Setup
- [ ] Azure subscription with sufficient quotas
- [ ] Resource group created
- [ ] AKS cluster provisioned with the following features:
  - [ ] Azure CNI networking
  - [ ] Azure Key Vault CSI driver add-on
  - [ ] Azure Workload Identity enabled
  - [ ] System-assigned managed identity
- [ ] Azure Database for PostgreSQL Flexible Server created
- [ ] Azure Storage Account created with containers:
  - [ ] `airbyte-logs`
  - [ ] `airbyte-state`
  - [ ] `airbyte-workload-output`
  - [ ] `airbyte-activity-payload`
- [ ] Azure Key Vault created with secrets:
  - [ ] `database-user`
  - [ ] `database-password`
  - [ ] `azure-storage-key`
- [ ] DNS zone configured (if using custom domain)
- [ ] SSL certificate available (if using HTTPS)

### ✅ Kubernetes Prerequisites
- [ ] kubectl configured and connected to AKS cluster
- [ ] Helm 3.x installed
- [ ] Azure CLI installed and logged in
- [ ] Appropriate RBAC permissions on AKS cluster

### ✅ Configuration Setup
- [ ] Clone the airbyte-aks-helm repository
- [ ] Review and customize values files:
  - [ ] `values-development.yaml` for dev environment
  - [ ] `values-production.yaml` for prod environment
- [ ] Update the following in values files:
  - [ ] Database connection strings
  - [ ] Storage account details
  - [ ] Key Vault references
  - [ ] Domain names and ingress settings
  - [ ] Resource limits and requests
  - [ ] Backup configurations

## Deployment Steps

### 🔧 Step 1: Environment Setup
```bash
# Set up Azure resources (customize script first)
./setup-azure.sh

# Validate chart
./validate-chart.sh
```

### 🚀 Step 2: Deploy Airbyte

#### For Development Environment:
```bash
# Deploy to development
./deploy.sh install development

# Or manually with Helm
helm install airbyte-dev . -f values-development.yaml --namespace airbyte --create-namespace
```

#### For Production Environment:
```bash
# Deploy to production
./deploy.sh install production

# Or manually with Helm
helm install airbyte-prod . -f values-production.yaml --namespace airbyte --create-namespace
```

### 🔍 Step 3: Verification
```bash
# Run health checks
./health-check.sh

# Check pod status
kubectl get pods -n airbyte

# Check services
kubectl get services -n airbyte

# Check ingress (if configured)
kubectl get ingress -n airbyte
```

## Post-Deployment Checklist

### ✅ Functional Verification
- [ ] All pods are running without errors
- [ ] Database connectivity verified
- [ ] Storage connectivity verified
- [ ] Key Vault integration working
- [ ] Web UI accessible
- [ ] API endpoints responding
- [ ] Authentication working (if enabled)

### ✅ Security Verification
- [ ] Network policies applied
- [ ] Pod security contexts configured
- [ ] Secrets properly managed via Key Vault
- [ ] RBAC permissions minimal and appropriate
- [ ] Container images from trusted sources

### ✅ Monitoring & Observability
- [ ] Prometheus metrics being collected
- [ ] Azure Monitor integration configured
- [ ] Log aggregation working
- [ ] Alerting rules configured
- [ ] Dashboard access verified

### ✅ Backup & Recovery
- [ ] Backup CronJob scheduled and running
- [ ] Backup storage configured
- [ ] Recovery procedures documented and tested
- [ ] Database backup strategy verified

### ✅ Performance & Scaling
- [ ] HPA configured for auto-scaling
- [ ] Resource limits appropriate for workload
- [ ] Storage performance adequate
- [ ] Network performance tested
- [ ] Load testing completed (for production)

## Troubleshooting Common Issues

### Pod Startup Issues
```bash
# Check pod logs
kubectl logs -n airbyte -l app.kubernetes.io/name=airbyte-webapp

# Check events
kubectl get events -n airbyte --sort-by='.lastTimestamp'

# Check resource constraints
kubectl describe pods -n airbyte
```

### Database Connection Issues
```bash
# Test database connectivity
kubectl run -it --rm debug --image=postgres:13 --restart=Never -- psql -h <db-host> -U <username> -d airbyte

# Check database secrets
kubectl get secrets -n airbyte airbyte-config-secrets -o yaml
```

### Storage Issues
```bash
# Check storage account access
kubectl run -it --rm debug --image=mcr.microsoft.com/azure-cli --restart=Never -- az storage blob list --account-name <storage-account> --container-name airbyte-logs

# Check persistent volumes
kubectl get pv,pvc -n airbyte
```

### Key Vault Issues
```bash
# Check CSI driver pods
kubectl get pods -n kube-system -l app=secrets-store-csi-driver

# Check secret provider class
kubectl describe secretproviderclass -n airbyte

# Check workload identity
kubectl describe serviceaccount -n airbyte
```

## Maintenance Tasks

### Regular Maintenance
- [ ] Monitor resource usage and scale as needed
- [ ] Review and rotate secrets regularly
- [ ] Update Airbyte to latest stable version
- [ ] Review backup retention and cleanup old backups
- [ ] Monitor security advisories and apply patches

### Quarterly Reviews
- [ ] Review and update resource allocations
- [ ] Performance testing and optimization
- [ ] Security audit and vulnerability scanning
- [ ] Disaster recovery testing
- [ ] Documentation updates

## Emergency Procedures

### Rollback Deployment
```bash
# Using deployment script
./deploy.sh rollback production

# Using Helm directly
helm rollback airbyte-prod -n airbyte
```

### Scale Down (Emergency)
```bash
# Scale down all deployments
kubectl scale deployment --all --replicas=0 -n airbyte

# Scale back up
kubectl scale deployment --all --replicas=1 -n airbyte
```

### Backup Restore
```bash
# Use migration script
./migrate.sh restore-backup <backup-name>

# Manual restore (adjust as needed)
kubectl exec -it <postgres-pod> -- pg_restore -d airbyte /backups/<backup-file>
```

## Support and Documentation

- **Project Repository**: https://github.com/your-org/airbyte-aks-helm
- **Airbyte Documentation**: https://docs.airbyte.io/
- **Azure AKS Documentation**: https://docs.microsoft.com/en-us/azure/aks/
- **Helm Documentation**: https://helm.sh/docs/

## Notes and Comments

_Use this section to document environment-specific configurations, known issues, or other important information._

---

**Last Updated**: $(date)
**Deployed By**: _Your Name_
**Environment**: _Development/Staging/Production_
