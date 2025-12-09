# Ansible Playbooks

> **📚 Complete Documentation**: See [docs/ansible.md](../docs/ansible.md) for the comprehensive Ansible guide.
> 
> **🔐 Secret Management**: See [SECRETS.md](../SECRETS.md) for complete secret management and Ansible Vault usage.

Infrastructure automation for hybrid k3s cluster deployment.

## Architecture

This setup deploys a **hybrid Kubernetes cluster**:

- **Control Plane Node** (Behind CGNAT/Home network):
  - Runs K3s server only
  - Tainted to prevent workload scheduling  
  - Uses Tailscale for cluster communication
  - No public IP required

- **Worker Node(s)** (Public IP, e.g., Netcup VPS):
  - Runs all application workloads
  - Handles ingress traffic via Cloudflared
  - Uses Tailscale to connect to control plane
  - Can use NodePort or hostNetwork for TCP services

## Quick Start

### 1. Setup Secrets with Ansible Vault

**Note:** The `vault.yml` file is not included in this repository for security reasons. You must create it from the provided example template.

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
# Configure:
#   - k3s_servers: Control plane node (set k3s_node_taint=true)
#   - k3s_agents: Worker nodes (set k3s_node_label as needed)

# 3. Deploy Tailscale first (required for hybrid cluster)
# Tailscale enables secure communication between control plane and workers
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# 4. Verify Tailscale connectivity
# Ensure all nodes can reach each other via Tailscale IPs (100.64.x.x)

# 5. Deploy k3s cluster
# Control plane will be tainted automatically
# Traefik and servicelb disabled for hybrid cluster
# Secrets are loaded from encrypted vault.yml
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# 6. Verify cluster
# SSH to control plane node and check cluster status
ssh user@control-plane
kubectl get nodes
# You should see control plane with NoSchedule taint
# and worker nodes in Ready state
```

## Ansible Vault Commands

> **📚 For complete Ansible Vault documentation and CI/CD integration**, see [SECRETS.md - Ansible Vault](../SECRETS.md#ansible-vault)

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

- **k3s**: Deploys k3s with hybrid cluster support
  - Server mode: Installs control plane with optional NoSchedule taint
  - Agent mode: Installs worker node, connects via Tailscale
  - Traefik and servicelb disabled
- **tailscale**: Installs Tailscale VPN on all nodes (required for hybrid setup)
- **hostname**: Configures system hostnames
  - See [Hostname Naming Convention](../docs/HOSTNAME_NAMING_CONVENTION.md) for standardized naming format

## Encrypted Variables

The following secrets are stored encrypted in `group_vars/all/vault.yml`:

- `vault_k3s_token`: K3s cluster token for agent nodes
- `vault_tailscale_key`: Tailscale authentication key
- `vault_tailscale_oauth_client_id`: Tailscale OAuth client ID (for Kubernetes operator)
- `vault_tailscale_oauth_client_secret`: Tailscale OAuth client secret (for Kubernetes operator)
- `vault_cloudflare_tunnel_token`: Cloudflare tunnel token

These are automatically referenced by the roles:
- K3s role uses `k3s_token: "{{ vault_k3s_token }}"`
- Tailscale role uses `tailscale_auth_key: "{{ vault_tailscale_key }}"`

## Next Steps

After Ansible deployment:

1. **Get kubeconfig from control plane**:
   ```bash
   scp user@control-plane:/etc/rancher/k3s/k3s.yaml ~/.kube/config
   # Update server URL to use Tailscale IP of control plane
   sed -i 's/127.0.0.1/100.64.x.x/' ~/.kube/config
   ```

2. **Verify cluster status**:
   ```bash
   kubectl get nodes -o wide
   # Control plane should show NoSchedule taint
   # Worker nodes should be Ready
   
   kubectl describe node <control-plane-name>
   # Should show Taints: node-role.kubernetes.io/control-plane:NoSchedule
   ```

3. **Deploy services via Helmfile**:
   ```bash
   cd ../helmfile
   helmfile apply
   ```

4. **Configure Kubernetes secrets with SOPS**:
   ```bash
   # Follow docs/setup.md guide for SOPS/age setup
   ```

## Troubleshooting

### Tailscale Connectivity Issues

If nodes can't communicate via Tailscale:

```bash
# Check Tailscale status on each node
sudo tailscale status

# Test connectivity between nodes
ping 100.64.x.x  # Tailscale IP of other node

# Check Tailscale logs
sudo journalctl -u tailscaled -f
```

### K3s Join Failures

If worker nodes fail to join the cluster:

```bash
# On worker node, check k3s logs
sudo journalctl -u k3s -f

# Verify control plane is reachable via Tailscale
telnet 100.64.x.x 6443  # Control plane Tailscale IP

# Check k3s token matches between control plane and worker
```

## Security Notes

- Always use Ansible Vault to encrypt sensitive data
- Use strong, unique passwords for vault encryption
- Keep `.vault_pass` file secure and never commit it to git
- Regularly rotate K3s tokens and Tailscale keys
- Use Tailscale ACLs to restrict node-to-node communication
