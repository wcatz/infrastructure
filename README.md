# Infrastructure Management

GitOps-based infrastructure for hybrid k3s clusters with Tailscale networking, Cloudflared tunnels, and HAProxy ingress.

## Architecture

This repository provides a **minimalist, modular framework** for deploying a hybrid Kubernetes cluster:

- **Control Plane Node** (Home/CGNAT):
  - Runs K3s server only (no workloads)
  - Tainted to prevent workload scheduling
  - Secured with Tailscale for cluster communication
  - No public exposure required

- **Worker Node(s)** (Netcup VPS/Public IP):
  - Runs all application workloads
  - Cloudflared for HTTP/HTTPS ingress via Cloudflare
  - HAProxy Ingress controller for routing
  - Tailscale for secure control plane communication
  - Supports NodePort services and `hostNetwork` when needed

## Stack

- **k3s**: Lightweight Kubernetes (Traefik disabled)
- **HAProxy Ingress**: HTTP/HTTPS routing via NodePort
- **Cloudflared**: Secure tunnel to Cloudflare edge
- **Tailscale**: VPN for secure inter-node communication
- **Prometheus/Grafana**: Monitoring stack
- **SOPS/age**: Secret encryption
- **Ansible Vault**: Infrastructure secret management

## Quick Setup

### 1. Deploy Hybrid K3s Cluster

```bash
cd ansible

# Setup Ansible Vault for secrets
cp .vault_pass.example .vault_pass
vim .vault_pass  # Add your vault password

# Configure encrypted secrets
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
vim group_vars/all/vault.yml  # Add your K3s token and Tailscale key
ansible-vault encrypt group_vars/all/vault.yml

# Setup inventory for hybrid cluster
cp inventory.ini.example inventory.ini
vim inventory.ini  # Configure control plane and worker nodes

# Deploy Tailscale on all nodes (required for hybrid cluster)
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# Deploy k3s cluster
# Control plane: Tainted, no workloads
# Workers: Run all workloads
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Get kubeconfig
scp user@k3s-control:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Update server URL to use Tailscale IP of control plane
sed -i 's/127.0.0.1/100.64.x.x/' ~/.kube/config
```

### 2. Deploy Services via Helmfile

```bash
cd helmfile

# Deploy HAProxy Ingress and monitoring
helmfile apply

# Enable Cloudflared for worker node ingress
# 1. Create Cloudflare tunnel and get credentials
# 2. Create Kubernetes secret with tunnel credentials
kubectl create namespace cloudflare
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
  -n cloudflare

# 3. Enable Cloudflared in config
vim config/enabled.yaml  # Set cloudflared: true

# 4. Configure ingress routes in values/cloudflared-values.yaml
# 5. Apply changes
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
  - Control plane: Tainted to prevent workload scheduling
  - Worker nodes: Labeled for workload placement
- Tailscale VPN on all nodes (required for cluster communication)
- Ansible Vault for encrypted secrets (K3s token, Tailscale key)

### Helmfile
- HAProxy Ingress (NodePort on workers: 30080/30443)
- Cloudflared tunnels (disabled by default - enable when configured)
- Tailscale Kubernetes Operator (optional)
- Prometheus & Grafana monitoring
- Environment configs (dev/staging/prod)

### Kubernetes Examples
- Modular deployment templates
- Service definitions (ClusterIP, NodePort, Headless)
- Ingress configurations for HAProxy
- ConfigMaps and Secrets with SOPS encryption
- See `kubernetes-examples/` directory

### GitHub Actions
- `helmfile-diff.yaml`: Preview changes on PRs
- `helmfile-apply.yaml`: Manual deployment to environments
- SOPS integration for secret decryption

## Environment Management

Deploy to specific environments:

```bash
helmfile -e dev apply
helmfile -e staging apply
helmfile -e prod apply
```

## Documentation

- [Ansible README](ansible/README.md) - Infrastructure provisioning
- [Helmfile README](helmfile/README.md) - Service deployment
- [Kubernetes Examples](kubernetes-examples/README.md) - Workload templates
- [Cloudflared Setup](helmfile/CLOUDFLARED_SETUP.md) - Tunnel configuration
- [Secrets Management](SECRETS.md) - SOPS and Ansible Vault
- [Testing Guide](TESTING.md) - Validation procedures

## Traffic Flow

### HTTP/HTTPS Traffic
```
Internet → Cloudflare → Cloudflared (worker) → HAProxy Ingress → Services → Pods
```

### Cluster Communication
```
Control Plane (CGNAT) ←→ Tailscale VPN ←→ Worker Nodes (Public IP)
```

### Key Features
- **No port forwarding required**: Cloudflared handles ingress
- **Secure cluster networking**: Tailscale VPN for inter-node communication
- **Workload isolation**: Control plane tainted to run only K3s components
- **Scalable architecture**: Add workers as needed without infrastructure changes
