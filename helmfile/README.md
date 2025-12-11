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
├── helmfile.yaml.gotmpl        # Main configuration
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

Control which services are deployed using the `enabled` configuration.

### Configuration Files

- **Base**: `config/enabled.yaml` - Default settings for all environments
- **Environment-specific**: `environments/{env}/enabled.yaml` - Override defaults per environment

### Example

Base configuration (`config/enabled.yaml`):
```yaml
enabled:
  prometheus: true      # Enabled by default
  grafana: true
  cloudflared: true
  tailscaleOperator: true
  githubRunner: false   # Disabled by default
  certManager: false
  velero: false
```

Production override (`environments/prod/enabled.yaml`):
```yaml
enabled:
  prometheus: true
  grafana: true
  cloudflared: true
  tailscaleOperator: true
  githubRunner: true    # Enable in production
  certManager: true     # Enable in production
  velero: true          # Enable in production
```

### Adding New Services

When adding a new Helm release:

1. **Define in `config/releases.yaml.gotmpl`**:
   ```yaml
   {{- if $enabled.myService | default false }}
     - name: my-service
       namespace: my-namespace
       chart: repo/chart-name
   {{- end }}
   ```

2. **Add to `config/enabled.yaml`**:
   ```yaml
   enabled:
     myService: false  # or true for default enabled
   ```

3. **Add to environment files** (`environments/{env}/enabled.yaml`):
   ```yaml
   enabled:
     myService: true  # Enable for this environment
   ```

4. **Update the documentation** in `config/releases.yaml.gotmpl` header

This ensures:
- No parsing errors from missing keys
- Clear default behavior
- Environment-specific control

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
