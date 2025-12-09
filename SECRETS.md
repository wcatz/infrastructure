# Secret Management Guide

This document provides comprehensive guidance and Standard Operating Procedures (SOP) for managing secrets in the hybrid Kubernetes infrastructure.

## Table of Contents

- [Overview](#overview)
- [Secret Management Responsibilities](#secret-management-responsibilities)
- [Secret Management Strategy](#secret-management-strategy)
- [SOPS with age](#sops-with-age)
- [Ansible Vault](#ansible-vault)
- [Cloudflared Secrets](#cloudflared-secrets)
- [Kubernetes Secrets](#kubernetes-secrets)
- [GitHub Actions Secrets](#github-actions-secrets)
- [CI/CD Integration](#cicd-integration)
- [Secret Rotation](#secret-rotation)
- [Security Best Practices](#security-best-practices)
- [Periodic Audits and Maintenance](#periodic-audits-and-maintenance)
- [Troubleshooting](#troubleshooting)

## Overview

This infrastructure uses a **defense-in-depth** approach to secret management with multiple layers of protection:

1. **SOPS with age**: Encrypt secrets at rest in Git
2. **Kubernetes Secrets**: Store encrypted secrets in the cluster
3. **External Secrets Operator**: Sync secrets from external sources (optional)
4. **Ansible Vault**: Encrypt infrastructure secrets for Ansible playbooks
5. **GitHub Secrets**: Store CI/CD credentials securely
6. **GitHub Secret Scanning**: Automated detection of accidentally committed secrets
7. **Push Protection**: Prevents pushing commits containing secrets

**Key Principles:**
- **Never commit plaintext secrets** - All secrets must be encrypted before commit
- **Encrypt at rest, encrypt in transit** - Multiple encryption layers
- **Least privilege access** - Limit who can access which secrets
- **Regular rotation** - All secrets have defined rotation schedules
- **Audit everything** - Track all secret access and modifications

## Secret Management Responsibilities

Understanding who is responsible for managing different types of secrets is critical for security:

### SOPS Age Keys

**Owner:** Infrastructure Team / Platform Administrators

**Location:** 
- Private key: `~/.config/sops/age/keys.txt` (local machine, never committed)
- Public key: `.sops.yaml` (committed to repository)

**Responsibilities:**
- Generate and securely backup age private keys
- Add public keys to `.sops.yaml` configuration
- Rotate keys annually or when compromised
- Share encrypted secrets via Git repository
- Never share private keys via email/Slack/unencrypted channels

**Backup Strategy:**
- Store private key in password manager (e.g., 1Password, Bitwarden)
- Keep encrypted backup on secure USB drive
- Document key ownership and recovery procedures

### Kubernetes Secrets

**Owner:** Application Developers / DevOps Team

**Location:**
- Encrypted in Git: `helmfile/secrets/*.enc.yaml`
- Deployed in cluster: Kubernetes etcd (encrypted at rest)

**Responsibilities:**
- Encrypt secrets with SOPS before committing
- Use appropriate secret types (Opaque, TLS, etc.)
- Follow naming conventions for secret resources
- Ensure secrets are namespace-scoped appropriately
- Document which applications use which secrets

**Access Control:**
- Kubernetes RBAC controls who can read/write secrets
- Network policies limit pod-to-pod secret exposure
- Audit logs track all secret access

### GitHub Actions Secrets

**Owner:** CI/CD Team / Repository Administrators

**Location:** GitHub repository settings → Secrets and variables → Actions

**Responsibilities:**
- Add required secrets for CI/CD workflows (SOPS_AGE_KEY, KUBECONFIG, etc.)
- Use environment-specific secrets (production vs. staging)
- Regularly rotate tokens and keys
- Review and remove unused secrets
- Limit secret access to specific workflows/environments

**Required Secrets:**
- `SOPS_AGE_KEY`: Private age key for decrypting SOPS-encrypted files
- `KUBECONFIG_PRODUCTION`: Base64-encoded kubeconfig for production deployments
- `KUBECONFIG_STAGING`: Base64-encoded kubeconfig for staging deployments
- `ANSIBLE_VAULT_PASSWORD`: Password for Ansible vault decryption

### Ansible Vault

**Owner:** Infrastructure Team

**Location:**
- Vault password: `ansible/.vault_pass` (local, gitignored)
- Encrypted data: `ansible/group_vars/all/vault.yml` (committed, encrypted)

**Responsibilities:**
- Generate strong vault passwords
- Encrypt sensitive Ansible variables (K3s token, Tailscale keys, etc.)
- Never commit `.vault_pass` to Git
- Share vault password securely with team members
- Rotate vault password annually

**Usage:**
- Infrastructure secrets: K3s cluster token, Tailscale auth keys
- API credentials: Cloudflare API tokens, OAuth secrets
- Initial deployment credentials

### SSH Keys

**Owner:** System Administrators

**Location:** 
- Private key: `~/.ssh/id_rsa` or `~/.ssh/id_ed25519` (local, never committed)
- Public key: Deployed to servers in `~/.ssh/authorized_keys`

**Responsibilities:**
- Use strong key types (Ed25519 or RSA 4096-bit)
- Protect private keys with passphrase
- Rotate annually or when employees leave
- Use separate keys for different environments
- Remove old keys from servers after rotation

### TLS Certificates

**Owner:** Automated (cert-manager) / Platform Team

**Location:**
- Managed by cert-manager in Kubernetes
- Automatically renewed before expiration

**Responsibilities:**
- Monitor certificate expiration alerts
- Ensure cert-manager is functioning correctly
- Maintain backup ACME credentials
- Handle manual certificate renewals if automation fails

### Cloudflared Tunnel Credentials

**Owner:** Network/Platform Team

**Location:**
- Original: `~/.cloudflared/<TUNNEL-ID>.json` (should be deleted after encryption)
- Encrypted: `helmfile/secrets/cloudflared-credentials.enc.yaml`
- Deployed: Kubernetes secret in `cloudflare` namespace

**Responsibilities:**
- Create and configure Cloudflare tunnels
- Encrypt credentials immediately after creation
- Securely delete plaintext credentials file
- Rotate tunnel credentials every 90 days
- Update DNS records when rotating tunnels

### Secret Types

| Secret Type | Tool | Location | Rotation Period |
|-------------|------|----------|-----------------|
| Cloudflared credentials | SOPS + Kubernetes | `helmfile/secrets/` | 90 days |
| TLS certificates | cert-manager | Automated | 90 days (auto) |
| Database passwords | SOPS + Kubernetes | Environment-specific | 180 days |
| API tokens | SOPS + Kubernetes | Environment-specific | 90 days |
| SSH keys | Manual | Server `~/.ssh/` | 365 days |
| age encryption keys | Manual | `~/.config/sops/age/` | 365 days |
| Ansible vault password | Manual | `ansible/.vault_pass` | 365 days |

## Secret Management Strategy

### Principles

1. **Never commit plaintext secrets to Git**
2. **Encrypt secrets before storing**
3. **Use different secrets per environment**
4. **Rotate secrets regularly**
5. **Minimize secret exposure**
6. **Audit secret access**

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Developer                               │
│  1. Creates secret (plaintext)                               │
│  2. Encrypts with SOPS (age key)                            │
│  3. Commits encrypted .enc.yaml to Git                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Repository                         │
│  - .sops.yaml (encryption config)                           │
│  - helmfile/secrets/*.enc.yaml (encrypted)                  │
│  - .gitignore (excludes *.yaml without .enc)                │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                   GitHub Actions CI/CD                       │
│  1. Reads SOPS_AGE_KEY from GitHub Secrets                  │
│  2. Decrypts .enc.yaml files                                │
│  3. Deploys to Kubernetes                                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                          │
│  - Secrets stored in etcd (encrypted at rest)               │
│  - Mounted to pods as volumes or env vars                   │
│  - External Secrets Operator syncs from vault (optional)    │
└─────────────────────────────────────────────────────────────┘
```

## SOPS with age

SOPS (Secrets OPerationS) with age encryption provides a secure way to store secrets in Git repositories while maintaining encryption at rest.

### Quick Start

For a rapid setup, follow these steps:

#### 1. Install age and SOPS

```bash
# macOS
brew install age sops

# Linux
# Detect architecture
ARCH=$(uname -m)
case $ARCH in
  x86_64) AGE_ARCH="amd64" ;;
  aarch64|arm64) AGE_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Install age
wget https://github.com/FiloSottile/age/releases/latest/download/age-latest-linux-${AGE_ARCH}.tar.gz
tar xzf age-latest-linux-${AGE_ARCH}.tar.gz
sudo mv age/age* /usr/local/bin/
rm -rf age age-latest-linux-${AGE_ARCH}.tar.gz

# Install SOPS
wget https://github.com/mozilla/sops/releases/latest/download/sops-latest.linux
chmod +x sops-latest.linux
sudo mv sops-latest.linux /usr/local/bin/sops
```

#### 2. Generate age Key

```bash
# Create directory
mkdir -p ~/.config/sops/age

# Generate key
age-keygen -o ~/.config/sops/age/keys.txt

# View public key
cat ~/.config/sops/age/keys.txt | grep "public key:"
```

**Example output:**
```
# created: 2024-01-15T10:30:00Z
# public key: age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567
AGE-SECRET-KEY-1ABC...XYZ
```

#### 3. Update .sops.yaml

Replace the placeholder in `.sops.yaml` with your actual public key:

```bash
# Get your public key
PUBLIC_KEY=$(cat ~/.config/sops/age/keys.txt | grep "public key:" | cut -d: -f2 | tr -d ' ')

# Update .sops.yaml (macOS)
sed -i '' "s/age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/$PUBLIC_KEY/g" .sops.yaml

# Update .sops.yaml (Linux)
sed -i "s/age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/$PUBLIC_KEY/g" .sops.yaml
```

Alternatively, manually edit `.sops.yaml`:

```yaml
creation_rules:
  - path_regex: \.enc\.yaml$
    age: >-
      age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567
```

#### 4. Backup Private Key

**⚠️ CRITICAL: Backup your age private key securely!**

If you lose this key, you **cannot decrypt your secrets**!

```bash
# Method 1: Copy to encrypted USB or secure location
cp ~/.config/sops/age/keys.txt /path/to/secure/backup/

# Method 2: Encrypt with GPG
gpg -c ~/.config/sops/age/keys.txt
# Save the .gpg file to backup location

# Method 3: Store in password manager
cat ~/.config/sops/age/keys.txt
# Copy the content and save in password manager (1Password, Bitwarden, etc.)
```

#### 5. Add to GitHub Secrets

For CI/CD to decrypt secrets:

```bash
# Using GitHub CLI
gh secret set SOPS_AGE_KEY < ~/.config/sops/age/keys.txt

# Or manually via web UI:
# 1. Go to repository Settings → Secrets and variables → Actions
# 2. Click "New repository secret"
# 3. Name: SOPS_AGE_KEY
# 4. Value: Paste content of ~/.config/sops/age/keys.txt
# 5. Click "Add secret"
```

### Detailed Setup

The detailed setup section provides additional context for the quick start steps above.

#### Install SOPS

SOPS should be installed as part of prerequisites (see docs/setup.md). Verify installation:

```bash
sops --version
age --version
```

### Usage

#### Encrypt a Secret

```bash
# Create plaintext secret
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: database
  namespace: default
type: Opaque
stringData:
  username: admin
  password: supersecret123
EOF

# Encrypt with SOPS
sops -e secret.yaml > secret.enc.yaml

# Delete plaintext
rm secret.yaml

# Commit encrypted file
git add secret.enc.yaml
git commit -m "Add database secret"
```

#### Decrypt a Secret

```bash
# View decrypted content
sops -d secret.enc.yaml

# Deploy to Kubernetes
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d secret.enc.yaml | kubectl apply -f -
```

#### Edit Encrypted Secret

```bash
# Opens decrypted content in $EDITOR
# Automatically re-encrypts on save
sops secret.enc.yaml
```

#### Rotate Encryption Keys

```bash
# Generate new age key
age-keygen -o ~/.config/sops/age/keys-new.txt

# Get new public key
NEW_PUBLIC_KEY=$(cat ~/.config/sops/age/keys-new.txt | grep "public key:" | cut -d: -f2 | tr -d ' ')

# Re-encrypt all secrets with new key
find . -name "*.enc.yaml" -type f -exec sops updatekeys --yes -i {} \;

# Update .sops.yaml with new public key
# Then backup old key and replace with new one
```

### Troubleshooting SOPS

#### Error: "no age identities found"

**Solution:**
```bash
# Verify age key exists
ls -la ~/.config/sops/age/keys.txt

# Set environment variable
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Or use inline:
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d secret.enc.yaml
```

#### Error: "Failed to get the data key"

**Solution:**
- Verify the public key in `.sops.yaml` matches your age key
- Ensure you're using the correct age private key
- Check file was encrypted with your public key

#### Public Key Mismatch

```bash
# Get your current public key
cat ~/.config/sops/age/keys.txt | grep "public key:"

# Check .sops.yaml
grep "age:" .sops.yaml

# If they don't match, update .sops.yaml with correct key
```

## Ansible Vault

Ansible Vault encrypts sensitive variables used in Ansible playbooks for infrastructure provisioning.

### Setup

#### 1. Create Vault Password File

```bash
cd ansible

# Create from example
cp .vault_pass.example .vault_pass

# Add a strong password
echo "your-secure-vault-password-here" > .vault_pass

# Secure the file
chmod 600 .vault_pass
```

**Important:** The `.vault_pass` file is gitignored and should never be committed to the repository.

#### 2. Create and Encrypt Vault Variables

```bash
# Create vault variables from example
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit with your secrets
vim group_vars/all/vault.yml
```

Example `vault.yml` content:

```yaml
---
# K3s cluster token (generate with: openssl rand -hex 32)
vault_k3s_token: "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6"

# Tailscale auth key from Tailscale admin console
vault_tailscale_key: "tskey-auth-kABCDEF1234567890-1234567890ABCDEFGHIJ"

# Tailscale OAuth credentials (for Kubernetes operator)
vault_tailscale_oauth_client_id: "kABCDEF1234567890"
vault_tailscale_oauth_client_secret: "tskey-client-kABCDEF1234567890-1234567890ABCDEFGHIJ"

# Cloudflare tunnel token (optional, if managing via Ansible)
vault_cloudflare_tunnel_token: "eyJhIjoiYWJjZGVmMTIzNDU2Nzg5MCIsInQiOiJhYmNkZWYxMjM0NTY3ODkwIn0="
```

#### 3. Encrypt the Vault File

```bash
# Encrypt the vault file
ansible-vault encrypt group_vars/all/vault.yml

# Verify encryption worked
cat group_vars/all/vault.yml
# Should show encrypted content starting with $ANSIBLE_VAULT
```

### Usage

#### Common Vault Commands

```bash
# Edit encrypted vault (decrypts, opens in $EDITOR, re-encrypts on save)
ansible-vault edit group_vars/all/vault.yml

# View encrypted vault content
ansible-vault view group_vars/all/vault.yml

# Decrypt a file (for manual inspection)
ansible-vault decrypt group_vars/all/vault.yml
# WARNING: File is now in plaintext!

# Re-encrypt after decrypting
ansible-vault encrypt group_vars/all/vault.yml

# Change vault password
ansible-vault rekey group_vars/all/vault.yml

# Verify vault can be decrypted
ansible-vault view group_vars/all/vault.yml --vault-password-file=.vault_pass
```

#### Using Vault Variables in Playbooks

Ansible automatically decrypts vault variables when playbooks run. Variables are referenced in roles:

```yaml
# In roles/k3s/defaults/main.yml
k3s_token: "{{ vault_k3s_token }}"

# In roles/tailscale/defaults/main.yml  
tailscale_auth_key: "{{ vault_tailscale_key }}"
```

#### Running Playbooks with Vault

```bash
# Ansible automatically uses .vault_pass if configured in ansible.cfg
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Or explicitly specify vault password file
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml \
  --vault-password-file=.vault_pass

# Or provide password via environment variable
export ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml
```

### Best Practices

1. **Never commit `.vault_pass`** - It's gitignored for a reason
2. **Use strong passwords** - Generate with: `openssl rand -base64 32`
3. **Share vault password securely** - Use password managers, not email/Slack
4. **Keep vault.yml encrypted** - Only decrypt temporarily when needed
5. **Rotate vault password annually** - Use `ansible-vault rekey`
6. **Backup vault password** - Store in secure location (password manager)
7. **Use separate vaults per environment** - Don't reuse production secrets

### Rotating Vault Password

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)
echo "$NEW_PASSWORD" > .vault_pass.new

# 2. Rekey all vaults
ansible-vault rekey group_vars/all/vault.yml \
  --vault-password-file=.vault_pass \
  --new-vault-password-file=.vault_pass.new

# 3. Replace old password file
mv .vault_pass .vault_pass.old
mv .vault_pass.new .vault_pass

# 4. Test decryption works
ansible-vault view group_vars/all/vault.yml

# 5. Securely delete old password
shred -u .vault_pass.old
```

## Cloudflared Secrets

Cloudflared requires tunnel credentials to establish secure tunnels to Cloudflare's edge network.

### Create Cloudflared Tunnel

```bash
# Authenticate with Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create infrastructure-tunnel

# Save tunnel ID and credentials
# Credentials saved to: ~/.cloudflared/<TUNNEL-ID>.json
```

### Encrypt Credentials with SOPS

```bash
# Create Kubernetes secret YAML
cat > helmfile/secrets/cloudflared-credentials.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-credentials
  namespace: cloudflare
type: Opaque
stringData:
  credentials.json: |
$(cat ~/.cloudflared/<TUNNEL-ID>.json | sed 's/^/    /')
EOF

# Encrypt with SOPS
sops -e helmfile/secrets/cloudflared-credentials.yaml > \
  helmfile/secrets/cloudflared-credentials.enc.yaml

# Delete plaintext
rm helmfile/secrets/cloudflared-credentials.yaml
shred -u ~/.cloudflared/<TUNNEL-ID>.json  # Securely delete original
```

### Deploy Cloudflared Secret

```bash
# Decrypt and apply
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -

# Verify
kubectl get secret cloudflared-credentials -n cloudflare
```

### Environment-Specific Cloudflared Secrets

**Production:**
```bash
# Create prod-specific credentials
cat > helmfile/environments/prod/cloudflared-credentials.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-credentials
  namespace: cloudflare
type: Opaque
stringData:
  credentials.json: |
$(cat ~/.cloudflared/prod-<TUNNEL-ID>.json | sed 's/^/    /')
EOF

# Encrypt
sops -e helmfile/environments/prod/cloudflared-credentials.yaml > \
  helmfile/environments/prod/cloudflared-credentials.enc.yaml

# Clean up
rm helmfile/environments/prod/cloudflared-credentials.yaml
```

**Staging:**
```bash
# Similar process for staging
sops -e helmfile/environments/staging/cloudflared-credentials.yaml > \
  helmfile/environments/staging/cloudflared-credentials.enc.yaml
```

## Kubernetes Secrets

### Best Practices

1. **Use `stringData` for readability**
   ```yaml
   stringData:
     password: "my-password"
   ```
   vs. base64-encoded `data`:
   ```yaml
   data:
     password: bXktcGFzc3dvcmQ=
   ```

2. **Always encrypt with SOPS before committing**

3. **Use appropriate secret types**
   - `Opaque`: Generic secrets
   - `kubernetes.io/tls`: TLS certificates
   - `kubernetes.io/dockerconfigjson`: Docker registry credentials
   - `kubernetes.io/basic-auth`: Basic authentication
   - `kubernetes.io/ssh-auth`: SSH keys

4. **Namespace secrets appropriately**

### Example: Database Credentials

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: production
type: Opaque
stringData:
  postgres-user: "admin"
  postgres-password: "change-me-in-production"
  postgres-database: "myapp"
  connection-string: "postgresql://admin:change-me-in-production@postgres:5432/myapp"
```

Encrypt and deploy:
```bash
sops -e postgres-credentials.yaml > postgres-credentials.enc.yaml
sops -d postgres-credentials.enc.yaml | kubectl apply -f -
```

### Example: TLS Certificate

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tls-certificate
  namespace: production
type: kubernetes.io/tls
stringData:
  tls.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDXTCCAkWgAwIBAgIJAKZ...
    -----END CERTIFICATE-----
  tls.key: |
    -----BEGIN PRIVATE KEY-----
    MIIEvQIBADANBgkqhkiG9w0B...
    -----END PRIVATE KEY-----
```

## GitHub Actions Secrets

### Required Secrets

Configure these in your GitHub repository settings:

1. **SOPS_AGE_KEY**
   - Description: Private age key for decrypting SOPS secrets
   - Value: Content of `~/.config/sops/age/keys.txt`
   - Usage: CI/CD decryption

2. **KUBECONFIG_PRODUCTION**
   - Description: Base64-encoded kubeconfig for production
   - Value: `base64 -w 0 ~/.kube/config-prod`
   - Usage: Production deployments

3. **KUBECONFIG_STAGING**
   - Description: Base64-encoded kubeconfig for staging
   - Value: `base64 -w 0 ~/.kube/config-staging`
   - Usage: Staging deployments

### Adding Secrets to GitHub

```bash
# Using GitHub CLI
gh secret set SOPS_AGE_KEY < ~/.config/sops/age/keys.txt

# Base64 encode kubeconfig
base64 -w 0 ~/.kube/config-prod | gh secret set KUBECONFIG_PRODUCTION --body-file=-
```

Or via web UI:
1. Go to repository **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add name and value
4. Click **Add secret**

## CI/CD Integration

Integrating secret management into CI/CD pipelines ensures secure automated deployments.

### GitHub Actions Integration

#### Setup Repository Secrets

Required secrets for CI/CD (see [GitHub Actions Secrets](#github-actions-secrets) section above):
- `SOPS_AGE_KEY` - For decrypting SOPS-encrypted files
- `ANSIBLE_VAULT_PASSWORD` - For Ansible playbook execution
- `KUBECONFIG_PRODUCTION` - For production Kubernetes deployments
- `KUBECONFIG_STAGING` - For staging deployments

#### Workflow Example with SOPS

```yaml
name: Deploy Application

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Install SOPS
        run: |
          wget https://github.com/mozilla/sops/releases/latest/download/sops-latest.linux
          chmod +x sops-latest.linux
          sudo mv sops-latest.linux /usr/local/bin/sops
      
      - name: Setup SOPS age key
        run: |
          mkdir -p ~/.config/sops/age
          echo "${{ secrets.SOPS_AGE_KEY }}" > ~/.config/sops/age/keys.txt
          chmod 600 ~/.config/sops/age/keys.txt
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
      
      - name: Decrypt and deploy secrets
        run: |
          export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
          sops -d helmfile/secrets/app-secrets.enc.yaml | kubectl apply -f -
        env:
          KUBECONFIG: ${{ secrets.KUBECONFIG_PRODUCTION }}
      
      - name: Cleanup sensitive files
        if: always()
        run: |
          rm -f ~/.config/sops/age/keys.txt
```

#### Workflow Example with Ansible Vault

```yaml
name: Deploy Infrastructure

on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install Ansible
        run: |
          pip install ansible
      
      - name: Setup Ansible Vault password
        run: |
          echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > ansible/.vault_pass
          chmod 600 ansible/.vault_pass
      
      - name: Deploy with Ansible
        run: |
          cd ansible
          ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml \
            --vault-password-file=.vault_pass
      
      - name: Cleanup vault password
        if: always()
        run: |
          rm -f ansible/.vault_pass
```

### Security Best Practices for CI/CD

1. **Never log decrypted secrets**
   - Use `echo "::add-mask::$SECRET"` in GitHub Actions to mask values
   - Avoid `set -x` or verbose mode when handling secrets

2. **Clean up sensitive files**
   - Always use `if: always()` for cleanup steps
   - Delete temporary key files after use

3. **Use environment-specific secrets**
   - Separate secrets for production vs. staging
   - Use GitHub Environments for additional protection

4. **Limit workflow permissions**
   - Use OIDC authentication when possible
   - Grant minimum required permissions

5. **Audit secret access**
   - Review GitHub Actions logs regularly
   - Monitor for unauthorized workflow runs

### GitLab CI Integration

For GitLab CI/CD:

```yaml
variables:
  ANSIBLE_VAULT_PASSWORD_FILE: ".vault_pass"

before_script:
  - apt-get update && apt-get install -y ansible sops
  - echo "$ANSIBLE_VAULT_PASSWORD" > .vault_pass
  - chmod 600 .vault_pass
  - mkdir -p ~/.config/sops/age
  - echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt

deploy:
  stage: deploy
  script:
    - cd ansible
    - ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml
  after_script:
    - rm -f .vault_pass ~/.config/sops/age/keys.txt
  only:
    - main
```

Set `ANSIBLE_VAULT_PASSWORD` and `SOPS_AGE_KEY` as protected and masked variables in GitLab CI/CD settings.

## Secret Rotation

### Rotation Schedule

| Secret Type | Frequency | Automation |
|-------------|-----------|------------|
| Cloudflared credentials | 90 days | Manual |
| TLS certificates | 90 days | Automated (cert-manager) |
| Database passwords | 180 days | Manual |
| API tokens | 90 days | Manual |
| age encryption keys | 365 days | Manual |
| SSH keys | 365 days | Manual |

### Rotation Procedures

#### Cloudflared Credentials

```bash
# 1. Create new tunnel
cloudflared tunnel create infrastructure-tunnel-new

# 2. Update DNS to point to new tunnel
cloudflared tunnel route dns infrastructure-tunnel-new app.example.com

# 3. Encrypt new credentials
sops -e cloudflared-new.yaml > cloudflared-new.enc.yaml

# 4. Deploy new secret
sops -d cloudflared-new.enc.yaml | kubectl apply -f -

# 5. Update Helmfile values to use new secret
# Edit helmfile/values/cloudflared-values.yaml

# 6. Deploy updated Helmfile
cd helmfile && helmfile apply

# 7. Verify new tunnel is working

# 8. Delete old tunnel
cloudflared tunnel delete infrastructure-tunnel-old

# 9. Delete old secret
kubectl delete secret cloudflared-credentials-old -n cloudflare
```

#### age Encryption Keys

```bash
# 1. Generate new key
age-keygen -o ~/.config/sops/age/keys-new.txt

# 2. Get public key
NEW_KEY=$(grep "public key:" ~/.config/sops/age/keys-new.txt | cut -d: -f2 | tr -d ' ')

# 3. Add new key to .sops.yaml (keep old key for now)
# Update creation_rules to include both keys comma-separated

# 4. Re-encrypt all secrets with both keys
find . -name "*.enc.yaml" -exec sops updatekeys --yes {} \;

# 5. Update GitHub secret SOPS_AGE_KEY with new key
gh secret set SOPS_AGE_KEY < ~/.config/sops/age/keys-new.txt

# 6. Test decryption with new key
mv ~/.config/sops/age/keys.txt ~/.config/sops/age/keys-old.txt
cp ~/.config/sops/age/keys-new.txt ~/.config/sops/age/keys.txt
sops -d test-secret.enc.yaml  # Should work

# 7. Remove old key from .sops.yaml
# Edit .sops.yaml to only include new key

# 8. Re-encrypt all secrets with only new key
find . -name "*.enc.yaml" -exec sops updatekeys --yes {} \;

# 9. Backup and archive old key securely
# Keep old key in secure backup for 90 days in case rollback needed
```

#### Database Passwords

```bash
# 1. Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# 2. Update secret YAML with new password
sops postgres-credentials.enc.yaml
# Edit password field, save

# 3. Apply updated secret
sops -d postgres-credentials.enc.yaml | kubectl apply -f -

# 4. Update database password
kubectl exec -it postgres-0 -n production -- \
  psql -U postgres -c "ALTER USER admin PASSWORD '$NEW_PASSWORD';"

# 5. Restart applications to pick up new credentials
kubectl rollout restart deployment/myapp -n production
```

## Security Best Practices

### Do's ✅

- **Encrypt all secrets** before committing to Git
- **Use SOPS** with age for encryption at rest
- **Rotate secrets** according to schedule
- **Use unique secrets** per environment
- **Limit secret access** with RBAC
- **Audit secret access** regularly
- **Backup encryption keys** securely
- **Use External Secrets Operator** for centralized secret management
- **Enable Kubernetes secrets encryption at rest**
- **Use service accounts** with minimal permissions

### Don'ts ❌

- **Never commit plaintext secrets** to Git
- **Never share age private keys** via email/Slack
- **Never reuse production secrets** in dev/staging
- **Never store secrets in ConfigMaps**
- **Never log secrets** in application logs
- **Never expose secrets** in environment variables unnecessarily
- **Never skip secret rotation**
- **Never commit .vault_pass** or age keys to Git
- **Never use default/example secrets** in production

### .gitignore Configuration

Ensure these patterns are in `.gitignore`:

```gitignore
# Secrets (only encrypted versions should be committed)
*secret*.yaml
!*secret*.enc.yaml
*credentials*.yaml
!*credentials*.enc.yaml
*.vault_pass
.vault_pass

# age keys
*.age
**/age/keys.txt

# Cloudflared
.cloudflared/*.json
!.cloudflared/config.yaml

# Ansible vault
group_vars/all/vault.yml
!group_vars/all/vault.yml.example

# Terraform (if used)
*.tfstate
*.tfstate.backup
.terraform/

# Kubeconfig
*.kubeconfig
kubeconfig
config-*
```

### Secret Scanning

Enable GitHub secret scanning:

1. Go to **Settings** → **Security** → **Code security and analysis**
2. Enable **Secret scanning**
3. Enable **Push protection**

This prevents accidental commits of secrets.

### Kubernetes RBAC for Secrets

Limit secret access with RBAC:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: production
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["specific-secret"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-secrets
  namespace: production
subjects:
- kind: ServiceAccount
  name: myapp
  namespace: production
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

### Encryption at Rest

Ensure Kubernetes encrypts secrets at rest in etcd:

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <BASE64_ENCODED_SECRET>
      - identity: {}
```

K3s enables this by default with auto-generated keys.

## Periodic Audits and Maintenance

Regular security audits and maintenance are essential for maintaining a secure infrastructure. This section provides guidance on periodic reviews and proactive security measures.

### Monthly Tasks

#### 1. Review GitHub Secret Scanning Alerts

GitHub automatically scans repositories for accidentally committed secrets. Review and address any alerts:

```bash
# Using GitHub CLI
gh api repos/wcatz/infrastructure/secret-scanning/alerts

# Or via web UI:
# Go to: Settings → Security → Secret scanning
```

**Actions to take:**
- Investigate each alert immediately
- Rotate any exposed secrets
- Remove secrets from Git history if needed
- Update .gitignore to prevent future occurrences

#### 2. Verify Push Protection is Active

Ensure push protection prevents accidental secret commits:

```bash
# Check if push protection is enabled
gh api repos/wcatz/infrastructure | jq '.security_and_analysis.secret_scanning_push_protection.status'
# Should return: "enabled"
```

**To enable push protection:**
1. Go to repository **Settings** → **Code security and analysis**
2. Enable **Push protection**
3. Test by attempting to commit a fake secret

#### 3. Review Access Logs

Check who accessed secrets and when:

```bash
# Kubernetes secret access (if audit logging enabled)
kubectl logs -n kube-system kube-apiserver-* | grep "secrets"

# GitHub Actions logs
gh run list --limit 20

# Review for:
# - Unexpected secret access
# - Failed authentication attempts  
# - Unusual access patterns
```

### Quarterly Tasks

#### 1. Secret Rotation Review

Review secret rotation schedule and rotate due secrets:

```bash
# Check last rotation dates
ls -lh helmfile/secrets/*.enc.yaml
git log --follow helmfile/secrets/*.enc.yaml

# Rotate secrets according to schedule:
# - Cloudflared credentials: 90 days
# - API tokens: 90 days
# - Database passwords: 180 days
```

#### 2. SOPS Age Key Audit

Verify all team members have current age keys:

```bash
# List all age public keys in .sops.yaml
grep "age:" .sops.yaml

# Verify each key owner is still on the team
# Remove keys for departed team members
# Add keys for new team members
```

#### 3. GitHub Actions Secret Audit

Review and clean up GitHub repository secrets:

```bash
# List all secrets
gh secret list

# Review each secret:
# - Is it still needed?
# - When was it last used?
# - Does it need rotation?
# - Remove unused secrets
```

#### 4. Ansible Vault Review

Verify Ansible vault integrity:

```bash
cd ansible

# Test vault decryption
ansible-vault view group_vars/all/vault.yml

# Review vault contents for:
# - Unused variables
# - Expired credentials
# - Secrets that should be rotated
```

### Semi-Annual Tasks (Every 6 Months)

#### 1. Comprehensive Secret Rotation

Rotate all manually-managed secrets:

```bash
# 1. Database passwords
# 2. API tokens
# 3. Service account credentials
# 4. SSH keys (if not rotated recently)
```

See [Secret Rotation](#secret-rotation) section for detailed procedures.

#### 2. Security Code Scanning

Run comprehensive code scanning to detect vulnerabilities:

```bash
# GitHub Advanced Security Code Scanning
# Go to: Security → Code scanning alerts

# Review and address all high/critical alerts
# Focus on:
# - Hardcoded secrets
# - Insecure cryptographic algorithms
# - SQL injection vulnerabilities
# - Authentication bypass issues
```

Enable automated code scanning:
1. Go to **Settings** → **Code security and analysis**
2. Enable **Code scanning** with CodeQL
3. Configure scanning on push and pull requests

#### 3. Dependency Scanning

Check for vulnerabilities in dependencies:

```bash
# Scan Ansible dependencies
pip list --outdated

# Scan Helm charts
helm plugin install https://github.com/databus23/helm-diff
cd helmfile && helmfile diff

# Review Dependabot alerts
gh api repos/wcatz/infrastructure/dependabot/alerts
```

Enable Dependabot:
1. Go to **Settings** → **Code security and analysis**
2. Enable **Dependabot alerts**
3. Enable **Dependabot security updates**

### Annual Tasks

#### 1. Age Encryption Key Rotation

Rotate SOPS age encryption keys annually:

See [SOPS Rotation](#rotate-encryption-keys) section for detailed steps.

**Key steps:**
1. Generate new age keypair
2. Add new public key to .sops.yaml
3. Re-encrypt all secrets with new key
4. Update GitHub secret SOPS_AGE_KEY
5. Remove old key after verification
6. Backup new key securely

#### 2. Ansible Vault Password Rotation

Rotate Ansible vault password annually:

See [Ansible Vault Rotation](#rotating-vault-password) section for detailed steps.

#### 3. SSH Key Rotation

Rotate SSH keys for server access:

```bash
# Generate new SSH key
ssh-keygen -t ed25519 -C "infrastructure-key-2024" -f ~/.ssh/infrastructure-2024

# Deploy new key to all servers
ansible all -i inventory.ini -m authorized_key \
  -a "user={{ ansible_user }} key='{{ lookup('file', '~/.ssh/infrastructure-2024.pub') }}'"

# Test new key
ssh -i ~/.ssh/infrastructure-2024 user@server

# Remove old key from servers
ansible all -i inventory.ini -m authorized_key \
  -a "user={{ ansible_user }} key='{{ lookup('file', '~/.ssh/infrastructure-2023.pub') }}' state=absent"

# Backup old key and update references
mv ~/.ssh/infrastructure-2023 ~/.ssh/infrastructure-2023.backup
mv ~/.ssh/infrastructure-2024 ~/.ssh/infrastructure
```

#### 4. Comprehensive Security Review

Conduct annual security assessment:

**Review checklist:**
- [ ] All secrets rotated per schedule
- [ ] Access control lists (RBAC) reviewed
- [ ] Network policies up to date
- [ ] Firewall rules validated
- [ ] TLS certificates auto-renewing
- [ ] Backup and recovery tested
- [ ] Incident response plan updated
- [ ] Security documentation current
- [ ] Team security training completed
- [ ] Compliance requirements met

### Automated Monitoring

Set up automated alerts for security events:

#### Prometheus Alerts

```yaml
# Example: Alert on secret access spike
- alert: HighSecretAccessRate
  expr: rate(apiserver_audit_event_total{objectRef_resource="secrets"}[5m]) > 10
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Unusual secret access rate detected"
    description: "Secret access rate is {{ $value }} per second"

# Alert on failed authentication
- alert: FailedAuthAttempts
  expr: rate(apiserver_audit_event_total{verb="create",objectRef_resource="tokenreviews",responseStatus_code!="200"}[5m]) > 5
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Multiple failed authentication attempts"
```

#### GitHub Actions Workflow

Create a workflow for periodic security checks:

```yaml
name: Security Audit

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday
  workflow_dispatch:

jobs:
  security-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Check for exposed secrets
        run: |
          # Scan for common secret patterns
          git grep -i "password\|secret\|token\|key" | grep -v ".enc.yaml" || true
      
      - name: Verify .gitignore
        run: |
          # Check .gitignore includes sensitive patterns
          grep -q ".vault_pass" .gitignore
          grep -q "keys.txt" .gitignore
          grep -q "credentials.json" .gitignore
      
      - name: Check secret rotation dates
        run: |
          # List secrets older than 90 days
          find helmfile/secrets -name "*.enc.yaml" -mtime +90
```

### Secret Leakage Detection

Proactive measures to detect secret leakage:

#### 1. GitHub Secret Scanning

Already covered in monthly tasks. Ensure it's active:

```bash
# Verify secret scanning is enabled
gh api repos/wcatz/infrastructure | jq '.security_and_analysis.secret_scanning.status'
```

#### 2. Git History Scanning

Use tools to scan Git history for secrets:

```bash
# Install gitleaks
brew install gitleaks  # macOS
# or download from: https://github.com/gitleaks/gitleaks

# Scan repository history
gitleaks detect --source . --verbose

# Scan specific branch
gitleaks detect --source . --branch main

# If secrets found, follow remediation:
# 1. Rotate the exposed secret immediately
# 2. Remove from Git history (use git-filter-repo or BFG)
# 3. Update .gitignore
# 4. Document the incident
```

#### 3. External Monitoring

Monitor for leaked secrets on external sites:

- **GitHub Secret Scanning Partner Program**: Automatically notifies on public leaks
- **Have I Been Pwned**: Check for credential leaks
- **Google Alerts**: Set up alerts for your domain/secret patterns

### Incident Response for Secret Exposure

If a secret is exposed:

**Immediate Actions (Within 1 hour):**
1. Rotate the exposed secret immediately
2. Revoke old secret/token
3. Review access logs for unauthorized use
4. Deploy updated secret to all affected systems

**Investigation (Within 24 hours):**
1. Determine scope of exposure
2. Identify how the secret was exposed
3. Check for unauthorized access or damage
4. Document findings

**Remediation:**
1. Remove secret from Git history if committed
2. Update .gitignore to prevent recurrence
3. Implement additional controls
4. Update documentation
5. Team training if needed

**Follow-up:**
1. Post-incident review
2. Update procedures
3. Test improvements
4. Schedule follow-up audit

## Troubleshooting

### Cannot decrypt SOPS file

**Error:** `Failed to get the data key required to decrypt the SOPS file`

**Solution:**
```bash
# Verify age key is present
ls -la ~/.config/sops/age/keys.txt

# Set SOPS_AGE_KEY_FILE
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Try decryption again
sops -d secret.enc.yaml
```

### Wrong age key

**Error:** `no age identities found`

**Solution:**
```bash
# Verify public key in .sops.yaml matches your age key
cat ~/.config/sops/age/keys.txt | grep "public key:"
grep "age:" .sops.yaml

# If they don't match, you need to:
# 1. Use the correct age key
# 2. Or re-encrypt with the current age key
```

### Cloudflared pod fails to start

**Error:** `Unable to read tunnel credentials`

**Solution:**
```bash
# Check secret exists
kubectl get secret cloudflared-credentials -n cloudflare

# Check secret content
kubectl get secret cloudflared-credentials -n cloudflare -o yaml

# Verify credentials.json key exists
kubectl get secret cloudflared-credentials -n cloudflare \
  -o jsonpath='{.data.credentials\.json}' | base64 -d | jq .

# Re-create secret if needed
sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -
```

### GitHub Actions SOPS decryption fails

**Error:** `SOPS_AGE_KEY not set`

**Solution:**
```bash
# Verify GitHub secret exists
gh secret list | grep SOPS_AGE_KEY

# Re-add if missing
gh secret set SOPS_AGE_KEY < ~/.config/sops/age/keys.txt

# Check workflow file configures the key correctly
```

### Secret not updated after rotation

**Issue:** Application still uses old credentials

**Solution:**
```bash
# Force pod restart to pick up new secret
kubectl rollout restart deployment/myapp -n production

# Or delete pods (if using StatefulSet)
kubectl delete pod myapp-0 -n production
```

---

## References

### External Documentation

- [SOPS Documentation](https://github.com/mozilla/sops) - Mozilla SOPS encryption tool
- [age Encryption](https://github.com/FiloSottile/age) - Modern encryption tool by Filippo Valsorda
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) - Kubernetes secrets documentation
- [External Secrets Operator](https://external-secrets.io/) - Kubernetes operator for external secret management
- [Cloudflared Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/) - Cloudflare tunnel documentation
- [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) - Ansible vault encryption

### Related Documentation

- [Setup Guide](docs/setup.md) - Complete infrastructure setup guide including secret management setup
- [Security Policy](SECURITY.md) - Security measures and best practices for the infrastructure
- [Operations Guide](docs/operate.md) - Day-to-day operations including secret management workflows
- [Ansible Guide](docs/ansible.md) - Ansible playbooks and vault usage
- [GitHub Actions OIDC](GITHUB_ACTIONS_OIDC.md) - GitHub Actions OIDC authentication setup

### Quick Navigation

**Setup and Getting Started:**
- [Initial SOPS Setup](#quick-start) - Get started with SOPS encryption
- [Ansible Vault Setup](#ansible-vault) - Configure Ansible vault for infrastructure secrets
- [CI/CD Integration](#cicd-integration) - Integrate secrets into deployment pipelines

**Day-to-Day Operations:**
- [Encrypt a Secret](#encrypt-a-secret) - How to encrypt secrets with SOPS
- [Decrypt a Secret](#decrypt-a-secret) - How to decrypt and deploy secrets
- [Edit Encrypted Secrets](#edit-encrypted-secret) - Modify existing encrypted secrets
- [Ansible Vault Commands](#common-vault-commands) - Common Ansible vault operations

**Security and Maintenance:**
- [Secret Rotation](#secret-rotation) - Rotation procedures for all secret types
- [Periodic Audits](#periodic-audits-and-maintenance) - Regular security audit tasks
- [Troubleshooting](#troubleshooting) - Common issues and solutions

---

**For immediate assistance, refer to:**
- Setup guide: [docs/setup.md](docs/setup.md)
- Operations guide: [docs/operate.md](docs/operate.md)
- Security policy: [SECURITY.md](SECURITY.md)
- GitHub Issues: [infrastructure/issues](https://github.com/wcatz/infrastructure/issues)
