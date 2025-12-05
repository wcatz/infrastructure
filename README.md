# Infrastructure Management

GitOps-based infrastructure for hybrid k3s clusters with Tailscale networking and Cloudflared tunnels.

## Architecture

This repository provides a **minimalist, modular framework** for deploying a hybrid Kubernetes cluster:

- **Control Plane Node** (Home/CGNAT):
  - Runs K3s server only (no workloads)
  - Tainted to prevent workload scheduling
  - Secured with Tailscale for cluster communication
  - No public exposure required
  - Internal-only access via Tailscale mesh

- **Worker Node(s)** (VPS/Public IP):
  - Runs all application workloads
  - Cloudflared for HTTP/HTTPS ingress via Cloudflare tunnels
  - Direct TCP exposure via NodePort or hostNetwork for P2P/services
  - Tailscale for secure control plane communication
  - Public IP for direct service access

## Stack

- **k3s**: Lightweight Kubernetes (Traefik and servicelb disabled)
- **Cloudflared**: Secure tunnel to Cloudflare edge, routes directly to Kubernetes services
- **Tailscale**: VPN for secure inter-node communication
- **Tailscale Operator**: Manages Tailscale connectivity in Kubernetes (optional)
- **Prometheus/Grafana**: Monitoring stack (optional)
- **SOPS/age**: Secret encryption
- **Ansible Vault**: Infrastructure secret management

## Key Features

- **No Load Balancers**: Simplified networking without HAProxy/MetalLB - uses Cloudflared for HTTP/S and direct TCP exposure via public IPs
- **Tailscale Mesh**: Secure L3 networking between cluster nodes for internal communication
- **Workload Placement**: Control plane behind CGNAT, workers with public IPs
- **Stateful Workloads**: PVC-based persistent storage with failover support
- **Hybrid Architecture**: Minimal and scalable design for distributed deployments
- **Direct Service Access**: TCP services exposed directly via NodePort on worker public IPs

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

# Deploy Tailscale first (required for hybrid cluster)
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# Deploy k3s cluster (secrets loaded from vault)
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Get kubeconfig
scp user@k3s-server:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Update server URL to use Tailscale IP of control plane
sed -i 's/127.0.0.1/TAILSCALE_IP/' ~/.kube/config
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
- K3s deployment with hybrid cluster support
  - Control plane tainted to prevent workload scheduling
  - Worker nodes for all workloads
  - Traefik and servicelb disabled
- Tailscale VPN on all nodes for secure inter-node communication
- Ansible Vault for encrypted secrets (K3s token, Tailscale keys, OAuth credentials)

### Helmfile
- Cloudflared tunnels (HTTP/S ingress, routes directly to services)
- Tailscale Kubernetes Operator (L3 mesh networking, optional)
- Prometheus & Grafana (monitoring)
- External Secrets (optional)
- HAProxy Ingress (legacy/optional - disabled by default)

### GitHub Actions
- `helmfile-diff.yaml`: Preview changes on PRs
- `helmfile-apply.yaml`: Manual Helmfile deployment with SOPS/age integration
- `cloudflared-setup.yaml`: Cloudflared tunnel configuration

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
- [Hybrid Cluster Setup](HYBRID_CLUSTER_SETUP.md)
- [Cloudflared Setup](helmfile/CLOUDFLARED_SETUP.md)
- [Secrets Management](SECRETS.md)
- [Testing Guide](TESTING.md)
- [Kubernetes Examples](kubernetes-examples/README.md)

## Traffic Flow

```
HTTP/S Traffic:
Internet → Cloudflare → Cloudflared Tunnel (worker) → Kubernetes Services → Pods

TCP Traffic (P2P/Direct Services):
Internet → Worker Public IP:NodePort → Application Pods

Internal Cluster Communication:
Control Plane ↔ Tailscale Mesh (L3) ↔ Worker Nodes
```

**Network Model**: Tailscale mesh for secure inter-node communication + public IPs on workers for direct service access. No load balancers (HAProxy/MetalLB) required.

## License

MIT
