# Infrastructure Validation and Utility Scripts

This directory contains scripts for validating, testing, and maintaining the hybrid Kubernetes infrastructure.

## Overview

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `validate-prereqs.sh` | Validates all prerequisites are installed and configured | Before initial setup |
| `validate-secret-management.sh` | Validates SOPS and Ansible Vault configuration | After configuring secrets |
| `validate.sh` | Comprehensive validation of deployed infrastructure | After deployment |
| `health-check.sh` | Checks cluster health and service status | Regular monitoring |
| `verify-github-security.sh` | Verifies GitHub security features are enabled | Monthly security audit |
| `check-links.sh` | Validates documentation links | Documentation updates |
| `test-validation-functions.sh` | Tests validation script functions | Development/debugging |

## Usage

### Initial Setup Validation

Before deploying infrastructure, validate prerequisites:

```bash
# Run prerequisite validation
./scripts/validate-prereqs.sh
```

**What it checks:**
- ✅ Required tools installed (ansible, kubectl, helm, helmfile, sops, age, cloudflared)
- ✅ Credentials configured (Ansible vault, SOPS age keys, Cloudflare tokens, Tailscale)
- ✅ Connectivity (Kubernetes cluster, Tailscale network, container registries)

### Secret Management Validation

After setting up SOPS and Ansible Vault:

```bash
# Validate secret management configuration
./scripts/validate-secret-management.sh
```

**What it checks:**
- ✅ SOPS age keys exist and are configured
- ✅ .sops.yaml configuration is valid
- ✅ Ansible vault password file exists
- ✅ Encrypted files can be decrypted
- ✅ GitHub secrets are configured
- ✅ .gitignore blocks sensitive files

### Post-Deployment Validation

After deploying the infrastructure:

```bash
# Run comprehensive validation
./scripts/validate.sh
```

**What it checks:**
- ✅ Kubernetes cluster is healthy
- ✅ All nodes are ready
- ✅ Required namespaces exist
- ✅ Critical services are running
- ✅ Secrets are deployed
- ✅ Network policies are active
- ✅ Ingress is functional

### Health Monitoring

Regular health checks (run daily or on-demand):

```bash
# Check cluster health
./scripts/health-check.sh
```

**What it checks:**
- ✅ Node status
- ✅ Failed pods
- ✅ PersistentVolume status
- ✅ Certificate status
- ✅ Backup status
- ✅ Critical secrets exist
- ✅ Security scan for exposed secrets

### GitHub Security Verification

Monthly security audits:

```bash
# Verify GitHub security features
./scripts/verify-github-security.sh
```

**Requirements:**
- GitHub CLI (`gh`) installed and authenticated

**What it checks:**
- ✅ Secret scanning enabled
- ✅ Push protection enabled
- ✅ Dependabot alerts enabled
- ✅ Code scanning status
- ✅ Open security alerts count

### Documentation Link Validation

When updating documentation:

```bash
# Check for broken links
./scripts/check-links.sh
```

**What it checks:**
- ✅ Internal documentation links
- ✅ Cross-references between files
- ✅ Markdown formatting

## Script Details

### validate-prereqs.sh

**Purpose:** Validates all prerequisites are installed before infrastructure deployment.

**Exit codes:**
- `0` - All prerequisites met
- `1` - Missing required tools or configuration

**Example output:**
```
=== Infrastructure Prerequisites Validation ===

1. Required Tools:
✅ ansible (2.10.0)
✅ kubectl (1.28.0)
✅ helm (3.12.0)
✅ helmfile (0.156.0)
✅ sops (3.8.1)
✅ age (1.1.1)
✅ cloudflared (2023.8.2)

2. Credentials:
✅ Ansible vault password file exists
✅ SOPS age key configured
⚠️  Cloudflare API token not configured (optional)

3. Connectivity:
✅ Kubernetes cluster accessible
✅ Tailscale network accessible
✅ Container registries accessible

=== Validation Complete ===
Status: PASS (2 warnings)
```

### validate-secret-management.sh

**Purpose:** Validates secret management configuration (SOPS, Ansible Vault).

**Checks:**
- SOPS age keys exist
- .sops.yaml is valid
- Ansible vault is configured
- Test encryption/decryption works
- .gitignore blocks sensitive files

**Example output:**
```
=== Secret Management Validation ===

SOPS Configuration:
✅ Age key exists: ~/.config/sops/age/keys.txt
✅ .sops.yaml configuration valid
✅ Test encryption successful
✅ Test decryption successful

Ansible Vault:
✅ Vault password file exists
✅ Vault file is encrypted
✅ Vault can be decrypted

.gitignore:
✅ Blocks .vault_pass
✅ Blocks age/keys.txt
✅ Blocks plaintext secrets
✅ Allows encrypted secrets (.enc.yaml)

=== Validation Complete ===
```

### validate.sh

**Purpose:** Comprehensive post-deployment validation.

**Validates:**
- Cluster connectivity
- Node readiness
- Required namespaces
- Service deployments
- Secrets deployment
- Network policies
- Ingress functionality

### health-check.sh

**Purpose:** Ongoing cluster health monitoring.

**Monitors:**
- Node status
- Pod health
- Resource usage
- Certificate expiration
- Backup status
- Security posture

**Can be run as cron job:**
```bash
# Add to crontab for daily checks
0 9 * * * /path/to/scripts/health-check.sh >> /var/log/cluster-health.log 2>&1
```

### verify-github-security.sh

**Purpose:** Verify GitHub repository security features are enabled.

**Prerequisites:**
```bash
# Install GitHub CLI
brew install gh  # macOS
# or: https://github.com/cli/cli#installation

# Authenticate
gh auth login
```

**Checks:**
- Secret scanning status
- Push protection status
- Dependabot alerts status
- Open security alerts
- Code scanning status

**Output format:**
```
=== GitHub Security Features Verification ===

✅ GitHub CLI authenticated

✅ Secret Scanning: ENABLED
✅ Push Protection: ENABLED
✅ Dependabot Security Updates: ENABLED

=== Security Alerts Summary ===

✅ No open secret scanning alerts
✅ No open Dependabot alerts
⚠️  Code Scanning: Not configured (recommended)

=== Verification Complete ===
```

### check-links.sh

**Purpose:** Validate documentation links and cross-references.

**Checks:**
- Internal file references
- Section anchors
- Relative paths
- Markdown formatting

### test-validation-functions.sh

**Purpose:** Unit tests for validation script functions.

**Usage:**
```bash
# Run tests
./scripts/test-validation-functions.sh

# Run specific test
./scripts/test-validation-functions.sh test_function_name
```

## Integration with CI/CD

These scripts can be integrated into GitHub Actions workflows:

```yaml
name: Validation

on: [push, pull_request]

jobs:
  validate-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check documentation links
        run: ./scripts/check-links.sh
  
  validate-secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate secret management
        run: ./scripts/validate-secret-management.sh
  
  verify-security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify GitHub security
        env:
          GH_TOKEN: ${{ github.token }}
        run: ./scripts/verify-github-security.sh
```

## Troubleshooting

### Permission Denied

If you get permission denied errors:

```bash
# Make scripts executable
chmod +x scripts/*.sh
```

### Missing Dependencies

If validation scripts fail due to missing tools:

```bash
# Install prerequisites (macOS)
brew install ansible kubectl helm helmfile sops age cloudflared

# Install prerequisites (Linux)
# See docs/setup.md for detailed installation instructions
```

### GitHub CLI Authentication

For `verify-github-security.sh`:

```bash
# Login to GitHub
gh auth login

# Verify authentication
gh auth status

# If issues persist, use token authentication
export GH_TOKEN=your_personal_access_token
```

## Cloudflare Tunnel Management Scripts

### import-cloudflared-credentials.sh

**Purpose:** Import existing Cloudflare Tunnel credentials into Kubernetes.

**Usage:**
```bash
./scripts/import-cloudflared-credentials.sh \
  -t <TUNNEL-ID> \
  -n <TUNNEL-NAME> \
  -e <ENVIRONMENT>
```

**Options:**
- `-t, --tunnel-id` - Tunnel ID (required)
- `-n, --tunnel-name` - Tunnel name (optional)
- `-c, --creds-file` - Path to credentials file (default: `~/.cloudflared/<TUNNEL-ID>.json`)
- `-e, --environment` - Target environment: dev/staging/prod (default: production)
- `-s, --skip-validation` - Skip tunnel validation
- `-h, --help` - Show help message

**What it does:**
1. Validates tunnel ID and credentials file
2. Creates Kubernetes secret YAML manifest
3. Encrypts credentials with SOPS
4. Saves encrypted secret to repository
5. Securely deletes plaintext files
6. Provides next steps for deployment

**Example:**
```bash
# Import production tunnel credentials
./scripts/import-cloudflared-credentials.sh \
  -t 12345678-1234-1234-1234-123456789abc \
  -n infrastructure-prod-tunnel \
  -e prod
```

### configure-tunnel-dns.sh

**Purpose:** Configure DNS routes for Cloudflare Tunnel.

**Usage:**
```bash
./scripts/configure-tunnel-dns.sh \
  -t <TUNNEL-NAME> \
  -d <DOMAINS>
```

**Options:**
- `-t, --tunnel-name` - Tunnel name (required)
- `-d, --domains` - Comma-separated domains (required)
- `-r, --remove` - Remove DNS routes instead of adding
- `-l, --list` - List existing DNS routes
- `-v, --verify` - Verify DNS propagation
- `-h, --help` - Show help message

**Example:**
```bash
# Add DNS routes for multiple domains
./scripts/configure-tunnel-dns.sh \
  -t infrastructure-prod-tunnel \
  -d "app.example.com,api.example.com,grafana.example.com"

# List existing routes
./scripts/configure-tunnel-dns.sh -t infrastructure-prod-tunnel -l
```

### validate-tunnel-setup.sh

**Purpose:** Validate Cloudflare Tunnel setup in Kubernetes.

**Usage:**
```bash
./scripts/validate-tunnel-setup.sh [OPTIONS]
```

**Options:**
- `-n, --namespace` - Kubernetes namespace (default: cloudflare)
- `-t, --tunnel-name` - Expected tunnel name
- `-d, --domains` - Domains to test
- `-s, --skip-dns` - Skip DNS verification
- `-h, --help` - Show help message

**What it validates:**
1. Kubernetes cluster connectivity
2. Namespace existence
3. Secret existence and validity
4. Deployment and pod status
5. Pod logs for errors
6. Tunnel connectivity
7. DNS configuration (optional)
8. HTTP accessibility (optional)

**Example:**
```bash
# Basic validation
./scripts/validate-tunnel-setup.sh

# Validate with specific tunnel and test domains
./scripts/validate-tunnel-setup.sh \
  -t infrastructure-prod-tunnel \
  -d "app.example.com,api.example.com"
```

## Complete Workflow Example

### Reusing Existing Cloudflare Tunnel

```bash
# 1. Import existing tunnel credentials
./scripts/import-cloudflared-credentials.sh \
  -t 12345678-1234-1234-1234-123456789abc \
  -n infrastructure-prod-tunnel \
  -e prod

# 2. Configure DNS routes
./scripts/configure-tunnel-dns.sh \
  -t infrastructure-prod-tunnel \
  -d "app.example.com,api.example.com,grafana.example.com" \
  -v

# 3. Update Helmfile configuration
vim helmfile/values/cloudflared-values.yaml
# Set tunnel ID, name, and ingress rules

# 4. Deploy to Kubernetes
cd helmfile
helmfile diff
helmfile apply

# 5. Validate deployment
cd ..
./scripts/validate-tunnel-setup.sh \
  -t infrastructure-prod-tunnel \
  -d "app.example.com,api.example.com,grafana.example.com"
```

## Related Documentation

- [Setup Guide](../docs/setup.md) - Complete infrastructure setup
- [Cloudflare Tunnel Setup](../helmfile/CLOUDFLARED_SETUP.md) - Comprehensive Cloudflare Tunnel guide
- [Secret Management](../SECRETS.md) - Secret management best practices
- [Security Policy](../SECURITY.md) - Security measures and verification
- [Operations Guide](../docs/operate.md) - Day-to-day operations

---

**Questions or Issues?**
- Open an issue: [GitHub Issues](https://github.com/wcatz/infrastructure/issues)
- See troubleshooting: [docs/operate.md#troubleshooting](../docs/operate.md#troubleshooting)
