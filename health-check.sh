#!/bin/bash

# Airbyte Health Check Script
# This script performs comprehensive health checks on the Airbyte deployment

set -euo pipefail

NAMESPACE="airbyte"
RELEASE_NAME="airbyte"
TIMEOUT=60

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
}

check_namespace() {
    log_info "Checking namespace: $NAMESPACE"
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "✓ Namespace exists"
    else
        log_error "✗ Namespace does not exist"
        return 1
    fi
}

check_helm_release() {
    log_info "Checking Helm release: $RELEASE_NAME"
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        local status
        status=$(helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" | awk '{print $8}')
        if [[ "$status" == "deployed" ]]; then
            log_info "✓ Helm release is deployed"
        else
            log_warn "✗ Helm release status: $status"
            return 1
        fi
    else
        log_error "✗ Helm release not found"
        return 1
    fi
}

check_pods() {
    log_info "Checking pod status..."
    
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$pods" ]]; then
        log_error "✗ No pods found"
        return 1
    fi
    
    local total_pods=0
    local ready_pods=0
    local failed_pods=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            total_pods=$((total_pods + 1))
            local pod_name status ready
            pod_name=$(echo "$line" | awk '{print $1}')
            ready=$(echo "$line" | awk '{print $2}')
            status=$(echo "$line" | awk '{print $3}')
            
            if [[ "$ready" =~ ^([0-9]+)/\1$ ]] && [[ "$status" == "Running" ]]; then
                ready_pods=$((ready_pods + 1))
                log_info "✓ $pod_name is ready"
            else
                log_error "✗ $pod_name is not ready ($ready, $status)"
                failed_pods=$((failed_pods + 1))
            fi
        fi
    done <<< "$pods"
    
    log_info "Pod Summary: $ready_pods/$total_pods ready, $failed_pods failed"
    
    if [[ $failed_pods -gt 0 ]]; then
        return 1
    fi
}

check_services() {
    log_info "Checking services..."
    
    local services
    services=$(kubectl get services -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$services" ]]; then
        log_error "✗ No services found"
        return 1
    fi
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local service_name cluster_ip
            service_name=$(echo "$line" | awk '{print $1}')
            cluster_ip=$(echo "$line" | awk '{print $3}')
            
            if [[ "$cluster_ip" != "<none>" ]] && [[ "$cluster_ip" != "" ]]; then
                log_info "✓ Service $service_name has cluster IP: $cluster_ip"
            else
                log_warn "? Service $service_name has no cluster IP"
            fi
        fi
    done <<< "$services"
}

check_ingress() {
    log_info "Checking ingress..."
    
    local ingress
    ingress=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$ingress" ]]; then
        log_warn "? No ingress found"
        return 0
    fi
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local ingress_name hosts address
            ingress_name=$(echo "$line" | awk '{print $1}')
            hosts=$(echo "$line" | awk '{print $3}')
            address=$(echo "$line" | awk '{print $4}')
            
            if [[ -n "$address" ]] && [[ "$address" != "<pending>" ]]; then
                log_info "✓ Ingress $ingress_name has address: $address"
                log_info "  Hosts: $hosts"
            else
                log_warn "? Ingress $ingress_name is pending address assignment"
            fi
        fi
    done <<< "$ingress"
}

check_secrets() {
    log_info "Checking secrets..."
    
    local required_secrets=("airbyte-config-secrets")
    
    for secret in "${required_secrets[@]}"; do
        if kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
            log_info "✓ Secret $secret exists"
        else
            log_error "✗ Required secret $secret not found"
            return 1
        fi
    done
}

check_health_endpoints() {
    log_info "Checking health endpoints..."
    
    # Check if webapp service is available
    if kubectl get service airbyte-webapp -n "$NAMESPACE" &> /dev/null; then
        log_info "Starting port-forward to test health endpoints..."
        
        # Start port forwarding in background
        kubectl port-forward -n "$NAMESPACE" service/airbyte-webapp 18080:80 &
        local pf_pid=$!
        
        # Wait a moment for port forwarding to establish
        sleep 3
        
        # Test webapp health
        if curl -f --max-time 10 http://localhost:18080/health &> /dev/null; then
            log_info "✓ Webapp health endpoint is responding"
        else
            log_error "✗ Webapp health endpoint is not responding"
        fi
        
        # Test API health
        if curl -f --max-time 10 http://localhost:18080/api/v1/health &> /dev/null; then
            log_info "✓ API health endpoint is responding"
        else
            log_warn "? API health endpoint is not responding (may be normal)"
        fi
        
        # Clean up port forward
        kill $pf_pid 2>/dev/null || true
        sleep 1
    else
        log_warn "? Webapp service not found, skipping health endpoint check"
    fi
}

check_resource_usage() {
    log_info "Checking resource usage..."
    
    # Check if metrics-server is available
    if kubectl top nodes &> /dev/null; then
        log_info "Node resource usage:"
        kubectl top nodes
        
        log_info "Pod resource usage in $NAMESPACE:"
        kubectl top pods -n "$NAMESPACE" --no-headers | while read -r line; do
            if [[ -n "$line" ]]; then
                local pod_name cpu memory
                pod_name=$(echo "$line" | awk '{print $1}')
                cpu=$(echo "$line" | awk '{print $2}')
                memory=$(echo "$line" | awk '{print $3}')
                log_info "  $pod_name: CPU=$cpu, Memory=$memory"
            fi
        done
    else
        log_warn "? Metrics server not available, skipping resource usage check"
    fi
}

check_persistent_volumes() {
    log_info "Checking persistent volumes..."
    
    local pvcs
    pvcs=$(kubectl get pvc -n "$NAMESPACE" --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$pvcs" ]]; then
        log_info "? No persistent volume claims found"
        return 0
    fi
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local pvc_name status volume
            pvc_name=$(echo "$line" | awk '{print $1}')
            status=$(echo "$line" | awk '{print $2}')
            volume=$(echo "$line" | awk '{print $3}')
            
            if [[ "$status" == "Bound" ]]; then
                log_info "✓ PVC $pvc_name is bound to $volume"
            else
                log_error "✗ PVC $pvc_name is $status"
            fi
        fi
    done <<< "$pvcs"
}

check_events() {
    log_info "Checking recent events..."
    
    local events
    events=$(kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp --no-headers 2>/dev/null | tail -10 || echo "")
    
    if [[ -n "$events" ]]; then
        log_info "Recent events in $NAMESPACE:"
        echo "$events" | while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local type reason message
                type=$(echo "$line" | awk '{print $2}')
                reason=$(echo "$line" | awk '{print $3}')
                
                if [[ "$type" == "Warning" ]]; then
                    log_warn "  Warning: $reason"
                else
                    log_info "  $type: $reason"
                fi
            fi
        done
    else
        log_info "No recent events found"
    fi
}

generate_report() {
    log_info "Generating health check report..."
    
    local report_file="health-check-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Airbyte Health Check Report"
        echo "Generated: $(date)"
        echo "Namespace: $NAMESPACE"
        echo "Release: $RELEASE_NAME"
        echo "=========================================="
        echo
        
        echo "Pods:"
        kubectl get pods -n "$NAMESPACE" -o wide
        echo
        
        echo "Services:"
        kubectl get services -n "$NAMESPACE"
        echo
        
        echo "Ingress:"
        kubectl get ingress -n "$NAMESPACE" || echo "No ingress found"
        echo
        
        echo "PVCs:"
        kubectl get pvc -n "$NAMESPACE" || echo "No PVCs found"
        echo
        
        echo "Recent Events:"
        kubectl get events -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -10
        echo
        
        if kubectl top nodes &> /dev/null; then
            echo "Resource Usage:"
            kubectl top nodes
            echo
            kubectl top pods -n "$NAMESPACE"
        fi
        
    } > "$report_file"
    
    log_info "Health check report saved to: $report_file"
}

main() {
    log_info "Starting Airbyte health check..."
    
    local exit_code=0
    
    check_prerequisites || exit_code=$?
    check_namespace || exit_code=$?
    check_helm_release || exit_code=$?
    check_pods || exit_code=$?
    check_services || exit_code=$?
    check_ingress || exit_code=$?
    check_secrets || exit_code=$?
    check_health_endpoints || exit_code=$?
    check_resource_usage || exit_code=$?
    check_persistent_volumes || exit_code=$?
    check_events || exit_code=$?
    
    generate_report
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "✅ All health checks passed!"
    else
        log_error "❌ Some health checks failed!"
    fi
    
    exit $exit_code
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -n, --namespace NAME    Kubernetes namespace [default: airbyte]"
            echo "  -r, --release NAME      Helm release name [default: airbyte]" 
            echo "  -t, --timeout SECONDS   Timeout for checks [default: 60]"
            echo "  -h, --help              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
