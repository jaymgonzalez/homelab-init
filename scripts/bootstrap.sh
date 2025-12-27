#!/bin/bash
# =============================================================================
# Bootstrap Script for Proxmox IaC
# =============================================================================
# Este script te guía en el proceso de setup inicial
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Header
echo ""
echo "============================================"
echo "  Proxmox IaC Bootstrap"
echo "============================================"
echo ""

# Check requirements
info "Checking requirements..."

command -v terraform >/dev/null 2>&1 || error "Terraform is not installed. Install it first: https://developer.hashicorp.com/terraform/downloads"
command -v ansible >/dev/null 2>&1 || error "Ansible is not installed. Install it first: pip install ansible"
command -v ssh >/dev/null 2>&1 || error "SSH client is not installed"

success "All requirements met!"

# Get configuration
echo ""
info "Let's configure your setup..."
echo ""

read -p "Proxmox host IP: " PVE_HOST
read -p "Proxmox node name [pve]: " PVE_NODE
PVE_NODE=${PVE_NODE:-pve}
read -p "Control Plane IP (CIDR format, e.g., 192.168.1.10/24): " CP_IP
read -p "Gateway: " GATEWAY

echo ""
info "Testing SSH connection to Proxmox..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$PVE_HOST exit 2>/dev/null; then
    success "SSH connection successful!"
else
    error "Cannot connect to $PVE_HOST via SSH. Please check your connection."
fi

# Step 1: PVE Post-Install
echo ""
echo "============================================"
echo "  Step 1: Proxmox Post-Install"
echo "============================================"
echo ""

read -p "Run PVE post-install? (y/n) [y]: " RUN_PVE
RUN_PVE=${RUN_PVE:-y}

if [[ "$RUN_PVE" =~ ^[Yy]$ ]]; then
    info "Updating Ansible inventory..."
    sed -i "s/ansible_host: .*/ansible_host: $PVE_HOST/" ansible/inventory/hosts.yml 2>/dev/null || true

    info "Running PVE post-install..."
    cd ansible
    ansible-playbook -i "$PVE_HOST," -u root playbooks/pve-post-install.yml
    cd ..
    success "PVE post-install complete!"
else
    warn "Skipping PVE post-install"
fi

# Step 2: Create API Token
echo ""
echo "============================================"
echo "  Step 2: Create Proxmox API Token"
echo "============================================"
echo ""
info "You need to create an API token in Proxmox for Terraform"
echo ""
echo "1. Go to Proxmox web UI: https://$PVE_HOST:8006"
echo "2. Datacenter -> Permissions -> API Tokens"
echo "3. Add: User=root@pam, Token ID=terraform"
echo "4. UNCHECK 'Privilege Separation'"
echo "5. Copy the token secret (you'll only see it once!)"
echo ""
read -p "Press Enter when done..."

read -p "Enter API Token ID [root@pam!terraform]: " API_TOKEN_ID
API_TOKEN_ID=${API_TOKEN_ID:-root@pam!terraform}
read -s -p "Enter API Token Secret: " API_TOKEN_SECRET
echo ""

# Step 3: Download LXC Template
echo ""
echo "============================================"
echo "  Step 3: Download LXC Template"
echo "============================================"
echo ""

info "Checking for Ubuntu 24.04 template..."
TEMPLATE_EXISTS=$(ssh root@$PVE_HOST "pveam list local | grep -c 'ubuntu-24.04-standard' || true")

if [ "$TEMPLATE_EXISTS" -eq 0 ]; then
    info "Downloading Ubuntu 24.04 template..."
    ssh root@$PVE_HOST "pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    success "Template downloaded!"
else
    success "Template already exists"
fi

# Step 4: Configure Terraform
echo ""
echo "============================================"
echo "  Step 4: Configure Terraform"
echo "============================================"
echo ""

info "Creating terraform.tfvars..."
cat > terraform/control-plane/terraform.tfvars <<EOF
# Proxmox Connection
proxmox_host             = "$PVE_HOST"
proxmox_api_token_id     = "$API_TOKEN_ID"
proxmox_api_token_secret = "$API_TOKEN_SECRET"
proxmox_tls_insecure     = true
proxmox_node             = "$PVE_NODE"

# Control Plane
control_plane_vmid     = 100
control_plane_hostname = "control-plane"
control_plane_cores    = 2
control_plane_memory   = 2048
control_plane_disk_size = "20G"
control_plane_storage  = "local-lvm"

# Network
control_plane_ip = "$CP_IP"
gateway          = "$GATEWAY"
nameserver       = "1.1.1.1"
network_bridge   = "vmbr0"

# Template
template = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"

# Access
root_password   = "$(openssl rand -base64 12)"
ssh_public_keys = "$(cat ~/.ssh/id_*.pub 2>/dev/null | head -1)"
EOF

success "terraform.tfvars created!"

# Step 5: Create Control Plane
echo ""
echo "============================================"
echo "  Step 5: Create Control Plane LXC"
echo "============================================"
echo ""

read -p "Create Control Plane LXC now? (y/n) [y]: " CREATE_CP
CREATE_CP=${CREATE_CP:-y}

if [[ "$CREATE_CP" =~ ^[Yy]$ ]]; then
    cd terraform/control-plane
    info "Initializing Terraform..."
    terraform init

    info "Planning..."
    terraform plan -out=tfplan

    echo ""
    read -p "Apply this plan? (y/n) [y]: " APPLY_PLAN
    APPLY_PLAN=${APPLY_PLAN:-y}

    if [[ "$APPLY_PLAN" =~ ^[Yy]$ ]]; then
        terraform apply tfplan
        success "Control Plane created!"
    fi
    cd ../..
fi

# Step 6: Configure Control Plane
CP_IP_CLEAN=$(echo $CP_IP | cut -d'/' -f1)

echo ""
echo "============================================"
echo "  Step 6: Configure Control Plane"
echo "============================================"
echo ""

info "Waiting for Control Plane to be ready..."
for i in {1..30}; do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$CP_IP_CLEAN exit 2>/dev/null; then
        success "Control Plane is up!"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 5
done

read -p "Configure Control Plane with Ansible? (y/n) [y]: " CONFIGURE_CP
CONFIGURE_CP=${CONFIGURE_CP:-y}

if [[ "$CONFIGURE_CP" =~ ^[Yy]$ ]]; then
    cd ansible
    ansible-playbook -i "$CP_IP_CLEAN," -u root playbooks/control-plane-setup.yml
    cd ..
    success "Control Plane configured!"
fi

# Done!
echo ""
echo "============================================"
echo "  🎉 Bootstrap Complete!"
echo "============================================"
echo ""
echo "Your Control Plane is ready at: $CP_IP_CLEAN"
echo ""
echo "Connect with: ssh root@$CP_IP_CLEAN"
echo ""
echo "Next steps:"
echo "  1. SSH into the control plane"
echo "  2. Clone this repo there"
echo "  3. Start deploying your infrastructure!"
echo ""
echo "============================================"
