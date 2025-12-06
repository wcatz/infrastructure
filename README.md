# Hybrid Kubernetes Infrastructure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s-326CE5?logo=kubernetes)](https://k3s.io/)
[![Helm](https://img.shields.io/badge/Helm-v3-0F1689?logo=helm)](https://helm.sh/)
[![Ansible](https://img.shields.io/badge/Ansible-2.10+-EE0000?logo=ansible)](https://www.ansible.com/)

**Production-ready hybrid Kubernetes infrastructure with secure Tailscale mesh networking and Cloudflare tunnel ingress.**

> **📚 Complete documentation available in [`docs/`](docs/)** - This README provides a quick overview and getting started guide.

## Overview

This repository provides infrastructure-as-code for deploying a **hybrid Kubernetes cluster** that:
- Runs a **control plane behind CGNAT** with no public IP required
- Deploys **workloads on public VPS workers** 
- Uses **Tailscale** for secure inter-node mesh networking
- Exposes services via **Cloudflared tunnels** (no load balancers)
- Manages everything declaratively with **Ansible** and **Helmfile**

**Perfect for home labs, edge computing, and cost-effective cloud deployments.**

## Table of Contents

- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [What You Get](#what-you-get)
- [Contributing](#contributing)
- [License](#license)

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                    ┌────▼─────┐
                    │Cloudflare│ (Edge Network)
                    └────┬─────┘
                         │ Secure Tunnel
            ┌────────────▼────────────┐
            │  Cloudflared Pod        │ (Worker Node)
            └────────────┬────────────┘
                         │
         ┌───────────────▼──────────────┐
         │    Kubernetes Services       │
         │         (Pods)               │
         └──────────────────────────────┘

Control Plane ←──→ Tailscale VPN ←──→ Worker Nodes
 (CGNAT/Home)      (100.64.0.0/10)     (Public VPS)
```

### Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **Control Plane** | K3s server (API, scheduler, etcd) | Home/CGNAT - no public IP needed |
| **Worker Nodes** | Application workloads | Public VPS with direct internet access |
| **Tailscale** | Secure L3 mesh network | All nodes - encrypted inter-node traffic |
| **Cloudflared** | HTTP/S ingress tunnels | Worker nodes - no load balancer required |
| **Ansible** | Infrastructure deployment | Local machine - automates k3s & Tailscale |
| **Helmfile** | Service management | Local machine - deploys apps declaratively |

### Why This Architecture?

✅ **No Port Forwarding**: Control plane stays completely private  
✅ **Cost Effective**: No cloud NAT gateways or load balancers  
✅ **Secure by Default**: All traffic encrypted via Tailscale mesh  
✅ **Scalable**: Add workers easily, control plane handles scheduling  
✅ **GitOps Ready**: Everything version-controlled and reproducible

## Quick Start

### Prerequisites

- **Local Machine**: Ansible, kubectl, Helm, Helmfile, SOPS, age, cloudflared
- **Servers**: 1+ Ubuntu/Debian machines (control plane can be behind CGNAT)
- **Accounts**: Tailscale, Cloudflare (both free tier OK)

### One-Command Deployment

```bash
# Clone repository
git clone https://github.com/wcatz/infrastructure.git
cd infrastructure

# Run unified deployment script
./runme.sh
```

The `runme.sh` script will:
1. ✅ Validate prerequisites
2. 🔐 Configure secrets (Ansible Vault + SOPS)
3. 🔒 Deploy Tailscale VPN mesh
4. ☸️  Deploy K3s cluster
5. 📦 Deploy services (Prometheus, Grafana, etc.)
6. 🌐 Configure Cloudflared tunnels
7. ✔️  Validate deployment

### Manual Setup

Prefer step-by-step? Follow the [**Complete Setup Guide**](docs/setup.md).

```bash
# 1. Install prerequisites
brew install ansible kubectl helm helmfile sops age cloudflared  # macOS
# See docs/setup.md for Linux instructions

# 2. Configure secrets
cd ansible
cp .vault_pass.example .vault_pass
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# Edit vault.yml with your secrets, then:
ansible-vault encrypt group_vars/all/vault.yml

# 3. Configure inventory
cp inventory.ini.example inventory.ini
# Edit inventory.ini with your server IPs

# 4. Deploy infrastructure
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# 5. Get kubeconfig
scp user@control-plane:/etc/rancher/k3s/k3s.yaml ~/.kube/config
# Update server URL to Tailscale IP

# 6. Deploy services
cd ../helmfile
helmfile apply
```

## Documentation

### 📖 Complete Guides

| Guide | Description |
|-------|-------------|
| **[Setup Guide](docs/setup.md)** | Complete setup from prerequisites to deployment |
| **[Operations Guide](docs/operate.md)** | Testing, monitoring, backups, disaster recovery |
| **[Ansible Guide](docs/ansible.md)** | Infrastructure automation and playbooks |
| **[Helmfile Guide](docs/helmfile.md)** | Service deployment and configuration |

### 🚀 Quick References

- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to this project
- **[Changelog](CHANGELOG.md)** - Version history and changes
- **[Validation Scripts](scripts/)** - Prerequisite and deployment validation

## What You Get

### Infrastructure Services

Deployed automatically via Helmfile:

- **🔍 Prometheus** - Metrics collection and alerting
- **📊 Grafana** - Monitoring dashboards and visualization  
- **🌐 Cloudflared** - HTTP/S ingress via Cloudflare tunnels
- **🔐 Tailscale Operator** - Kubernetes Tailscale resource management
- **📜 cert-manager** - Automatic TLS certificate management
- **🔑 External Secrets** - Integration with Vault/AWS Secrets Manager
- **💾 Velero** - Backup and disaster recovery

### Automation & GitOps

- **Ansible Playbooks**: Automated k3s and Tailscale deployment
- **Helmfile Releases**: Declarative service management
- **GitHub Actions**: CI/CD workflows for testing and deployment
- **Secret Management**: SOPS encryption + Ansible Vault
- **Validation Scripts**: Automated prerequisite and deployment checks

## Contributing

We welcome contributions! Please see our [**Contributing Guide**](CONTRIBUTING.md) for details on:

- Code of conduct
- Development workflow
- Pull request process
- Documentation standards
- Testing guidelines

## License

[MIT License](LICENSE)

---

**Need Help?**
- 📖 **Documentation**: Start with [docs/setup.md](docs/setup.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/wcatz/infrastructure/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/wcatz/infrastructure/discussions)

**Quick Links**:
- [Complete Setup Guide](docs/setup.md)
- [Operations Manual](docs/operate.md)
- [Troubleshooting](docs/operate.md#troubleshooting)
