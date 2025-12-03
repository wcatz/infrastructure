# Helmfile Configuration Guide

This directory contains Helmfile configurations for managing Kubernetes deployments across multiple environments.

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Quick Start](#quick-start)
- [Environment Management](#environment-management)
- [Managing Releases](#managing-releases)
- [Adding New Applications](#adding-new-applications)
- [Validation and Testing](#validation-and-testing)
- [Troubleshooting](#troubleshooting)

## Overview

Helmfile is a declarative specification for deploying Helm charts. This configuration uses:
- **Gotmpl templates** for dynamic configuration
- **Environment-specific values** for dev/staging/prod deployments
- **Modular release definitions** for maintainability
- **GitOps workflows** for automated deployments

## Directory Structure

```
helmfile/
├── helmfile.yaml                    # Main Helmfile configuration
├── config/                          # Configuration templates
│   ├── repositories.yaml.gotmpl     # Helm repository definitions
│   ├── releases.yaml.gotmpl         # Release definitions
│   └── enabled.yaml                 # Enable/disable applications
├── values/                          # Base Helm values files
│   ├── cloudflared-values.yaml      # Cloudflared base configuration
│   ├── haproxy-ingress.yaml         # HAProxy ingress base config
│   └── prometheus-values.yaml       # Prometheus base configuration
├── environments/                    # Environment-specific overrides
│   ├── dev/                        # Development environment
│   │   ├── cloudflared-values.yaml
│   │   └── haproxy-ingress.yaml
│   ├── staging/                    # Staging environment
│   │   ├── cloudflared-values.yaml
│   │   └── haproxy-ingress.yaml
│   └── prod/                       # Production environment
│       ├── cloudflared-values.yaml
│       └── haproxy-ingress.yaml
├── CLOUDFLARED_SETUP.md            # Cloudflared setup guide
└── README.md                        # This file
```

## Quick Start

### Prerequisites

- Helm 3.13+ installed
- Helmfile 0.159+ installed
- kubectl configured with cluster access
- Kubernetes cluster running

### Install Tools

> **Note:** Helm is a prerequisite for Helmfile. Install Helm first, verify the installation, then install Helmfile and the required helm-diff plugin.

#### Step 1: Install Helm

**macOS:**
```bash
brew install helm
```

**Linux:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Verify Helm installation:**
```bash
helm version
```

You should see output showing Helm version 3.13 or later.

#### Step 2: Install Helm-Diff Plugin

The helm-diff plugin is required by Helmfile. Install it with a pinned version to avoid compatibility issues:

```bash
# Uninstall any existing version
helm plugin uninstall diff || true

# Install pinned version v3.6.0
helm plugin install https://github.com/databus23/helm-diff --version v3.6.0

# Verify installation
helm plugin list
```

#### Step 3: Install Helmfile

**macOS:**
```bash
brew install helmfile
```

**Linux:**
```bash
wget https://github.com/helmfile/helmfile/releases/download/v0.159.0/helmfile_0.159.0_linux_amd64.tar.gz
tar xzf helmfile_0.159.0_linux_amd64.tar.gz
sudo mv helmfile /usr/local/bin/

# Verify installation
helmfile version
```

### Deploy Default Environment

```bash
cd helmfile

# View what would be deployed
helmfile diff

# Deploy all enabled releases
helmfile apply

# Deploy specific release
helmfile -l name=haproxy-ingress apply
```

## Environment Management

### Environment-Specific Deployments

The configuration supports multiple environments with dedicated values files:

**Development:**
```bash
# Preview changes
helmfile -e dev diff

# Deploy to dev
helmfile -e dev apply
```

**Staging:**
```bash
# Preview changes
helmfile -e staging diff

# Deploy to staging
helmfile -e staging apply
```

**Production:**
```bash
# Preview changes
helmfile -e prod diff

# Deploy to production (use with caution!)
helmfile -e prod apply
```

### Environment Configuration

Environment-specific values are loaded from `environments/{env}/` and override base values:

1. **Base values**: `values/app-name.yaml` (applied to all environments)
2. **Environment values**: `environments/{env}/app-name.yaml` (environment-specific overrides)

Example for Cloudflared in production:
```bash
helmfile -e prod -l name=cloudflared apply
```

This loads:
- `values/cloudflared-values.yaml` (base)
- `environments/prod/cloudflared-values.yaml` (prod overrides)

### Parameterization Best Practices

1. **Keep base values generic** - suitable for all environments
2. **Use environment files for differences**:
   - Replica counts (higher in prod)
   - Resource limits (larger in prod)
   - Timeouts (shorter in dev)
   - Feature flags (experimental features in dev/staging)
3. **Document environment-specific settings** in comments

## Managing Releases

### List All Releases

```bash
# Show all releases
helmfile list

# Show releases for specific environment
helmfile -e prod list
```

### Viewing Differences

Before deploying, always preview changes:

```bash
# Show diff for all releases
helmfile diff

# Show diff for specific release
helmfile -l name=cloudflared diff

# Show diff with context
helmfile diff --context 5
```

### Deploying Changes

```bash
# Deploy all enabled releases
helmfile apply

# Deploy specific release
helmfile -l name=haproxy-ingress apply

# Deploy with sync (more thorough)
helmfile sync
```

### Updating a Release

1. **Edit values file**:
   ```bash
   vim values/haproxy-ingress.yaml
   # or
   vim environments/prod/haproxy-ingress.yaml
   ```

2. **Preview changes**:
   ```bash
   helmfile -l name=haproxy-ingress diff
   ```

3. **Apply changes**:
   ```bash
   helmfile -l name=haproxy-ingress apply
   ```

### Rolling Back

```bash
# Check release history
helm history haproxy-ingress -n haproxy-ingress

# Rollback to previous version
helm rollback haproxy-ingress -n haproxy-ingress

# Rollback to specific revision
helm rollback haproxy-ingress 3 -n haproxy-ingress
```

### Destroying Releases

```bash
# Delete specific release
helmfile -l name=cloudflared destroy

# Delete all releases (use with extreme caution!)
helmfile destroy
```

## Adding New Applications

### Step 1: Add Helm Repository

Edit `config/repositories.yaml.gotmpl`:

```yaml
repositories:
  - name: my-repo
    url: https://charts.example.com
```

### Step 2: Create Release Definition

Edit `config/releases.yaml.gotmpl`:

```yaml
{{- if $enabled.myApp | default false }}
  - name: my-app
    namespace: my-namespace
    createNamespace: true
    chart: my-repo/my-chart
    version: 1.0.0
    values:
      - values/my-app-values.yaml
      {{- if eq .Environment.Name "dev" }}
      - environments/dev/my-app-values.yaml
      {{- else if eq .Environment.Name "staging" }}
      - environments/staging/my-app-values.yaml
      {{- else if eq .Environment.Name "prod" }}
      - environments/prod/my-app-values.yaml
      {{- end }}
{{- end }}
```

### Step 3: Create Values File

Create `values/my-app-values.yaml`:

```yaml
# Base configuration for my-app
replicaCount: 2

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

### Step 4: Enable the Application

Edit `config/enabled.yaml`:

```yaml
enabled:
  prometheus: true
  haproxyIngress: true
  cloudflared: false
  myApp: true  # Enable your new app
```

### Step 5: Deploy

```bash
# Preview
helmfile -l name=my-app diff

# Deploy
helmfile -l name=my-app apply
```

## Validation and Testing

### Linting Helmfile Configuration

```bash
# Validate Helmfile syntax
helmfile lint

# Template and validate without applying
helmfile template
```

### Testing in Staging

Always test changes in staging before production:

```bash
# 1. Deploy to staging
helmfile -e staging apply

# 2. Verify deployment
kubectl get pods -A

# 3. Test functionality
# ... run tests ...

# 4. If successful, deploy to production
helmfile -e prod apply
```

### Validation Checklist

Before deploying to production:

- [ ] Changes tested in dev environment
- [ ] Changes tested in staging environment
- [ ] `helmfile diff` reviewed for unexpected changes
- [ ] Resource limits appropriate for environment
- [ ] Security configurations verified
- [ ] Monitoring and alerts configured
- [ ] Backup and rollback plan documented
- [ ] Team notified of deployment

### CI/CD Integration

This repository includes GitHub Actions workflows:

**Helmfile Diff** (automatic on PRs):
- Runs `helmfile diff` on pull requests
- Posts diff output as PR comment
- Helps review changes before merge

**Helmfile Apply** (manual deployment):
- Manually triggered from GitHub Actions
- Deploys to selected environment
- Requires proper Kubernetes credentials

See [../.github/workflows/](../.github/workflows/) for workflow definitions.

## Troubleshooting

### Common Issues

#### Release Not Found

```bash
# Check if release exists
helm list -A

# Check Helmfile configuration
helmfile list
```

#### Values Not Applied

```bash
# Debug values being passed to chart
helmfile -l name=my-app template > /tmp/debug.yaml
cat /tmp/debug.yaml
```

#### Chart Version Conflicts

```bash
# Update repository cache
helm repo update

# List available versions
helm search repo my-repo/my-chart --versions
```

#### Diff Shows Unexpected Changes

```bash
# Show detailed diff
helmfile -l name=my-app diff --detailed-exitcode

# Check current deployed values
helm get values my-app -n my-namespace
```

### Debugging Commands

```bash
# Show Helmfile state
helmfile status

# Validate Helmfile syntax
helmfile lint

# Show expanded templates
helmfile template

# Show diff with context
helmfile diff --context 10

# Force sync (dangerous!)
helmfile sync --force
```

### Getting Help

```bash
# Helmfile help
helmfile --help

# Helm help
helm --help

# Check versions
helmfile version
helm version
kubectl version
```

## Best Practices

### Version Control

- Always commit changes to values files
- Create pull requests for review
- Use meaningful commit messages
- Tag releases for production deployments

### Security

- Never commit secrets to git
- Use Kubernetes secrets or external secret management
- Enable RBAC for namespace access
- Use `--suppress-secrets` flag in CI/CD

### Monitoring

- Enable metrics for all applications
- Configure Prometheus ServiceMonitors
- Set up alerts for critical services
- Monitor resource usage and adjust limits

### Documentation

- Document custom values in comments
- Keep README files up to date
- Document environment-specific requirements
- Maintain changelog for major changes

## Advanced Usage

### Multi-Cluster Deployments

```bash
# Deploy to specific cluster
export KUBECONFIG=/path/to/cluster1-config.yaml
helmfile -e prod apply

export KUBECONFIG=/path/to/cluster2-config.yaml
helmfile -e prod apply
```

### Selective Deployment

```bash
# Deploy only ingress-related releases
helmfile -l category=ingress apply

# Deploy everything except monitoring
helmfile -l category!=monitoring apply
```

### Custom Environments

Create custom environment configuration:

```bash
# Create custom environment
mkdir environments/custom

# Use custom environment
helmfile -e custom apply
```

## References

- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GitOps Best Practices](https://www.weave.works/technologies/gitops/)

## Support

For issues or questions:
1. Check this documentation
2. Review [CLOUDFLARED_SETUP.md](CLOUDFLARED_SETUP.md) for Cloudflared-specific help
3. Check GitHub Issues
4. Contact the infrastructure team
