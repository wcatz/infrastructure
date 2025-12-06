# Secret Management

> **⚠️ DEPRECATED**: This documentation has been consolidated into the new [docs/setup.md](docs/setup.md#3-secret-management) guide.
> 
> **Please refer to**: [docs/setup.md - Secret Management](docs/setup.md#3-secret-management)

This repository uses two different secret management systems:
- **Ansible Vault**: For Ansible playbook secrets (K3s token, Tailscale key)
- **SOPS with age**: For Kubernetes secrets and Helmfile values

## Ansible Vault (for Ansible Playbooks)

### Setup

1. **Create vault password file**:
```bash
cd ansible
cp .vault_pass.example .vault_pass
vim .vault_pass  # Add your vault password (keep this secure!)
```

2. **Create vault variables**:
```bash
# Copy example file
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit with your secrets
vim group_vars/all/vault.yml
```

3. **Encrypt the vault file**:
```bash
ansible-vault encrypt group_vars/all/vault.yml
```

### Usage

The vault contains the following encrypted variables:
- `vault_k3s_token`: K3s cluster token (generate with `openssl rand -hex 32`)
- `vault_tailscale_key`: Tailscale authentication key

These are automatically decrypted when running playbooks if `.vault_pass` exists.

### Common Commands

```bash
# Edit encrypted vault
ansible-vault edit group_vars/all/vault.yml

# View encrypted vault
ansible-vault view group_vars/all/vault.yml

# Change vault password
ansible-vault rekey group_vars/all/vault.yml

# Run playbook with specific vault password file
ansible-playbook playbooks/deploy-k3s.yaml --vault-password-file=.vault_pass
```

### CI/CD Integration

For GitHub Actions or other CI/CD systems:

1. Store vault password as a repository secret: `ANSIBLE_VAULT_PASSWORD`
2. In workflow, write it to a file:
   ```yaml
   - name: Setup Ansible Vault
     run: echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > ansible/.vault_pass
   ```

## SOPS with age (for Kubernetes Secrets)

Simple secret encryption using SOPS with age.

## Setup

### Install Tools

```bash
# macOS
brew install age sops

# Linux
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/

wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

### Generate Age Key

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# View public key
cat ~/.config/sops/age/keys.txt | grep "public key:"
```

**Important: Back up `~/.config/sops/age/keys.txt` securely!**

### Passphrase-Protected Age Keys

For additional security, you can protect your age key with a passphrase:

```bash
# Generate passphrase-protected key
age-keygen | age -p > ~/.config/sops/age/keys.txt.age

# When needed, decrypt to use
age -d ~/.config/sops/age/keys.txt.age > ~/.config/sops/age/keys.txt

# Remember to remove decrypted key when done
rm ~/.config/sops/age/keys.txt
```

**For GitHub Actions:**
- Store the encrypted key (`keys.txt.age`) in the repository
- Store the passphrase in GitHub Secrets as `AGE_PASSPHRASE`
- Decrypt in workflow before using SOPS

### Configure SOPS

Create `.sops.yaml`:

```yaml
creation_rules:
  - age: YOUR_PUBLIC_KEY_HERE
```

## Usage

### Encrypt Secrets

```bash
# Create secret
cat > secrets/db.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: database
type: Opaque
stringData:
  username: admin
  password: supersecret
EOF

# Encrypt
sops -e secrets/db.yaml > secrets/db.enc.yaml
rm secrets/db.yaml
```

### Deploy Secrets

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d secrets/db.enc.yaml | kubectl apply -f -
```

### Edit Encrypted Secrets

```bash
sops secrets/db.enc.yaml
```

## GitHub Actions

Add to repository secrets:
- Name: `SOPS_AGE_KEY`
- Value: Content of `~/.config/sops/age/keys.txt`

**Alternative: Passphrase-Protected Approach**

For enhanced security with passphrase-protected keys:

1. **Generate and encrypt age key**:
```bash
age-keygen | age -p > age-keys.txt.age
# Enter a strong passphrase when prompted
```

2. **Store in repository** (encrypted key is safe to commit):
```bash
mkdir -p .github/secrets
mv age-keys.txt.age .github/secrets/
git add .github/secrets/age-keys.txt.age
git commit -m "Add encrypted age key"
```

3. **Add passphrase to GitHub Secrets**:
   - Name: `AGE_PASSPHRASE`
   - Value: Your passphrase

4. **Update workflow** to decrypt key before use:
```yaml
- name: Setup age key
  env:
    AGE_PASSPHRASE: ${{ secrets.AGE_PASSPHRASE }}
  run: |
    mkdir -p ~/.config/sops/age
    echo "$AGE_PASSPHRASE" | age -d .github/secrets/age-keys.txt.age > ~/.config/sops/age/keys.txt
    chmod 600 ~/.config/sops/age/keys.txt
```

Workflows decrypt automatically.

## Helmfile Integration

Helmfile auto-decrypts `.enc.yaml`:

```bash
sops -e helmfile/values/secret.yaml > helmfile/values/secret.enc.yaml
helmfile apply
```

## Team Keys

For multiple team members:

```yaml
# .sops.yaml
creation_rules:
  - age: >-
      age1user1key,
      age1user2key
```

## Best Practices

- Never commit plaintext secrets
- Back up age private keys
- Add `*.dec.yaml` to `.gitignore`
- Rotate keys periodically

## Secret Rotation Procedures

Regular rotation of secrets is critical for maintaining security. Follow these procedures for different types of secrets.

### Age Key Rotation

Age keys should be rotated **quarterly** (every 3 months) or immediately if compromised.

#### Rotation Steps:

1. **Generate new age key**:
   ```bash
   age-keygen -o ~/.config/sops/age/keys-new.txt
   cat ~/.config/sops/age/keys-new.txt | grep "public key:"
   # Note the new public key: age1...
   ```

2. **Update .sops.yaml with both keys** (for transition period):
   ```yaml
   creation_rules:
     - age: >-
         age1OLD_PUBLIC_KEY,
         age1NEW_PUBLIC_KEY
   ```

3. **Re-encrypt all secrets with both keys**:
   ```bash
   # Find and re-encrypt all SOPS files
   find . -name "*.enc.yaml" -type f | while read file; do
     echo "Re-encrypting $file..."
     sops updatekeys -y "$file"
   done
   ```

4. **Verify secrets can be decrypted with new key**:
   ```bash
   # Backup old key
   cp ~/.config/sops/age/keys.txt ~/.config/sops/age/keys-old.txt
   
   # Test with new key only
   cp ~/.config/sops/age/keys-new.txt ~/.config/sops/age/keys.txt
   sops -d secrets/test.enc.yaml
   ```

5. **Update GitHub Actions secret** `SOPS_AGE_KEY`:
   - Go to repository Settings → Secrets and variables → Actions
   - Update `SOPS_AGE_KEY` with content from `keys-new.txt`

6. **Remove old key from .sops.yaml**:
   ```yaml
   creation_rules:
     - age: age1NEW_PUBLIC_KEY
   ```

7. **Commit and push changes**:
   ```bash
   git add .sops.yaml
   git commit -m "chore: rotate age encryption key"
   git push
   ```

8. **Securely destroy old key** after 1 week verification period:
   ```bash
   # After confirming all systems work with new key
   shred -u ~/.config/sops/age/keys-old.txt
   ```

#### Rotation Schedule

| Key Type | Rotation Frequency | Last Rotated | Next Rotation |
|----------|-------------------|--------------|---------------|
| Age encryption key | Quarterly | YYYY-MM-DD | YYYY-MM-DD |
| Ansible vault password | Annually | YYYY-MM-DD | YYYY-MM-DD |

**Action Required**: Update the table above after each rotation.

### Ansible Vault Password Rotation

Ansible Vault passwords should be rotated **annually** or if compromised.

#### Rotation Steps:

1. **Create new vault password**:
   ```bash
   # Generate strong password
   openssl rand -base64 32 > ansible/.vault_pass.new
   ```

2. **Rekey all vault files**:
   ```bash
   cd ansible
   ansible-vault rekey --new-vault-password-file=.vault_pass.new group_vars/all/vault.yml
   ```

3. **Replace old password**:
   ```bash
   mv .vault_pass .vault_pass.old
   mv .vault_pass.new .vault_pass
   ```

4. **Update GitHub Actions secret** `ANSIBLE_VAULT_PASSWORD`:
   - Update the secret with the new password

5. **Test playbooks**:
   ```bash
   ansible-playbook --syntax-check playbooks/deploy-k3s.yaml
   ```

6. **Securely destroy old password**:
   ```bash
   shred -u .vault_pass.old
   ```

### Kubernetes Secrets Rotation

Application secrets in Kubernetes should be rotated based on sensitivity:

- **Database passwords**: Every 6 months
- **API tokens**: Every 90 days
- **TLS certificates**: Automated via cert-manager (90 days before expiry)
- **Service account tokens**: Every 90 days

#### Rotation Steps:

1. **Create new secret version**:
   ```bash
   # Generate new password/token
   NEW_PASSWORD=$(openssl rand -base64 32)
   
   # Create new secret (SOPS encrypted)
   cat > secrets/db-new.yaml <<EOF
   apiVersion: v1
   kind: Secret
   metadata:
     name: database-credentials
     namespace: production
   type: Opaque
   stringData:
     username: admin
     password: $NEW_PASSWORD
   EOF
   
   sops -e secrets/db-new.yaml > secrets/db-new.enc.yaml
   rm secrets/db-new.yaml
   ```

2. **Update application to use new secret**:
   ```bash
   sops -d secrets/db-new.enc.yaml | kubectl apply -f -
   ```

3. **Restart affected pods**:
   ```bash
   kubectl rollout restart deployment/myapp -n production
   ```

4. **Verify application functionality**:
   ```bash
   kubectl logs -n production deployment/myapp --tail=50
   ```

5. **Update database/service with new credentials**:
   ```bash
   # Update the actual service (e.g., MySQL password)
   kubectl exec -it mysql-0 -n production -- \
     mysql -u root -p -e "ALTER USER 'admin'@'%' IDENTIFIED BY '$NEW_PASSWORD';"
   ```

### External Secrets Rotation

When using External Secrets Operator with HashiCorp Vault or AWS Secrets Manager:

1. **Rotate secret in external vault**:
   ```bash
   # AWS Secrets Manager example
   aws secretsmanager update-secret \
     --secret-id prod/database/password \
     --secret-string "$NEW_PASSWORD"
   ```

2. **External Secrets Operator automatically syncs** (typically within 1 hour)

3. **Force immediate sync** (if needed):
   ```bash
   kubectl annotate externalsecret database-credentials \
     force-sync=$(date +%s) -n production
   ```

## Automated Secret Expiration Checks

Automated monitoring for secret expiration is implemented via GitHub Actions.

### Secret Expiration Workflow

A scheduled workflow runs weekly to check for:
- Age key rotation due dates (quarterly)
- Ansible Vault password rotation due dates (annually)
- Certificate expiration (via cert-manager integration)
- External secrets sync status

See `.github/workflows/secret-expiration-check.yaml` for implementation.

### Expiration Alerts

Alerts are sent when:
- Age keys are within 2 weeks of rotation due date
- Ansible Vault password is within 1 month of rotation due date
- TLS certificates are within 30 days of expiration
- External secrets sync failures

### Manual Expiration Check

To manually check secret expiration status:

```bash
# Check age key age (should be < 90 days)
AGE_KEY_FILE=~/.config/sops/age/keys.txt
if [ -f "$AGE_KEY_FILE" ]; then
  KEY_AGE_DAYS=$(( ($(date +%s) - $(stat -c %Y "$AGE_KEY_FILE")) / 86400 ))
  echo "Age key is $KEY_AGE_DAYS days old"
  if [ $KEY_AGE_DAYS -gt 90 ]; then
    echo "⚠️  WARNING: Age key rotation overdue!"
  fi
fi

# Check certificate expiration
kubectl get certificates -A -o json | \
  jq -r '.items[] | select(.status.notAfter != null) | 
    "\(.metadata.namespace)/\(.metadata.name): expires \(.status.notAfter)"'
```

## External Secrets Operator Integration

For production environments, integrate with external secret management systems for enhanced security and centralized secret management.

### Supported Backends

- **HashiCorp Vault**: Enterprise-grade secret management
- **AWS Secrets Manager**: AWS-native secret storage
- **Azure Key Vault**: Azure-native secret storage
- **Google Secret Manager**: GCP-native secret storage

### HashiCorp Vault Integration

#### Prerequisites

1. **Deploy Vault** (outside cluster or managed service)
2. **Enable Kubernetes auth** in Vault
3. **Create policies** for secret access

#### Setup Steps

1. **Vault is already enabled in Helmfile** (see `config/enabled.yaml`)

2. **Configure Vault connection**:
   ```yaml
   # helmfile/values/external-secrets-values.yaml
   apiVersion: external-secrets.io/v1beta1
   kind: SecretStore
   metadata:
     name: vault-backend
     namespace: production
   spec:
     provider:
       vault:
         server: "https://vault.example.com"
         path: "secret"
         version: "v2"
         auth:
           kubernetes:
             mountPath: "kubernetes"
             role: "external-secrets"
             serviceAccountRef:
               name: "external-secrets"
   ```

3. **Create ExternalSecret**:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: database-credentials
     namespace: production
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: vault-backend
       kind: SecretStore
     target:
       name: database-credentials
       creationPolicy: Owner
     data:
       - secretKey: username
         remoteRef:
           key: database
           property: username
       - secretKey: password
         remoteRef:
           key: database
           property: password
   ```

4. **Verify synchronization**:
   ```bash
   kubectl get externalsecret -n production
   kubectl describe externalsecret database-credentials -n production
   ```

### AWS Secrets Manager Integration

1. **Configure AWS SecretStore**:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: SecretStore
   metadata:
     name: aws-secrets-manager
     namespace: production
   spec:
     provider:
       aws:
         service: SecretsManager
         region: us-west-2
         auth:
           jwt:
             serviceAccountRef:
               name: external-secrets
   ```

2. **Use IRSA (IAM Roles for Service Accounts)** for authentication (recommended)

3. **Create ExternalSecret** referencing AWS secret ARN

### Benefits of External Secrets Operator

- **Centralized Secret Management**: Single source of truth
- **Automatic Rotation**: Secrets auto-sync on external updates
- **Audit Trail**: All secret access logged in vault
- **Fine-grained Access Control**: Vault policies control access
- **Reduced Secret Sprawl**: No secrets in Git or CI/CD
- **Compliance**: Meets regulatory requirements

### Migration Path

To migrate from SOPS to External Secrets Operator:

1. **Deploy External Secrets Operator** (already in Helmfile)
2. **Set up Vault/AWS Secrets Manager** backend
3. **Migrate secrets one namespace at a time**:
   - Create secrets in external vault
   - Create ExternalSecret resources
   - Verify sync works
   - Remove SOPS-encrypted files
4. **Keep age keys for Helmfile values** (values files can stay SOPS-encrypted)

See `helmfile/values/external-secrets-values.yaml` for configuration examples.
