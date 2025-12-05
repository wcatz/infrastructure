# Infrastructure Management

GitOps-based infrastructure for k3s clusters with Cloudflare tunnels, Tailscale VPN, and HAProxy ingress.

## Stack

- **k3s**: Lightweight Kubernetes
- **HAProxy Ingress**: HTTP/HTTPS ingress controller
- **Cloudflared**: Secure tunnel to Cloudflare
- **Tailscale**: VPN on hosts + Kubernetes operator
- **Prometheus/Grafana**: Monitoring
- **SOPS**: Secret encryption for GitOps

## Quick Setup

### 1. Deploy k3s Cluster

```bash
cd ansible
cp inventory.ini.example inventory.ini
# Edit inventory.ini with your servers

# Generate token and deploy
openssl rand -hex 32
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml -e "k3s_token=YOUR_TOKEN"

# Get kubeconfig
scp user@k3s-server:/etc/rancher/k3s/k3s.yaml ~/.kube/config
sed -i 's/127.0.0.1/YOUR_SERVER_IP/' ~/.kube/config
```

### 2. Deploy Services via Helmfile

```bash
cd helmfile

# Review and enable services
vim config/enabled.yaml

# Deploy all enabled services
helmfile apply
```

### 3. Setup Secrets with SOPS

```bash
# Install age and sops
brew install age sops

# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Create .sops.yaml with your public key
cat > .sops.yaml << EOY
creation_rules:
  - age: YOUR_PUBLIC_KEY
EOY

# Encrypt secrets
sops -e secrets/example.yaml > secrets/example.enc.yaml

# Deploy secrets
sops -d secrets/example.enc.yaml | kubectl apply -f -
```

## Components

### Ansible (`ansible/`)
- k3s deployment (Traefik disabled)
- Tailscale VPN setup on hosts
- System configuration

### Helmfile (`helmfile/`)
- HAProxy Ingress Controller
- Cloudflared tunnels
- Tailscale Kubernetes Operator
- Prometheus & Grafana monitoring
- Environment-specific configs (dev/staging/prod)

### GitHub Actions (`.github/workflows/`)
- `helmfile-diff.yaml`: Preview changes on PRs
- `helmfile-apply.yaml`: Manual deployment workflow

## Environment Management

Override base configs per environment:

```bash
# Deploy to specific environment
helmfile -e dev apply
helmfile -e staging apply
helmfile -e prod apply
```

Environment overrides in `helmfile/environments/{env}/`.

## Documentation

- [Ansible README](ansible/README.md) - Playbook details
- [Helmfile README](helmfile/README.md) - Release management
- [Cloudflared Setup](helmfile/CLOUDFLARED_SETUP.md) - Tunnel configuration
- [Secrets Management](SECRETS.md) - SOPS and secret workflows
- [Disaster Recovery](DISASTER_RECOVERY.md) - Backup and restore
- [Testing Guide](TESTING.md) - Validation procedures

## Traffic Flow

```
Internet → Cloudflare Tunnel → HAProxy Ingress → k3s Services
                                      ↓
                            Prometheus Monitoring
```

Tailscale provides secure VPN access to infrastructure.
