#!/bin/bash
# =============================================================================
# Migrate Terraform State to GitLab
# =============================================================================
# This script migrates existing Terraform state from local storage to GitLab
# HTTP backend for all modules.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$REPO_ROOT/terraform"

echo "========================================="
echo "Terraform State Migration to GitLab"
echo "========================================="
echo ""

# Function to migrate a module
migrate_module() {
    local module_name=$1
    local module_path="$TERRAFORM_DIR/$module_name"

    echo "---"
    echo "Migrating: $module_name"
    echo "---"

    if [ ! -d "$module_path" ]; then
        echo "⚠️  Module not found: $module_path"
        return
    fi

    cd "$module_path"

    # Check if local state exists
    if [ -f "terraform.tfstate" ]; then
        echo "✓ Local state file found"

        # Create backup
        backup_file="terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)"
        cp terraform.tfstate "$backup_file"
        echo "✓ Backup created: $backup_file"
    else
        echo "ℹ️  No local state file found (might already be using remote backend)"
    fi

    # Check if backend.hcl exists
    if [ ! -f "backend.hcl" ]; then
        echo "❌ backend.hcl not found. Please create it from backend.hcl.example"
        return 1
    fi

    # Initialize with new backend
    echo ""
    echo "Initializing with GitLab backend..."
    echo "If prompted, answer 'yes' to copy existing state to new backend."
    echo ""

    terraform init -backend-config=backend.hcl

    echo ""
    echo "✓ Migration complete for $module_name"
    echo ""
    echo "Verifying state..."
    terraform state list
    echo ""
}

# Migrate each module
modules=("control-plane" "gitlab" "gitlab-config")

for module in "${modules[@]}"; do
    migrate_module "$module"
    echo ""
    read -p "Press Enter to continue to next module (or Ctrl+C to stop)..."
    echo ""
done

echo "========================================="
echo "✓ All migrations complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Verify states in GitLab UI: http://YOUR_GITLAB/root/proxmox-iac/-/terraform"
echo "2. Delete old local .tfstate files (keep backups!)"
echo "3. Test terraform plan/apply in each module"
echo ""
