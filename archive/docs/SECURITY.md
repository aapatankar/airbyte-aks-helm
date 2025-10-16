# 🔒 Security Hardening Guide for Airbyte on AKS

This guide provides comprehensive security recommendations for deploying Airbyte on Azure Kubernetes Service (AKS).

## 🛡️ Infrastructure Security

### AKS Cluster Security
- **Private Cluster**: Enable private cluster mode to isolate API server
- **Network Security**: Use Azure CNI with network policies
- **Node Security**: Enable Azure Defender for Kubernetes
- **RBAC**: Enable Kubernetes RBAC and Azure AD integration
- **Disk Encryption**: Enable encryption at rest for OS and data disks

```bash
# Example AKS cluster with security features
az aks create \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-private-cluster \
  --network-plugin azure \
  --network-policy calico \
  --enable-managed-identity \
  --enable-azure-rbac \
  --enable-encryption-at-host \
  --defender-config-log-analytics-workspace-id /subscriptions/.../workspaces/... \
  --enable-workload-identity \
  --enable-oidc-issuer
```

### Azure Database for PostgreSQL Security
- **Private Endpoint**: Use private endpoints for database access
- **SSL/TLS**: Enforce SSL connections (already configured in our chart)
- **Firewall Rules**: Restrict access to known IP ranges
- **Azure AD Authentication**: Enable Azure AD authentication
- **Backup Encryption**: Enable backup encryption

### Azure Storage Security
- **Private Endpoints**: Use private endpoints for storage access
- **Access Keys**: Rotate access keys regularly via Azure Key Vault
- **Network Access**: Restrict network access to trusted networks
- **Encryption**: Enable encryption in transit and at rest (default)

## 🔐 Authentication & Authorization

### Azure Workload Identity (Configured in Chart)
Our chart includes Azure Workload Identity integration:

```yaml
# In values-production.yaml
azure:
  workloadIdentity:
    enabled: true
    clientId: "your-client-id"
    tenantId: "your-tenant-id"
```

### Service Account Configuration
```yaml
security:
  serviceAccount:
    create: true
    annotations:
      azure.workload.identity/client-id: "your-client-id"
    name: ""
```

### RBAC Configuration
Our chart includes minimal RBAC permissions. Review and adjust as needed:

```bash
# Check current permissions
kubectl auth can-i --list --as=system:serviceaccount:airbyte:airbyte-prod-airbyte-aks
```

## 🔒 Secret Management

### Azure Key Vault Integration (Configured in Chart)
Our chart integrates with Azure Key Vault CSI driver:

```yaml
azure:
  keyVaultCSI:
    enabled: true
    vaultUrl: "https://your-vault.vault.azure.net/"
    tenantId: "your-tenant-id"
```

### Secret Rotation Strategy
1. **Database Passwords**: Rotate every 90 days
2. **Storage Keys**: Rotate every 30 days
3. **Application Secrets**: Rotate as needed

```bash
# Example secret rotation script
#!/bin/bash
# Rotate database password
NEW_PASSWORD=$(openssl rand -base64 32)
az keyvault secret set --vault-name "your-vault" --name "database-password" --value "$NEW_PASSWORD"

# Update database with new password
# (This would involve connecting to PostgreSQL and updating the user password)

# Restart Airbyte pods to pick up new secret
kubectl rollout restart deployment -n airbyte
```

## 🌐 Network Security

### Network Policies (Configured in Chart)
Our chart includes comprehensive network policies:

```yaml
security:
  networkPolicies:
    enabled: true
    ingress:
      enabled: true
      allowedSources:
        - namespaceSelector: {}
        - podSelector: {}
    egress:
      enabled: true
      allowedDestinations:
        - namespaceSelector: {}
        - podSelector: {}
```

### Additional Network Security Measures

#### 1. Ingress Security
```yaml
# Example ingress with security annotations
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-ciphers: "ECDHE-RSA-AES128-GCM-SHA256,ECDHE-RSA-AES256-GCM-SHA384"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

#### 2. Private Endpoints
Configure private endpoints for all Azure services:

```bash
# Create private endpoint for PostgreSQL
az network private-endpoint create \
  --resource-group myResourceGroup \
  --name myPostgreSQLPrivateEndpoint \
  --vnet-name myVNet \
  --subnet mySubnet \
  --private-connection-resource-id $POSTGRESQL_ID \
  --group-id postgresqlServer \
  --connection-name myPostgreSQLConnection
```

## 🛡️ Container Security

### Pod Security Standards (Configured in Chart)
Our chart includes pod security contexts:

```yaml
security:
  podSecurityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
    supplementalGroups: []
```

### Container Security Context
```yaml
security:
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1000
```

### Image Security
1. **Image Scanning**: Use Azure Container Registry with security scanning
2. **Image Signing**: Use Notary v2 for image signing
3. **Base Images**: Use minimal base images (distroless, alpine)
4. **Regular Updates**: Keep base images and dependencies updated

```bash
# Example image scanning with ACR
az acr task create \
  --registry myRegistry \
  --name mySecurityTask \
  --image myapp:{{.Run.ID}} \
  --context https://github.com/myuser/myapp.git \
  --file Dockerfile \
  --commit-trigger-enabled false \
  --base-image-trigger-enabled true
```

## 🔍 Monitoring & Auditing

### Security Monitoring (Configured in Chart)
Our chart includes monitoring configuration:

```yaml
monitoring:
  enabled: true
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
  azureMonitor:
    enabled: true
    workspaceId: "your-workspace-id"
```

### Azure Security Center Integration
Enable Azure Defender for Kubernetes:

```bash
az security auto-provisioning-setting update \
  --name "default" \
  --auto-provision "On"

az security workspace-setting create \
  --name "default" \
  --target-workspace "/subscriptions/.../workspaces/..."
```

### Audit Logging
Enable Kubernetes audit logging:

```bash
az aks update \
  --resource-group myResourceGroup \
  --name myAKSCluster \
  --enable-azure-monitor-metrics \
  --enable-network-observability
```

## 🚨 Threat Detection & Response

### Security Alerts Configuration
1. **Failed Authentication Attempts**
2. **Unusual Network Traffic**
3. **Privilege Escalation Attempts**
4. **Unusual Container Behavior**

### Incident Response Plan
1. **Detection**: Automated alerts trigger incident response
2. **Assessment**: Security team evaluates the threat
3. **Containment**: Isolate affected components
4. **Recovery**: Restore services from known good state
5. **Lessons Learned**: Update security measures

## 🔧 Security Hardening Checklist

### ✅ Pre-Deployment Security
- [ ] Private AKS cluster enabled
- [ ] Network policies configured
- [ ] Azure AD RBAC enabled
- [ ] Private endpoints for all Azure services
- [ ] Azure Key Vault for secret management
- [ ] Container image scanning enabled
- [ ] Pod security standards enforced

### ✅ Runtime Security
- [ ] Security contexts configured
- [ ] Non-root containers enforced
- [ ] Read-only root filesystem
- [ ] Resource limits enforced
- [ ] Network policies active
- [ ] Secret rotation automated

### ✅ Monitoring & Compliance
- [ ] Azure Defender enabled
- [ ] Audit logging configured
- [ ] Security alerts active
- [ ] Compliance scanning scheduled
- [ ] Vulnerability assessments automated
- [ ] Incident response plan documented

## 🛠️ Security Tools & Commands

### Security Scanning
```bash
# Scan for misconfigurations with kube-score
kube-score score values-production.yaml

# Scan for security issues with kubesec
kubesec scan airbyte-deployment.yaml

# Check RBAC permissions
kubectl auth can-i --list --as=system:serviceaccount:airbyte:airbyte-service-account
```

### Security Testing
```bash
# Network policy testing
kubectl run test-pod --image=busybox --rm -it -- /bin/sh

# Pod security testing
kubectl run privileged-test --image=busybox --privileged --rm -it -- /bin/sh
```

### Security Maintenance
```bash
# Update all container images
helm upgrade airbyte-prod . -f values-production.yaml --reuse-values

# Rotate secrets
kubectl delete secret airbyte-config-secrets
./setup-azure.sh  # Recreate with new secrets

# Update network policies
helm upgrade airbyte-prod . -f values-production.yaml --set security.networkPolicies.enabled=true
```

## 📚 Security Resources

- **Azure Security Baseline for AKS**: https://docs.microsoft.com/en-us/security/benchmark/azure/baselines/aks-security-baseline
- **Kubernetes Security Best Practices**: https://kubernetes.io/docs/concepts/security/
- **OWASP Kubernetes Security Cheat Sheet**: https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html
- **CIS Kubernetes Benchmark**: https://www.cisecurity.org/benchmark/kubernetes

---

⚠️ **Important**: Security is an ongoing process. Regularly review and update your security configurations, monitor for new threats, and stay updated with the latest security best practices.
