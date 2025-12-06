# Helmfile Configuration

> **📚 Complete Documentation**: See [docs/helmfile.md](../docs/helmfile.md) for the comprehensive Helmfile guide.

Declarative Helm chart management for k3s infrastructure.

## Quick Start

```bash
# Install prerequisites
brew install helm helmfile
helm plugin install https://github.com/databus23/helm-diff

# Deploy all enabled services
helmfile apply

# Deploy to specific environment
helmfile -e prod apply
```

## Structure

```
helmfile/
├── helmfile.yaml              # Main configuration
├── config/
│   ├── enabled.yaml           # Enable/disable services
│   ├── repositories.yaml.gotmpl
│   └── releases.yaml.gotmpl
├── values/                    # Base values
│   ├── cloudflared-values.yaml
│   ├── grafana-values.yaml
│   ├── prometheus-values.yaml
│   └── tailscale-operator-values.yaml
└── environments/              # Environment overrides
    ├── dev/
    ├── staging/
    └── prod/
```

## Enabled Services

Edit `config/enabled.yaml`:

```yaml
enabled:
  prometheus: true
  haproxyIngress: false  # Disabled for hybrid cluster
  cloudflared: true  # HTTP/S ingress via Cloudflare tunnels
  grafana: true
  tailscaleOperator: true  # L3 mesh networking
  externalSecrets: true
```

## Environment Overrides

Environment-specific values in `environments/{env}/`:

```yaml
# environments/prod/cloudflared-values.yaml
cloudflare:
  tunnelName: "prod-tunnel"
  tunnelId: "your-prod-tunnel-id"
```

## Secrets with SOPS

Helmfile auto-decrypts `.enc.yaml` files:

```bash
sops -e values/secret.yaml > values/secret.enc.yaml
helmfile apply
```
