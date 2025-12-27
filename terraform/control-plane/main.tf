# =============================================================================
# Control Plane LXC Container
# =============================================================================
# Este contenedor será el punto central para gestionar toda la infraestructura
# con Terraform y Ansible. Una vez configurado, desde aquí se despliega todo.
# =============================================================================

resource "proxmox_lxc" "control_plane" {
  target_node  = var.proxmox_node
  hostname     = var.control_plane_hostname
  vmid         = var.control_plane_vmid
  ostemplate   = var.template
  password     = var.root_password
  unprivileged = true # Unprivileged is more secure and works with Docker

  cores  = var.control_plane_cores
  memory = var.control_plane_memory
  swap   = var.control_plane_swap

  # SSH keys
  ssh_public_keys = var.ssh_public_keys

  # Root filesystem
  rootfs {
    storage = var.control_plane_storage
    size    = var.control_plane_disk_size
  }

  # Network configuration
  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = var.control_plane_ip
    gw     = var.gateway
    tag    = var.vlan_tag > 0 ? var.vlan_tag : null
  }

  # DNS
  nameserver = var.nameserver

  # Features - Temporarily disabled to test permissions
  # features {
  #   nesting = true # Permite Docker dentro del container
  #   keyctl  = true # Necesario para algunos servicios
  # }

  # Start on boot
  onboot = true
  start  = true

  # Tags
  tags = join(";", var.tags)

  # Lifecycle
  lifecycle {
    ignore_changes = [
      # Ignorar cambios en el template después de la creación
      ostemplate,
    ]
  }
}

# Local para extraer IP sin máscara
locals {
  control_plane_ip_clean = split("/", var.control_plane_ip)[0]
}
