# GitLab CE Implementation Plan

## Overview

Add GitLab CE (Community Edition) with Container Registry to the Proxmox homelab infrastructure. GitLab will run in a dedicated LXC container, while GitLab Runner will be installed on the existing control-plane LXC using Docker executor.

**User Requirements:**
- GitLab CE in a new LXC container
- GitLab Runner on control-plane (not in GitLab LXC)
- Docker executor for Runner
- Container Registry enabled
- 30GB storage for GitLab
- Minimal resource usage (homelab optimized)

## Architecture Decisions

### Network Configuration
- **VMID:** 101 (next after control-plane's 100)
- **Hostname:** gitlab
- **IP Address:** 192.168.10.101/24 (VLAN 10, same as control-plane)
- **Gateway:** 192.168.10.1
- **DNS:** 1.1.1.1

### Resource Allocation
**GitLab LXC:**
- CPU: 2 cores
- RAM: 4096 MB (4GB - GitLab minimum)
- Swap: 1024 MB
- Disk: 30G (as requested)
- Storage: local-lvm
- Unprivileged: true

**Control-plane modifications:**
- Add Docker Engine (~500MB disk)
- Current 20GB disk should be sufficient
- May need RAM increase from 2GB → 3GB (monitor after Docker install)

### GitLab Configuration
- **Installation:** GitLab Omnibus (DEB package)
- **external_url:** http://192.168.10.101
- **Container Registry:** http://registry.192.168.10.101:5050
- **Optimization:** Reduced Puma/Sidekiq workers, disable monitoring stack

### GitLab Runner Configuration
- **Location:** control-plane LXC (not in GitLab LXC)
- **Executor:** Docker
- **Default image:** alpine:latest
- **Concurrency:** 2 (homelab optimized)

## File Structure

```
terraform/
└── gitlab/                              # NEW directory
    ├── main.tf                          # LXC resource definition
    ├── variables.tf                     # Variable declarations
    ├── outputs.tf                       # Outputs (IP, URL, SSH command)
    ├── providers.tf                     # Proxmox provider config
    └── terraform.tfvars.example         # Configuration template

ansible/
├── inventory/
│   └── hosts.yml                        # UPDATE: Add gitlab group
├── playbooks/
│   ├── gitlab-setup.yml                 # NEW: Install GitLab CE
│   ├── control-plane-docker.yml         # NEW: Install Docker on control-plane
│   ├── gitlab-runner-setup.yml          # NEW: Install/register Runner
│   └── gitlab-full-config.yml           # NEW: Meta-playbook (all-in-one)
└── group_vars/all/
    └── vault.yml                        # UPDATE: Add GitLab secrets
```

## Implementation Steps

### Phase 1: Terraform - GitLab LXC Container

#### 1.1 Create `terraform/gitlab/providers.tf`
Copy from `terraform/control-plane/providers.tf` (identical configuration)

#### 1.2 Create `terraform/gitlab/variables.tf`
Follow control-plane pattern with sections:
- Proxmox Connection (proxmox_host, proxmox_api_token_id, proxmox_api_token_secret, proxmox_node)
- GitLab LXC Configuration (gitlab_vmid=101, gitlab_hostname="gitlab", gitlab_cores=2, gitlab_memory=4096, gitlab_swap=1024, gitlab_disk_size="30G")
- Network Configuration (gitlab_ip, gateway, nameserver, network_bridge, vlan_tag=10)
- Template, SSH, Tags

#### 1.3 Create `terraform/gitlab/main.tf`
```hcl
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

  ssh_public_keys = var.ssh_public_keys

  rootfs {
    storage = var.gitlab_storage
    size    = var.gitlab_disk_size
  }

  network {
    name   = "eth0"
    bridge = var.network_bridge
    ip     = var.gitlab_ip
    gw     = var.gateway
    tag    = var.vlan_tag > 0 ? var.vlan_tag : null
  }

  nameserver = var.nameserver
  onboot     = true
  start      = true
  tags       = join(";", var.tags)

  lifecycle {
    ignore_changes = [ostemplate]
  }
}

locals {
  gitlab_ip_clean = split("/", var.gitlab_ip)[0]
}
```

#### 1.4 Create `terraform/gitlab/outputs.tf`
Export: gitlab_id, gitlab_hostname, gitlab_ip, gitlab_url, registry_url, ssh_command, ansible_inventory_entry

#### 1.5 Create `terraform/gitlab/terraform.tfvars.example`
Template with inline comments for all variables (same structure as control-plane)

### Phase 2: Ansible - GitLab Installation

#### 2.1 Create `ansible/playbooks/control-plane-docker.yml`
**Purpose:** Install Docker Engine on control-plane for GitLab Runner

**Tasks:**
1. Install prerequisites (ca-certificates, curl, gnupg)
2. Add Docker GPG key and repository
3. Install Docker CE packages (docker-ce, docker-ce-cli, containerd.io)
4. Start and enable Docker service
5. Verify installation (docker --version, docker run hello-world)
6. Add Docker aliases to bashrc (d, dps, di, dc)

#### 2.2 Create `ansible/playbooks/gitlab-setup.yml`
**Purpose:** Install and configure GitLab CE with Container Registry

**Variables:**
- `gitlab_external_url: "http://{{ ansible_host }}"`
- `gitlab_registry_external_url: "http://registry.{{ ansible_host }}:5050"`
- `gitlab_initial_root_password: "{{ vault_gitlab_initial_root_password }}"`
- `gitlab_puma_worker_processes: 2` (homelab optimization)
- `gitlab_sidekiq_concurrency: 10` (homelab optimization)
- `disable_prometheus: true` (save resources)

**Tasks:**
1. System update and install dependencies (curl, ca-certificates, openssh-server, postfix)
2. Add GitLab repository and GPG key
3. Install GitLab CE package (with GITLAB_ROOT_PASSWORD env var)
4. Configure `/etc/gitlab/gitlab.rb`:
   - Set external_url
   - Enable Container Registry with registry_external_url
   - Reduce Puma workers (2) and Sidekiq concurrency (10)
   - Disable Prometheus/Grafana monitoring
5. Run `gitlab-ctl reconfigure` (async: 600s)
6. Wait for GitLab to become ready (uri check, retries: 30)
7. Display summary (URL, credentials)

#### 2.3 Create `ansible/playbooks/gitlab-runner-setup.yml`
**Purpose:** Install GitLab Runner on control-plane and register with GitLab

**Variables:**
- `gitlab_url: "http://{{ hostvars['gitlab']['ansible_host'] }}"`
- `gitlab_runner_registration_token: "{{ vault_gitlab_runner_registration_token }}"`

**Tasks:**
1. Add GitLab Runner repository
2. Install gitlab-runner package
3. Check if runner already registered
4. Register runner:
   ```bash
   gitlab-runner register \
     --non-interactive \
     --url "http://192.168.10.101" \
     --registration-token "TOKEN" \
     --executor "docker" \
     --docker-image "alpine:latest" \
     --description "Control Plane Runner" \
     --tag-list "docker,homelab" \
     --run-untagged="true"
   ```
5. Configure concurrency=2 in /etc/gitlab-runner/config.toml
6. Start and enable gitlab-runner service
7. Verify status (gitlab-runner status)

#### 2.4 Create `ansible/playbooks/gitlab-full-config.yml`
**Purpose:** Meta-playbook for complete GitLab deployment

```yaml
- name: Install Docker on Control Plane
  import_playbook: control-plane-docker.yml

- name: Install and Configure GitLab CE
  import_playbook: gitlab-setup.yml

- name: Install GitLab Runner on Control Plane
  import_playbook: gitlab-runner-setup.yml
```

### Phase 3: Inventory and Vault Updates

#### 3.1 Update `ansible/inventory/hosts.yml`
Add gitlab group after control_plane:

```yaml
    # -------------------------------------------------------------------------
    # GitLab CE Server
    # -------------------------------------------------------------------------
    gitlab:
      hosts:
        gitlab:
          ansible_host: 192.168.10.101
```

#### 3.2 Update `ansible/group_vars/all/vault.yml`
Add encrypted secrets:

```bash
ansible-vault edit ansible/group_vars/all/vault.yml
```

Add:
```yaml
# GitLab Configuration
vault_gitlab_initial_root_password: "CHANGEME-strong-password"
vault_gitlab_runner_registration_token: ""  # Obtained after GitLab install
```

**Note:** Runner registration token workflow:
1. Deploy GitLab first (token will be empty)
2. Login to GitLab, navigate to Admin → CI/CD → Runners
3. Copy registration token
4. Update vault with token
5. Re-run gitlab-runner-setup.yml

### Phase 4: Documentation

Update `README.md` with GitLab deployment section following existing patterns.

## Critical Configuration Details

### GitLab Omnibus Configuration (`/etc/gitlab/gitlab.rb`)

Key settings to configure:
```ruby
external_url 'http://192.168.10.101'
registry_external_url 'http://registry.192.168.10.101:5050'
gitlab_rails['registry_enabled'] = true

# Homelab optimizations
puma['worker_processes'] = 2
sidekiq['concurrency'] = 10
prometheus_monitoring['enable'] = false
grafana['enable'] = false
postgresql['shared_buffers'] = "256MB"
redis['maxmemory'] = "256mb"
```

### Docker Requirements

Control-plane must have:
- Docker Engine installed (docker-ce, docker-ce-cli, containerd.io)
- Docker service running and enabled
- Feature `nesting=true` already enabled (check with `pct config 100`)

### Expected Resource Usage

**GitLab LXC (4GB RAM):**
- Idle: ~2.5GB RAM, 5-10% CPU
- During builds: ~3.5GB RAM, 40-60% CPU

**Control-plane with Docker + Runner:**
- Idle: ~600MB RAM
- During Docker builds: 1.5-2GB RAM
- **Consider increasing control-plane RAM to 3GB if issues occur**

## Deployment Workflow

### Standard Deployment

```bash
# 1. Create GitLab LXC
cd /home/jay/proxmox-iac/terraform/gitlab
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform plan
terraform apply

# 2. Update inventory
cd /home/jay/proxmox-iac/ansible
# Edit inventory/hosts.yml to add gitlab host

# 3. Add initial root password to vault
ansible-vault edit group_vars/all/vault.yml
# Add vault_gitlab_initial_root_password

# 4. Run complete setup
ansible-playbook -i inventory/hosts.yml playbooks/gitlab-full-config.yml

# 5. Access GitLab and get runner token
# Open http://192.168.10.101
# Login: root / (vault password)
# Navigate: Admin → CI/CD → Runners
# Copy registration token

# 6. Add token to vault and register runner
ansible-vault edit group_vars/all/vault.yml
# Add vault_gitlab_runner_registration_token
ansible-playbook -i inventory/hosts.yml playbooks/gitlab-runner-setup.yml
```

### Alternative: Step-by-Step

```bash
# Install Docker first
ansible-playbook -i inventory/hosts.yml playbooks/control-plane-docker.yml

# Install GitLab
ansible-playbook -i inventory/hosts.yml playbooks/gitlab-setup.yml

# Later: Install runner when token ready
ansible-playbook -i inventory/hosts.yml playbooks/gitlab-runner-setup.yml
```

## Post-Deployment Tasks

1. **Access GitLab:** http://192.168.10.101 (root / vault_password)
2. **Change root password** (optional, via UI)
3. **Disable sign-ups:** Admin → Settings → General → Sign-up restrictions
4. **Verify Container Registry:** http://registry.192.168.10.101:5050
5. **Test Docker login:** `docker login registry.192.168.10.101:5050`
6. **Verify Runner:** Admin → CI/CD → Runners (should show "Control Plane Runner" with green status)
7. **Create test project** with `.gitlab-ci.yml` to verify pipeline execution

## Verification Checklist

- [ ] GitLab LXC created (VMID 101)
- [ ] GitLab accessible at http://192.168.10.101
- [ ] Docker installed on control-plane
- [ ] GitLab Runner registered and active
- [ ] Test pipeline runs successfully
- [ ] Container Registry accessible
- [ ] Can push/pull images to/from registry

## Troubleshooting

**GitLab not starting:**
- Check memory: `gitlab-ctl status`
- Check logs: `gitlab-ctl tail`
- Reconfigure: `gitlab-ctl reconfigure`

**Runner not connecting:**
- Check logs: `journalctl -u gitlab-runner -f`
- Verify token is correct in vault
- Test network: `ping 192.168.10.101` from control-plane

**Docker permission issues:**
- Verify nesting: `pct config 100 | grep features`
- Check Docker: `systemctl status docker`

**Out of memory:**
- Monitor GitLab: `free -h` inside GitLab LXC
- Increase RAM if needed: `pct set 101 -memory 5120`
- Monitor control-plane during builds

## Critical Files to Create/Modify

**New files (8):**
1. `/home/jay/proxmox-iac/terraform/gitlab/main.tf`
2. `/home/jay/proxmox-iac/terraform/gitlab/variables.tf`
3. `/home/jay/proxmox-iac/terraform/gitlab/outputs.tf`
4. `/home/jay/proxmox-iac/terraform/gitlab/providers.tf`
5. `/home/jay/proxmox-iac/terraform/gitlab/terraform.tfvars.example`
6. `/home/jay/proxmox-iac/ansible/playbooks/gitlab-setup.yml`
7. `/home/jay/proxmox-iac/ansible/playbooks/control-plane-docker.yml`
8. `/home/jay/proxmox-iac/ansible/playbooks/gitlab-runner-setup.yml`
9. `/home/jay/proxmox-iac/ansible/playbooks/gitlab-full-config.yml`

**Modified files (2):**
1. `/home/jay/proxmox-iac/ansible/inventory/hosts.yml` - Add gitlab group
2. `/home/jay/proxmox-iac/ansible/group_vars/all/vault.yml` - Add GitLab secrets

**Optional:**
- `/home/jay/proxmox-iac/README.md` - Add GitLab documentation section
