# Secret Management

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
