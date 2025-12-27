# =============================================================================
# Outputs
# =============================================================================

output "gitlab_id" {
  description = "VM ID of the GitLab container"
  value       = proxmox_lxc.gitlab.vmid
}

output "gitlab_hostname" {
  description = "Hostname of GitLab"
  value       = proxmox_lxc.gitlab.hostname
}

output "gitlab_ip" {
  description = "IP address of GitLab"
  value       = local.gitlab_ip_clean
}

output "gitlab_url" {
  description = "GitLab web interface URL"
  value       = "http://${local.gitlab_ip_clean}"
}

output "registry_url" {
  description = "GitLab Container Registry URL"
  value       = "http://registry.${local.gitlab_ip_clean}:5050"
}

output "ssh_command" {
  description = "SSH command to connect to GitLab"
  value       = "ssh root@${local.gitlab_ip_clean}"
}

output "ansible_inventory_entry" {
  description = "Entry to add to Ansible inventory"
  value       = <<-EOT
    gitlab:
      hosts:
        ${proxmox_lxc.gitlab.hostname}:
          ansible_host: ${local.gitlab_ip_clean}
          ansible_user: root
  EOT
}
