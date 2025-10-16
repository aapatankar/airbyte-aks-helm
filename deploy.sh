#!/bin/bash

# Airbyte AKS Deployment Script
# This script helps deploy Airbyte to Azure Kubernetes Service

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART_PATH="$SCRIPT_DIR"
NAMESPACE="airbyte"
RELEASE_NAME="airbyte"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Airbyte AKS Deployment Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    install         Install Airbyte
    upgrade         Upgrade existing Airbyte installation
    uninstall       Uninstall Airbyte
    status          Check deployment status
    setup           Run initial setup (create namespace, secrets, etc.)
    validate        Validate configuration and prerequisites
    backup          Create a backup
    restore         Restore from backup

Options:
    -e, --environment ENV    Environment (development|staging|production) [default: development]
    -n, --namespace NS       Kubernetes namespace [default: airbyte]
    -r, --release NAME       Helm release name [default: airbyte]
    -f, --values-file FILE   Additional values file
    --dry-run               Run in dry-run mode
    --wait                  Wait for deployment to be ready
    -h, --help              Show this help message

Examples:
    $0 install -e production
    $0 upgrade -e staging --wait
    $0 setup -e production
    $0 status
    $0 backup
    
EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed or not in PATH"
        exit 1
    fi
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if we're connected to an AKS cluster
    CLUSTER_NAME=$(kubectl config current-context 2>/dev/null || echo "unknown")
    if [[ ! "$CLUSTER_NAME" =~ aks ]]; then
        log_warn "Current cluster '${CLUSTER_NAME}' doesn't appear to be an AKS cluster"
    fi
    
    log_info "Prerequisites check passed"
}

# Validate environment configuration
validate_config() {
    local environment=$1
    local values_file="values-${environment}.yaml"
    
    log_info "Validating configuration for environment: $environment"
    
    if [[ ! -f "$HELM_CHART_PATH/$values_file" ]]; then
        log_error "Values file not found: $values_file"
        exit 1
    fi
    
    # Validate Helm chart
    helm lint "$HELM_CHART_PATH" --values "$HELM_CHART_PATH/$values_file" || {
        log_error "Helm chart validation failed"
        exit 1
    }
    
    log_info "Configuration validation passed"
}

# Create namespace if it doesn't exist
create_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    else
        log_info "Namespace '$NAMESPACE' already exists"
    fi
}

# Setup secrets
setup_secrets() {
    local environment=$1
    
    log_info "Setting up secrets for environment: $environment"
    
    if [[ "$environment" == "development" ]]; then
        # Create basic secrets for development
        kubectl create secret generic airbyte-config-secrets \
            --from-literal=database-user='airbyte' \
            --from-literal=database-password='airbyte123' \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        # For production/staging, check if secrets exist
        if ! kubectl get secret airbyte-config-secrets -n "$NAMESPACE" &> /dev/null; then
            log_error "Secret 'airbyte-config-secrets' not found in namespace '$NAMESPACE'"
            log_error "Please create the required secrets manually for $environment environment"
            cat << EOF

Required secrets for $environment environment:
kubectl create secret generic airbyte-config-secrets \\
  --from-literal=database-user='your-db-user' \\
  --from-literal=database-password='your-db-password' \\
  --from-literal=azure-storage-key='your-storage-key' \\
  --from-literal=azure-client-secret='your-client-secret' \\
  --namespace=$NAMESPACE

EOF
            exit 1
        fi
    fi
    
    log_info "Secrets setup completed"
}

# Add required Helm repositories
setup_helm_repos() {
    log_info "Setting up Helm repositories..."
    
    # Add Airbyte repo
    helm repo add airbyte-v2 https://airbytehq.github.io/charts || true
    
    # Add ingress-nginx repo
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true
    
    # Add cert-manager repo
    helm repo add jetstack https://charts.jetstack.io || true
    
    # Update repos
    helm repo update
    
    log_info "Helm repositories setup completed"
}

# Install required components
install_dependencies() {
    local environment=$1
    
    log_info "Installing dependencies for $environment environment..."
    
    # Install ingress-nginx if not present
    if ! kubectl get deployment ingress-nginx-controller -n ingress-nginx &> /dev/null; then
        log_info "Installing NGINX Ingress Controller..."
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace ingress-nginx \
            --create-namespace \
            --set controller.service.type=LoadBalancer \
            --wait
    fi
    
    # Install cert-manager for production/staging
    if [[ "$environment" != "development" ]] && ! kubectl get deployment cert-manager -n cert-manager &> /dev/null; then
        log_info "Installing cert-manager..."
        helm upgrade --install cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --create-namespace \
            --set installCRDs=true \
            --wait
    fi
    
    log_info "Dependencies installation completed"
}

# Install Airbyte
install_airbyte() {
    local environment=$1
    local dry_run=$2
    local wait_flag=$3
    local additional_values=$4
    
    local values_file="values-${environment}.yaml"
    local helm_args=()
    
    log_info "Installing Airbyte with environment: $environment"
    
    helm_args+=(upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH")
    helm_args+=(--namespace "$NAMESPACE")
    helm_args+=(--values "$HELM_CHART_PATH/$values_file")
    
    if [[ -n "$additional_values" ]]; then
        helm_args+=(--values "$additional_values")
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        helm_args+=(--dry-run)
    fi
    
    if [[ "$wait_flag" == "true" ]]; then
        helm_args+=(--wait --timeout 10m)
    fi
    
    helm "${helm_args[@]}"
    
    if [[ "$dry_run" != "true" ]]; then
        log_info "Airbyte installation completed"
        show_status
    fi
}

# Upgrade Airbyte
upgrade_airbyte() {
    local environment=$1
    local dry_run=$2
    local wait_flag=$3
    local additional_values=$4
    
    log_info "Upgrading Airbyte..."
    install_airbyte "$environment" "$dry_run" "$wait_flag" "$additional_values"
}

# Uninstall Airbyte
uninstall_airbyte() {
    log_info "Uninstalling Airbyte..."
    
    helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE" || true
    
    # Optionally remove namespace
    read -p "Do you want to remove the namespace '$NAMESPACE'? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace "$NAMESPACE" || true
    fi
    
    log_info "Airbyte uninstallation completed"
}

# Show deployment status
show_status() {
    log_info "Checking Airbyte deployment status..."
    
    echo "=== Helm Release ==="
    helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" || echo "Release not found"
    echo
    
    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE" -o wide
    echo
    
    echo "=== Services ==="
    kubectl get services -n "$NAMESPACE"
    echo
    
    echo "=== Ingress ==="
    kubectl get ingress -n "$NAMESPACE"
    echo
    
    # Check if all pods are ready
    local ready_pods
    ready_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
    local total_pods
    total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [[ $ready_pods -eq $total_pods ]] && [[ $total_pods -gt 0 ]]; then
        log_info "All pods are ready ($ready_pods/$total_pods)"
    else
        log_warn "Some pods are not ready ($ready_pods/$total_pods)"
    fi
}

# Create backup
create_backup() {
    log_info "Creating backup..."
    
    local backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Export Helm values
    helm get values "$RELEASE_NAME" -n "$NAMESPACE" > "$backup_dir/helm-values.yaml"
    
    # Export Kubernetes resources
    kubectl get all,secrets,configmaps,ingress -n "$NAMESPACE" -o yaml > "$backup_dir/k8s-resources.yaml"
    
    # Database backup (if using external database)
    log_info "Note: Database backup should be handled separately using your database provider's backup tools"
    
    log_info "Backup created in: $backup_dir"
}

# Setup command
setup_environment() {
    local environment=$1
    
    log_info "Setting up environment: $environment"
    
    create_namespace
    setup_helm_repos
    install_dependencies "$environment"
    setup_secrets "$environment"
    
    log_info "Environment setup completed"
}

# Parse command line arguments
COMMAND=""
ENVIRONMENT="development"
DRY_RUN="false"
WAIT_FLAG="false"
ADDITIONAL_VALUES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        install|upgrade|uninstall|status|setup|validate|backup)
            COMMAND=$1
            shift
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values-file)
            ADDITIONAL_VALUES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --wait)
            WAIT_FLAG="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    log_error "Invalid environment: $ENVIRONMENT. Must be one of: development, staging, production"
    exit 1
fi

# Main execution
case $COMMAND in
    install)
        check_prerequisites
        validate_config "$ENVIRONMENT"
        setup_environment "$ENVIRONMENT"
        install_airbyte "$ENVIRONMENT" "$DRY_RUN" "$WAIT_FLAG" "$ADDITIONAL_VALUES"
        ;;
    upgrade)
        check_prerequisites
        validate_config "$ENVIRONMENT"
        upgrade_airbyte "$ENVIRONMENT" "$DRY_RUN" "$WAIT_FLAG" "$ADDITIONAL_VALUES"
        ;;
    uninstall)
        check_prerequisites
        uninstall_airbyte
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    setup)
        check_prerequisites
        setup_environment "$ENVIRONMENT"
        ;;
    validate)
        check_prerequisites
        validate_config "$ENVIRONMENT"
        log_info "Validation completed successfully"
        ;;
    backup)
        check_prerequisites
        create_backup
        ;;
    "")
        log_error "No command specified"
        show_help
        exit 1
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
