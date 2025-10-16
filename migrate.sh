#!/bin/bash

# Airbyte Migration and Upgrade Script
# This script helps migrate data and upgrade Airbyte deployments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="airbyte"
RELEASE_NAME="airbyte"
BACKUP_DIR="$SCRIPT_DIR/migration-backups/$(date +%Y%m%d_%H%M%S)"

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

show_help() {
    cat << EOF
Airbyte Migration and Upgrade Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    backup          Create a full backup before migration
    restore         Restore from a backup
    migrate-db      Migrate database schema
    upgrade         Upgrade Airbyte to new version
    rollback        Rollback to previous version
    validate        Validate migration/upgrade
    
Options:
    -n, --namespace NS       Kubernetes namespace [default: airbyte]
    -r, --release NAME       Helm release name [default: airbyte]
    -b, --backup-dir DIR     Backup directory
    -v, --version VERSION    Target version for upgrade
    --dry-run               Run in dry-run mode
    -h, --help              Show this help message

Examples:
    $0 backup
    $0 upgrade -v 1.8.0
    $0 migrate-db --dry-run
    $0 rollback
    
EOF
}

create_migration_backup() {
    local dry_run=$1
    
    log_info "Creating migration backup..."
    mkdir -p "$BACKUP_DIR"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would create backup in: $BACKUP_DIR"
        return
    fi
    
    # Backup Helm values
    log_info "Backing up Helm values..."
    helm get values "$RELEASE_NAME" -n "$NAMESPACE" > "$BACKUP_DIR/helm-values.yaml"
    
    # Backup Kubernetes resources
    log_info "Backing up Kubernetes resources..."
    kubectl get all,secrets,configmaps,ingress,pvc -n "$NAMESPACE" -o yaml > "$BACKUP_DIR/k8s-resources.yaml"
    
    # Backup database (if external)
    if kubectl get secret airbyte-config-secrets -n "$NAMESPACE" -o jsonpath='{.data.database-host}' 2>/dev/null | base64 -d | grep -q "."; then
        log_info "Backing up external database..."
        
        # Create database backup job
        cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: airbyte-migration-backup
  namespace: $NAMESPACE
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: postgres-backup
        image: postgres:13
        command:
        - /bin/bash
        - -c
        - |
          pg_dump \
            --host="\$DB_HOST" \
            --port="\$DB_PORT" \
            --username="\$DB_USER" \
            --dbname="\$DB_NAME" \
            --verbose \
            --clean \
            --no-owner \
            --no-privileges \
            > /backup/migration-backup.sql
        env:
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: airbyte-config-secrets
              key: database-host
              optional: true
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "airbyte"
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: airbyte-config-secrets
              key: database-user
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: airbyte-config-secrets
              key: database-password
        volumeMounts:
        - name: backup-storage
          mountPath: /backup
      volumes:
      - name: backup-storage
        emptyDir: {}
EOF
        
        # Wait for backup job to complete
        kubectl wait --for=condition=complete job/airbyte-migration-backup -n "$NAMESPACE" --timeout=600s
        
        # Copy backup from pod
        kubectl cp "$NAMESPACE/$(kubectl get pods -n "$NAMESPACE" -l job-name=airbyte-migration-backup -o jsonpath='{.items[0].metadata.name}'):/backup/migration-backup.sql" "$BACKUP_DIR/database-backup.sql"
        
        # Clean up backup job
        kubectl delete job airbyte-migration-backup -n "$NAMESPACE"
    fi
    
    # Create backup manifest
    cat << EOF > "$BACKUP_DIR/backup-manifest.yaml"
backup:
  timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
  namespace: $NAMESPACE
  release: $RELEASE_NAME
  version: $(helm list -n "$NAMESPACE" | grep "$RELEASE_NAME" | awk '{print $10}')
  files:
    - helm-values.yaml
    - k8s-resources.yaml
    - database-backup.sql
EOF
    
    log_info "Migration backup completed: $BACKUP_DIR"
}

perform_upgrade() {
    local target_version=$1
    local dry_run=$2
    
    log_info "Upgrading Airbyte to version: $target_version"
    
    # Pre-upgrade validation
    log_info "Running pre-upgrade validation..."
    if ! helm lint "$SCRIPT_DIR" --values "$SCRIPT_DIR/values-production.yaml"; then
        log_error "Helm chart validation failed"
        return 1
    fi
    
    # Scale down workloads
    if [[ "$dry_run" != "true" ]]; then
        log_info "Scaling down workloads..."
        kubectl scale deployment airbyte-worker --replicas=0 -n "$NAMESPACE" || true
        kubectl scale deployment airbyte-workload-launcher --replicas=0 -n "$NAMESPACE" || true
        
        # Wait for pods to terminate
        kubectl wait --for=delete pod -l app.kubernetes.io/component=worker -n "$NAMESPACE" --timeout=300s || true
    fi
    
    # Perform upgrade
    local helm_args=()
    helm_args+=(upgrade "$RELEASE_NAME" "$SCRIPT_DIR")
    helm_args+=(--namespace "$NAMESPACE")
    helm_args+=(--set global.image.tag="$target_version")
    
    if [[ "$dry_run" == "true" ]]; then
        helm_args+=(--dry-run)
    else
        helm_args+=(--wait --timeout=600s)
    fi
    
    helm "${helm_args[@]}"
    
    if [[ "$dry_run" != "true" ]]; then
        # Run database migrations if needed
        log_info "Running database migrations..."
        kubectl wait --for=condition=available deployment/airbyte-server -n "$NAMESPACE" --timeout=600s
        
        # Scale workloads back up
        log_info "Scaling workloads back up..."
        kubectl scale deployment airbyte-worker --replicas=2 -n "$NAMESPACE"
        kubectl scale deployment airbyte-workload-launcher --replicas=1 -n "$NAMESPACE"
    fi
    
    log_info "Upgrade completed successfully"
}

validate_upgrade() {
    log_info "Validating upgrade..."
    
    # Check pod status
    local ready_pods
    ready_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -c "1/1.*Running" || echo "0")
    local total_pods  
    total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l || echo "0")
    
    if [[ $ready_pods -eq $total_pods ]] && [[ $total_pods -gt 0 ]]; then
        log_info "✓ All pods are ready ($ready_pods/$total_pods)"
    else
        log_error "✗ Some pods are not ready ($ready_pods/$total_pods)"
        kubectl get pods -n "$NAMESPACE"
        return 1
    fi
    
    # Test health endpoints
    log_info "Testing health endpoints..."
    kubectl port-forward -n "$NAMESPACE" service/airbyte-webapp 18080:80 &
    local pf_pid=$!
    sleep 5
    
    if curl -f --max-time 10 http://localhost:18080/health &> /dev/null; then
        log_info "✓ Health endpoints are responding"
    else
        log_error "✗ Health endpoints are not responding"
        kill $pf_pid 2>/dev/null || true
        return 1
    fi
    
    kill $pf_pid 2>/dev/null || true
    
    log_info "Validation completed successfully"
}

perform_rollback() {
    log_info "Rolling back Airbyte deployment..."
    
    # Get previous revision
    local previous_revision
    previous_revision=$(helm history "$RELEASE_NAME" -n "$NAMESPACE" --max=2 -o json | jq -r '.[0].revision')
    
    if [[ "$previous_revision" == "null" ]] || [[ "$previous_revision" == "1" ]]; then
        log_error "No previous revision found for rollback"
        return 1
    fi
    
    log_info "Rolling back to revision: $previous_revision"
    helm rollback "$RELEASE_NAME" "$previous_revision" -n "$NAMESPACE" --wait
    
    log_info "Rollback completed successfully"
}

migrate_database() {
    local dry_run=$1
    
    log_info "Running database migration..."
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY RUN] Would run database migration"
        return
    fi
    
    # Create migration job
    cat << EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: airbyte-db-migration
  namespace: $NAMESPACE
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migration
        image: airbyte/bootloader:latest
        env:
        - name: DATABASE_URL
          value: "jdbc:postgresql://\$(DB_HOST):\$(DB_PORT)/\$(DB_NAME)"
        - name: DB_HOST
          valueFrom:
            secretKeyRef:
              name: airbyte-config-secrets
              key: database-host
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "airbyte"
        - name: DATABASE_USER
          valueFrom:
            secretKeyRef:
              name: airbyte-config-secrets
              key: database-user
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: airbyte-config-secrets
              key: database-password
EOF
    
    # Wait for migration to complete
    kubectl wait --for=condition=complete job/airbyte-db-migration -n "$NAMESPACE" --timeout=600s
    
    # Check migration logs
    kubectl logs job/airbyte-db-migration -n "$NAMESPACE"
    
    # Clean up migration job
    kubectl delete job airbyte-db-migration -n "$NAMESPACE"
    
    log_info "Database migration completed"
}

# Parse command line arguments
COMMAND=""
TARGET_VERSION=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        backup|restore|migrate-db|upgrade|rollback|validate)
            COMMAND=$1
            shift
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -v|--version)
            TARGET_VERSION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
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

# Main execution
case $COMMAND in
    backup)
        create_migration_backup "$DRY_RUN"
        ;;
    upgrade)
        if [[ -z "$TARGET_VERSION" ]]; then
            log_error "Target version is required for upgrade"
            exit 1
        fi
        create_migration_backup "$DRY_RUN"
        perform_upgrade "$TARGET_VERSION" "$DRY_RUN"
        if [[ "$DRY_RUN" != "true" ]]; then
            validate_upgrade
        fi
        ;;
    migrate-db)
        migrate_database "$DRY_RUN"
        ;;
    rollback)
        perform_rollback
        validate_upgrade
        ;;
    validate)
        validate_upgrade
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
