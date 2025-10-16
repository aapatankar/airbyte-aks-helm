# Airbyte Heartbeat Timeout Configuration - 96 Hours

## Overview

This document describes the implementation of a 96-hour heartbeat timeout configuration for Airbyte deployed on Azure Kubernetes Service (AKS). The heartbeat timeout controls how long Airbyte waits before considering a sync operation as potentially failed due to lack of activity.

## Configuration Details

### Timeout Value
- **Original Timeout**: 3 hours (10,800 seconds)
- **New Timeout**: 96 hours (345,600 seconds)
- **Purpose**: Allows for very long-running sync operations without heartbeat failures

### Implementation Methods

We've implemented the heartbeat timeout using multiple methods to ensure comprehensive coverage:

#### 1. Feature Flags Configuration (`flags.yml`)
**Location**: `templates/flags-configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "airbyte-aks.fullname" . }}-flags-config
data:
  flags.yml: |
    # Heartbeat configuration
    heartbeat-max-seconds-between-messages: 345600  # 96 hours
    heartbeat.failSync: true
```

This is the primary method according to Airbyte documentation. The flags file is mounted in Airbyte containers and read during startup.

#### 2. Environment Variables
**Applied to all Airbyte components**: Server, Worker, Workload Launcher, and Webapp

```yaml
env_vars:
  HEARTBEAT_MAX_SECONDS_BETWEEN_MESSAGES: "345600"
  HEARTBEAT_FAIL_SYNC: "true"

# Component-specific configuration
server:
  extraEnvVars:
    - name: HEARTBEAT_MAX_SECONDS_BETWEEN_MESSAGES
      value: "345600"
    - name: HEARTBEAT_FAIL_SYNC
      value: "true"
```

Environment variables provide a fallback method and ensure the configuration is available to all processes.

## Files Modified

### 1. `values.yaml` (Default Configuration)
Added heartbeat configuration to the Airbyte subchart section:
- Global environment variables
- Component-specific environment variables
- Feature flags configuration

### 2. `values-production.yaml` (Production Configuration)
Enhanced production deployment with:
- 96-hour heartbeat timeout
- Applied to all production components
- Integrated with existing resource configurations

### 3. `values-development.yaml` (Development Configuration)
Added development-friendly heartbeat configuration:
- Same 96-hour timeout for consistency
- Minimal resource overhead
- Compatible with local development

### 4. `templates/flags-configmap.yaml` (New Template)
Created a ConfigMap template for Airbyte feature flags:
- Primary configuration method
- Follows Airbyte's recommended approach
- Templated for flexibility

## Deployment Impact

### Benefits
1. **Long-Running Syncs**: Supports very long sync operations (up to 96 hours)
2. **Reduced False Failures**: Prevents premature sync failures due to heartbeat timeouts
3. **Enterprise Compatibility**: Suitable for large enterprise data synchronization
4. **Comprehensive Coverage**: Multiple configuration methods ensure reliability

### Considerations
1. **Monitoring**: Longer timeouts may delay detection of actual failures
2. **Resource Usage**: Long-running syncs may consume resources for extended periods
3. **Alerting**: May need to adjust monitoring and alerting thresholds

## Validation

### Chart Validation
```bash
# Lint the chart
helm lint . -f values-production.yaml

# Template rendering test
helm template airbyte-test . -f values-production.yaml
```

### Environment Variable Verification
The heartbeat timeout can be verified in deployed pods:
```bash
# Check environment variables in running pods
kubectl exec -it <airbyte-server-pod> -- env | grep HEARTBEAT

# Expected output:
# HEARTBEAT_MAX_SECONDS_BETWEEN_MESSAGES=345600
# HEARTBEAT_FAIL_SYNC=true
```

### Feature Flags Verification
```bash
# Check the flags ConfigMap
kubectl get configmap airbyte-prod-airbyte-aks-flags-config -o yaml

# Check if flags are mounted in pods
kubectl exec -it <airbyte-server-pod> -- cat /etc/launchdarkly/flags.yml
```

## Usage Examples

### Development Deployment
```bash
./deploy.sh install development
# or
helm install airbyte-dev . -f values-development.yaml
```

### Production Deployment
```bash
./deploy.sh install production
# or
helm install airbyte-prod . -f values-production.yaml
```

### Verification After Deployment
```bash
# Run health checks
./health-check.sh

# Check heartbeat configuration
kubectl logs -l app.kubernetes.io/name=airbyte-server | grep -i heartbeat
```

## Troubleshooting

### Common Issues

#### 1. Environment Variables Not Set
**Symptoms**: Heartbeat timeouts still occur after 3 hours
**Solution**: Verify environment variables are set in pods

```bash
kubectl exec -it <pod-name> -- env | grep HEARTBEAT
```

#### 2. ConfigMap Not Mounted
**Symptoms**: Feature flags not taking effect
**Solution**: Check if ConfigMap exists and is properly mounted

```bash
kubectl get configmap | grep flags
kubectl describe pod <pod-name> | grep -A 5 -B 5 configmap
```

#### 3. Configuration Not Applied
**Symptoms**: Default timeout still in effect
**Solution**: Restart Airbyte components to pick up new configuration

```bash
kubectl rollout restart deployment -l app.kubernetes.io/name=airbyte
```

## Monitoring

### Recommended Metrics to Monitor
1. **Sync Duration**: Track actual sync durations vs. timeout
2. **Heartbeat Events**: Monitor heartbeat timeout occurrences
3. **Resource Usage**: Monitor CPU/memory during long syncs
4. **Sync Success Rate**: Ensure configuration doesn't mask real failures

### Alerting Considerations
- Adjust alerting thresholds to account for 96-hour timeout
- Monitor for syncs that approach the 96-hour limit
- Alert on recurring heartbeat failures (may indicate real issues)

## Future Considerations

### Customization Options
The timeout can be easily adjusted by modifying the values files:
```yaml
airbyte:
  global:
    heartbeat:
      maxSecondsBetweenMessages: 172800  # 48 hours
```

### Environment-Specific Timeouts
Different environments can have different timeout values:
- Development: 24 hours
- Staging: 48 hours  
- Production: 96 hours

## References

- [Airbyte Heartbeat Documentation](https://docs.airbyte.io/platform/understanding-airbyte/heartbeats)
- [Airbyte Helm Chart Repository](https://github.com/airbytehq/charts)
- [Azure Kubernetes Service Documentation](https://docs.microsoft.com/en-us/azure/aks/)

---

**Implementation Date**: October 14, 2025  
**Configuration Version**: 1.0  
**Timeout Setting**: 96 hours (345,600 seconds)
