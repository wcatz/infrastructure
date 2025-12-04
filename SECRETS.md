# Secret Management Guide

This guide provides comprehensive instructions for managing secrets securely in the infrastructure stack.

## Table of Contents

- [Overview](#overview)
- [Secret Management Strategies](#secret-management-strategies)
- [External Secrets Operator](#external-secrets-operator)
- [SOPS Encryption](#sops-encryption)
- [Kubernetes Secrets](#kubernetes-secrets)
- [Cloudflared Credentials](#cloudflared-credentials)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

Secret management is critical for maintaining the security of the infrastructure. This guide covers multiple approaches:

1. **Kubernetes Secrets**: Native secret storage (base64 encoded)
2. **External Secrets Operator**: Sync secrets from external sources (AWS, Azure, Vault, etc.)
3. **SOPS**: Encrypt secrets in Git for GitOps workflows
4. **Cloudflared Credentials**: Specific handling for tunnel credentials

## Secret Management Strategies

### Strategy Comparison

| Strategy | Use Case | Pros | Cons |
|----------|----------|------|------|
| Kubernetes Secrets | Simple deployments | Easy to use, built-in | Base64 only, not encrypted at rest by default |
| External Secrets Operator | Production environments | Centralized, audit trail | Requires external secret store |
| SOPS | GitOps workflows | Encrypted in Git, versioned | Requires key management |
| Sealed Secrets | Kubernetes-native encryption | No external dependencies | Cluster-specific |

### Recommended Approach

**For Production**: Use External Secrets Operator with a backend like AWS Secrets Manager, Azure Key Vault, or HashiCorp Vault.

**For GitOps**: Use SOPS to encrypt secrets in Git for version control and audit trail.

**For Development**: Standard Kubernetes secrets are acceptable for non-sensitive data.

## External Secrets Operator

The External Secrets Operator (ESO) synchronizes secrets from external secret management systems into Kubernetes.

### Installation

The External Secrets Operator is included in the Helmfile configuration:

```bash
cd helmfile
# Enable External Secrets Operator in config/enabled.yaml
# Set: externalSecrets: true

helmfile -l name=external-secrets apply
```

### Supported Backends

- AWS Secrets Manager
- AWS Parameter Store
- Azure Key Vault
- Google Cloud Secret Manager
- HashiCorp Vault
- 1Password
- Doppler
- And many more...

### Configuration Example

#### 1. Create a SecretStore

Define how to connect to your external secret backend:

```yaml
# secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: default
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-credentials
            key: secret-access-key
```

#### 2. Create an ExternalSecret

Define which secrets to sync:

```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: database-credentials
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: prod/db/mysql
        property: username
    - secretKey: password
      remoteRef:
        key: prod/db/mysql
        property: password
```

The operator will create a Kubernetes secret named `db-credentials` with the synced data.

#### 3. Deploy the Resources

```bash
kubectl apply -f secret-store.yaml
kubectl apply -f external-secret.yaml

# Verify the secret was created
kubectl get secret db-credentials -o yaml
```

### AWS Secrets Manager Example

1. **Create secret in AWS**:
   ```bash
   aws secretsmanager create-secret \
     --name prod/db/mysql \
     --secret-string '{"username":"admin","password":"secure123"}'
   ```

2. **Create IAM credentials** with SecretsManager read permissions

3. **Create Kubernetes secret** with AWS credentials:
   ```bash
   kubectl create secret generic aws-credentials \
     --from-literal=access-key-id=AKIAIOSFODNN7EXAMPLE \
     --from-literal=secret-access-key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY \
     -n default
   ```

4. **Apply SecretStore and ExternalSecret** as shown above

### Azure Key Vault Example

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-keyvault
  namespace: default
spec:
  provider:
    azurekv:
      authType: ServicePrincipal
      vaultUrl: "https://my-vault.vault.azure.net"
      tenantId: "tenant-id"
      authSecretRef:
        clientId:
          name: azure-credentials
          key: client-id
        clientSecret:
          name: azure-credentials
          key: client-secret
```

### HashiCorp Vault Example

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: default
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
```

## SOPS Encryption

SOPS (Secrets OPerationS) allows you to encrypt secrets in Git while keeping the structure visible for GitOps workflows.

### Installation

```bash
# macOS
brew install sops

# Linux
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
chmod +x sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
```

### Key Management Options

SOPS supports multiple key management systems:
- **age**: Simple, modern encryption (recommended for getting started)
- **GPG**: Traditional PGP encryption
- **AWS KMS**: AWS Key Management Service
- **Azure Key Vault**: Azure key storage
- **GCP KMS**: Google Cloud KMS
- **HashiCorp Vault**: Vault Transit engine

### Using age (Recommended for simplicity)

#### 1. Generate an age key

```bash
# Install age
brew install age  # macOS
# or download from https://github.com/FiloSottile/age/releases
# Linux: verify checksum after download
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz.sha256
sha256sum -c age-v1.1.1-linux-amd64.tar.gz.sha256
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age /usr/local/bin/

# Generate a key pair
age-keygen -o key.txt

# The output shows your public key:
# Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

**Important**: Store `key.txt` securely and **never commit it to Git**.

#### 2. Configure SOPS

Create `.sops.yaml` in the repository root:

```yaml
creation_rules:
  - path_regex: .*/secrets/.*\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
  - path_regex: .*/.*\.enc\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

#### 3. Encrypt a secret file

```bash
# Create a secret file
cat > secrets/db-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: default
type: Opaque
stringData:
  username: admin
  password: supersecret123
EOF

# Encrypt it
sops -e -i secrets/db-secret.yaml

# The file is now encrypted but structure is visible
cat secrets/db-secret.yaml
```

#### 4. Decrypt when needed

```bash
# Set the private key location
export SOPS_AGE_KEY_FILE=key.txt

# Decrypt in place (for editing)
sops -d -i secrets/db-secret.yaml

# Decrypt to stdout (for applying)
sops -d secrets/db-secret.yaml | kubectl apply -f -
```

### Using GPG

#### 1. Generate GPG key

```bash
gpg --full-generate-key
# Select: (1) RSA and RSA
# Key size: 4096
# Expiration: 0 (does not expire) or set expiration
# Enter name and email
```

#### 2. Export and backup your key

```bash
# List keys
gpg --list-secret-keys

# Export private key (backup securely!)
gpg --export-secret-keys -a "your-email@example.com" > private-key.asc

# Export public key (share with team)
gpg --export -a "your-email@example.com" > public-key.asc
```

#### 3. Configure SOPS with GPG

Create `.sops.yaml`:

```yaml
creation_rules:
  - path_regex: .*/secrets/.*\.yaml$
    pgp: 'FBC7B9E2A4F9289AC0C1D4843D16CEE4A27381B4'  # Your GPG fingerprint
```

#### 4. Encrypt and decrypt

```bash
# Encrypt
sops -e secrets/db-secret.yaml > secrets/db-secret.enc.yaml

# Decrypt
sops -d secrets/db-secret.enc.yaml | kubectl apply -f -
```

### Using AWS KMS

#### 1. Create KMS key in AWS

```bash
aws kms create-key --description "SOPS encryption key"
# Note the KeyId from the output
```

#### 2. Configure SOPS

```yaml
creation_rules:
  - path_regex: .*/secrets/.*\.yaml$
    kms: 'arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012'
```

#### 3. Encrypt (requires AWS credentials)

```bash
export AWS_PROFILE=your-profile
sops -e -i secrets/db-secret.yaml
```

### SOPS in CI/CD

For GitHub Actions:

```yaml
- name: Decrypt secrets
  env:
    SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
  run: |
    echo "$SOPS_AGE_KEY" > /tmp/key.txt
    export SOPS_AGE_KEY_FILE=/tmp/key.txt
    sops -d secrets/db-secret.yaml | kubectl apply -f -
    rm /tmp/key.txt
```

## Kubernetes Secrets

Standard Kubernetes secrets for non-sensitive or already-encrypted data.

### Creating Secrets

#### From literal values

```bash
kubectl create secret generic app-config \
  --from-literal=api-key=abc123 \
  --from-literal=db-host=mysql.default.svc.cluster.local \
  -n default
```

#### From files

```bash
kubectl create secret generic tls-cert \
  --from-file=tls.crt=/path/to/tls.crt \
  --from-file=tls.key=/path/to/tls.key \
  -n default
```

#### From env file

```bash
# Create .env file
cat > app.env <<EOF
DATABASE_URL=postgresql://user:pass@host:5432/db
API_KEY=abc123
EOF

kubectl create secret generic app-env \
  --from-env-file=app.env \
  -n default
```

#### From YAML manifest

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: default
type: Opaque
data:
  # Base64 encoded values
  username: YWRtaW4=
  password: cGFzc3dvcmQxMjM=
```

Or with stringData (auto-encoded):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: default
type: Opaque
stringData:
  username: admin
  password: password123
```

### Using Secrets in Pods

#### As environment variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: myapp:latest
      env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
```

#### As mounted files

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app
spec:
  containers:
    - name: app
      image: myapp:latest
      volumeMounts:
        - name: secret-volume
          mountPath: /etc/secrets
          readOnly: true
  volumes:
    - name: secret-volume
      secret:
        secretName: app-secret
```

## Cloudflared Credentials

Special handling for Cloudflare tunnel credentials.

### Creating Tunnel Credentials

1. **Install cloudflared CLI**:
   ```bash
   brew install cloudflare/cloudflare/cloudflared
   ```

2. **Login and create tunnel**:
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create my-tunnel
   ```

   This creates a credentials file at `~/.cloudflared/<TUNNEL-ID>.json`

3. **Create Kubernetes secret**:
   ```bash
   kubectl create namespace cloudflare
   kubectl create secret generic cloudflared-credentials \
     --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
     -n cloudflare
   ```

### Managing Tunnel Credentials

**Do NOT commit the credentials file to Git!**

#### Option 1: Manual Management

Create secrets manually on each cluster as shown above.

#### Option 2: SOPS Encryption

Encrypt the credentials for version control:

```bash
# Copy credentials to secrets directory
cp ~/.cloudflared/<TUNNEL-ID>.json secrets/cloudflared-credentials.json

# Encrypt with SOPS
sops -e -i secrets/cloudflared-credentials.json

# Commit the encrypted file
git add secrets/cloudflared-credentials.json
git commit -m "Add encrypted cloudflared credentials"
```

Deploy:

```bash
# Decrypt and create secret
sops -d secrets/cloudflared-credentials.json | \
  kubectl create secret generic cloudflared-credentials \
    --from-file=credentials.json=/dev/stdin \
    -n cloudflare
```

#### Option 3: External Secrets Operator

Store in AWS Secrets Manager or similar:

```bash
# Store in AWS Secrets Manager
aws secretsmanager create-secret \
  --name cloudflared/tunnel-credentials \
  --secret-string file://~/.cloudflared/<TUNNEL-ID>.json
```

ExternalSecret manifest:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflared-credentials
  namespace: cloudflare
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: cloudflared-credentials
    creationPolicy: Owner
    template:
      data:
        credentials.json: "{{ .credentials }}"
  data:
    - secretKey: credentials
      remoteRef:
        key: cloudflared/tunnel-credentials
```

### Rotating Tunnel Credentials

1. **Create a new tunnel**:
   ```bash
   cloudflared tunnel create new-tunnel
   ```

2. **Update DNS routes**:
   ```bash
   cloudflared tunnel route dns new-tunnel app.example.com
   ```

3. **Update Kubernetes secret**:
   ```bash
   kubectl create secret generic cloudflared-credentials \
     --from-file=credentials.json=$HOME/.cloudflared/<NEW-TUNNEL-ID>.json \
     -n cloudflare \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. **Update Helmfile values** with new tunnel ID

5. **Redeploy cloudflared**:
   ```bash
   cd helmfile
   helmfile -l name=cloudflared apply
   ```

6. **Delete old tunnel**:
   ```bash
   cloudflared tunnel delete old-tunnel
   ```

## Best Practices

### General Security

1. **Never commit secrets to Git** (unless encrypted with SOPS)
2. **Use different secrets per environment** (dev, staging, prod)
3. **Rotate secrets regularly** (quarterly at minimum)
4. **Limit secret access** with RBAC
5. **Audit secret access** regularly
6. **Use strong, random passwords** (not dictionary words)

### Secret Naming

Use consistent naming conventions:

```
{environment}-{service}-{type}

Examples:
- prod-mysql-credentials
- staging-api-keys
- dev-oauth-secrets
```

### Secret Scoping

- Use **namespaces** to scope secrets
- Apply **RBAC policies** to limit access
- Use **ServiceAccounts** for pod access
- Avoid cluster-wide secrets

### RBAC for Secrets

Limit who can access secrets:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["db-credentials"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-db-secrets
  namespace: default
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: default
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

### Monitoring and Auditing

Enable audit logging for secret access:

```yaml
# kube-apiserver audit policy
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
```

### Backup and Recovery

- **Back up encryption keys** securely (offline, encrypted)
- **Document key locations** in secure documentation
- **Test recovery procedures** regularly
- **Have a key rotation plan**

## Troubleshooting

### Common Issues

#### Secret not found

```bash
# Check if secret exists
kubectl get secret -n namespace

# Check secret details
kubectl describe secret secret-name -n namespace

# View secret data
kubectl get secret secret-name -o yaml -n namespace
```

#### External Secrets not syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret -n namespace
kubectl describe externalsecret external-secret-name -n namespace

# Check SecretStore connectivity
kubectl get secretstore -n namespace
kubectl describe secretstore store-name -n namespace

# Check operator logs
kubectl logs -n external-secrets-system deployment/external-secrets
```

#### SOPS decryption fails

```bash
# Verify key file exists
ls -la $SOPS_AGE_KEY_FILE

# Check key permissions
chmod 600 $SOPS_AGE_KEY_FILE

# Verify the correct key is being used
sops -d --verbose secrets/file.enc.yaml
```

#### Permission denied errors

```bash
# Check RBAC permissions
kubectl auth can-i get secrets --as=system:serviceaccount:namespace:sa-name

# Check ServiceAccount
kubectl get sa -n namespace
kubectl describe sa sa-name -n namespace
```

### Getting Help

- Check [Kubernetes Secrets documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
- Review [External Secrets Operator docs](https://external-secrets.io/)
- Consult [SOPS documentation](https://github.com/mozilla/sops)
- See [Cloudflared documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

### Security Incident Response

If secrets are compromised:

1. **Immediately rotate** all affected secrets
2. **Revoke access** for compromised credentials
3. **Audit logs** to determine scope of access
4. **Update applications** with new credentials
5. **Review and improve** security practices
6. **Document the incident** and lessons learned

## Additional Resources

- [Kubernetes Secret Management](https://kubernetes.io/docs/concepts/configuration/secret/)
- [External Secrets Operator](https://external-secrets.io/)
- [SOPS by Mozilla](https://github.com/mozilla/sops)
- [age Encryption](https://age-encryption.org/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [HashiCorp Vault](https://www.vaultproject.io/)
