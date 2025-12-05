# Secrets Management Guide

Comprehensive guide for managing secrets securely using SOPS, Ansible Vault, and External Secrets Operator.

## Table of Contents

- [Overview](#overview)
- [SOPS with age](#sops-with-age)
- [SOPS with Cloud KMS](#sops-with-cloud-kms)
- [Ansible Vault Integration](#ansible-vault-integration)
- [Developer Workflow](#developer-workflow)
- [CI/CD Integration](#cicd-integration)
- [Best Practices](#best-practices)

## Overview

This infrastructure supports multiple secret management strategies:

1. **SOPS + age**: Simple, file-based encryption for GitOps workflows
2. **SOPS + Cloud KMS**: Enterprise-grade key management (AWS KMS, Azure Key Vault, GCP KMS)
3. **Ansible Vault**: Encrypted variables for Ansible playbooks
4. **External Secrets Operator**: Sync secrets from external providers

### Strategy Selection Guide

| Scenario | Recommended Solution |
|----------|---------------------|
| Local development | SOPS + age |
| Small teams without cloud | SOPS + age |
| AWS-based infrastructure | SOPS + AWS KMS |
| Azure-based infrastructure | SOPS + Azure Key Vault |
| GCP-based infrastructure | SOPS + GCP KMS |
| Multi-cloud | External Secrets Operator |
| Ansible-only deployments | Ansible Vault |

## SOPS with age

age provides simple, modern encryption without external dependencies.

### Initial Setup

#### 1. Install age

```bash
# macOS
brew install age

# Linux
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/
```

#### 2. Generate Keys

```bash
# Create directory for keys
mkdir -p ~/.config/sops/age

# Generate key pair
age-keygen -o ~/.config/sops/age/keys.txt

# View public key
cat ~/.config/sops/age/keys.txt | grep "public key:"
```

**Important**: Back up `~/.config/sops/age/keys.txt` securely and never commit it to Git!

#### 3. Configure SOPS

Create `.sops.yaml` in repository root:

```yaml
creation_rules:
  # Encrypt all files in secrets/ directory
  - path_regex: secrets/.*\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
  
  # Encrypt files with .enc.yaml extension
  - path_regex: .*\.enc\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
  
  # Encrypt Ansible vault files
  - path_regex: ansible/group_vars/.*\.vault\.yml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### Encrypting Secrets

#### Kubernetes Secrets

```bash
# Create secret file
mkdir -p secrets
cat > secrets/db-credentials.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: production
type: Opaque
stringData:
  username: dbuser
  password: "SuperSecret123!"
  host: mysql.production.svc.cluster.local
EOF

# Encrypt in place
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -e -i secrets/db-credentials.yaml

# File is now encrypted but structure visible
cat secrets/db-credentials.yaml
```

#### Helm Values Files

```bash
# Create sensitive values
cat > helmfile/values/mysql-values.enc.yaml <<EOF
mysql:
  auth:
    rootPassword: "RootPass123!"
    username: appuser
    password: "AppPass123!"
    database: myapp
EOF

# Encrypt
sops -e -i helmfile/values/mysql-values.enc.yaml
```

### Decrypting and Using Secrets

#### Deploy to Kubernetes

```bash
# Decrypt and apply
sops -d secrets/db-credentials.yaml | kubectl apply -f -

# Verify
kubectl get secret database-credentials -n production
```

#### Use in Helmfile

```bash
# Helmfile automatically decrypts .enc.yaml files
helmfile apply
```

#### Edit Encrypted Files

```bash
# Edit in place (decrypts, opens editor, re-encrypts on save)
sops secrets/db-credentials.yaml

# Or manually decrypt, edit, re-encrypt
sops -d secrets/db-credentials.yaml > /tmp/temp.yaml
# Edit /tmp/temp.yaml
sops -e /tmp/temp.yaml > secrets/db-credentials.yaml
rm /tmp/temp.yaml
```

## SOPS with Cloud KMS

### AWS KMS

#### 1. Create KMS Key

```bash
# Create KMS key
aws kms create-key \
  --description "SOPS encryption key for infrastructure" \
  --tags TagKey=Environment,TagValue=production

# Create alias
aws kms create-alias \
  --alias-name alias/sops-infrastructure \
  --target-key-id <KEY-ID>

# Note the ARN for .sops.yaml
```

#### 2. Configure SOPS

Update `.sops.yaml`:

```yaml
creation_rules:
  - path_regex: secrets/prod/.*\.yaml$
    kms: 'arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012'
  
  - path_regex: secrets/staging/.*\.yaml$
    kms: 'arn:aws:kms:us-west-2:123456789012:key/staging-key-id'
  
  - path_regex: secrets/dev/.*\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

#### 3. Encrypt with AWS KMS

```bash
# Set AWS credentials
export AWS_PROFILE=infrastructure

# Encrypt file
sops -e secrets/prod/database.yaml > secrets/prod/database.enc.yaml

# SOPS uses AWS CLI credentials automatically
```

### Azure Key Vault

#### 1. Create Key Vault

```bash
# Create resource group
az group create --name infrastructure-rg --location eastus

# Create key vault
az keyvault create \
  --name infrastructure-kv \
  --resource-group infrastructure-rg \
  --location eastus

# Create key
az keyvault key create \
  --vault-name infrastructure-kv \
  --name sops-key \
  --protection software
```

#### 2. Configure SOPS

```yaml
creation_rules:
  - path_regex: secrets/prod/.*\.yaml$
    azure_keyvault: 'https://infrastructure-kv.vault.azure.net/keys/sops-key/version'
```

#### 3. Authenticate

```bash
# Login to Azure
az login

# Encrypt
sops -e secrets/prod/database.yaml > secrets/prod/database.enc.yaml
```

### GCP KMS

#### 1. Create KMS Key

```bash
# Create keyring
gcloud kms keyrings create sops \
  --location global

# Create key
gcloud kms keys create infrastructure-key \
  --location global \
  --keyring sops \
  --purpose encryption
```

#### 2. Configure SOPS

```yaml
creation_rules:
  - path_regex: secrets/prod/.*\.yaml$
    gcp_kms: 'projects/my-project/locations/global/keyRings/sops/cryptoKeys/infrastructure-key'
```

## Ansible Vault Integration

### Setup Ansible Vault with SOPS

#### 1. Create Vault Password File

```bash
# Generate random vault password
openssl rand -base64 32 > ansible/.vault_pass

# Encrypt vault password with SOPS
sops -e ansible/.vault_pass > ansible/.vault_pass.enc

# Remove plaintext
rm ansible/.vault_pass

# Add to .gitignore
echo "ansible/.vault_pass" >> .gitignore
```

#### 2. Configure Ansible

Edit `ansible/ansible.cfg`:

```ini
[defaults]
vault_password_file = .vault_pass
```

#### 3. Create Encrypted Variables

```bash
# Decrypt vault password (in CI/CD or locally)
sops -d ansible/.vault_pass.enc > ansible/.vault_pass
chmod 600 ansible/.vault_pass

# Create encrypted variables
cat > ansible/group_vars/all.vault.yml <<EOF
---
k3s_token: "generated-secure-token-here"
tailscale_auth_key: "tskey-auth-xxxxx-yyyyy"
cloudflared_tunnel_token: "tunnel-token-here"
EOF

# Encrypt with Ansible Vault
ansible-vault encrypt ansible/group_vars/all.vault.yml

# Clean up vault password
rm ansible/.vault_pass
```

### Using Vault Variables

In playbooks:

```yaml
---
- name: Deploy k3s
  hosts: k3s_servers
  vars_files:
    - group_vars/all.vault.yml
  tasks:
    - name: Install k3s
      include_role:
        name: k3s
      vars:
        k3s_token: "{{ k3s_token }}"
```

### Editing Vault Files

```bash
# Decrypt vault password
sops -d ansible/.vault_pass.enc > ansible/.vault_pass
chmod 600 ansible/.vault_pass

# Edit vault file
ansible-vault edit ansible/group_vars/all.vault.yml

# Clean up
rm ansible/.vault_pass
```

## Developer Workflow

### Without Direct Key Access

Developers can create secrets without accessing private keys using environment-based tooling.

#### AWS KMS Workflow

```bash
# Developer creates secret (using their AWS credentials)
cat > secrets/prod/new-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: new-secret
  namespace: production
type: Opaque
stringData:
  api_key: "new-api-key"
EOF

# Encrypt (uses their AWS IAM permissions)
export AWS_PROFILE=developer
sops -e secrets/prod/new-secret.yaml > secrets/prod/new-secret.enc.yaml

# Commit and push
git add secrets/prod/new-secret.enc.yaml
git commit -m "Add new API secret"
git push
```

**IAM Policy for Developers**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "arn:aws:kms:us-west-2:123456789012:key/sops-key-id"
    }
  ]
}
```

#### Azure Key Vault Workflow

```bash
# Authenticate
az login

# Create and encrypt secret
sops -e secrets/prod/new-secret.yaml > secrets/prod/new-secret.enc.yaml

# Commit
git add secrets/prod/new-secret.enc.yaml
git commit -m "Add new secret"
```

**Required Azure Permissions**:
- Key Vault Crypto User
- Key Vault Secrets Officer (for secret management)

### Team Key Sharing (age)

For teams using age, share public keys:

#### 1. Collect Public Keys

```yaml
# .sops.yaml with multiple recipients
creation_rules:
  - path_regex: secrets/.*\.yaml$
    age: >-
      age1user1publickey111111111111111111111111111111111111111,
      age1user2publickey222222222222222222222222222222222222222,
      age1user3publickey333333333333333333333333333333333333333
```

#### 2. Re-encrypt for New Users

```bash
# Add new user's public key to .sops.yaml
# Re-encrypt all secrets
find secrets -name "*.yaml" -exec sops updatekeys -y {} \;
```

## CI/CD Integration

### GitHub Actions with age

```yaml
name: Deploy Secrets
on:
  push:
    branches: [main]
    paths:
      - 'secrets/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install SOPS
        run: |
          wget -O /usr/local/bin/sops https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
          chmod +x /usr/local/bin/sops
      
      - name: Setup age key
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: |
          mkdir -p ~/.config/sops/age
          echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
          chmod 600 ~/.config/sops/age/keys.txt
      
      - name: Decrypt and apply secrets
        run: |
          for file in secrets/*.yaml; do
            sops -d "$file" | kubectl apply -f -
          done
```

**GitHub Secret Setup**:
1. Go to repository Settings → Secrets
2. Add `SOPS_AGE_KEY` with content of `~/.config/sops/age/keys.txt`

### GitHub Actions with AWS KMS

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v2
  with:
    role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
    aws-region: us-west-2

- name: Decrypt and apply secrets
  run: |
    for file in secrets/prod/*.enc.yaml; do
      sops -d "$file" | kubectl apply -f -
    done
```

### GitLab CI with Azure Key Vault

```yaml
deploy-secrets:
  image: alpine:latest
  before_script:
    - apk add --no-cache curl
    - curl -LO https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
    - chmod +x sops-v3.8.1.linux.amd64
    - mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
  script:
    - az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID
    - sops -d secrets/prod/database.enc.yaml | kubectl apply -f -
```

## Best Practices

### Secret Organization

```
secrets/
├── dev/
│   ├── database.yaml
│   ├── api-keys.yaml
│   └── tls-certs.yaml
├── staging/
│   ├── database.yaml
│   ├── api-keys.yaml
│   └── tls-certs.yaml
└── prod/
    ├── database.yaml
    ├── api-keys.yaml
    └── tls-certs.yaml
```

### Naming Conventions

```
{environment}-{service}-{type}

Examples:
- prod-mysql-credentials.yaml
- staging-api-keys.yaml
- dev-tls-certificates.yaml
```

### Git Commits

```bash
# Always encrypt before committing
sops -e -i secrets/prod/new-secret.yaml
git add secrets/prod/new-secret.yaml
git commit -m "Add production database credentials"

# Never commit plaintext secrets
# Add to .gitignore:
*.dec.yaml
*.vault_pass
!*.enc.yaml
```

### Key Rotation

#### age Keys

```bash
# Generate new key
age-keygen -o ~/.config/sops/age/new-keys.txt

# Add to .sops.yaml
# Re-encrypt all secrets
find secrets -name "*.yaml" -exec sops updatekeys {} \;

# Update CI/CD secrets
# Delete old key after verification
```

#### KMS Keys

```bash
# Create new KMS key version (AWS)
aws kms create-key --description "New SOPS key"

# Update .sops.yaml with new ARN
# Re-encrypt secrets
sops updatekeys secrets/prod/*.yaml

# Rotate after verification
aws kms schedule-key-deletion --key-id old-key-id --pending-window-in-days 30
```

### Audit Trail

```bash
# Track who encrypted/decrypted
# SOPS metadata shows key fingerprints

# View SOPS metadata
sops -d --extract '["sops"]' secrets/prod/database.yaml

# Shows:
# - Last modified date
# - Key fingerprints used
# - MAC for integrity
```

### Backup Strategies

1. **Private Keys**: Store encrypted backups in secure locations (1Password, Vault, etc.)
2. **Git History**: All encrypted secrets are version-controlled
3. **KMS Keys**: Configure automatic backups for cloud KMS keys
4. **Recovery Procedures**: Document key recovery procedures

## Troubleshooting

### Cannot Decrypt File

```bash
# Check SOPS version
sops --version

# Verify key file
cat ~/.config/sops/age/keys.txt

# Check SOPS metadata
sops -d --extract '["sops"]' secrets/file.yaml

# Verify key matches
grep "public key" ~/.config/sops/age/keys.txt
```

### AWS KMS Access Denied

```bash
# Check AWS credentials
aws sts get-caller-identity

# Verify KMS permissions
aws kms describe-key --key-id alias/sops-infrastructure

# Test decrypt permission
aws kms decrypt --ciphertext-blob fileb://test.enc --key-id alias/sops-infrastructure
```

### File Corruption

```bash
# SOPS includes MAC for integrity verification
# If MAC check fails, file is corrupted

# Restore from Git
git checkout HEAD -- secrets/corrupted-file.yaml

# Or restore from backup
```

## Additional Resources

- [SOPS Documentation](https://github.com/mozilla/sops)
- [age Specification](https://age-encryption.org/)
- [AWS KMS Documentation](https://docs.aws.amazon.com/kms/)
- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
- [GCP KMS Documentation](https://cloud.google.com/kms/docs)
- [External Secrets Operator](https://external-secrets.io/)
