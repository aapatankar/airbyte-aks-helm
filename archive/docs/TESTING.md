# Testing the Helm Chart

This document describes how to test the Airbyte AKS Helm chart.

## Prerequisites

- Docker Desktop with Kubernetes enabled, or
- Kind cluster, or 
- Access to an AKS cluster
- Helm 3.x installed
- kubectl configured

## Unit Testing

### Lint the Helm Chart

```bash
# Lint with development values
helm lint . --values values-development.yaml

# Lint with production values  
helm lint . --values values-production.yaml
```

### Template Validation

```bash
# Generate templates for development
helm template airbyte . --values values-development.yaml --output-dir ./test-output/development

# Generate templates for production
helm template airbyte . --values values-production.yaml --output-dir ./test-output/production

# Check generated files
ls -la test-output/development/airbyte-aks/templates/
```

### Dry Run Installation

```bash
# Test development installation
./deploy.sh install -e development --dry-run

# Test production installation
./deploy.sh install -e production --dry-run
```

## Integration Testing

### Local Testing with Kind

```bash
# Create a Kind cluster
kind create cluster --name airbyte-test

# Install to Kind cluster
./deploy.sh install -e development

# Test the deployment
kubectl wait --for=condition=available --timeout=300s deployment/airbyte-server -n airbyte

# Check if all pods are running
kubectl get pods -n airbyte

# Test connectivity
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80 &
curl -f http://localhost:8080/health || echo "Health check failed"

# Cleanup
kind delete cluster --name airbyte-test
```

### Testing with Minikube

```bash
# Start Minikube
minikube start --memory=4096 --cpus=2

# Enable addons
minikube addons enable ingress

# Deploy Airbyte
./deploy.sh install -e development

# Test the deployment
kubectl wait --for=condition=available --timeout=300s deployment/airbyte-server -n airbyte

# Get service URL
minikube service airbyte-webapp -n airbyte --url

# Cleanup
minikube delete
```

## Functional Testing

### Test Script

Create a test script to validate functionality:

```bash
#!/bin/bash
# test-functionality.sh

set -e

NAMESPACE="airbyte"
TIMEOUT="300s"

echo "Testing Airbyte deployment..."

# Wait for deployments to be ready
echo "Waiting for deployments..."
kubectl wait --for=condition=available --timeout=$TIMEOUT deployment/airbyte-server -n $NAMESPACE
kubectl wait --for=condition=available --timeout=$TIMEOUT deployment/airbyte-worker -n $NAMESPACE
kubectl wait --for=condition=available --timeout=$TIMEOUT deployment/airbyte-workload-launcher -n $NAMESPACE

# Check if all pods are running
echo "Checking pod status..."
kubectl get pods -n $NAMESPACE

# Test health endpoints
echo "Testing health endpoints..."
kubectl port-forward -n $NAMESPACE service/airbyte-webapp 8080:80 &
PORT_FORWARD_PID=$!

sleep 5

# Test webapp health
if curl -f http://localhost:8080/health; then
    echo "✓ Webapp health check passed"
else
    echo "✗ Webapp health check failed"
    exit 1
fi

# Test API endpoint
if curl -f http://localhost:8080/api/v1/health; then
    echo "✓ API health check passed"
else
    echo "✗ API health check failed" 
    exit 1
fi

# Cleanup
kill $PORT_FORWARD_PID 2>/dev/null || true

echo "All tests passed!"
```

### Database Connection Testing

```bash
# Test PostgreSQL connection (for external database)
kubectl run postgres-test --rm -it --image=postgres:13 --restart=Never -- \
  psql -h your-postgres-server.postgres.database.azure.com \
       -U airbyte_admin \
       -d airbyte \
       -c "SELECT version();"
```

### Storage Testing

```bash
# Test Azure Storage connection
kubectl run azure-test --rm -it --image=mcr.microsoft.com/azure-cli --restart=Never -- \
  az storage blob list \
    --container-name airbyte-logs \
    --account-name yourstorageaccount \
    --account-key "your-storage-key"
```

## Load Testing

### Simple Load Test

```bash
# Install hey (HTTP load testing tool)
# On macOS: brew install hey
# On Linux: go install github.com/rakyll/hey@latest

# Port forward to the service
kubectl port-forward -n airbyte service/airbyte-webapp 8080:80 &

# Run load test
hey -z 30s -c 10 http://localhost:8080/health

# Cleanup
pkill -f "port-forward"
```

### Stress Testing

```bash
# Scale up workers and test
kubectl scale deployment airbyte-worker --replicas=5 -n airbyte

# Monitor resource usage
kubectl top pods -n airbyte

# Check horizontal pod autoscaler (if enabled)
kubectl get hpa -n airbyte
```

## Security Testing

### Network Policy Testing

```bash
# Test network policies (if enabled)
kubectl run test-pod --rm -it --image=busybox --restart=Never -- \
  wget -qO- --timeout=5 http://airbyte-server.airbyte.svc.cluster.local:8000/health || echo "Connection blocked (expected)"
```

### RBAC Testing

```bash
# Test service account permissions
kubectl auth can-i --list --as=system:serviceaccount:airbyte:airbyte-aks

# Test workload identity (Azure)
kubectl run workload-test --rm -it --image=mcr.microsoft.com/azure-cli \
  --serviceaccount=airbyte-aks --restart=Never -- \
  az account show
```

## Monitoring Testing

### Metrics Testing

```bash
# Check if metrics endpoints are available
kubectl port-forward -n airbyte service/airbyte-server 8000:8000 &
curl -f http://localhost:8000/metrics || echo "Metrics not available"
pkill -f "port-forward"
```

### Log Testing

```bash
# Check if logs are being generated
kubectl logs -n airbyte deployment/airbyte-server --tail=10
kubectl logs -n airbyte deployment/airbyte-worker --tail=10
```

## Backup and Recovery Testing

### Test Backup Process

```bash
# Run backup
./deploy.sh backup

# Check backup files
ls -la backups/

# Test database dump (if using external database)
kubectl run postgres-backup --rm -it --image=postgres:13 --restart=Never -- \
  pg_dump -h your-postgres-server.postgres.database.azure.com \
          -U airbyte_admin \
          -d airbyte \
          --schema-only
```

## Upgrade Testing

### Test Rolling Update

```bash
# Deploy initial version
./deploy.sh install -e development

# Wait for deployment
kubectl wait --for=condition=available --timeout=300s deployment/airbyte-server -n airbyte

# Upgrade to newer version (modify image tag in values)
./deploy.sh upgrade -e development --wait

# Verify no downtime
kubectl get pods -n airbyte -w
```

## Cleanup

### Clean Test Environment

```bash
# Uninstall Airbyte
./deploy.sh uninstall

# Clean test outputs
rm -rf test-output/

# Remove test resources
kubectl delete namespace airbyte --ignore-not-found
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Test Airbyte Helm Chart

on:
  pull_request:
    paths:
    - 'airbyte-aks-helm/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Helm
      uses: azure/setup-helm@v3
      
    - name: Lint Helm chart
      run: |
        cd airbyte-aks-helm
        helm lint . --values values-development.yaml
        helm lint . --values values-production.yaml
        
    - name: Template validation
      run: |
        cd airbyte-aks-helm
        helm template airbyte . --values values-development.yaml > /tmp/dev-template.yaml
        helm template airbyte . --values values-production.yaml > /tmp/prod-template.yaml
        
    - name: Set up Kind
      uses: helm/kind-action@v1.4.0
      
    - name: Test deployment
      run: |
        cd airbyte-aks-helm
        ./deploy.sh install -e development
        kubectl wait --for=condition=available --timeout=300s deployment/airbyte-server -n airbyte
```

This testing framework ensures that your Helm chart is robust and works correctly across different environments.
