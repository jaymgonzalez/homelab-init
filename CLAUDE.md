# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Proxmox Infrastructure as Code bootstrap project for setting up a Proxmox VE homelab from scratch. The architecture follows a two-stage approach:

1. **PVE Host Setup**: Ansible configures the Proxmox host (disables enterprise repos, enables no-subscription repos, installs utilities)
2. **Control Plane LXC**: Terraform creates a privileged LXC container that serves as the IaC control center, equipped with Terraform, Ansible, Git, and SSH keys

The control plane LXC is the central management node from which all future infrastructure deployments are managed.

## Workflow

The standard bootstrap workflow:

```bash
# 1. Prepare the PVE host (from local machine)
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/pve-post-install.yml

# 2. Create the control plane LXC (from local machine)
cd terraform/control-plane
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply

# 3. Configure the control plane (from local machine)
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/control-plane-setup-apps.yml

# 4. Use the control plane (SSH into it)
ssh root@<control-plane-ip>
```

Alternatively, use the guided bootstrap script: `./scripts/bootstrap.sh`

## Terraform

**Provider**: Telmate/proxmox ~> 3.0
**Required Version**: >= 1.9.5

### Common Commands

```bash
cd terraform/control-plane
terraform init
terraform validate
terraform plan
terraform apply
terraform destroy
terraform output  # View outputs like SSH command, IP address
```

### Authentication

Uses Proxmox API tokens (not username/password). Create token in Proxmox UI:
- Datacenter → Permissions → API Tokens
- Add: User=root@pam, Token ID=terraform
- **Must uncheck "Privilege Separation"** for full access

### Key Configuration Points

- **LXC is privileged** (`unprivileged = false`) to support Docker if needed
- **Features enabled**: `nesting = true` (for Docker), `keyctl = true`
- **Auto-provisioning**: `null_resource.run_ansible` optionally triggers Ansible playbook after creation
- **IP extraction**: `local.control_plane_ip_clean` strips CIDR notation from IP variable

## Ansible

### Common Commands

```bash
cd ansible

# Run specific playbook
ansible-playbook -i inventory/hosts.yml playbooks/pve-post-install.yml
ansible-playbook -i inventory/hosts.yml playbooks/control-plane-setup-apps.yml

# Run against single host
ansible-playbook -i "192.168.1.10," -u root playbooks/control-plane-setup-apps.yml

# Check connectivity
ansible all -i inventory/hosts.yml -m ping
```

### Inventory Structure

Located in `ansible/inventory/hosts.yml`:
- **proxmox** group: PVE hosts (supports multiple nodes in a cluster)
- **control_plane** group: Control plane LXC(s)
- **qdevice** group: Quorum device for cluster HA
- **gitlab** group: GitLab CE server
- Default user: root
- Python interpreter: /usr/bin/python3

**Common variables** in `ansible/group_vars/all/`:
- `common.yml`: Shared SSH keys and other common configuration
- `vault.yml`: Encrypted secrets (API tokens, passwords, etc.)

### Playbooks

**pve-post-install.yml** (runs on Proxmox host):
- Disables enterprise repos
- Enables no-subscription repos
- Removes subscription nag popup
- Installs common utilities (vim, htop, git, tmux, etc.)
- Adds SSH public keys to authorized_keys
- Configures SSH (key-based only, disables root password login)
- Based on tteck's Proxmox helper scripts

**IMPORTANT**: Add your SSH public keys before running this playbook to avoid getting locked out when password authentication is disabled.

**control-plane-setup-apps.yml** (runs on control plane LXC):
- Installs Terraform (version 1.14.3 by default)
- Installs Ansible via pipx with dependencies (proxmoxer, requests, jmespath)
- Configures Git (user, email, default branch)
- Generates ED25519 SSH key for the control plane
- Creates workspace at `/opt/iac` with subdirectories (terraform, ansible, scripts, secrets)
- Installs Tailscale VPN for secure remote access
- Adds useful bash aliases (tf, tfi, tfp, tfa, ap, al, ts, tss, etc.)

**qdevice-setup.yml** (runs on QDevice - Raspberry Pi or similar):
- Updates system packages
- Installs corosync-qnetd package
- Configures SSH keys for secure access
- Enables and starts corosync-qnetd service
- **Note**: Supports Cloudflare Tunnel access (see `docs/CLOUDFLARE_TUNNEL.md`)

**qdevice-cluster-setup.yml** (runs on first Proxmox node):
- Checks cluster status and prerequisites
- Configures the QDevice on the Proxmox cluster
- Verifies QDevice connectivity and status

## Proxmox Cluster Setup

### Creating a 2-Node Cluster

**On the first node** (e.g., pve-main):
```bash
pvecm create homelab-cluster
```

**On the second node** (e.g., pve-mini):
```bash
pvecm add <IP-of-first-node>
# Enter root password when prompted
# Accept the certificate fingerprint
```

**Verify cluster status** (on either node):
```bash
pvecm status
pvecm nodes
```

### Quorum Device (QDevice) Setup

A 2-node cluster requires both nodes online for quorum. Adding a QDevice (lightweight third "vote") enables the cluster to maintain quorum with only one node online, providing true high availability.

**Requirements:**
- A third device (Raspberry Pi, old laptop, small VM, or VPS)
- Debian or Ubuntu OS
- Network connectivity to both Proxmox nodes

**Setup workflow:**

```bash
# 1. Update inventory with your Raspberry Pi IP
# Edit ansible/inventory/hosts.yml and set qdevice ansible_host

# 2. Setup the QDevice (installs corosync-qnetd)
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/qdevice-setup.yml

# 3. Configure QDevice on cluster (from one PVE node)
ansible-playbook -i inventory/hosts.yml playbooks/qdevice-cluster-setup.yml

# 4. Verify QDevice status (on any PVE node)
pvecm status  # Should show Qdevice information
corosync-qdevice-tool -s  # Detailed QDevice status
```

**After QDevice setup:**
- Cluster has 3 votes total (node1 + node2 + qdevice)
- Quorum requires 2 votes
- Either Proxmox node can be shut down without losing quorum
- Cluster operations remain available with one node offline

**Important notes:**
- QDevice doesn't run VMs/containers, it only provides a vote
- Very lightweight resource requirements (~512MB RAM is sufficient)
- Critical for planned maintenance on 2-node clusters
- Without QDevice, both nodes must be online for cluster operations

### Deploying Resources Across Nodes

With a cluster configured, specify which node to deploy resources to:

```hcl
# In Terraform modules
resource "proxmox_lxc" "example" {
  target_node = "pve-mini"  # Deploy to specific node
  # ... rest of config
}
```

The control plane Terraform provider connects to the cluster API (via any node) and can deploy to any cluster member.

## Tailscale Integration

The control plane includes Tailscale for secure remote access to your homelab.

### Configuration

Tailscale installation is controlled by variables in `control-plane-setup-apps.yml`:

```yaml
install_tailscale: true  # Set to false to skip Tailscale
tailscale_authkey: ""    # Leave empty for manual auth, or provide auth key
tailscale_args: "--ssh --accept-routes"  # Default arguments for tailscale up
```

### Manual Connection (no auth key)

If `tailscale_authkey` is empty, after the playbook completes:

```bash
ssh root@<control-plane-ip>
tailscale up --ssh --accept-routes
# Follow the URL to authenticate
```

### Automatic Connection (with auth key)

1. Generate auth key in Tailscale admin console (Settings → Keys)
2. Set `tailscale_authkey` variable before running playbook
3. Control plane will auto-connect to your tailnet

### Tailscale Features Enabled

- `--ssh`: Enables Tailscale SSH (access control plane via Tailscale)
- `--accept-routes`: Accepts subnet routes from other Tailscale nodes

### Common Commands

```bash
tailscale status         # or: tss
tailscale ping <node>
tailscale ip
tailscale logout
```

## Architecture Details

### Control Plane LXC Specifications

- **Purpose**: Central IaC management node
- **Container Type**: Privileged (to support Docker)
- **Default Resources**: 2 cores, 2GB RAM, 512MB swap, 20GB disk
- **Storage**: Uses `local-lvm` by default
- **Network**: Static IP via bridge `vmbr0`, configurable VLAN support
- **Features**: Nesting enabled (Docker support), keyctl enabled

### Network Configuration

- Control plane uses static IP in CIDR format (e.g., `192.168.1.10/24`)
- Gateway and nameserver configurable
- VLAN support via `vlan_tag` variable (set to `-1` to disable)

### Post-Bootstrap Next Steps

After control plane is configured, typical next deployments mentioned in README:
- GitLab (self-hosted Git)
- Vault (secrets management)
- Home Assistant (home automation)
- Traefik/Nginx (reverse proxy)
- Monitoring stack (Prometheus + Grafana)

## SSH Key Configuration

### Centralized SSH Key Management

SSH public keys are managed centrally in `ansible/group_vars/all/common.yml` to avoid duplication:

```yaml
# ansible/group_vars/all/common.yml
common_ssh_public_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@laptop"
  - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABA... user@desktop"
```

The inventory file references this variable:

```yaml
# ansible/inventory/hosts.yml
proxmox:
  hosts:
    pve-main:
      ansible_host: 192.168.1.10
      ssh_public_keys: "{{ common_ssh_public_keys }}"
```

**Benefits:**
- Define keys once, use everywhere
- Easy to add/remove keys across all infrastructure
- No duplication in inventory file

**Getting your public key:**

```bash
cat ~/.ssh/id_ed25519.pub
# or
cat ~/.ssh/id_rsa.pub
```

**Per-host override (optional):**

If you need host-specific keys, override in the inventory:

```yaml
pve-main:
  ansible_host: 192.168.1.10
  ssh_public_keys:
    - "{{ common_ssh_public_keys }}"  # Include common keys
    - "ssh-ed25519 AAAAC3... special-key@host"  # Plus host-specific key
```

The playbook will:
1. Create `/root/.ssh` directory with proper permissions (700)
2. Add keys to `/root/.ssh/authorized_keys` with proper permissions (600)
3. Set `PermitRootLogin prohibit-password` in sshd_config
4. Enable `PubkeyAuthentication yes`
5. Restart SSH daemon

**WARNING**: The playbook will show a warning if SSH is configured but no keys are added. Make sure to add at least one SSH key before running to avoid getting locked out.

## Configuration Files

### terraform.tfvars

Create from `terraform.tfvars.example`. Critical variables:
- `proxmox_host`: IP/hostname of PVE
- `proxmox_api_token_id`: Format `user@realm!tokenid`
- `proxmox_api_token_secret`: Token secret from Proxmox UI
- `control_plane_ip`: CIDR format IP for control plane
- `gateway`: Network gateway
- `ssh_public_keys`: SSH keys to add to control plane (supports multiple keys)
- `root_password`: Container root password

### inventory/hosts.yml

Update `ansible_host` values for your environment:
- `pve-main`: First Proxmox node IP (e.g., 192.168.1.10)
- `pve-mini`: Second Proxmox node IP (e.g., 192.168.1.11) - if using cluster
- `control`: Control plane LXC IP
- `qdevice`: QDevice IP (e.g., 192.168.1.20) - if using cluster with QDevice
- `gitlab`: GitLab server IP - if deployed

## GitLab Integration

This project uses GitLab for source control and Terraform state storage.

### GitLab Project Management

The `terraform/gitlab-config` module manages GitLab resources using the GitLab provider:
- Creates the `proxmox-iac` project
- Configures project settings (visibility, features, etc.)
- Provides outputs for Git URLs and Terraform state backend URLs

**Setup:**
```bash
cd terraform/gitlab-config
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with GitLab URL and token
terraform init
terraform apply
```

### Terraform State Storage

All Terraform modules use GitLab's HTTP backend for state storage:
- **control-plane**: State stored at `/api/v4/projects/1/terraform/state/control-plane`
- **gitlab**: State stored at `/api/v4/projects/1/terraform/state/gitlab`
- **gitlab-config**: State stored at `/api/v4/projects/1/terraform/state/gitlab-config`

**Benefits:**
- Centralized state management in GitLab
- Automatic state locking (prevents concurrent modifications)
- State versioning and history in GitLab UI
- No local `.tfstate` files to manage

**Backend Configuration:**

Each module has:
- `backend.tf` - Defines the HTTP backend (checked into Git)
- `backend.hcl` - Contains credentials (gitignored, never committed)
- `backend.hcl.example` - Template for creating `backend.hcl`

**Initialize with GitLab backend:**
```bash
cd terraform/<module-name>
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your GitLab credentials
terraform init -backend-config=backend.hcl
```

**Migrate existing state:**
```bash
# Backup first!
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)

# Initialize with new backend (Terraform will detect migration)
terraform init -backend-config=backend.hcl
# Answer "yes" when prompted to copy state

# Verify
terraform state list
```

**Automated migration script:**
```bash
./scripts/migrate-state-to-gitlab.sh
```

See `terraform/MIGRATION_GUIDE.md` for detailed migration instructions.

### Git Remotes

The repository is hosted in GitLab:
- **GitLab**: `git@192.168.10.101:root/proxmox-iac.git` (primary, SSH)
- **GitHub**: Original bootstrap repo (not actively maintained)

**Common Git operations:**
```bash
# Push to GitLab
git push gitlab main

# View remotes
git remote -v

# Add SSH key to GitLab (Settings → SSH Keys)
cat ~/.ssh/id_ed25519.pub
```

## Important Notes

- The bootstrap process requires Terraform and Ansible on your **local machine** for initial setup
- Proxmox VE 8.x is expected
- Debian 13 LXC template must be downloaded to PVE before running Terraform (`pveam download local debian-13-standard_13.1-2_amd64.tar.zst`)
- Control plane SSH key is auto-generated and displayed during setup - add it to GitLab SSH keys and PVE authorized_keys
- The workspace directory on control plane is `/opt/iac` with the `$IAC_HOME` environment variable
- **Terraform state is stored in GitLab** using HTTP backend (see GitLab Integration section above)
