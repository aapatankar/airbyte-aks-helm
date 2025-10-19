#!/bin/bash
# Helm Chart API V2 Validation Script
# Ensures your chart remains compliant with Helm Chart API v2

set -e

CHART_DIR="."
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Validating Helm Chart API V2 Compliance..."
echo "================================================"

# Check 1: Chart.yaml apiVersion
echo -n "1. Checking Chart.yaml apiVersion... "
if grep -q "apiVersion: v2" Chart.yaml; then
    echo -e "${GREEN}✅ PASS${NC} - Using apiVersion: v2"
else
    echo -e "${RED}❌ FAIL${NC} - Must use apiVersion: v2"
    exit 1
fi

# Check 2: Chart type specified
echo -n "2. Checking chart type... "
if grep -q "type: application" Chart.yaml; then
    echo -e "${GREEN}✅ PASS${NC} - Chart type specified"
else
    echo -e "${YELLOW}⚠️  WARN${NC} - Chart type not specified (recommended for v2)"
fi

# Check 3: Dependencies in Chart.yaml (not requirements.yaml)
echo -n "3. Checking dependency format... "
if grep -q "dependencies:" Chart.yaml; then
    echo -e "${GREEN}✅ PASS${NC} - Dependencies in Chart.yaml (v2 format)"
elif [ -f "requirements.yaml" ]; then
    echo -e "${RED}❌ FAIL${NC} - Found requirements.yaml (v1 format). Use dependencies in Chart.yaml"
    exit 1
else
    echo -e "${GREEN}✅ PASS${NC} - No dependencies found"
fi

# Check 4: No requirements.yaml file exists
echo -n "4. Checking for legacy requirements.yaml... "
if [ -f "requirements.yaml" ]; then
    echo -e "${RED}❌ FAIL${NC} - requirements.yaml found (v1 legacy file)"
    exit 1
else
    echo -e "${GREEN}✅ PASS${NC} - No legacy requirements.yaml"
fi

# Check 5: Chart.lock exists if dependencies present
echo -n "5. Checking Chart.lock... "
if grep -q "dependencies:" Chart.yaml; then
    if [ -f "Chart.lock" ]; then
        echo -e "${GREEN}✅ PASS${NC} - Chart.lock present for dependencies"
    else
        echo -e "${YELLOW}⚠️  WARN${NC} - Chart.lock missing. Run 'helm dependency update'"
    fi
else
    echo -e "${GREEN}✅ PASS${NC} - No dependencies, Chart.lock not needed"
fi

# Check 6: Helm version compatibility
echo -n "6. Checking Helm version... "
HELM_VERSION=$(helm version --short --client | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
MAJOR_VERSION=$(echo $HELM_VERSION | cut -d'.' -f1 | tr -d 'v')

if [ "$MAJOR_VERSION" -ge 3 ]; then
    echo -e "${GREEN}✅ PASS${NC} - Helm $HELM_VERSION supports Chart API v2"
else
    echo -e "${RED}❌ FAIL${NC} - Helm $HELM_VERSION does not support Chart API v2. Upgrade to Helm 3.x"
    exit 1
fi

# Check 7: Lint validation
echo -n "7. Running helm lint... "
if helm lint . > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PASS${NC} - Chart passes lint validation"
else
    echo -e "${RED}❌ FAIL${NC} - Chart fails lint validation"
    echo "Run 'helm lint .' for details"
    exit 1
fi

# Check 8: Template validation
echo -n "8. Validating templates... "
if helm template test-release . > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PASS${NC} - Templates render successfully"
else
    echo -e "${RED}❌ FAIL${NC} - Template rendering failed"
    echo "Run 'helm template test-release .' for details"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 SUCCESS!${NC} Your chart is fully compliant with Helm Chart API V2"
echo ""
echo "📋 Summary:"
echo "  - Chart API Version: v2 ✅"
echo "  - Chart Type: application ✅"
echo "  - Dependencies: Chart.yaml format ✅"
echo "  - Helm Version: Compatible ✅"
echo "  - Validation: All checks passed ✅"
