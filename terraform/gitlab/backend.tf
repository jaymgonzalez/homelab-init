# =============================================================================
# GitLab HTTP Backend Configuration
# =============================================================================
# State is stored in GitLab: http://192.168.10.101/root/proxmox-iac
#
# To initialize/migrate:
#   terraform init -backend-config=backend.hcl
#
# Or set environment variables:
#   export TF_HTTP_USERNAME="root"
#   export TF_HTTP_PASSWORD="your-gitlab-token"
#   terraform init
# =============================================================================

terraform {
  backend "http" {
    # These will be provided via backend.hcl or environment variables
  }
}
