# =============================================================================
# Outputs
# =============================================================================

output "project_id" {
  description = "GitLab project ID"
  value       = gitlab_project.proxmox_iac.id
}

output "project_name" {
  description = "GitLab project name"
  value       = gitlab_project.proxmox_iac.name
}

output "project_path" {
  description = "GitLab project path"
  value       = gitlab_project.proxmox_iac.path_with_namespace
}

output "project_url" {
  description = "GitLab project web URL"
  value       = gitlab_project.proxmox_iac.web_url
}

output "http_url" {
  description = "Git HTTP clone URL"
  value       = gitlab_project.proxmox_iac.http_url_to_repo
}

output "ssh_url" {
  description = "Git SSH clone URL"
  value       = gitlab_project.proxmox_iac.ssh_url_to_repo
}

output "terraform_state_url" {
  description = "Terraform HTTP backend URL for this project"
  value       = "${var.gitlab_url}/api/v4/projects/${gitlab_project.proxmox_iac.id}/terraform/state"
}

output "group_id" {
  description = "GitLab group ID (if created)"
  value       = var.group_name != "" ? gitlab_group.homelab[0].id : null
}
