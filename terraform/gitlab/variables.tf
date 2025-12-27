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
# GitLab LXC Configuration
# =============================================================================

variable "gitlab_vmid" {
  description = "VM ID for the GitLab LXC"
  type        = number
  default     = 101
}

variable "gitlab_hostname" {
  description = "Hostname for GitLab"
  type        = string
  default     = "gitlab"
}

variable "gitlab_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "gitlab_memory" {
  description = "Memory in MB (GitLab minimum is 4GB)"
  type        = number
  default     = 4096
}

variable "gitlab_swap" {
  description = "Swap in MB"
  type        = number
  default     = 1024
}

variable "gitlab_disk_size" {
  description = "Root disk size (e.g., 30G)"
  type        = string
  default     = "30G"
}

variable "gitlab_storage" {
  description = "Storage pool for the LXC"
  type        = string
  default     = "local-lvm"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "gitlab_ip" {
  description = "Static IP for GitLab (CIDR format, e.g., 192.168.10.101/24)"
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
  description = "VLAN tag (use 10 for same network as control-plane, -1 to disable)"
  type        = number
  default     = 10
}

# =============================================================================
# Template Configuration
# =============================================================================

variable "template" {
  description = "LXC template to use (e.g., local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst)"
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
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
  default     = ["iac", "gitlab", "terraform"]
}
