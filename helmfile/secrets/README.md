# Encrypted Secrets Directory

This directory contains encrypted Kubernetes secrets using SOPS with age encryption.

## Important

- **Only encrypted `.enc.yaml` files** should be committed to Git
- **Never commit plaintext `.yaml` files** to this directory
- Use `.gitignore` to prevent accidental commits

## Usage

### Creating a New Secret

```bash
# 1. Create plaintext secret
cat > my-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
stringData:
  username: admin
  password: changeme
EOF

# 2. Encrypt with SOPS
sops -e my-secret.yaml > my-secret.enc.yaml

# 3. Delete plaintext
rm my-secret.yaml

# 4. Commit encrypted file
git add my-secret.enc.yaml
```

### Deploying Secrets

```bash
# Set age key location
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Decrypt and apply
sops -d my-secret.enc.yaml | kubectl apply -f -
```

### Editing Encrypted Secrets

```bash
# Edit in-place (SOPS will decrypt, open editor, and re-encrypt)
sops my-secret.enc.yaml
```

## Example Secrets

Example encrypted secret files with placeholder values:

- `cloudflared-credentials-example.enc.yaml` - Cloudflare tunnel credentials
- `github-runner-secrets-example.enc.yaml` - GitHub Actions runner tokens
- `monitoring-secrets-example.enc.yaml` - Grafana admin password

**Note:** These are examples only. Replace with your actual encrypted secrets.

## See Also

- [SECRETS.md](../../SECRETS.md) - Complete secret management guide
- [.sops.yaml](../../.sops.yaml) - SOPS configuration
- [docs/setup.md](../../docs/setup.md) - Setup instructions
