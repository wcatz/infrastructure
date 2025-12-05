# Infrastructure Management

GitOps-based infrastructure for k3s clusters with Cloudflare tunnels, Tailscale VPN, and HAProxy ingress.

## Stack

- **k3s**: Lightweight Kubernetes
- **HAProxy Ingress**: HTTP/HTTPS via NodePort (ports 30080/30443)
- **Cloudflared**: Secure tunnel to Cloudflare
- **Tailscale**: VPN on hosts + Kubernetes operator
- **Prometheus/Grafana**: Monitoring
- **SOPS**: Secret encryption (age-based)

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
- k3s deployment (Traefik disabled)
- Tailscale VPN on hosts

### Helmfile
- HAProxy Ingress (NodePort 30080/30443)
- Cloudflared tunnels
- Tailscale Kubernetes Operator
- Prometheus & Grafana
- Environment configs (dev/staging/prod)

### GitHub Actions
- `helmfile-diff.yaml`: Preview changes on PRs
- `helmfile-apply.yaml`: Manual deployment

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
- [Cloudflared Setup](helmfile/CLOUDFLARED_SETUP.md)
- [Secrets Management](SECRETS.md)
- [Testing Guide](TESTING.md)

## Traffic Flow

```
Internet → External LB → NodePort 30080/30443 → HAProxy Ingress → Services
```

Tailscale provides VPN access to infrastructure.
