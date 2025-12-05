# Secret Management with SOPS

Simple secret encryption using SOPS with age for GitOps workflows.

## Quick Start

### 1. Install Tools

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

### 2. Generate Age Key

```bash
# Generate key pair
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# View public key
cat ~/.config/sops/age/keys.txt | grep "public key:"
# Example: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

**Important**: Back up `~/.config/sops/age/keys.txt` securely!

### 3. Configure SOPS

Create `.sops.yaml` in repository root:

```yaml
creation_rules:
  - age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### 4. Encrypt Secrets

```bash
# Create secret
cat > secrets/db-creds.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: database
  namespace: default
type: Opaque
stringData:
  username: admin
  password: supersecret
EOF

# Encrypt with SOPS
sops -e secrets/db-creds.yaml > secrets/db-creds.enc.yaml
rm secrets/db-creds.yaml
```

### 5. Deploy Secrets

```bash
# Decrypt and apply
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d secrets/db-creds.enc.yaml | kubectl apply -f -

# Or edit encrypted file
sops secrets/db-creds.enc.yaml
```

## GitHub Actions

Add private key to repository secrets:

1. Settings → Secrets → Actions
2. New secret: `SOPS_AGE_KEY`
3. Value: Content of `~/.config/sops/age/keys.txt`

Workflows automatically decrypt during deployment.

## Helmfile Integration

Helmfile auto-decrypts `.enc.yaml`:

```bash
sops -e helmfile/values/secret.yaml > helmfile/values/secret.enc.yaml

# Reference in helmfile (decrypts automatically)
values:
  - values/secret.enc.yaml
```

## Team Keys

Multiple recipients:

```yaml
# .sops.yaml
creation_rules:
  - age: >-
      age1user1key,
      age1user2key
```

## Best Practices

- Never commit `keys.txt` or plaintext secrets
- Back up private keys securely
- Use separate keys per environment
- Rotate keys periodically
- Add `*.dec.yaml` to `.gitignore`
