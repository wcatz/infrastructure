# Ansible Playbooks

Infrastructure automation for k3s cluster deployment.

## Quick Start

### 1. Setup Secrets with Ansible Vault

```bash
# 1. Create vault password file
cp .vault_pass.example .vault_pass
vim .vault_pass  # Add your vault password

# 2. Create and encrypt secrets
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vim group_vars/all/vault.yml  # Add your actual secrets

# 3. Encrypt the vault file
ansible-vault encrypt group_vars/all/vault.yml

# Note: To edit encrypted secrets later, use:
ansible-vault edit group_vars/all/vault.yml
```

### 2. Deploy Infrastructure

```bash
# 1. Copy inventory template
cp inventory.ini.example inventory.ini

# 2. Edit inventory with your servers
vim inventory.ini

# 3. Deploy k3s cluster (Traefik disabled for HAProxy)
# Secrets are now automatically loaded from encrypted vault.yml
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# 4. Setup Tailscale on hosts
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml
```

## Ansible Vault Commands

```bash
# Encrypt a file
ansible-vault encrypt group_vars/all/vault.yml

# Decrypt a file (for viewing)
ansible-vault decrypt group_vars/all/vault.yml

# Edit encrypted file
ansible-vault edit group_vars/all/vault.yml

# View encrypted file without editing
ansible-vault view group_vars/all/vault.yml

# Change vault password
ansible-vault rekey group_vars/all/vault.yml

# Run playbook with vault password from environment variable
ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass ansible-playbook playbooks/deploy-k3s.yaml
```

## Roles

- **k3s**: Deploys k3s (Traefik disabled)
- **tailscale**: Installs Tailscale VPN on hosts
- **hostname**: Configures system hostnames

## Encrypted Variables

The following secrets are stored encrypted in `group_vars/all/vault.yml`:

- `vault_k3s_token`: K3s cluster token for agent nodes
- `vault_tailscale_key`: Tailscale authentication key

These are automatically referenced by the roles:
- K3s role uses `k3s_token: "{{ vault_k3s_token }}"`
- Tailscale role uses `tailscale_auth_key: "{{ vault_tailscale_key }}"`

## Next Steps

After Ansible deployment:
1. Copy kubeconfig from k3s server
2. Deploy services via Helmfile (HAProxy, Cloudflared, Tailscale Operator)
3. Configure Kubernetes secrets with SOPS
