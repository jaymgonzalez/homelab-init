# =============================================================================
# GitLab CE LXC Container
# =============================================================================
# This container hosts GitLab CE with Container Registry enabled.
# GitLab Runner will be installed on the control-plane, not in this container.
# =============================================================================

resource "proxmox_lxc" "gitlab" {
  target_node  = var.proxmox_node
  hostname     = var.gitlab_hostname
  vmid         = var.gitlab_vmid
  ostemplate   = var.template
  password     = var.root_password
  unprivileged = true

  cores  = var.gitlab_cores
  memory = var.gitlab_memory
  swap   = var.gitlab_swap

  # SSH keys
  ssh_public_keys = var.ssh_public_keys

  # Root filesystem
  rootfs {
    storage = var.gitlab_storage
    size    = var.gitlab_disk_size
  }

  # Network configuration
  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = var.gitlab_ip
    gw     = var.gateway
    tag    = var.vlan_tag > 0 ? var.vlan_tag : null
  }

  # DNS
  nameserver = var.nameserver

  # Start on boot
  onboot = true
  start  = true

  # Tags
  tags = join(";", var.tags)

  # Lifecycle
  lifecycle {
    ignore_changes = [
      # Ignore changes to template after creation
      ostemplate,
    ]
  }
}

# Extract IP without CIDR mask
locals {
  gitlab_ip_clean = split("/", var.gitlab_ip)[0]
}
