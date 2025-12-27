# =============================================================================
# Outputs
# =============================================================================

output "control_plane_id" {
  description = "VM ID of the control plane container"
  value       = proxmox_lxc.control_plane.vmid
}

output "control_plane_hostname" {
  description = "Hostname of the control plane"
  value       = proxmox_lxc.control_plane.hostname
}

output "control_plane_ip" {
  description = "IP address of the control plane"
  value       = local.control_plane_ip_clean
}

output "ssh_command" {
  description = "SSH command to connect to the control plane"
  value       = "ssh root@${local.control_plane_ip_clean}"
}

output "ansible_inventory_entry" {
  description = "Entry to add to Ansible inventory"
  value       = <<-EOT
    control_plane:
      hosts:
        ${proxmox_lxc.control_plane.hostname}:
          ansible_host: ${local.control_plane_ip_clean}
          ansible_user: root
  EOT
}
