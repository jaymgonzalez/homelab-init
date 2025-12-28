# Traefik Reverse Proxy Implementation Plan

## Overview

Deploy Traefik as a dedicated LXC container (VMID 102) to provide automatic HTTPS via Let's Encrypt and replace SSH tunnel access to homelab services with proper domain-based access.

## User Requirements

- **Deployment:** Dedicated LXC container (VMID 102, IP: 192.168.10.102/24)
- **DNS:** Real domain with local DNS overrides (user will set up Pi-hole/dnsmasq)
- **TLS:** Let's Encrypt automatic SSL certificates
- **Initial Services:** GitLab Web UI and GitLab Container Registry

## Architecture Decisions

| Component | Decision | Rationale |
|-----------|----------|-----------|
| **Installation Method** | Docker Compose | Flexibility, easy updates, community support |
| **Configuration Provider** | File Provider (YAML) | Can proxy services on different LXC hosts |
| **Let's Encrypt Challenge** | HTTP-01 | Simple setup, no DNS API needed |
| **Container Type** | Unprivileged | Traefik doesn't need privileges |
| **Resources** | 1 core, 512MB RAM, 8GB disk | Lightweight reverse proxy |
| **Network** | VLAN 10 (same as GitLab) | Direct L2 access to services |

## Implementation Steps

### Phase 1: Create Traefik LXC with Terraform

**Create new module:** `terraform/traefik/`

**Files to create:**

1. **terraform/traefik/providers.tf**
   - Copy from `terraform/gitlab/providers.tf` (identical)
   - Proxmox provider configuration

2. **terraform/traefik/variables.tf**
   - Proxmox connection variables
   - Traefik-specific variables with `traefik_*` prefix
   - VMID: 102, hostname: "traefik"
   - Resources: 1 core, 512MB RAM, 256MB swap, 8GB disk
   - Network: traefik_ip, gateway, nameserver, vlan_tag=10

3. **terraform/traefik/main.tf**
   - `resource "proxmox_lxc" "traefik"` following GitLab pattern
   - `unprivileged = true` (unlike GitLab's false)
   - Local value: `traefik_ip_clean = split("/", var.traefik_ip)[0]`

4. **terraform/traefik/outputs.tf**
   - traefik_id, traefik_ip, ssh_command
   - dashboard_url: `http://{ip}:8080`
   - **port_forward_commands:** iptables rules for Proxmox host
   - ansible_inventory_entry
   - next_steps with deployment instructions

5. **terraform/traefik/terraform.tfvars.example**
   - Template with documentation
   - traefik_ip = "192.168.10.102/24"
   - vlan_tag = 10

**Deployment:**
```bash
cd terraform/traefik
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (IMPORTANT: set your domain!)
terraform init
terraform plan
terraform apply
```

### Phase 2: Install and Configure Traefik with Ansible

**Files to create:**

1. **ansible/playbooks/traefik-setup.yml**

   **Variables (user must configure):**
   - `traefik_domain: "example.com"` - CHANGE to your domain
   - `letsencrypt_email: "admin@example.com"` - CHANGE to your email
   - `gitlab_ip: "192.168.10.101"`
   - `traefik_version: "v3.2"`

   **Tasks:**
   - Update system packages
   - Install Docker Engine (GPG key, repository, packages)
   - Create `/opt/traefik` directory structure
   - Create `acme.json` with mode 0600
   - Deploy `traefik.yml` (static config):
     - API dashboard on port 8080 (insecure mode, internal only)
     - Entrypoints: web (:80, redirect to HTTPS), websecure (:443)
     - Let's Encrypt resolver with HTTP-01 challenge
     - File provider watching `/etc/traefik/dynamic`
   - Deploy `dynamic/gitlab.yml`:
     - Router for `gitlab.{domain}` → `http://192.168.10.101`
     - TLS via Let's Encrypt
   - Deploy `dynamic/registry.yml`:
     - Router for `registry.{domain}` → `http://192.168.10.101:5050`
     - TLS via Let's Encrypt
   - Deploy `docker-compose.yml`:
     - Traefik v3.2 container
     - Ports: 80, 443, 8080
     - Volume mounts for config and certificates
   - Start Traefik with `docker compose up -d`
   - Wait for Traefik to be ready (URI check on port 8080)
   - Add bash aliases (traefik-logs, traefik-restart, etc.)
   - Display summary with URLs and next steps

2. **ansible/playbooks/gitlab-reconfigure-for-traefik.yml**

   **Variables:**
   - `traefik_domain: "example.com"` - CHANGE to your domain
   - `gitlab_external_url: "https://gitlab.{domain}"`
   - `gitlab_registry_external_url: "https://registry.{domain}"`

   **Tasks:**
   - Backup `/etc/gitlab/gitlab.rb`
   - Update `external_url` to use domain (not IP)
   - Update `registry_external_url` to use domain (not IP:port)
   - Configure GitLab nginx to trust Traefik proxy:
     - `nginx['listen_https'] = false` (Traefik handles SSL)
     - Set X-Forwarded-Proto headers
     - Registry nginx same configuration
   - Run `gitlab-ctl reconfigure`
   - Wait for GitLab to be ready
   - Display summary with new URLs

**Deployment:**
```bash
cd ansible
# 1. Edit playbooks with your domain name
vim playbooks/traefik-setup.yml  # Change traefik_domain and letsencrypt_email
vim playbooks/gitlab-reconfigure-for-traefik.yml  # Change traefik_domain

# 2. Install Traefik
ansible-playbook -i inventory/hosts.yml playbooks/traefik-setup.yml

# 3. Wait for Let's Encrypt certificates (1-2 minutes)
# Check dashboard: http://192.168.10.102:8080

# 4. Reconfigure GitLab
ansible-playbook -i inventory/hosts.yml playbooks/gitlab-reconfigure-for-traefik.yml
```

### Phase 3: Update Inventory

**File to modify:** `ansible/inventory/hosts.yml`

**Add after gitlab group:**
```yaml
    traefik:
      hosts:
        traefik:
          ansible_host: 192.168.10.102
```

### Phase 4: Network Configuration

**On Proxmox host** (run commands from Terraform output):

```bash
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Forward port 80 and 443 to Traefik LXC
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 80 -j DNAT --to 192.168.10.102:80
iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport 443 -j DNAT --to 192.168.10.102:443
iptables -t nat -A POSTROUTING -s 192.168.10.102/32 -o vmbr0 -p tcp --sport 80 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.10.102/32 -o vmbr0 -p tcp --sport 443 -j MASQUERADE

# Make persistent
apt-get install -y iptables-persistent
netfilter-persistent save
```

### Phase 5: DNS Configuration

**Option 1: Pi-hole Local DNS Records**
1. Login to Pi-hole admin
2. Navigate to: Local DNS → DNS Records
3. Add:
   - `gitlab.yourdomain.com` → `YOUR_PUBLIC_IP`
   - `registry.yourdomain.com` → `YOUR_PUBLIC_IP`

**Option 2: dnsmasq** (`/etc/dnsmasq.d/homelab.conf`)
```
address=/gitlab.yourdomain.com/YOUR_PUBLIC_IP
address=/registry.yourdomain.com/YOUR_PUBLIC_IP
```

**Option 3: Public DNS** (if external access needed)
- Add A records at your domain registrar
- `gitlab.yourdomain.com` → `YOUR_PUBLIC_IP`
- `registry.yourdomain.com` → `YOUR_PUBLIC_IP`

**Router:** Forward ports 80/443 from WAN to Proxmox host IP

## Critical Files Summary

### New Files (8 total)

**Terraform:**
- `terraform/traefik/main.tf` - LXC resource
- `terraform/traefik/variables.tf` - Variable declarations
- `terraform/traefik/outputs.tf` - Outputs and next steps
- `terraform/traefik/providers.tf` - Proxmox provider
- `terraform/traefik/terraform.tfvars.example` - Configuration template

**Ansible:**
- `ansible/playbooks/traefik-setup.yml` - Main installation
- `ansible/playbooks/gitlab-reconfigure-for-traefik.yml` - GitLab reconfiguration

### Modified Files (1)

- `ansible/inventory/hosts.yml` - Add traefik group

## Complete Deployment Workflow

```bash
# 1. Create Traefik LXC
cd /home/jay/proxmox-iac/terraform/traefik
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Set domain, credentials, IP
terraform init && terraform plan && terraform apply

# 2. Configure port forwarding on Proxmox host
terraform output port_forward_commands  # Copy and run on Proxmox host

# 3. Update Ansible inventory
cd /home/jay/proxmox-iac/ansible
vim inventory/hosts.yml  # Add traefik group

# 4. Install Traefik
vim playbooks/traefik-setup.yml  # Set traefik_domain and letsencrypt_email
ansible-playbook -i inventory/hosts.yml playbooks/traefik-setup.yml

# 5. Configure DNS (Pi-hole or public DNS)
# Add A records: gitlab.yourdomain.com, registry.yourdomain.com → YOUR_PUBLIC_IP

# 6. Wait for Let's Encrypt certificates (check dashboard)
# Dashboard: http://192.168.10.102:8080

# 7. Reconfigure GitLab
vim playbooks/gitlab-reconfigure-for-traefik.yml  # Set traefik_domain
ansible-playbook -i inventory/hosts.yml playbooks/gitlab-reconfigure-for-traefik.yml

# 8. Verify
# https://gitlab.yourdomain.com (should have valid SSL)
# https://registry.yourdomain.com (should work)
```

## Important Notes

### REQUIRED: Domain Configuration
You **MUST** replace `example.com` with your actual domain in these files:
- `terraform/traefik/terraform.tfvars`
- `ansible/playbooks/traefik-setup.yml` (traefik_domain variable)
- `ansible/playbooks/gitlab-reconfigure-for-traefik.yml` (traefik_domain variable)

### Let's Encrypt Requirements
- Port 80 must be accessible from internet (for HTTP-01 challenge)
- DNS records must resolve to your public IP
- Wait 10-60 minutes for DNS propagation
- Test with staging first to avoid rate limits (50 certs/week)

### Security Considerations
1. **Dashboard:** Currently internal-only on port 8080. Access via SSH tunnel or Tailscale
2. **Staging certificates:** Add `caServer: https://acme-staging-v02.api.letsencrypt.org/directory` to test
3. **Certificate backup:** Backup `/opt/traefik/acme.json` regularly

### Post-GitLab Reconfiguration
- Users need to update Git remote URLs: `git remote set-url origin https://gitlab.yourdomain.com/user/repo.git`
- GitLab Runner may need re-registration with new URL
- Registry login: `docker login registry.yourdomain.com`

## Troubleshooting

**Traefik not starting:**
```bash
ssh root@192.168.10.102
docker compose -f /opt/traefik/docker-compose.yml logs -f
# Check acme.json permissions (must be 600)
```

**Let's Encrypt not working:**
```bash
# Check DNS: nslookup gitlab.yourdomain.com
# Check port 80 open: Use https://www.yougetsignal.com/tools/open-ports/
# View Traefik dashboard: http://192.168.10.102:8080
# Check logs: docker logs traefik 2>&1 | grep -i acme
```

**GitLab not accessible:**
```bash
# Test routing: curl -H "Host: gitlab.yourdomain.com" http://192.168.10.102
# Test backend: ssh root@192.168.10.102 && curl http://192.168.10.101
# Check GitLab: ssh root@192.168.10.101 && gitlab-ctl status
```

## Future Enhancements

1. **Add more services:** Create new YAML files in `/opt/traefik/dynamic/`
2. **Dashboard authentication:** Add BasicAuth middleware
3. **DNS-01 challenge:** For wildcard certificates (requires DNS provider API)
4. **Monitoring:** Prometheus metrics from Traefik
5. **Rate limiting:** Add middleware for public services

## Verification Checklist

After deployment:
- [ ] Traefik LXC running (VMID 102, IP 192.168.10.102)
- [ ] Traefik container running (`docker ps` on Traefik LXC)
- [ ] Dashboard accessible: http://192.168.10.102:8080
- [ ] Port forwarding active on Proxmox host (80, 443)
- [ ] DNS records configured
- [ ] GitLab accessible: https://gitlab.yourdomain.com
- [ ] Valid Let's Encrypt certificate (green lock in browser)
- [ ] Registry accessible: https://registry.yourdomain.com
- [ ] Docker login works: `docker login registry.yourdomain.com`
- [ ] HTTP redirects to HTTPS
- [ ] No errors in Traefik logs