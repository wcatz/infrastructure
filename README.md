# Infrastructure Management

GitOps-based infrastructure for hybrid k3s cluster with Cloudflare tunnels and Tailscale mesh networking.

## Architecture

This infrastructure implements a hybrid Kubernetes cluster designed for:
- **Control Node (Home)**: Behind CGNAT, acts as Kubernetes control plane, uses Cloudflared for HTTP/S ingress
- **Worker Node (Netcup)**: Public IP exposed, hosts stateful workloads (e.g., Cardano node), exposes TCP ports via NodePort/hostNetwork

## Stack

- **k3s**: Lightweight Kubernetes (Traefik and servicelb disabled)
- **Tailscale**: L3 mesh networking for secure inter-node communication
- **Cloudflared**: HTTP/HTTPS ingress via Cloudflare tunnels
- **Tailscale Operator**: Manages Tailscale connectivity in Kubernetes
- **Prometheus/Grafana**: Monitoring
- **SOPS**: Secret encryption (age-based)

## Key Features

- **No HAProxy/MetalLB**: Simplified networking with Cloudflared for HTTP/S and direct TCP exposure
- **Tailscale Mesh**: Secure L3 networking between cluster nodes
- **Workload Placement**: Control plane behind CGNAT, workers with public IPs
- **Stateful Workloads**: PVC-based persistent storage with failover support
- **Hybrid Architecture**: Minimal and scalable design for distributed deployments

## Quick Setup

### 1. Deploy k3s Cluster

```bash
cd ansible

# Setup Ansible Vault for secrets
cp .vault_pass.example .vault_pass
vim .vault_pass  # Add your vault password

# Configure encrypted secrets
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vim group_vars/all/vault.yml  # Add your K3s token and Tailscale key
ansible-vault encrypt group_vars/all/vault.yml

# Setup inventory
cp inventory.ini.example inventory.ini
vim inventory.ini  # Edit with your servers

# Deploy k3s cluster (secrets loaded from vault)
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Get kubeconfig
scp user@k3s-server:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/YOUR_SERVER_IP/' ~/.kube/config
```

### 2. Deploy Services via Helmfile

```bash
cd helmfile
helmfile apply
```

### 3. Setup Secrets with SOPS

```bash
# Install tools
brew install age sops

# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Create .sops.yaml with your public key
cat > .sops.yaml << EOY
creation_rules:
  - age: YOUR_PUBLIC_KEY
EOY

# Encrypt and deploy secrets
sops -e secrets/example.yaml > secrets/example.enc.yaml
sops -d secrets/example.enc.yaml | kubectl apply -f -
```

## Components

### Ansible
- k3s deployment (Traefik and servicelb disabled for hybrid setup)
- Tailscale VPN on hosts for secure inter-node communication
- Ansible Vault for encrypted secrets (K3s token, Tailscale keys, OAuth credentials)

### Helmfile
- Cloudflared tunnels (HTTP/S ingress)
- Tailscale Kubernetes Operator (L3 mesh networking)
- Prometheus & Grafana (monitoring)
- External Secrets (optional)
- Environment configs (dev/staging/prod)
- Workload manifests (Cardano node, etc.)

### GitHub Actions
- `helmfile-diff.yaml`: Preview changes on PRs
- `helmfile-apply.yaml`: Manual Helmfile deployment with SOPS/age integration
- `deploy-workloads.yaml`: Deploy stateful workloads (Cardano node, etc.)

## Environment Management

Deploy to specific environments:

```bash
helmfile -e dev apply
helmfile -e staging apply
helmfile -e prod apply
```

## Documentation

- [Ansible README](ansible/README.md)
- [Helmfile README](helmfile/README.md)
- [Tailscale Setup](TAILSCALE_SETUP.md)
- [Workload Deployment](WORKLOAD_DEPLOYMENT.md)
- [Cloudflared Setup](helmfile/CLOUDFLARED_SETUP.md)
- [Secrets Management](SECRETS.md)
- [Testing Guide](TESTING.md)

## Traffic Flow

```
HTTP/S Traffic:
Internet → Cloudflare → Cloudflared (tunnel) → Services

TCP Traffic (Cardano P2P):
Internet → Worker Public IP:30001 (NodePort) → Cardano Node Pod

Internal Cluster:
Nodes ↔ Tailscale Mesh (L3) ↔ Kubernetes Services
```

Tailscale provides secure L3 mesh networking for inter-node communication.
