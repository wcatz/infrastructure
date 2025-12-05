# Helmfile Configuration

Declarative Helm chart management for k3s infrastructure.

## Quick Start

```bash
# Install prerequisites
brew install helm helmfile
helm plugin install https://github.com/databus23/helm-diff

# Preview changes
helmfile diff

# Deploy all enabled services
helmfile apply

# Deploy specific service
helmfile -l name=haproxy-ingress apply

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
├── values/                    # Base values for all environments
│   ├── haproxy-ingress.yaml
│   ├── cloudflared-values.yaml
│   ├── grafana-values.yaml
│   └── prometheus-values.yaml
└── environments/              # Environment-specific overrides
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
  tailscaleOperator: true  # Kubernetes Tailscale operator
  externalSecrets: true
  velero: false  # Enable for backup/restore
```

## Environment Overrides

Create environment-specific values in `environments/{env}/`:

- **Dev**: Lower resources, shorter retention
- **Staging**: Moderate resources, medium retention
- **Prod**: Higher resources, longer retention, HA configs

Example override:
```yaml
# environments/prod/haproxy-ingress.yaml
controller:
  replicaCount: 3
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
```

## Adding New Services

1. Add repository to `config/repositories.yaml.gotmpl`
2. Add release to `config/releases.yaml.gotmpl`
3. Create values file in `values/`
4. Enable in `config/enabled.yaml`
5. (Optional) Add environment overrides

## Secrets with SOPS

Helmfile automatically decrypts `.enc.yaml` files with SOPS.

```bash
# Create encrypted values
sops -e values/secret-values.yaml > values/secret-values.enc.yaml

# Helmfile will decrypt automatically
helmfile apply
```
