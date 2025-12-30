# Terraform State Migration to GitLab

This guide covers migrating existing Terraform state from local storage to GitLab HTTP backend.

## Overview

All Terraform modules now use GitLab's built-in HTTP backend for state storage. States are stored at:
- **control-plane**: `http://192.168.10.101/api/v4/projects/1/terraform/state/control-plane`
- **gitlab**: `http://192.168.10.101/api/v4/projects/1/terraform/state/gitlab`
- **gitlab-config**: `http://192.168.10.101/api/v4/projects/1/terraform/state/gitlab-config`

## Prerequisites

- GitLab project created and accessible
- Personal access token with API scope
- `backend.hcl` files configured (already done if following the main guide)

## Migration Steps

### 1. Migrate control-plane state

```bash
cd terraform/control-plane

# Backup existing state (important!)
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# Initialize with new backend (Terraform will detect the change)
terraform init -backend-config=backend.hcl

# Terraform will ask: "Do you want to copy existing state to the new backend?"
# Answer: yes

# Verify migration
terraform state list
```

### 2. Migrate gitlab state

```bash
cd terraform/gitlab

# Backup existing state
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# Initialize with new backend
terraform init -backend-config=backend.hcl

# Answer yes to copy state

# Verify migration
terraform state list
```

### 3. Initialize gitlab-config state

```bash
cd terraform/gitlab-config

# This module may already be using GitLab backend
# If you have local state, run:
terraform init -backend-config=backend.hcl

# If starting fresh:
terraform init -backend-config=backend.hcl
terraform plan
terraform apply  # If you haven't applied yet
```

## Verification

After migration, verify state is in GitLab:

1. **Via Web UI**: Navigate to your GitLab project → **Infrastructure → Terraform states**
2. **Via CLI**: Run `terraform state list` in each module - should work without local `.tfstate` files

## Rollback (if needed)

If you need to roll back to local state:

```bash
# Remove backend configuration
rm backend.tf

# Copy backup back
cp terraform.tfstate.backup-YYYYMMDD terraform.tfstate

# Reinitialize
terraform init -migrate-state
```

## Working with Remote State

After migration:
- **Pull latest state**: `terraform refresh`
- **View state**: `terraform state list`
- **State locking**: Automatic via GitLab (prevents concurrent modifications)
- **State history**: Available in GitLab UI under Infrastructure → Terraform states

## Troubleshooting

### State Lock Error
If you get a lock error:
```bash
# Force unlock (use carefully!)
terraform force-unlock LOCK_ID
```

### Authentication Failed
Ensure your token in `backend.hcl` is correct and has API scope.

### State Mismatch
If Terraform detects state mismatch after migration:
```bash
# Pull remote state
terraform state pull > current-state.json
# Review and compare with local backup
```

## Security Notes

- `backend.hcl` contains credentials → gitignored, never commit
- State files may contain sensitive data → stored securely in GitLab
- Access controlled via GitLab project permissions
- Consider enabling state encryption in GitLab settings (Settings → CI/CD → Variables)
