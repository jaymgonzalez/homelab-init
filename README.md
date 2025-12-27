# Proxmox IaC Bootstrap

Infrastructure as Code para bootstrappear un cluster Proxmox desde cero.

## Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                     Proxmox VE Host                         │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              PVE Post-Install (Ansible)               │  │
│  │  • Disable enterprise repo                            │  │
│  │  • Enable no-subscription repo                        │  │
│  │  • Install utilities                                  │  │
│  │  • Configure SSH                                      │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │           Control Plane LXC (Terraform)               │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐  │  │
│  │  │  Terraform  │ │   Ansible   │ │  Git + SSH Keys │  │  │
│  │  └─────────────┘ └─────────────┘ └─────────────────┘  │  │
│  │                                                       │  │
│  │  Desde aquí gestionas el resto de la infra           │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Preparar el PVE host

```bash
# Desde tu máquina local, ejecuta el post-install en el PVE
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/pve-post-install.yml
```

### 2. Crear el Control Plane LXC

```bash
cd terraform/control-plane
cp terraform.tfvars.example terraform.tfvars
# Edita terraform.tfvars con tus valores

terraform init
terraform plan
terraform apply
```

### 3. Bootstrap y Configurar el Control Plane (todo en uno)

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/control-plane-full-config.yml
```

**¿Qué hace este paso?**
1. **Tailscale Bootstrap:**
   - Configura VLAN 10 temporal con NAT
   - Instala Tailscale en el contenedor
   - Conecta usando auth key desde vault
   - Actualiza inventario con IP de Tailscale
2. **Control Plane Setup:**
   - Se conecta vía Tailscale (IP actualizada automáticamente)
   - Instala Terraform y Ansible
   - Configura Git y genera SSH keys
   - Crea workspace en /opt/iac

**Alternativamente**, puedes ejecutar los playbooks por separado:
```bash
# Solo Tailscale
ansible-playbook -i inventory/hosts.yml playbooks/control-plane-tailscale.yml

# Solo configuración del control plane
ansible-playbook -i inventory/hosts.yml playbooks/control-plane-setup.yml
```

## Estructura del Proyecto

```
.
├── README.md
├── terraform/
│   ├── control-plane/          # LXC control plane
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   └── terraform.tfvars.example
│   └── modules/                # Módulos reutilizables
│       └── lxc/
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   └── hosts.yml
│   ├── playbooks/
│   │   ├── pve-post-install.yml
│   │   ├── control-plane-tailscale.yml
│   │   ├── control-plane-setup.yml
│   │   └── control-plane-full-config.yml
│   └── group_vars/
│       └── all/
│           └── vault.yml
└── scripts/
    └── bootstrap.sh            # Script inicial para empezar
```

## Requisitos

### En tu máquina local (para el bootstrap inicial)
- Terraform >= 1.5
- Ansible >= 2.15
- SSH access al PVE host

### En el PVE host
- Proxmox VE 8.x
- Template LXC de Debian 13 descargado (`pveam download local debian-13-standard_13.1-2_amd64.tar.zst`)

## Variables Importantes

### Terraform (terraform.tfvars)
```hcl
proxmox_host     = "192.168.1.100"
proxmox_user     = "root@pam"
proxmox_password = "your-password"  # O usar API token
control_plane_ip = "192.168.1.10/24"
gateway          = "192.168.1.1"
```

### Ansible (inventory/hosts.yml)
```yaml
all:
  children:
    proxmox:
      hosts:
        pve:
          ansible_host: 192.168.1.100
    control_plane:
      hosts:
        control:
          ansible_host: 192.168.1.10
```

## Próximos Pasos (después del bootstrap)

Una vez tengas el control plane funcionando, desde ahí puedes:

1. **GitLab** - Self-hosted Git
2. **Vault** - Gestión de secretos
3. **Home Assistant** - Automatización
4. **Traefik/Nginx** - Reverse proxy
5. **Monitoring stack** - Prometheus + Grafana

## Notas

- El control plane LXC es privilegiado para poder ejecutar Docker si lo necesitas
- Los secretos se manejan con variables de entorno o Vault (próximo paso)
- El post-install de PVE está basado en el script de tteck pero en Ansible
