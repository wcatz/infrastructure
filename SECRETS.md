# Secret Management with SOPS

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

**Back up `~/.config/sops/age/keys.txt` securely!**

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
