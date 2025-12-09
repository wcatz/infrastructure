# Infrastructure Setup Guide

Complete step-by-step guide for setting up the hybrid Kubernetes infrastructure with Tailscale networking and Cloudflared tunnels.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [1. Tailscale Setup](#1-tailscale-setup)
- [2. Ansible Configuration](#2-ansible-configuration)
- [3. Secret Management](#3-secret-management)
- [4. K3s Cluster Deployment](#4-k3s-cluster-deployment)
- [5. Firewall Configuration](#5-firewall-configuration)
- [6. Cloudflared Tunnel Setup](#6-cloudflared-tunnel-setup)
- [7. GitHub Actions Runner Setup](#7-github-actions-runner-setup)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

## Overview

This guide will walk you through deploying a production-ready hybrid Kubernetes cluster using:

- **Control Plane**: Behind CGNAT/NAT with no public IP required
- **Worker Nodes**: Public IPs for ingress and direct service access
- **Tailscale**: Secure L3 mesh networking for inter-node communication
- **Cloudflared**: HTTP/HTTPS ingress via Cloudflare tunnels (no load balancer required)
- **NodePort**: Direct TCP/UDP service exposure on worker nodes
- **K3s**: Lightweight Kubernetes distribution

### Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              Internet                                     │
└─────────────────────────┬────────────────────────────┬───────────────────┘
                          │                            │
                  ┌───────▼────────┐          ┌────────▼─────────┐
                  │  Cloudflare    │          │   Direct TCP/UDP │
                  │  Edge Network  │          │   Connections    │
                  └───────┬────────┘          └────────┬─────────┘
                          │                            │
                          │ Secure Tunnel              │ NodePort
                          │ (HTTP/HTTPS)               │ (30000-32767)
                          │                            │
            ┌─────────────▼────────────┐   ┌───────────▼──────────────┐
            │   Cloudflared Pod        │   │   Worker Public IP       │
            │   (Worker Node)          │   │   e.g., 1.2.3.4:30001    │
            └─────────────┬────────────┘   └───────────┬──────────────┘
                          │                            │
                          └────────────┬───────────────┘
                                       │
                          ┌────────────▼─────────────┐
                          │   Kubernetes Services    │
                          │   ClusterIP / NodePort   │
                          └────────────┬─────────────┘
                                       │
                          ┌────────────▼─────────────┐
                          │    Application Pods      │
                          │  (HTTP/S + TCP/UDP)      │
                          └──────────────────────────┘

Control Plane ←──→ Tailscale VPN ←──→ Worker Nodes
 (CGNAT/Home)      (100.64.0.0/10)      (Public IP)
```

## Prerequisites

### Hardware/Infrastructure Requirements

**Control Plane Node:**
- Fresh Ubuntu 20.04+ or Debian 11+ installation
- Minimum 1GB RAM, 10GB disk
- Network access (can be behind CGNAT/NAT)
- SSH access configured

**Worker Node(s):**
- Fresh Ubuntu 20.04+ or Debian 11+ installation
- Minimum 2GB RAM, 20GB disk
- **Public IP address** (required for direct service access)
- SSH access configured

### Accounts & Services

- **Tailscale Account**: Free tier works ([signup](https://login.tailscale.com/start))
- **Cloudflare Account**: Free tier for DNS and tunnels ([signup](https://dash.cloudflare.com/sign-up))
- **Domain**: Registered domain managed in Cloudflare DNS
- **GitHub Account**: For CI/CD integration (optional)

### Local Tools Installation

#### macOS
```bash
brew install ansible kubectl helm helmfile sops age cloudflared
```

#### Linux (Debian/Ubuntu)
```bash
# Install Ansible
sudo apt-get update
sudo apt-get install -y ansible kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
  x86_64) HELMFILE_ARCH="amd64"; AGE_ARCH="amd64" ;;
  aarch64|arm64) HELMFILE_ARCH="arm64"; AGE_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Install Helmfile
wget https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_${HELMFILE_ARCH}
chmod +x helmfile_linux_${HELMFILE_ARCH}
sudo mv helmfile_linux_${HELMFILE_ARCH} /usr/local/bin/helmfile

# Install Helm diff plugin
helm plugin install https://github.com/databus23/helm-diff

# Install SOPS
wget https://github.com/mozilla/sops/releases/latest/download/sops-latest.linux
chmod +x sops-latest.linux
sudo mv sops-latest.linux /usr/local/bin/sops

# Install age
wget https://github.com/FiloSottile/age/releases/latest/download/age-latest-linux-${AGE_ARCH}.tar.gz
tar xzf age-latest-linux-${AGE_ARCH}.tar.gz
sudo mv age/age* /usr/local/bin/
rm -rf age age-latest-linux-${AGE_ARCH}.tar.gz

# Install Cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
```

### Validate Prerequisites

After installing the required tools, validate your environment:

```bash
# Run the prerequisite validation script
./scripts/validate-prereqs.sh
```

The validation script checks:
- **Required Tools**: Verifies installation of ansible, kubectl, helm, helmfile, sops, age, and other dependencies
- **Credentials**: Checks for Ansible vault files, SOPS age keys, Cloudflare tokens, and Tailscale authentication
- **Connectivity**: Tests access to Kubernetes cluster, Tailscale network, container registries, and external services

**Expected Output:**
- ✅ Green checkmarks indicate successful checks
- ⚠️  Yellow warnings indicate optional components or recommended configurations
- ❌ Red errors indicate missing required components that must be resolved

## 1. Tailscale Setup

Tailscale provides secure L3 mesh networking for inter-node communication in the hybrid cluster.

### 1.1. Generate Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Configure:
   - **Description**: `k3s-hybrid-cluster`
   - **Reusable**: ✓ (to use for multiple nodes)
   - **Ephemeral**: ✗ (keep nodes persistent)
   - **Tags**: `tag:k8s` (for ACL organization)
   - **Expiration**: Set appropriate expiration (e.g., 90 days)
4. Copy the generated key (starts with `tskey-auth-`)

### 1.2. Configure Tailscale ACLs

For enhanced security, configure access control lists in Tailscale admin console:

1. Go to **Tailscale Admin Console** → **Access Controls**
2. Add the following ACL configuration:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:k8s"],
      "dst": ["tag:k8s:*"]
    },
    {
      "action": "accept",
      "src": ["tag:control-plane"],
      "dst": ["tag:worker:6443"]
    },
    {
      "action": "accept",
      "src": ["tag:worker"],
      "dst": ["tag:control-plane:6443,10250"]
    },
    {
      "action": "accept",
      "src": ["tag:ci", "tag:github-runner"],
      "dst": ["tag:control-plane:6443,10250"]
    },
    {
      "action": "accept",
      "src": ["tag:ci", "tag:github-runner"],
      "dst": ["tag:worker:*"]
    }
  ],
  "tagOwners": {
    "tag:k8s": ["autogroup:admin"],
    "tag:control-plane": ["autogroup:admin"],
    "tag:worker": ["autogroup:admin"],
    "tag:ci": ["autogroup:admin"],
    "tag:github-runner": ["autogroup:admin"]
  }
}
```

**Key ACL Rules:**
- All k8s nodes can communicate with each other
- Workers can access control plane on port 6443 (Kubernetes API)
- Control plane can access workers on port 10250 (kubelet)
- GitHub runners can access control plane and workers for CI/CD

## 2. Ansible Configuration

### 2.1. Clone Repository

```bash
git clone https://github.com/wcatz/infrastructure.git
cd infrastructure/ansible
```

### 2.2. Configure Ansible Vault

Ansible Vault encrypts sensitive data like K3s tokens and Tailscale keys.

```bash
# Create vault password file
cp .vault_pass.example .vault_pass
echo "your-secure-vault-password" > .vault_pass
chmod 600 .vault_pass

# Create vault variables
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
```

Edit `group_vars/all/vault.yml` and add your secrets:

```yaml
---
# K3s cluster token (generate with: openssl rand -hex 32)
vault_k3s_token: "your-k3s-token-here"

# Tailscale auth key from section 1.1
vault_tailscale_key: "tskey-auth-your-key-here"
```

Encrypt the vault file:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

**Common Ansible Vault Commands:**

```bash
# Edit encrypted vault
ansible-vault edit group_vars/all/vault.yml

# View encrypted vault
ansible-vault view group_vars/all/vault.yml

# Change vault password
ansible-vault rekey group_vars/all/vault.yml
```

### 2.3. Configure Inventory

```bash
cp inventory.ini.example inventory.ini
```

Edit `inventory.ini` with your server details:

```ini
[k3s_servers]
# Control plane - use local IP initially, will update to Tailscale IP later
k3s-control ansible_host=192.168.1.100 ansible_user=youruser k3s_node_taint=true

[k3s_agents]
# Worker node(s) - use public IP
k3s-worker-01 ansible_host=1.2.3.4 ansible_user=youruser k3s_node_label="node-role=worker"

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 2.4. Test Connectivity

```bash
ansible all -i inventory.ini -m ping
```

All nodes should respond with `SUCCESS`.

## 3. Secret Management

This infrastructure uses a comprehensive, multi-layered secret management approach:
- **Ansible Vault**: For infrastructure secrets (K3s token, Tailscale keys)
- **SOPS with age**: For Kubernetes secrets and Helmfile values
- **GitHub Secrets**: For CI/CD credentials
- **GitHub Secret Scanning**: Automated detection and prevention

> **📚 Complete Secret Management Guide**: See [SECRETS.md](../SECRETS.md) for comprehensive documentation

### 3.1. SOPS Setup (for Kubernetes Secrets)

SOPS (Secrets OPerationS) with age encryption allows you to safely store encrypted secrets in Git.

#### Quick Start

**1. Install age and SOPS**

Already installed in prerequisites section. Verify:

```bash
sops --version
age --version
```

**2. Generate age Encryption Key**

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

**⚠️ CRITICAL: Backup your private key immediately!**

The private key in `~/.config/sops/age/keys.txt` is required to decrypt all secrets. Without it, you cannot recover encrypted data.

```bash
# Backup methods:

# Method 1: Store in password manager (recommended)
cat ~/.config/sops/age/keys.txt
# Copy and save in 1Password, Bitwarden, etc.

# Method 2: Encrypt with GPG
gpg -c ~/.config/sops/age/keys.txt
# Save the .gpg file to secure backup location

# Method 3: Copy to encrypted USB
cp ~/.config/sops/age/keys.txt /Volumes/SecureUSB/age-key-backup.txt
```

**3. Update .sops.yaml Configuration**

The repository includes a `.sops.yaml` file. Update it with your public key:

```bash
# Get your public key
PUBLIC_KEY=$(cat ~/.config/sops/age/keys.txt | grep "public key:" | cut -d: -f2 | tr -d ' ')

# Update .sops.yaml (macOS)
sed -i '' "s/age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/$PUBLIC_KEY/g" .sops.yaml

# Update .sops.yaml (Linux)
sed -i "s/age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/$PUBLIC_KEY/g" .sops.yaml

# Verify
cat .sops.yaml
```

**4. Add to GitHub Secrets (for CI/CD)**

For GitHub Actions to decrypt secrets:

```bash
# Using GitHub CLI (recommended)
gh secret set SOPS_AGE_KEY < ~/.config/sops/age/keys.txt

# Or manually via web UI:
# 1. Go to repository Settings → Secrets and variables → Actions
# 2. Click "New repository secret"
# 3. Name: SOPS_AGE_KEY
# 4. Value: Paste entire content of ~/.config/sops/age/keys.txt
# 5. Click "Add secret"
```

#### Using SOPS

**Encrypt a Secret:**

```bash
# Create secret
cat > helmfile/secrets/app-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: app-credentials
  namespace: default
type: Opaque
stringData:
  username: admin
  password: supersecret
  api-key: abc123xyz789
EOF

# Encrypt with SOPS
sops -e helmfile/secrets/app-secret.yaml > helmfile/secrets/app-secret.enc.yaml

# Delete plaintext (important!)
rm helmfile/secrets/app-secret.yaml

# Commit encrypted file
git add helmfile/secrets/app-secret.enc.yaml
git commit -m "Add app credentials"
```

**Deploy Encrypted Secret:**

```bash
# Set environment variable
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Decrypt and apply to Kubernetes
sops -d helmfile/secrets/app-secret.enc.yaml | kubectl apply -f -

# Verify
kubectl get secret app-credentials -n default
```

**Edit Encrypted Secret:**

```bash
# SOPS automatically decrypts, opens in $EDITOR, and re-encrypts
sops helmfile/secrets/app-secret.enc.yaml

# Make changes, save, and commit
git add helmfile/secrets/app-secret.enc.yaml
git commit -m "Update app credentials"
```

### 3.2. Ansible Vault (for Infrastructure Secrets)

Ansible Vault encrypts sensitive Ansible variables used during infrastructure provisioning.

**1. Create Vault Password**

```bash
cd ansible

# Copy example
cp .vault_pass.example .vault_pass

# Generate strong password
openssl rand -base64 32 > .vault_pass

# Secure the file
chmod 600 .vault_pass
```

**Important:** Never commit `.vault_pass` to Git (it's gitignored).

**2. Create and Encrypt Vault Variables**

```bash
# Copy example
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit with your secrets
vim group_vars/all/vault.yml
```

Add your actual secrets:

```yaml
---
# K3s cluster token (generate with: openssl rand -hex 32)
vault_k3s_token: "your-k3s-token-here"

# Tailscale auth key from Tailscale admin console
vault_tailscale_key: "tskey-auth-your-key-here"
```

**3. Encrypt the Vault**

```bash
# Encrypt
ansible-vault encrypt group_vars/all/vault.yml

# Verify encryption
cat group_vars/all/vault.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256...
```

**Common Vault Commands:**

```bash
# Edit encrypted vault
ansible-vault edit group_vars/all/vault.yml

# View encrypted vault
ansible-vault view group_vars/all/vault.yml

# Change vault password
ansible-vault rekey group_vars/all/vault.yml
```

### 3.3. GitHub Secret Scanning and Push Protection

GitHub provides built-in security features to prevent secret leaks.

#### Enable Secret Scanning

1. Go to repository **Settings** → **Code security and analysis**
2. Enable **Secret scanning**
   - Automatically detects secrets in commits, issues, and discussions
   - Alerts you when secrets are found
   - Supports 200+ secret types (API keys, tokens, certificates)

3. Enable **Push protection**
   - Prevents pushing commits containing secrets
   - Blocks the push and provides remediation guidance
   - Can be bypassed in emergencies (with audit trail)

#### Verify Protection is Active

```bash
# Check secret scanning status
gh api repos/wcatz/infrastructure | jq '.security_and_analysis.secret_scanning.status'
# Expected: "enabled"

# Check push protection status
gh api repos/wcatz/infrastructure | jq '.security_and_analysis.secret_scanning_push_protection.status'
# Expected: "enabled"
```

#### Test Push Protection

Create a test commit with a fake secret to verify protection:

```bash
# Create test file with fake secret
echo "github_token: ghp_1234567890abcdefghijklmnopqrstuvwxyz12" > test-secret.txt

# Try to commit and push
git add test-secret.txt
git commit -m "Test push protection"
git push

# Expected result: Push should be blocked with message:
# "Push protection: Secret detected in commit"

# Clean up
git reset HEAD~1
rm test-secret.txt
```

### 3.4. CI/CD Integration

Configure secrets for GitHub Actions workflows:

```bash
# Set SOPS age key (already done in 3.1 step 4)
gh secret set SOPS_AGE_KEY < ~/.config/sops/age/keys.txt

# Set Ansible vault password
gh secret set ANSIBLE_VAULT_PASSWORD < ansible/.vault_pass

# Set kubeconfig for deployments (after cluster setup)
base64 -w 0 ~/.kube/config | gh secret set KUBECONFIG_PRODUCTION --body-file=-
```

Verify secrets are set:

```bash
gh secret list
```

See [SECRETS.md - CI/CD Integration](../SECRETS.md#cicd-integration) for complete workflow examples.

### 3.5. Secret Rotation Best Practices

**Rotation Schedule:**

| Secret Type | Frequency | Tool |
|-------------|-----------|------|
| SOPS age keys | Annually | Manual |
| Ansible vault password | Annually | ansible-vault rekey |
| Cloudflared credentials | 90 days | Manual |
| Database passwords | 180 days | Manual |
| API tokens | 90 days | Manual |
| SSH keys | 365 days | ssh-keygen |
| TLS certificates | 90 days | cert-manager (automated) |

**Rotation Procedures:**

See [SECRETS.md - Secret Rotation](../SECRETS.md#secret-rotation) for detailed rotation procedures for each secret type.

**Rotation Reminders:**

Set calendar reminders or use GitHub Issues with due dates:

```bash
# Create rotation reminder issue
gh issue create --title "Quarterly Secret Rotation" \
  --body "Rotate Cloudflared credentials and API tokens" \
  --label "security,maintenance" \
  --milestone "Q2-2024"
```

### 3.6. Periodic Security Audits

Regular audits ensure secrets remain secure:

**Monthly:**
- Review GitHub secret scanning alerts
- Verify push protection is active
- Check access logs for unusual activity

**Quarterly:**
- Rotate short-lived secrets (Cloudflared, API tokens)
- Audit SOPS age keys (remove departed team members)
- Review GitHub Actions secrets usage

**Semi-Annually:**
- Rotate database passwords
- Run security code scanning
- Dependency vulnerability scanning

**Annually:**
- Rotate SOPS age encryption keys
- Rotate Ansible vault passwords
- Rotate SSH keys
- Comprehensive security review

See [SECRETS.md - Periodic Audits and Maintenance](../SECRETS.md#periodic-audits-and-maintenance) for detailed audit checklists and procedures.

## 4. K3s Cluster Deployment

### 4.1. Install Tailscale on All Nodes

```bash
cd ansible
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml
```

**Get Tailscale IPs after installation:**

```bash
# SSH to each node
ssh user@control-plane
tailscale ip -4  # Note this IP (e.g., 100.64.1.10)

ssh user@worker-01
tailscale ip -4  # Note this IP (e.g., 100.64.1.20)
```

### 4.2. Update Inventory with Tailscale IPs

Edit `inventory.ini` to use Tailscale IP for control plane:

```ini
[k3s_servers]
k3s-control ansible_host=100.64.1.10 ansible_user=youruser k3s_node_taint=true
```

This ensures the K3s API server is accessible via Tailscale.

### 4.3. Deploy K3s Cluster

```bash
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml
```

This will:
- Install K3s server on control plane
- Install K3s agent on worker nodes
- Apply NoSchedule taint to control plane
- Label worker nodes
- Configure K3s to use Tailscale for inter-node communication

### 4.4. Verify Cluster

#### Get Kubeconfig

```bash
# From your local machine (must have Tailscale installed)
scp youruser@100.64.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update server URL to use Tailscale IP
sed -i 's/127.0.0.1/100.64.1.10/' ~/.kube/config
```

**Important**: Your local machine needs Tailscale installed and connected!

#### Test Cluster Access

```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

Expected output:
```
NAME            STATUS   ROLES                  AGE   VERSION
k3s-control     Ready    control-plane,master   5m    v1.28.5+k3s1
k3s-worker-01   Ready    <none>                 3m    v1.28.5+k3s1
```

#### Verify Control Plane Taint

```bash
kubectl describe node k3s-control | grep Taints
# Expected: node-role.kubernetes.io/control-plane:NoSchedule
```

#### Deploy Test Pod

```bash
kubectl run test-nginx --image=nginx:alpine --port=80

# Wait for pod to be running
kubectl get pods -w

# Verify it's on a worker node, not control plane
kubectl get pod test-nginx -o wide

# Cleanup
kubectl delete pod test-nginx
```

## 5. Firewall Configuration

Proper firewall configuration is critical for security in the hybrid cluster architecture.

### 5.1. Control Plane Firewall Rules

Control plane nodes run only the K3s server and are typically behind CGNAT/NAT. All access is through Tailscale.

#### UFW Configuration (Ubuntu/Debian)

```bash
# ⚠️ WARNING: This will reset all firewall rules!
# Ensure you have console/physical access before running this.

# Reset UFW
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow loopback
sudo ufw allow in on lo

# Allow SSH from Tailscale network
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH from Tailscale'

# Allow Kubernetes API from Tailscale network only
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp comment 'K8s API server'

# Allow Kubelet API from Tailscale network only
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp comment 'Kubelet API'

# Allow Tailscale
sudo ufw allow 41641/udp comment 'Tailscale WireGuard'

# Explicitly deny public access to Kubernetes API
sudo ufw deny 6443/tcp comment 'Block public K8s API'

# Enable firewall
sudo ufw --force enable

# Verify rules
sudo ufw status numbered
```

### 5.2. Worker Node Firewall Rules

Worker nodes have public IPs and run all application workloads. They expose services via Cloudflared tunnels and NodePorts.

#### UFW Configuration (Ubuntu/Debian)

```bash
# ⚠️ WARNING: This will reset all firewall rules!
# Ensure you have console/physical access before running this.

# Reset UFW
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow loopback
sudo ufw allow in on lo

# Allow SSH from Tailscale network
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH from Tailscale'

# Allow Kubelet API from Tailscale network
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp comment 'Kubelet API'

# Allow Tailscale
sudo ufw allow 41641/udp comment 'Tailscale WireGuard'

# Add specific NodePorts as needed for your services
# Example: Web service on NodePort 30080
# sudo ufw allow 30080/tcp comment 'NodePort: web-service'

# Example: Rate limit public NodePort to prevent DoS
# sudo ufw limit 30080/tcp

# Enable firewall
sudo ufw --force enable

# Verify rules
sudo ufw status numbered
```

**Important Firewall Notes:**
- ✅ **NO public ingress to control plane** - All access via Tailscale only
- ⚠️ **Selective NodePort exposure on workers** - Only open specific ports needed
- ✅ **Cloudflared handles HTTP/S** - No need to expose ports 80/443 publicly
- ⚠️ **Rate limiting** - Use `ufw limit` for exposed NodePorts

### 5.3. Port Reference

**Kubernetes Ports:**
- 6443/tcp: Kubernetes API Server (control plane)
- 10250/tcp: Kubelet API
- 30000-32767/tcp+udp: NodePort service range

**Tailscale Ports:**
- 41641/udp: WireGuard tunnel endpoint
- 443/tcp: Control plane (outbound only)

## 6. Cloudflared Tunnel Setup

Cloudflared creates secure tunnels for HTTP/HTTPS ingress without opening firewall ports.

### 6.1. Install Cloudflared CLI

Already installed in the prerequisites section.

### 6.2. Authenticate with Cloudflare

```bash
cloudflared tunnel login
```

This opens a browser to authenticate and select your domain.

### 6.3. Create Tunnel

```bash
cloudflared tunnel create infrastructure-tunnel
```

**Save the output:**
- Tunnel ID: `<TUNNEL-ID>`
- Credentials file: `~/.cloudflared/<TUNNEL-ID>.json`

### 6.4. Create Kubernetes Secret

```bash
# Create namespace
kubectl create namespace cloudflare

# Create secret from credentials file
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
  -n cloudflare
```

### 6.5. Configure DNS Routes

```bash
# Route hostnames to your tunnel
cloudflared tunnel route dns infrastructure-tunnel app.example.com
cloudflared tunnel route dns infrastructure-tunnel api.example.com
```

### 6.6. Update Cloudflared Values

Edit `helmfile/values/cloudflared-values.yaml`:

```yaml
cloudflare:
  tunnelName: "infrastructure-tunnel"
  tunnelId: "<TUNNEL-ID>"

ingress:
  # Route directly to your Kubernetes services
  - hostname: app.example.com
    service: http://my-web-app.default.svc.cluster.local:80
  - hostname: api.example.com
    service: http://my-api.default.svc.cluster.local:8080
  # Catch-all
  - service: http_status:404
```

### 6.7. Enable and Deploy Cloudflared

Edit `helmfile/config/enabled.yaml`:

```yaml
enabled:
  cloudflared: true  # Change from false to true
```

Deploy via Helmfile:

```bash
cd helmfile
helmfile apply
```

### 6.8. Verify Cloudflared

```bash
kubectl get pods -n cloudflare
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared
```

## 7. GitHub Actions Runner Setup

Set up a self-hosted GitHub Actions runner with Tailscale connectivity to access the Kubernetes control plane.

### 7.1. Create Tailscale Auth Key for Runner

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Generate a new auth key
3. Configure:
   - **Description**: `github-runner`
   - **Reusable**: ✓
   - **Ephemeral**: ✓ (recommended for runners)
   - **Tags**: `tag:github-runner,tag:ci`

### 7.2. Kubernetes-Based Runner (Recommended)

#### Create Secrets

```bash
# Create namespace
kubectl create namespace github-runner

# Create GitHub runner token secret
# Get token from: https://github.com/OWNER/REPO/settings/actions/runners/new
kubectl create secret generic github-runner-token \
  --from-literal=token=YOUR_GITHUB_REGISTRATION_TOKEN \
  -n github-runner

# Create Tailscale auth key secret
kubectl create secret generic tailscale-auth \
  --from-literal=authkey=YOUR_TAILSCALE_AUTH_KEY \
  -n github-runner
```

#### Deploy Runner via Helmfile

The runner chart is already configured in the Helmfile.

Enable it in `helmfile/config/enabled.yaml`:

```yaml
enabled:
  githubRunner: true
```

Deploy:

```bash
cd helmfile
helmfile apply
```

#### Verify Runner

```bash
kubectl get pods -n github-runner
kubectl logs -n github-runner -l app=github-runner
```

Check GitHub repository settings to see the runner online.

### 7.3. Usage in Workflows

Use the self-hosted runner in your GitHub Actions workflows:

```yaml
jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy to Kubernetes
        run: |
          kubectl apply -f manifests/
          
      - name: Run Helmfile
        run: |
          cd helmfile
          helmfile apply
```

## Troubleshooting

### Control Plane Not Accessible

**Problem**: Cannot connect to K3s API server

```bash
# Check Tailscale connectivity
tailscale ping 100.64.1.10

# Verify K3s is running
ssh user@100.64.1.10
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### Worker Not Joining Cluster

**Problem**: Worker node shows as NotReady or doesn't appear

```bash
# On worker node, check agent status
ssh user@worker-01
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -f

# Verify Tailscale connectivity to control plane
tailscale ping 100.64.1.10

# Check K3s agent can reach control plane API
curl -k https://100.64.1.10:6443
```

### Pods Not Scheduling

**Problem**: Pods stuck in Pending state

```bash
kubectl describe pod <pod-name>

# Check if control plane taint is correctly applied
kubectl get nodes -o json | jq '.items[].spec.taints'

# Check node resources
kubectl describe node <worker-node>
```

### Cloudflared Not Connecting

**Problem**: Cloudflared pods crash or tunnel not connecting

```bash
# Check credentials secret
kubectl get secret cloudflared-credentials -n cloudflare -o yaml

# Check pod logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Verify tunnel status
cloudflared tunnel info infrastructure-tunnel

# Check DNS records
dig app.example.com
```

## Next Steps

Congratulations! Your hybrid Kubernetes cluster is now set up. Next steps:

1. **Deploy Services**: See [docs/helmfile.md](helmfile.md) for service deployment
2. **Operations Guide**: See [docs/operate.md](operate.md) for testing, monitoring, and maintenance
3. **Deploy Applications**: See [docs/operate.md#kubernetes-workload-examples](operate.md#kubernetes-workload-examples)
4. **Set Up Monitoring**: Configure Prometheus and Grafana dashboards
5. **Implement Disaster Recovery**: See disaster recovery procedures in [docs/operate.md](operate.md#disaster-recovery)

---

[⬅ Back to README](../README.md) | [Next: Ansible Guide ➡](ansible.md)
