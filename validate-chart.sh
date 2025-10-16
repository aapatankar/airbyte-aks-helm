#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}==== $1 ====${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    print_header "Validating Prerequisites"
    
    local missing_tools=()
    
    if ! command_exists helm; then
        missing_tools+=("helm")
    else
        print_success "Helm is installed ($(helm version --short 2>/dev/null || echo 'version check failed'))"
    fi
    
    if ! command_exists kubectl; then
        missing_tools+=("kubectl")
    else
        print_success "kubectl is installed ($(kubectl version --client --short 2>/dev/null || echo 'version check failed'))"
    fi
    
    if ! command_exists az; then
        missing_tools+=("azure-cli")
    else
        print_success "Azure CLI is installed ($(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo 'version check failed'))"
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install the missing tools and run this script again"
        return 1
    fi
    
    return 0
}

# Validate chart structure
validate_chart_structure() {
    print_header "Validating Chart Structure"
    
    local required_files=(
        "Chart.yaml"
        "values.yaml"
        "values-development.yaml"
        "values-production.yaml"
        "templates/_helpers.tpl"
        "templates/serviceaccount.yaml"
        "templates/networkpolicy.yaml"
        "templates/secretproviderclass.yaml"
        "templates/monitoring-configmap.yaml"
        "templates/backup-cronjob.yaml"
        "templates/hpa.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_success "Found $file"
        else
            print_error "Missing $file"
            return 1
        fi
    done
    
    # Check for executable scripts
    local scripts=("deploy.sh" "setup-azure.sh" "health-check.sh" "migrate.sh")
    for script in "${scripts[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            print_success "Script $script is executable"
        elif [[ -f "$script" ]]; then
            print_warning "Script $script exists but is not executable"
            chmod +x "$script"
            print_success "Made $script executable"
        else
            print_error "Missing script $script"
        fi
    done
    
    return 0
}

# Run comprehensive helm validation
run_helm_validation() {
    print_header "Running Helm Validation"
    
    # Update dependencies first
    print_info "Updating Helm dependencies..."
    if helm dependency update; then
        print_success "Dependencies updated successfully"
    else
        print_error "Failed to update dependencies"
        return 1
    fi
    
    # Lint with different value files
    local value_files=("" "values-development.yaml" "values-production.yaml")
    local value_names=("default" "development" "production")
    
    for i in "${!value_files[@]}"; do
        local value_file="${value_files[$i]}"
        local value_name="${value_names[$i]}"
        
        print_info "Linting with $value_name values..."
        if [[ -z "$value_file" ]]; then
            helm_cmd="helm lint ."
        else
            helm_cmd="helm lint . -f $value_file"
        fi
        
        if eval "$helm_cmd" >/dev/null 2>&1; then
            print_success "Lint passed for $value_name configuration"
        else
            print_error "Lint failed for $value_name configuration"
            eval "$helm_cmd" # Show the error
            return 1
        fi
    done
    
    return 0
}

# Test template rendering
test_template_rendering() {
    print_header "Testing Template Rendering"
    
    local configs=("default::" "development::values-development.yaml" "production::values-production.yaml")
    
    for config in "${configs[@]}"; do
        local name="${config%%::*}"
        local values_file="${config##*::}"
        
        print_info "Testing template rendering for $name configuration..."
        
        if [[ -z "$values_file" ]]; then
            helm_cmd="helm template test-$name . --dry-run"
        else
            helm_cmd="helm template test-$name . -f $values_file --dry-run"
        fi
        
        if eval "$helm_cmd" >/dev/null 2>&1; then
            print_success "Template rendering successful for $name"
        else
            print_error "Template rendering failed for $name"
            return 1
        fi
    done
    
    return 0
}

# Validate Azure-specific features
validate_azure_features() {
    print_header "Validating Azure-Specific Features"
    
    print_info "Checking Azure Key Vault CSI driver integration..."
    if helm template . -f values-production.yaml | grep -q "SecretProviderClass"; then
        print_success "Azure Key Vault CSI driver integration found"
    else
        print_warning "Azure Key Vault CSI driver integration not found"
    fi
    
    print_info "Checking Azure Workload Identity configuration..."
    if helm template . -f values-production.yaml | grep -q "azure.workload.identity"; then
        print_success "Azure Workload Identity configuration found"
    else
        print_warning "Azure Workload Identity configuration not found"
    fi
    
    print_info "Checking Azure Storage configuration..."
    if helm template . -f values-production.yaml | grep -q '"type": "azure"'; then
        print_success "Azure Storage configuration found"
    else
        print_warning "Azure Storage configuration not found"
    fi
    
    return 0
}

# Validate security features
validate_security_features() {
    print_header "Validating Security Features"
    
    print_info "Checking Network Policies..."
    if helm template . -f values-production.yaml | grep -q "NetworkPolicy"; then
        print_success "Network Policies configured"
    else
        print_warning "Network Policies not found"
    fi
    
    print_info "Checking Service Account configuration..."
    if helm template . | grep -q "ServiceAccount"; then
        print_success "Service Account configured"
    else
        print_error "Service Account not found"
        return 1
    fi
    
    print_info "Checking Pod Security Context..."
    if helm template . -f values-production.yaml | grep -q "securityContext"; then
        print_success "Pod Security Context configured"
    else
        print_warning "Pod Security Context not found"
    fi
    
    return 0
}

# Validate monitoring and observability
validate_monitoring() {
    print_header "Validating Monitoring & Observability"
    
    print_info "Checking monitoring configuration..."
    if helm template . -f values-production.yaml --show-only templates/monitoring-configmap.yaml >/dev/null 2>&1; then
        print_success "Monitoring ConfigMap template is valid"
    else
        print_error "Monitoring ConfigMap template has issues"
        return 1
    fi
    
    print_info "Checking HPA configuration..."
    if helm template . -f values-production.yaml --show-only templates/hpa.yaml >/dev/null 2>&1; then
        print_success "HPA template is valid"
    else
        print_warning "HPA template has issues"
    fi
    
    return 0
}

# Validate backup functionality
validate_backup() {
    print_header "Validating Backup Functionality"
    
    print_info "Checking backup CronJob..."
    if helm template . -f values-production.yaml --show-only templates/backup-cronjob.yaml >/dev/null 2>&1; then
        print_success "Backup CronJob template is valid"
    else
        print_error "Backup CronJob template has issues"
        return 1
    fi
    
    return 0
}

# Generate deployment commands
generate_deployment_commands() {
    print_header "Deployment Commands"
    
    echo -e "\n${BLUE}Quick Start Commands:${NC}"
    echo -e "1. ${YELLOW}Set up Azure resources:${NC}"
    echo -e "   ./setup-azure.sh"
    
    echo -e "\n2. ${YELLOW}Deploy to development:${NC}"
    echo -e "   ./deploy.sh install development"
    
    echo -e "\n3. ${YELLOW}Deploy to production:${NC}"
    echo -e "   ./deploy.sh install production"
    
    echo -e "\n4. ${YELLOW}Check deployment health:${NC}"
    echo -e "   ./health-check.sh"
    
    echo -e "\n5. ${YELLOW}Monitor deployment:${NC}"
    echo -e "   kubectl get pods -l app.kubernetes.io/name=airbyte"
    echo -e "   kubectl logs -l app.kubernetes.io/name=airbyte-webapp"
    
    echo -e "\n${BLUE}Manual Helm Commands:${NC}"
    echo -e "1. ${YELLOW}Install with development values:${NC}"
    echo -e "   helm install airbyte-dev . -f values-development.yaml"
    
    echo -e "\n2. ${YELLOW}Install with production values:${NC}"
    echo -e "   helm install airbyte-prod . -f values-production.yaml"
    
    echo -e "\n3. ${YELLOW}Upgrade deployment:${NC}"
    echo -e "   helm upgrade airbyte-prod . -f values-production.yaml"
    
    echo -e "\n4. ${YELLOW}Uninstall deployment:${NC}"
    echo -e "   helm uninstall airbyte-prod"
}

# Main validation function
main() {
    echo -e "${BLUE}🔍 Airbyte AKS Helm Chart Validation${NC}"
    echo -e "${BLUE}======================================${NC}"
    
    local failed_checks=0
    
    if ! validate_prerequisites; then
        ((failed_checks++))
    fi
    
    if ! validate_chart_structure; then
        ((failed_checks++))
    fi
    
    if ! run_helm_validation; then
        ((failed_checks++))
    fi
    
    if ! test_template_rendering; then
        ((failed_checks++))
    fi
    
    validate_azure_features
    validate_security_features
    validate_monitoring
    validate_backup
    
    print_header "Validation Summary"
    
    if [[ $failed_checks -eq 0 ]]; then
        print_success "All critical validations passed!"
        print_info "Your Airbyte AKS Helm chart is ready for deployment"
        
        generate_deployment_commands
        
        print_info "\nFor more information, check the documentation:"
        print_info "- README.md: Overall project documentation"
        print_info "- QUICKSTART.md: Quick deployment guide"
        print_info "- TESTING.md: Testing procedures"
        
    else
        print_error "$failed_checks critical validation(s) failed"
        print_info "Please fix the issues above before deploying"
        return 1
    fi
    
    return 0
}

# Run the main function
main "$@"
