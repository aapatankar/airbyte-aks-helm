#!/bin/bash

# Azure Setup Script for Airbyte AKS Deployment
# This script helps set up the required Azure resources

set -euo pipefail

# Configuration
RESOURCE_GROUP=""
LOCATION="eastus"
AKS_CLUSTER_NAME=""
POSTGRES_SERVER_NAME=""
STORAGE_ACCOUNT_NAME=""
KEY_VAULT_NAME=""
ACR_NAME=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
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

show_help() {
    cat << EOF
Azure Setup Script for Airbyte AKS Deployment

Usage: $0 [OPTIONS]

Options:
    -g, --resource-group NAME    Azure resource group name (required)
    -l, --location LOCATION      Azure region [default: eastus]
    -c, --cluster-name NAME      AKS cluster name (required)
    -p, --postgres-name NAME     PostgreSQL server name (required)
    -s, --storage-name NAME      Storage account name (required)
    -k, --keyvault-name NAME     Key Vault name (required)
    -r, --acr-name NAME          Container Registry name (optional)
    --create-all                 Create all resources
    --create-aks                 Create AKS cluster only
    --create-postgres           Create PostgreSQL only
    --create-storage            Create Storage Account only
    --create-keyvault           Create Key Vault only
    --create-acr                Create Container Registry only
    -h, --help                  Show this help message

Examples:
    $0 -g mygroup -c myaks -p mypostgres -s mystorage -k mykeyvault --create-all
    $0 -g mygroup -c myaks --create-aks
    
EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure CLI. Run 'az login' first."
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

validate_names() {
    # Validate resource names according to Azure naming conventions
    if [[ ${#STORAGE_ACCOUNT_NAME} -lt 3 || ${#STORAGE_ACCOUNT_NAME} -gt 24 ]]; then
        log_error "Storage account name must be between 3 and 24 characters"
        exit 1
    fi
    
    if [[ ! "$STORAGE_ACCOUNT_NAME" =~ ^[a-z0-9]+$ ]]; then
        log_error "Storage account name must contain only lowercase letters and numbers"
        exit 1
    fi
    
    if [[ -n "$ACR_NAME" ]] && [[ ! "$ACR_NAME" =~ ^[a-zA-Z0-9]+$ ]]; then
        log_error "ACR name must contain only alphanumeric characters"
        exit 1
    fi
}

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        log_info "Resource group created successfully"
    fi
}

create_aks_cluster() {
    log_info "Creating AKS cluster: $AKS_CLUSTER_NAME"
    
    if az aks show --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME" &> /dev/null; then
        log_info "AKS cluster '$AKS_CLUSTER_NAME' already exists"
    else
        az aks create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$AKS_CLUSTER_NAME" \
            --node-count 3 \
            --node-vm-size Standard_D2s_v3 \
            --enable-addons monitoring,azure-keyvault-secrets-provider \
            --enable-oidc-issuer \
            --enable-workload-identity \
            --generate-ssh-keys \
            --network-plugin azure \
            --network-policy calico
        
        log_info "AKS cluster created successfully"
    fi
    
    # Get credentials
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$AKS_CLUSTER_NAME"
    log_info "AKS credentials configured"
}

create_postgres_server() {
    log_info "Creating PostgreSQL server: $POSTGRES_SERVER_NAME"
    
    if az postgres flexible-server show --resource-group "$RESOURCE_GROUP" --name "$POSTGRES_SERVER_NAME" &> /dev/null; then
        log_info "PostgreSQL server '$POSTGRES_SERVER_NAME' already exists"
    else
        # Generate a random password
        local admin_password
        admin_password=$(openssl rand -base64 32)
        
        az postgres flexible-server create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$POSTGRES_SERVER_NAME" \
            --location "$LOCATION" \
            --admin-user airbyte_admin \
            --admin-password "$admin_password" \
            --sku-name Standard_D2s_v3 \
            --tier GeneralPurpose \
            --storage-size 128 \
            --version 13
        
        # Create Airbyte database
        az postgres flexible-server db create \
            --resource-group "$RESOURCE_GROUP" \
            --server-name "$POSTGRES_SERVER_NAME" \
            --database-name airbyte
        
        # Configure firewall to allow AKS
        az postgres flexible-server firewall-rule create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$POSTGRES_SERVER_NAME" \
            --rule-name AllowAzureServices \
            --start-ip-address 0.0.0.0 \
            --end-ip-address 0.0.0.0
        
        log_info "PostgreSQL server created successfully"
        log_info "Admin password: $admin_password"
        log_warn "Please save the admin password securely!"
    fi
}

create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Storage account '$STORAGE_ACCOUNT_NAME' already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2
        
        # Create containers
        local storage_key
        storage_key=$(az storage account keys list --account-name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --query '[0].value' -o tsv)
        
        for container in airbyte-logs airbyte-state airbyte-workload-output airbyte-activity-payload; do
            az storage container create \
                --name "$container" \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --account-key "$storage_key"
        done
        
        log_info "Storage account created successfully"
        log_info "Storage key: $storage_key"
        log_warn "Please save the storage key securely!"
    fi
}

create_key_vault() {
    log_info "Creating Key Vault: $KEY_VAULT_NAME"
    
    if az keyvault show --name "$KEY_VAULT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Key Vault '$KEY_VAULT_NAME' already exists"
    else
        az keyvault create \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --enable-rbac-authorization
        
        log_info "Key Vault created successfully"
    fi
}

create_container_registry() {
    if [[ -z "$ACR_NAME" ]]; then
        log_info "Skipping ACR creation (not specified)"
        return
    fi
    
    log_info "Creating Container Registry: $ACR_NAME"
    
    if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Container Registry '$ACR_NAME' already exists"
    else
        az acr create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ACR_NAME" \
            --sku Basic
        
        # Attach ACR to AKS cluster
        az aks update \
            --name "$AKS_CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --attach-acr "$ACR_NAME"
        
        log_info "Container Registry created and attached to AKS"
    fi
}

setup_workload_identity() {
    log_info "Setting up Workload Identity..."
    
    local identity_name="airbyte-workload-identity"
    
    # Create managed identity
    az identity create \
        --name "$identity_name" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION"
    
    local client_id
    client_id=$(az identity show --name "$identity_name" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)
    
    # Assign roles
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee "$client_id" \
        --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"
    
    az role assignment create \
        --role "Storage Blob Data Contributor" \
        --assignee "$client_id" \
        --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
    
    log_info "Workload Identity setup completed"
    log_info "Client ID: $client_id"
}

create_all_resources() {
    create_resource_group
    create_aks_cluster
    create_postgres_server
    create_storage_account
    create_key_vault
    create_container_registry
    setup_workload_identity
}

# Parse arguments
CREATE_ALL=false
CREATE_AKS=false
CREATE_POSTGRES=false
CREATE_STORAGE=false
CREATE_KEYVAULT=false
CREATE_ACR=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -c|--cluster-name)
            AKS_CLUSTER_NAME="$2"
            shift 2
            ;;
        -p|--postgres-name)
            POSTGRES_SERVER_NAME="$2"
            shift 2
            ;;
        -s|--storage-name)
            STORAGE_ACCOUNT_NAME="$2"
            shift 2
            ;;
        -k|--keyvault-name)
            KEY_VAULT_NAME="$2"
            shift 2
            ;;
        -r|--acr-name)
            ACR_NAME="$2"
            shift 2
            ;;
        --create-all)
            CREATE_ALL=true
            shift
            ;;
        --create-aks)
            CREATE_AKS=true
            shift
            ;;
        --create-postgres)
            CREATE_POSTGRES=true
            shift
            ;;
        --create-storage)
            CREATE_STORAGE=true
            shift
            ;;
        --create-keyvault)
            CREATE_KEYVAULT=true
            shift
            ;;
        --create-acr)
            CREATE_ACR=true
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

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    log_error "Resource group name is required"
    exit 1
fi

if [[ "$CREATE_ALL" == true || "$CREATE_AKS" == true ]] && [[ -z "$AKS_CLUSTER_NAME" ]]; then
    log_error "AKS cluster name is required"
    exit 1
fi

if [[ "$CREATE_ALL" == true || "$CREATE_POSTGRES" == true ]] && [[ -z "$POSTGRES_SERVER_NAME" ]]; then
    log_error "PostgreSQL server name is required"
    exit 1
fi

if [[ "$CREATE_ALL" == true || "$CREATE_STORAGE" == true ]] && [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
    log_error "Storage account name is required"
    exit 1
fi

if [[ "$CREATE_ALL" == true || "$CREATE_KEYVAULT" == true ]] && [[ -z "$KEY_VAULT_NAME" ]]; then
    log_error "Key Vault name is required"
    exit 1
fi

check_prerequisites
validate_names

# Execute based on flags
if [[ "$CREATE_ALL" == true ]]; then
    create_all_resources
else
    create_resource_group
    
    if [[ "$CREATE_AKS" == true ]]; then
        create_aks_cluster
    fi
    
    if [[ "$CREATE_POSTGRES" == true ]]; then
        create_postgres_server
    fi
    
    if [[ "$CREATE_STORAGE" == true ]]; then
        create_storage_account
    fi
    
    if [[ "$CREATE_KEYVAULT" == true ]]; then
        create_key_vault
    fi
    
    if [[ "$CREATE_ACR" == true ]]; then
        create_container_registry
    fi
fi

log_info "Azure setup completed successfully!"
