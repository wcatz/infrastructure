# Secret Management Guide

This document provides comprehensive guidance on managing secrets in the hybrid Kubernetes infrastructure.

## Table of Contents

- [Overview](#overview)
- [Secret Management Strategy](#secret-management-strategy)
- [SOPS with age](#sops-with-age)
- [Cloudflared Secrets](#cloudflared-secrets)
- [Kubernetes Secrets](#kubernetes-secrets)
- [GitHub Actions Secrets](#github-actions-secrets)
- [Secret Rotation](#secret-rotation)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

This infrastructure uses a **defense-in-depth** approach to secret management:

1. **SOPS with age**: Encrypt secrets at rest in Git
2. **Kubernetes Secrets**: Store encrypted secrets in the cluster
3. **External Secrets Operator**: Sync secrets from external sources (optional)
4. **Ansible Vault**: Encrypt infrastructure secrets for Ansible playbooks
5. **GitHub Secrets**: Store CI/CD credentials securely

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

### Setup

#### 1. Install age

```bash
# macOS
brew install age

# Linux
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/
```

#### 2. Generate age Key

```bash
# Create age directory
mkdir -p ~/.config/sops/age

# Generate new key
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

Replace the placeholder age public key in `.sops.yaml`:

```yaml
creation_rules:
  - path_regex: \.enc\.yaml$
    age: >-
      age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567
```

#### 4. Backup Private Key

**⚠️ CRITICAL: Backup your age private key securely!**

```bash
# Copy to secure location (encrypted USB, password manager, vault)
cp ~/.config/sops/age/keys.txt /path/to/secure/backup/

# Or encrypt with GPG
gpg -c ~/.config/sops/age/keys.txt
# Save the .gpg file to backup location
```

**If you lose this key, you cannot decrypt your secrets!**

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

- [SOPS Documentation](https://github.com/mozilla/sops)
- [age Encryption](https://github.com/FiloSottile/age)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [External Secrets Operator](https://external-secrets.io/)
- [Cloudflared Tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html)

---

**For immediate assistance, refer to:**
- Setup guide: [docs/setup.md](docs/setup.md)
- Operations guide: [docs/operate.md](docs/operate.md)
- GitHub Issues: [infrastructure/issues](https://github.com/wcatz/infrastructure/issues)
