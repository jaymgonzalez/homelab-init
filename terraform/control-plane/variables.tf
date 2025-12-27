# =============================================================================
# Proxmox Connection
# =============================================================================

variable "proxmox_host" {
  description = "Proxmox host IP or hostname"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID (e.g., terraform@pve!terraform)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

# =============================================================================
# Control Plane LXC Configuration
# =============================================================================

variable "control_plane_vmid" {
  description = "VM ID for the control plane LXC"
  type        = number
  default     = 100
}

variable "control_plane_hostname" {
  description = "Hostname for the control plane"
  type        = string
  default     = "control-plane"
}

variable "control_plane_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "control_plane_memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "control_plane_swap" {
  description = "Swap in MB"
  type        = number
  default     = 512
}

variable "control_plane_disk_size" {
  description = "Root disk size (e.g., 20G)"
  type        = string
  default     = "20G"
}

variable "control_plane_storage" {
  description = "Storage pool for the LXC"
  type        = string
  default     = "local-lvm"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "control_plane_ip" {
  description = "Static IP for the control plane (CIDR format, e.g., 192.168.1.10/24)"
  type        = string
}

variable "gateway" {
  description = "Network gateway"
  type        = string
}

variable "nameserver" {
  description = "DNS nameserver"
  type        = string
  default     = "1.1.1.1"
}

variable "network_bridge" {
  description = "Network bridge to use"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag (optional, -1 to disable)"
  type        = number
  default     = -1
}

# =============================================================================
# Template Configuration
# =============================================================================

variable "template" {
  description = "LXC template to use (e.g., local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst)"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

# =============================================================================
# SSH Configuration
# =============================================================================

variable "ssh_public_keys" {
  description = "SSH public keys to add to the container"
  type        = string
  default     = ""
}

variable "root_password" {
  description = "Root password for the container"
  type        = string
  sensitive   = true
}

# =============================================================================
# Tags
# =============================================================================

variable "tags" {
  description = "Tags for the LXC container"
  type        = list(string)
  default     = ["iac", "control-plane", "terraform"]
}
