# SOPS Setup Instructions

This file provides quick setup instructions for SOPS with age encryption.

## Quick Start

### 1. Install age and SOPS

```bash
# macOS
brew install age sops

# Linux
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/

wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
chmod +x sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
```

### 2. Generate age Key

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

### 3. Update .sops.yaml

Replace the placeholder in `.sops.yaml` with your actual public key:

```bash
# Get your public key
PUBLIC_KEY=$(cat ~/.config/sops/age/keys.txt | grep "public key:" | cut -d: -f2 | tr -d ' ')

# Update .sops.yaml (replace all instances)
sed -i "s/age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/$PUBLIC_KEY/g" .sops.yaml
```

### 4. Backup Private Key

**⚠️ CRITICAL: Backup your age private key securely!**

```bash
# Method 1: Copy to encrypted USB or secure location
cp ~/.config/sops/age/keys.txt /path/to/secure/backup/

# Method 2: Encrypt with GPG
gpg -c ~/.config/sops/age/keys.txt
# Save the .gpg file to backup location

# Method 3: Store in password manager
cat ~/.config/sops/age/keys.txt
# Copy the content and save in password manager
```

### 5. Add to GitHub Secrets

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

## Usage

### Encrypt a Secret

```bash
# Create plaintext secret
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
stringData:
  username: admin
  password: supersecret
EOF

# Encrypt
sops -e secret.yaml > secret.enc.yaml

# Delete plaintext
rm secret.yaml

# Commit encrypted file
git add secret.enc.yaml
git commit -m "Add encrypted secret"
```

### Decrypt and Deploy

```bash
# Set age key location
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Decrypt and apply to Kubernetes
sops -d secret.enc.yaml | kubectl apply -f -
```

### Edit Encrypted Secret

```bash
# Edit in-place (auto-decrypts and re-encrypts)
sops secret.enc.yaml
```

## Troubleshooting

### Error: "no age identities found"

**Solution:**
```bash
# Verify age key exists
ls -la ~/.config/sops/age/keys.txt

# Set environment variable
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Or use inline:
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt sops -d secret.enc.yaml
```

### Error: "Failed to get the data key"

**Solution:**
- Verify the public key in `.sops.yaml` matches your age key
- Ensure you're using the correct age private key
- Check file was encrypted with your public key

### Public Key Mismatch

```bash
# Get your current public key
cat ~/.config/sops/age/keys.txt | grep "public key:"

# Check .sops.yaml
grep "age:" .sops.yaml

# If they don't match, update .sops.yaml with correct key
```

## See Also

- [SECRETS.md](SECRETS.md) - Complete secret management guide
- [SECURITY.md](SECURITY.md) - Security policies and best practices
- [.sops.yaml](.sops.yaml) - SOPS configuration file
- [docs/setup.md](docs/setup.md#3-secret-management) - Setup instructions
