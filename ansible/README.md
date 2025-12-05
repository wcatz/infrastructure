# Ansible Playbooks

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
  - Traefik disabled
- **tailscale**: Installs Tailscale VPN on all nodes (required for hybrid setup)
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
   
   kubectl describe node <control-plane-name> | grep Taints
   # Should show: node-role.kubernetes.io/control-plane:NoSchedule
   ```

3. **Deploy services via Helmfile**:
   ```bash
   cd ../helmfile
   helmfile apply  # Deploys Prometheus, Grafana
   ```

4. **Configure Cloudflared for ingress** (on worker nodes):
   - See [Cloudflared Setup Guide](../helmfile/CLOUDFLARED_SETUP.md)

5. **Deploy workloads**:
   - Use templates from `kubernetes-examples/` directory
   - All workloads automatically schedule on worker nodes
   - See [Kubernetes Examples README](../kubernetes-examples/README.md)

## Hybrid Cluster Configuration

### Inventory Example
```ini
[k3s_servers]
k3s-control ansible_host=100.64.1.10 ansible_user=ubuntu k3s_node_taint=true

[k3s_agents]
k3s-worker-01 ansible_host=1.2.3.4 ansible_user=ubuntu k3s_node_label="node-role=worker"
```

### Important Variables

**Control Plane Node**:
- `k3s_node_taint=true`: Applies NoSchedule taint to prevent workload scheduling
- `ansible_host`: Should be Tailscale IP (100.64.x.x) for secure communication

**Worker Nodes**:
- `k3s_node_label`: Custom labels for node selection (optional)
- `ansible_host`: Can be public IP or Tailscale IP

**All Nodes**:
- `vault_tailscale_key`: Tailscale auth key (in encrypted vault.yml)
- `vault_k3s_token`: K3s cluster token (in encrypted vault.yml)

### Tailscale Configuration

Tailscale is **required** for hybrid cluster networking:
- Control plane behind CGNAT uses Tailscale IP for API server
- Workers connect to control plane via Tailscale network
- Provides encrypted, authenticated cluster communication

**ACL Recommendations**:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:k3s-node"],
      "dst": ["tag:k3s-node:*"]
    }
  ],
  "tagOwners": {
    "tag:k3s-node": ["your-email@example.com"]
  }
}
```

Apply tags when creating Tailscale auth key:
```bash
# Use --advertise-tags when setting up nodes
tailscale_args: "--accept-routes --advertise-tags=tag:k3s-node"
```
