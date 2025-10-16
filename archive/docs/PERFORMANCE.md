# ⚡ Performance Optimization Guide for Airbyte on AKS

This guide provides comprehensive performance optimization strategies for running Airbyte on Azure Kubernetes Service (AKS).

## 🎯 Performance Objectives

### Key Performance Metrics
- **Sync Throughput**: Records per second processed
- **Sync Latency**: Time to complete full sync operations
- **Resource Utilization**: CPU, Memory, Network, Storage efficiency
- **Availability**: Uptime and service availability
- **Scalability**: Ability to handle increasing workloads

## 🏗️ Infrastructure Optimization

### AKS Cluster Configuration

#### Node Pool Optimization
```bash
# Create optimized node pools for different workloads
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
  --os-disk-type Premium_LRS \
  --node-taints airbyte=worker:NoSchedule
```

#### Storage Optimization
```yaml
# In values-production.yaml
global:
  storage:
    azure:
      storageClass: "managed-premium"  # Use Premium SSD
      replicationFactor: "LRS"         # Locally redundant for performance
```

### Database Performance (PostgreSQL)

#### Azure Database for PostgreSQL Configuration
```bash
# Configure for optimal performance
az postgres flexible-server parameter set \
  --resource-group myResourceGroup \
  --server-name mypostgresql \
  --name shared_preload_libraries \
  --value "pg_stat_statements"

az postgres flexible-server parameter set \
  --resource-group myResourceGroup \
  --server-name mypostgresql \
  --name max_connections \
  --value "200"

az postgres flexible-server parameter set \
  --resource-group myResourceGroup \
  --server-name mypostgresql \
  --name work_mem \
  --value "32MB"
```

#### Connection Pooling
```yaml
# Configure connection pooling in values-production.yaml
airbyte:
  database:
    connectionPool:
      maxConnections: 20
      minConnections: 5
      maxIdleTime: "300s"
```

## 🚀 Airbyte Optimization

### Resource Allocation

#### CPU and Memory Optimization
```yaml
# In values-production.yaml
airbyte:
  webapp:
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
        cpu: "1000m"
        memory: "2Gi"
      limits:
        cpu: "2000m"
        memory: "4Gi"
  
  worker:
    resources:
      requests:
        cpu: "2000m"
        memory: "4Gi"
      limits:
        cpu: "4000m"
        memory: "8Gi"
    
    # Scale workers based on load
    replicaCount: 3
    maxReplicas: 10
```

#### Auto-scaling Configuration
```yaml
# HPA configuration in our chart
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
  
  # Custom metrics scaling
  customMetrics:
    - type: Pods
      pods:
        metric:
          name: sync_queue_length
        target:
          type: AverageValue
          averageValue: "10"
```

### Connector Optimization

#### Connector Resource Allocation
```yaml
airbyte:
  connectorResources:
    # High-volume connectors
    postgres:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "1000m"
        memory: "2Gi"
    
    # Medium-volume connectors
    mysql:
      requests:
        cpu: "250m"
        memory: "512Mi"
      limits:
        cpu: "500m"
        memory: "1Gi"
```

#### Sync Configuration Optimization
```yaml
# Optimize sync settings
airbyte:
  sync:
    # Increase batch sizes for better throughput
    batchSize: 10000
    
    # Configure parallel processing
    maxWorkers: 4
    
    # Optimize sync frequency
    syncInterval: "1h"  # Adjust based on requirements
    
    # Configure normalization
    normalization:
      enabled: true
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "1000m"
          memory: "2Gi"
```

## 📊 Monitoring & Observability

### Performance Metrics Collection

#### Prometheus Configuration
```yaml
# In values-production.yaml
monitoring:
  prometheus:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
      scrapeTimeout: 10s
    
    # Custom metrics
    customMetrics:
      - name: airbyte_sync_duration_seconds
        help: "Duration of sync operations"
        type: histogram
        
      - name: airbyte_sync_records_total
        help: "Total records synced"
        type: counter
        
      - name: airbyte_active_connections
        help: "Number of active connections"
        type: gauge
```

#### Azure Monitor Integration
```yaml
monitoring:
  azureMonitor:
    enabled: true
    workspaceId: "your-workspace-id"
    
    # Custom dashboards
    dashboards:
      - name: "Airbyte Performance"
        queries:
          - "Perf | where ObjectName == 'Processor' | summarize avg(CounterValue) by Computer"
          - "ContainerLog | where ContainerName contains 'airbyte' | summarize count() by LogLevel"
```

### Performance Dashboard

#### Key Performance Indicators (KPIs)
1. **Sync Throughput Metrics**
   - Records processed per second
   - Data volume transferred per hour
   - Sync completion rate

2. **Resource Utilization Metrics**
   - CPU utilization by component
   - Memory utilization by component
   - Network I/O throughput
   - Storage I/O latency

3. **Error and Reliability Metrics**
   - Sync failure rate
   - Connection timeout rate
   - Pod restart frequency

## 🔧 Performance Tuning

### JVM Optimization for Java Components

#### Airbyte Server JVM Settings
```yaml
airbyte:
  server:
    env:
      - name: JAVA_OPTS
        value: >-
          -Xms2g -Xmx4g
          -XX:+UseG1GC
          -XX:MaxGCPauseMillis=200
          -XX:+HeapDumpOnOutOfMemoryError
          -XX:HeapDumpPath=/tmp/heapdump.hprof
```

#### Airbyte Worker JVM Settings
```yaml
airbyte:
  worker:
    env:
      - name: JAVA_OPTS
        value: >-
          -Xms4g -Xmx8g
          -XX:+UseG1GC
          -XX:MaxGCPauseMillis=200
          -XX:G1HeapRegionSize=32m
          -XX:+DisableExplicitGC
```

### Database Performance Tuning

#### PostgreSQL Connection Pool Optimization
```yaml
# Configure PgBouncer for connection pooling
pgbouncer:
  enabled: true
  config:
    poolMode: "transaction"
    maxClientConn: 100
    defaultPoolSize: 20
    maxDbConnections: 30
    reservePoolSize: 5
    reservePoolTimeout: 3
```

#### Database Query Optimization
```sql
-- Create indexes for frequently queried tables
CREATE INDEX CONCURRENTLY idx_jobs_status_created_at 
ON jobs(status, created_at) 
WHERE status IN ('pending', 'running');

CREATE INDEX CONCURRENTLY idx_sync_stats_connection_id 
ON sync_stats(connection_id, created_at DESC);

-- Analyze and update statistics
ANALYZE;
```

### Network Optimization

#### Service Mesh Configuration (Optional)
```yaml
# Istio service mesh for advanced traffic management
istio:
  enabled: false  # Enable if needed
  sidecar:
    resources:
      requests:
        cpu: "10m"
        memory: "40Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
```

#### Network Policies for Performance
```yaml
security:
  networkPolicies:
    enabled: true
    optimizeForPerformance: true  # Reduces policy overhead
    allowIntraNamespace: true
```

## 📈 Scaling Strategies

### Horizontal Pod Autoscaling (HPA)

#### Advanced HPA Configuration
```yaml
# Custom HPA with multiple metrics
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: airbyte-worker-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: airbyte-worker
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
  - type: Pods
    pods:
      metric:
        name: pending_jobs
      target:
        type: AverageValue
        averageValue: "5"
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
```

### Vertical Pod Autoscaling (VPA)

#### VPA Configuration
```yaml
# Enable VPA for right-sizing
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: airbyte-worker-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: airbyte-worker
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: airbyte-worker
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 4
        memory: 8Gi
```

## 🧪 Performance Testing

### Load Testing Strategy

#### Connection Load Testing
```bash
#!/bin/bash
# Load test script for Airbyte connections

# Test database source connector
for i in {1..10}; do
  curl -X POST "http://airbyte-server/api/v1/connections/sync" \
    -H "Content-Type: application/json" \
    -d "{\"connectionId\": \"connection-${i}\"}" &
done
wait

# Monitor performance during test
kubectl top pods -n airbyte
kubectl get hpa -n airbyte
```

#### Synthetic Data Generation
```python
# synthetic_data_generator.py
import random
import psycopg2
from datetime import datetime, timedelta

def generate_test_data(conn, num_records=100000):
    cursor = conn.cursor()
    
    for i in range(num_records):
        cursor.execute("""
            INSERT INTO test_table (id, name, email, created_at)
            VALUES (%s, %s, %s, %s)
        """, (
            i,
            f"user_{i}",
            f"user_{i}@example.com",
            datetime.now() - timedelta(seconds=random.randint(0, 86400))
        ))
        
        if i % 1000 == 0:
            conn.commit()
            print(f"Inserted {i} records")
    
    conn.commit()
    cursor.close()
```

### Performance Benchmarking
```bash
#!/bin/bash
# Benchmark script

echo "Starting performance benchmark..."

# Measure sync performance
START_TIME=$(date +%s)
kubectl exec -it airbyte-worker -- airbyte-cli sync run --connection-id $CONNECTION_ID
END_TIME=$(date +%s)
SYNC_DURATION=$((END_TIME - START_TIME))

echo "Sync completed in ${SYNC_DURATION} seconds"

# Collect metrics
kubectl exec -it prometheus -- promtool query instant 'rate(airbyte_sync_records_total[5m])'
kubectl exec -it prometheus -- promtool query instant 'airbyte_sync_duration_seconds'
```

## 🎛️ Performance Monitoring Dashboard

### Grafana Dashboard Configuration
```json
{
  "dashboard": {
    "title": "Airbyte Performance Dashboard",
    "panels": [
      {
        "title": "Sync Throughput",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(airbyte_sync_records_total[5m])",
            "legendFormat": "Records/sec"
          }
        ]
      },
      {
        "title": "Resource Utilization",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total[5m]) * 100",
            "legendFormat": "CPU %"
          },
          {
            "expr": "container_memory_usage_bytes / container_spec_memory_limit_bytes * 100",
            "legendFormat": "Memory %"
          }
        ]
      }
    ]
  }
}
```

## ✅ Performance Optimization Checklist

### ✅ Infrastructure Optimization
- [ ] Optimized node pool configuration
- [ ] Premium storage for high I/O workloads
- [ ] Database performance tuning
- [ ] Network optimization
- [ ] Load balancer configuration

### ✅ Application Optimization
- [ ] JVM tuning for Java components
- [ ] Connection pooling configured
- [ ] Batch size optimization
- [ ] Parallel processing enabled
- [ ] Resource limits properly set

### ✅ Monitoring & Observability
- [ ] Performance metrics collection
- [ ] Custom dashboards configured
- [ ] Alerting for performance degradation
- [ ] Log aggregation for troubleshooting
- [ ] SLA monitoring implemented

### ✅ Scaling Configuration
- [ ] HPA configured with appropriate metrics
- [ ] VPA enabled for right-sizing
- [ ] Cluster autoscaling enabled
- [ ] Resource quotas defined
- [ ] Performance testing completed

## 🚨 Performance Troubleshooting

### Common Performance Issues

#### High CPU Usage
```bash
# Identify CPU-intensive pods
kubectl top pods -n airbyte --sort-by=cpu

# Check for CPU throttling
kubectl describe pod <pod-name> -n airbyte | grep -A 5 -B 5 "throttling"

# Scale horizontally if needed
kubectl scale deployment airbyte-worker --replicas=5 -n airbyte
```

#### Memory Issues
```bash
# Check memory usage
kubectl top pods -n airbyte --sort-by=memory

# Check for OOMKilled pods
kubectl get pods -n airbyte | grep OOMKilled

# Analyze memory usage patterns
kubectl exec -it <pod-name> -n airbyte -- /bin/sh -c "cat /proc/meminfo"
```

#### Slow Database Performance
```sql
-- Check slow queries
SELECT query, mean_time, calls
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Check database connections
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state;
```

---

⚡ **Remember**: Performance optimization is an iterative process. Continuously monitor, measure, and adjust based on your specific workload patterns and requirements.
