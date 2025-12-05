# Ansible Playbooks

Infrastructure automation for k3s cluster deployment.

## Quick Start

```bash
# 1. Copy inventory template
cp inventory.ini.example inventory.ini

# 2. Edit inventory with your servers
vim inventory.ini

# 3. Generate k3s token
openssl rand -hex 32

# 4. Deploy k3s cluster (Traefik disabled for HAProxy)
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml -e "k3s_token=YOUR_TOKEN"

# 5. Setup Tailscale on hosts
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml -e "tailscale_auth_key=YOUR_KEY"
```

## Roles

- **k3s**: Deploys k3s (Traefik disabled)
- **tailscale**: Installs Tailscale VPN on hosts
- **hostname**: Configures system hostnames

## Next Steps

After Ansible deployment:
1. Copy kubeconfig from k3s server
2. Deploy services via Helmfile (HAProxy, Cloudflared, Tailscale Operator)
3. Configure secrets with SOPS
