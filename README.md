# Infrastructure Management

GitOps-based infrastructure for hybrid k3s clusters with Tailscale networking and Cloudflared tunnels.

## Table of Contents

- [Architecture](#architecture)
- [Stack](#stack)
- [Key Features](#key-features)
- [Prerequisites](#prerequisites)
- [Quick Setup](#quick-setup)
  - [1. Deploy k3s Cluster](#1-deploy-k3s-cluster)
  - [2. Deploy Services via Helmfile](#2-deploy-services-via-helmfile)
  - [3. Setup Secrets with SOPS](#3-setup-secrets-with-sops)
- [Components](#components)
- [Environment Management](#environment-management)
- [Traffic Flow](#traffic-flow)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

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

## Prerequisites

Before starting, ensure you have the following:

### Required Tools

- **Ansible** (>= 2.10): For infrastructure automation
- **kubectl**: Kubernetes command-line tool
- **Helm** (>= 3.x): Kubernetes package manager
- **Helmfile**: Declarative Helm chart deployment
- **SOPS** and **age**: For secret encryption
- **Git**: Version control

### Infrastructure Requirements

- **Control Plane Node**: Server with SSH access (can be behind CGNAT/NAT)
- **Worker Node(s)**: VPS or server with public IP address
- **Tailscale Account**: For secure mesh networking ([tailscale.com](https://tailscale.com))
- **Cloudflare Account** (optional): For HTTP/S ingress via tunnels

### Installation

```bash
# macOS
brew install ansible kubectl helm helmfile sops age

# Linux (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install -y ansible kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Helmfile
wget https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64
chmod +x helmfile_linux_amd64 && sudo mv helmfile_linux_amd64 /usr/local/bin/helmfile

# Install Helm diff plugin
helm plugin install https://github.com/databus23/helm-diff

# Install SOPS and age
wget https://github.com/mozilla/sops/releases/latest/download/sops-latest.linux
chmod +x sops-latest.linux && sudo mv sops-latest.linux /usr/local/bin/sops
wget https://github.com/FiloSottile/age/releases/latest/download/age-latest-linux-amd64.tar.gz
tar xzf age-latest-linux-amd64.tar.gz && sudo mv age/age* /usr/local/bin/
```

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
- `helmfile-apply-self-hosted.yaml`: Deployment using self-hosted runner with Tailscale
- `test-self-hosted-runner.yaml`: Test and validate self-hosted runner connectivity
- `cloudflared-setup.yaml`: Cloudflared tunnel configuration
- **Self-Hosted Runner**: GitHub Actions runner with Tailscale access to control plane behind CGNAT

## Environment Management

Deploy to specific environments:

```bash
helmfile -e dev apply
helmfile -e staging apply
helmfile -e prod apply
```

## Documentation

### Setup Guides

- [Tailscale Setup](TAILSCALE_SETUP.md) - Configure Tailscale VPN mesh networking
- [Hybrid Cluster Setup](HYBRID_CLUSTER_SETUP.md) - Deploy hybrid k3s cluster architecture
- [Secrets Management](SECRETS.md) - SOPS/age and Ansible Vault configuration
- [GitHub Actions Runner Setup](GITHUB_RUNNER_SETUP.md) - Self-hosted runner with Tailscale
- [Cloudflared Setup](helmfile/CLOUDFLARED_SETUP.md) - Configure Cloudflare tunnels

### Component Documentation

- [Ansible README](ansible/README.md) - Ansible playbooks and roles
- [Helmfile README](helmfile/README.md) - Helmfile configuration and services
- [Kubernetes Examples](kubernetes-examples/README.md) - Example workload configurations

### Operational Guides

- [Testing Guide](TESTING.md) - Testing procedures and validation
- [Deployment Audit](DEPLOYMENT_AUDIT.md) - Deployment verification
- [Disaster Recovery](DISASTER_RECOVERY.md) - Backup and recovery procedures
- [Worker Backup Recovery](WORKER_BACKUP_RECOVERY.md) - Worker node recovery

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

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:

- Code of conduct
- Development workflow
- Pull request process
- Coding standards
- Testing guidelines

## License

MIT
