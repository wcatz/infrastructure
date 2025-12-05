# Helmfile Configuration

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
│   ├── haproxy-ingress.yaml
│   ├── cloudflared-values.yaml
│   ├── grafana-values.yaml
│   └── prometheus-values.yaml
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
  haproxyIngress: true
  cloudflared: false  # Enable after tunnel setup
  grafana: true
  tailscaleOperator: false
  externalSecrets: true
```

## Environment Overrides

Environment-specific values in `environments/{env}/`:

```yaml
# environments/prod/haproxy-ingress.yaml
controller:
  replicaCount: 3
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
```

## Secrets with SOPS

Helmfile auto-decrypts `.enc.yaml` files:

```bash
sops -e values/secret.yaml > values/secret.enc.yaml
helmfile apply
```
