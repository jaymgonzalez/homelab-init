# =============================================================================
# GitLab Project for proxmox-iac
# =============================================================================
# This configuration creates and manages the proxmox-iac project in GitLab,
# which will host the repository and Terraform state files.
# =============================================================================

# Optional: Create a group if specified
resource "gitlab_group" "homelab" {
  count = var.group_name != "" ? 1 : 0

  name        = var.group_name
  path        = var.group_path != "" ? var.group_path : lower(replace(var.group_name, " ", "-"))
  description = "Homelab Infrastructure Projects"
  visibility_level = var.project_visibility
}

# Create the proxmox-iac project
resource "gitlab_project" "proxmox_iac" {
  name        = var.project_name
  description = var.project_description

  # If group is created, use it; otherwise use personal namespace
  namespace_id = var.group_name != "" ? gitlab_group.homelab[0].id : null

  # Visibility
  visibility_level = var.project_visibility

  # Default branch
  default_branch = var.project_default_branch

  # Features
  issues_access_level            = var.enable_issues ? "enabled" : "disabled"
  wiki_access_level              = var.enable_wiki ? "enabled" : "disabled"
  snippets_access_level          = var.enable_snippets ? "enabled" : "disabled"
  container_registry_access_level = var.enable_container_registry ? "enabled" : "disabled"
  lfs_enabled                    = var.enable_lfs

  # Repository settings
  initialize_with_readme = false # We're pushing existing code
  only_allow_merge_if_pipeline_succeeds = false
  remove_source_branch_after_merge = true

  # Tags
  topics = ["proxmox", "infrastructure-as-code", "terraform", "ansible", "homelab"]
}
