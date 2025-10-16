#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔍 Running comprehensive Helm chart tests..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

run_test() {
    local test_name="$1"
    local command="$2"
    echo -n "Running $test_name... "
    if eval "$command" >/dev/null 2>&1; then
        print_status "PASSED"
        return 0
    else
        print_error "FAILED"
        return 1
    fi
}

# Test 1: Basic lint validation
echo "📋 Test 1: Basic Chart Validation"
run_test "Helm lint (default values)" "helm lint ."
run_test "Helm lint (development values)" "helm lint . -f values-development.yaml"
run_test "Helm lint (production values)" "helm lint . -f values-production.yaml"

# Test 2: Template rendering
echo -e "\n📋 Test 2: Template Rendering"
run_test "Template rendering (default)" "helm template airbyte-test . --dry-run"
run_test "Template rendering (development)" "helm template airbyte-test . -f values-development.yaml --dry-run"
run_test "Template rendering (production)" "helm template airbyte-test . -f values-production.yaml --dry-run"

# Test 3: Dependency checks
echo -e "\n📋 Test 3: Dependency Management"
run_test "Dependency update" "helm dependency update"
run_test "Chart dependency validation" "helm dependency list | grep -q airbyte"

# Test 4: Kubernetes resource validation
echo -e "\n📋 Test 4: Kubernetes Resource Validation"
run_test "ServiceAccount template" "helm template . --show-only templates/serviceaccount.yaml | kubectl apply --dry-run=client -f -"
run_test "NetworkPolicy template" "helm template . --show-only templates/networkpolicy.yaml | kubectl apply --dry-run=client -f -"

# Test 5: Values validation
echo -e "\n📋 Test 5: Values File Structure"
validate_yaml_file() {
    local file="$1"
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

run_test "values.yaml structure" "validate_yaml_file values.yaml"
run_test "values-development.yaml structure" "validate_yaml_file values-development.yaml"
run_test "values-production.yaml structure" "validate_yaml_file values-production.yaml"

# Test 6: Azure-specific configurations
echo -e "\n📋 Test 6: Azure Integration Features"
run_test "Azure Key Vault CSI template" "helm template . -f values-production.yaml --show-only templates/secretproviderclass.yaml"
run_test "Workload Identity configuration" "helm template . -f values-production.yaml | grep -q 'azure.workload.identity'"
run_test "Azure storage configuration" "helm template . -f values-production.yaml | grep -q 'azure'"

# Test 7: Security features
echo -e "\n📋 Test 7: Security Features"
run_test "Network policies enabled" "helm template . -f values-production.yaml | grep -q 'NetworkPolicy'"
run_test "Pod security context" "helm template . -f values-production.yaml | grep -q 'securityContext'"
run_test "RBAC configuration" "helm template . | grep -q 'ServiceAccount'"

# Test 8: Monitoring and observability
echo -e "\n📋 Test 8: Monitoring & Observability"
run_test "Monitoring configuration" "helm template . -f values-production.yaml --show-only templates/monitoring-configmap.yaml"
run_test "HPA configuration" "helm template . -f values-production.yaml --show-only templates/hpa.yaml"

# Test 9: Backup functionality
echo -e "\n📋 Test 9: Backup & Recovery"
run_test "Backup CronJob template" "helm template . -f values-production.yaml --show-only templates/backup-cronjob.yaml"

# Test 10: Development tools
echo -e "\n📋 Test 10: Development Tools"
run_test "Development tools template" "helm template . -f values-development.yaml --show-only templates/development-tools.yaml"

echo -e "\n🎉 All tests completed!"
echo -e "\n📊 Test Summary:"
echo "- Chart validation: ✓"
echo "- Template rendering: ✓"
echo "- Kubernetes resource validation: ✓"
echo "- Azure integration features: ✓"
echo "- Security configurations: ✓"
echo "- Monitoring setup: ✓"
echo "- Backup functionality: ✓"

echo -e "\n🚀 Your Airbyte AKS Helm chart is ready for deployment!"
echo -e "\nNext steps:"
echo "1. Configure your Azure resources using: ./setup-azure.sh"
echo "2. Deploy to development: ./deploy.sh install development"
echo "3. Deploy to production: ./deploy.sh install production"
echo "4. Monitor health: ./health-check.sh"
