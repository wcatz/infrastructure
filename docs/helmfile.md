# Helmfile Configuration Guide

Complete guide for managing Kubernetes services with Helmfile in the hybrid cluster infrastructure.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Structure](#structure)
- [Enabled Services](#enabled-services)
- [Configuration](#configuration)
- [Environments](#environments)
- [Common Tasks](#common-tasks)
- [Service-Specific Configuration](#service-specific-configuration)
- [Troubleshooting](#troubleshooting)

## Overview

Helmfile provides declarative Helm chart management for the k3s infrastructure.

**Key Features:**
- **Declarative Configuration**: All services defined in YAML
- **Environment Support**: Dev, staging, and production configurations
- **Secret Management**: Integration with SOPS for encrypted values
- **Dependency Management**: Automatic ordering of service deployments
- **GitOps Ready**: Version-controlled infrastructure

**Services Managed by Helmfile:**
- Cloudflared (HTTP/S ingress via tunnels)
- Prometheus (metrics collection)
- Grafana (monitoring dashboards)
- Tailscale Operator (Kubernetes Tailscale resources)
- cert-manager (TLS certificate management)
- Velero (backup and restore)

**Note**: External Secrets Operator has been removed. Secrets are now managed using Ansible Vault and SOPS for encryption at rest.

## Quick Start

### Prerequisites

```bash
# Install prerequisites
brew install helm helmfile  # macOS
# or download from releases for Linux

# Install Helm diff plugin
helm plugin install https://github.com/databus23/helm-diff
```

### Deploy All Services

```bash
cd helmfile

# Preview changes
helmfile diff --suppress-secrets

# Deploy all enabled services
helmfile apply

# Deploy to specific environment
helmfile -e prod apply
```

### Deploy Specific Service

```bash
# Deploy only Prometheus
helmfile -l name=prometheus apply

# Deploy only Cloudflared
helmfile -l name=cloudflared apply
```

## Structure

```
helmfile/
├── helmfile.yaml              # Main configuration
├── .sops.yaml                 # SOPS encryption config
├── config/
│   ├── enabled.yaml           # Enable/disable services
│   ├── repositories.yaml.gotmpl
│   └── releases.yaml.gotmpl   # Service definitions
├── values/                    # Base values
│   ├── cloudflared-values.yaml
│   ├── grafana-values.yaml
│   ├── prometheus-values.yaml
│   ├── tailscale-operator-values.yaml
│   ├── cert-manager-values.yaml
│   ├── external-secrets-values.yaml
│   └── velero-values.yaml
├── environments/              # Environment overrides
│   ├── dev/
│   │   └── values.yaml
│   ├── staging/
│   │   └── values.yaml
│   └── prod/
│       └── values.yaml
├── manifests/                 # Raw Kubernetes manifests
│   └── namespace.yaml
└── charts/                    # Custom charts
    └── github-runner/
```

## Enabled Services

Services are enabled/disabled in `config/enabled.yaml`:

```yaml
enabled:
  # Monitoring
  prometheus: true
  grafana: true
  
  # Ingress and networking
  cloudflared: true
  tailscaleOperator: true
  
  # Certificate management
  certManager: true
  
  # Backup and restore
  velero: true
  
  # CI/CD
  githubRunner: false  # Enable for self-hosted runners
  
  # Legacy/Optional
  haproxyIngress: false  # Disabled for hybrid cluster
  metallb: false         # Not needed with Cloudflared
```

### Enable/Disable Services

Edit `config/enabled.yaml`:

```yaml
enabled:
  prometheus: true   # Enable service
  grafana: false     # Disable service
```

Then apply:

```bash
helmfile apply
```

## Configuration

### Helmfile.yaml

Main configuration file defining:
- Repositories
- Releases (services)
- Environments
- Hooks

```yaml
# Example from helmfile.yaml
repositories:
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts
  - name: grafana
    url: https://grafana.github.io/helm-charts

releases:
  - name: prometheus
    namespace: monitoring
    chart: prometheus-community/prometheus
    version: 25.8.0
    values:
      - values/prometheus-values.yaml
      - environments/{{ .Environment.Name }}/prometheus-values.yaml
```

### Base Values

Service configuration files in `values/`:

**Example: `values/prometheus-values.yaml`**

```yaml
server:
  retention: "30d"
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi

alertmanager:
  enabled: true

nodeExporter:
  enabled: true
```

### Environment Overrides

Environment-specific values in `environments/<env>/`:

**Example: `environments/prod/prometheus-values.yaml`**

```yaml
server:
  retention: "90d"  # Override for production
  resources:
    limits:
      memory: 4Gi   # More memory in prod
```

## Environments

### Default Environment

If no environment specified, uses default settings:

```bash
helmfile apply
# Same as: helmfile -e default apply
```

### Development Environment

```bash
helmfile -e dev apply
```

Configuration:
- Lower resource limits
- Shorter retention periods
- More verbose logging
- Test/development settings

### Staging Environment

```bash
helmfile -e staging apply
```

Configuration:
- Production-like settings
- Moderate resources
- Testing migrations and upgrades

### Production Environment

```bash
helmfile -e prod apply
```

Configuration:
- Maximum resources
- Longest retention
- High availability
- Production-grade monitoring

### Environment Variables

Pass environment variables to Helmfile:

```bash
export ENVIRONMENT=prod
helmfile -e ${ENVIRONMENT} apply
```

## Common Tasks

### Preview Changes

```bash
# Show diff for all services
helmfile diff --suppress-secrets

# Show diff for specific service
helmfile -l name=prometheus diff --suppress-secrets

# Show diff for specific environment
helmfile -e prod diff --suppress-secrets
```

### Apply Changes

```bash
# Apply all enabled services
helmfile apply

# Apply specific service
helmfile -l name=grafana apply

# Apply with concurrency
helmfile apply --concurrency=3
```

### List Releases

```bash
# List all releases
helmfile list

# List releases in specific namespace
helmfile list --selector namespace=monitoring
```

### Sync Releases

Force synchronization of releases:

```bash
# Sync all releases
helmfile sync

# Sync specific release
helmfile -l name=prometheus sync
```

### Delete Releases

```bash
# Delete all releases (careful!)
helmfile delete

# Delete specific release
helmfile -l name=prometheus delete

# Purge release (remove all resources)
helmfile -l name=prometheus delete --purge
```

### Template Generation

Generate manifests without applying:

```bash
# Generate all manifests
helmfile template --suppress-secrets > all-manifests.yaml

# Generate for specific service
helmfile -l name=prometheus template > prometheus-manifests.yaml

# Apply generated manifests
kubectl apply -f prometheus-manifests.yaml
```

### Validate Configuration

```bash
# Lint Helmfile configuration
helmfile lint

# Test template generation
helmfile template --suppress-secrets > /dev/null

# Validate with kubectl
helmfile template | kubectl apply --dry-run=client -f -
```

## Service-Specific Configuration

### Cloudflared

**Location**: `values/cloudflared-values.yaml`

```yaml
cloudflare:
  tunnelName: "infrastructure-tunnel"
  tunnelId: "<TUNNEL-ID>"

ingress:
  - hostname: app.example.com
    service: http://my-app.default.svc.cluster.local:80
  - hostname: api.example.com
    service: http://my-api.default.svc.cluster.local:8080
  - service: http_status:404  # Catch-all
```

**Enable Cloudflared:**

```yaml
# config/enabled.yaml
enabled:
  cloudflared: true
```

**Deploy:**

```bash
helmfile -l name=cloudflared apply
```

### Prometheus

**Location**: `values/prometheus-values.yaml`

```yaml
server:
  retention: "30d"
  persistentVolume:
    enabled: true
    size: 50Gi
  
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 4Gi

alertmanager:
  enabled: true
  persistentVolume:
    enabled: true
    size: 10Gi

nodeExporter:
  enabled: true
```

**Access Prometheus:**

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:80
open http://localhost:9090
```

### Grafana

**Location**: `values/grafana-values.yaml`

```yaml
adminPassword: "changeme"  # Change in production!

persistence:
  enabled: true
  size: 10Gi

datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus.monitoring.svc.cluster.local:80
      isDefault: true

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
    - name: 'default'
      folder: ''
      type: file
      options:
        path: /var/lib/grafana/dashboards/default
```

**Access Grafana:**

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
open http://localhost:3000
# Default: admin / changeme
```

### Tailscale Operator

**Location**: `values/tailscale-operator-values.yaml`

```yaml
oauth:
  clientId: "<CLIENT-ID>"
  clientSecret: "<CLIENT-SECRET>"

operatorConfig:
  hostname: "k8s-operator"
  tags: "tag:k8s-operator"
```

**Setup OAuth credentials:**

1. Go to https://login.tailscale.com/admin/settings/oauth
2. Generate OAuth client
3. Create Kubernetes secret:

```bash
kubectl create namespace tailscale
kubectl create secret generic operator-oauth \
  --from-literal=client_id=<CLIENT-ID> \
  --from-literal=client_secret=<CLIENT-SECRET> \
  -n tailscale
```

### cert-manager

**Location**: `values/cert-manager-values.yaml`

```yaml
installCRDs: true

resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

**Create ClusterIssuer:**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

### Velero

**Location**: `values/velero-values.yaml`

```yaml
configuration:
  provider: aws  # or gcp, azure
  
  backupStorageLocation:
    name: default
    bucket: velero-backups
    prefix: k8s-cluster
    
  volumeSnapshotLocation:
    name: default
    
credentials:
  useSecret: true
  secretContents:
    cloud: |
      [default]
      aws_access_key_id=<ACCESS-KEY>
      aws_secret_access_key=<SECRET-KEY>

initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.8.0
    volumeMounts:
      - mountPath: /target
        name: plugins
```

**Create backup:**

```bash
velero backup create full-backup-$(date +%Y%m%d) \
  --include-namespaces '*' \
  --snapshot-volumes
```

## Troubleshooting

### Helmfile Diff Shows Changes but Nothing Changed

**Cause**: Helm template rendering differences

**Solution**:

```bash
# Force update
helmfile -l name=<service> sync

# Or update with --force
helmfile -l name=<service> apply --force
```

### Service Not Deploying

**Check enabled status:**

```bash
cat config/enabled.yaml | grep <service>
```

**Check Helmfile logs:**

```bash
helmfile -l name=<service> apply --debug
```

**Check Helm release status:**

```bash
helm list -n <namespace>
helm status <release-name> -n <namespace>
```

### Values Not Applied

**Check value precedence:**

1. Base values: `values/<service>-values.yaml`
2. Environment values: `environments/<env>/<service>-values.yaml`
3. Command line: `-e key=value`

**Debug values:**

```bash
# Show computed values
helmfile -l name=<service> write-values

# Show final manifests
helmfile -l name=<service> template
```

### SOPS Decryption Errors

**Error**: "Failed to decrypt"

**Solution**:

```bash
# Check age key file exists
ls ~/.config/sops/age/keys.txt

# Set SOPS_AGE_KEY_FILE
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Verify key is correct
sops -d values/secret.enc.yaml
```

### Repository Not Found

**Error**: "chart not found"

**Solution**:

```bash
# Update repository cache
helm repo update

# Force Helmfile to update
helmfile repos

# Check repository is defined
grep -A 2 "name: <repo>" helmfile.yaml
```

### Namespace Issues

**Error**: "namespace not found"

**Solution**:

```bash
# Create namespace
kubectl create namespace <namespace>

# Or add to helmfile manifests
cat > manifests/<namespace>-namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: <namespace>
EOF

helmfile apply
```

### Resource Limits

**Error**: "Insufficient resources"

**Solution**:

```bash
# Check node resources
kubectl top nodes

# Adjust limits in values file
# values/<service>-values.yaml:
resources:
  limits:
    memory: "512Mi"  # Reduce from 2Gi
```

---

[⬅ Back to Ansible Guide](ansible.md) | [Next: Operations Guide ➡](operate.md)
