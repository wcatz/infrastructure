# GitHub Actions Self-Hosted Runner Setup Guide

This guide explains how to set up a self-hosted GitHub Actions runner with Tailscale connectivity to access the Kubernetes control plane behind CGNAT.

**Two deployment options available:**
1. **Kubernetes-based** (Recommended): Runner deployed as a pod with Tailscale sidecar
2. **Host-based**: Runner installed directly on worker node

## Table of Contents

- [Overview](#overview)
- [Deployment Options](#deployment-options)
  - [Option 1: Kubernetes Deployment (Recommended)](#option-1-kubernetes-deployment-recommended)
  - [Option 2: Host-Based Deployment](#option-2-host-based-deployment)
- [Security Configuration](#security-configuration)
- [Usage in Workflows](#usage-in-workflows)
- [Testing and Validation](#testing-and-validation)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

## Overview

This setup solves the challenge of running Kubernetes operations (kubectl, Helm) from GitHub Actions when the control plane is behind CGNAT (Carrier-Grade NAT) and not publicly accessible.

### Solution Benefits

- **No NAT Traversal Required**: Bypasses CGNAT using Tailscale VPN
- **Secure Access**: All traffic encrypted via Tailscale mesh network
- **Seamless kubectl/Helm**: Commands work exactly as they would locally
- **No Public Exposure**: Control plane remains private and secure
- **Cost Effective**: Uses existing infrastructure, no additional servers required
- **Cloud-Native** (Kubernetes option): Declarative, version-controlled, scalable

---

## Deployment Options

### Option 1: Kubernetes Deployment (Recommended)

**Deploy the runner as a Kubernetes pod with Tailscale sidecar.**

✅ **Advantages:**
- Declarative configuration (GitOps-ready)
- Easy scaling (multiple runner replicas)
- Automatic restarts and health checks
- Version controlled with Helm
- No host-level changes needed
- Ephemeral runners for better security

📋 **Requirements:**
- Kubernetes cluster with kubectl access
- Tailscale auth key
- GitHub runner registration token or PAT

#### Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Kubernetes Worker Node (Public IP)                      │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Pod: github-runner-0                               │ │
│  │  ┌──────────────┐      ┌─────────────────────────┐ │ │
│  │  │ Tailscale    │      │ GitHub Runner           │ │ │
│  │  │ Sidecar      │◄────►│ Container               │ │ │
│  │  │              │      │                         │ │ │
│  │  │ - VPN access │      │ - Runs workflows        │ │ │
│  │  │ - Routes to  │      │ - kubectl/helm access   │ │ │
│  │  │   control    │      │ - Service account auth  │ │ │
│  │  └──────────────┘      └─────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────┬─────────────────────────────────────┘
                      │
                      │ Tailscale Mesh (100.64.x.x)
                      ▼
          ┌───────────────────────┐
          │ Control Plane (CGNAT) │
          │ K3s API: 6443         │
          └───────────────────────┘
```

#### Quick Start

**Step 1: Create Secrets**

```bash
# Create namespace
kubectl create namespace github-runner

# Create GitHub runner token secret
# Get token from: https://github.com/OWNER/REPO/settings/actions/runners/new
kubectl create secret generic github-runner-token \
  --from-literal=token=YOUR_GITHUB_REGISTRATION_TOKEN \
  -n github-runner

# Create Tailscale auth key secret
# Get from: https://login.tailscale.com/admin/settings/keys
kubectl create secret generic tailscale-auth \
  --from-literal=authkey=YOUR_TAILSCALE_AUTH_KEY \
  -n github-runner
```

**Step 2: Configure Values**

Edit `helmfile/values/github-runner-values.yaml`:

```yaml
github:
  repository: "https://github.com/YOUR_ORG/YOUR_REPO"

runner:
  replicas: 1
  labels:
    - self-hosted
    - kubernetes
    - tailscale

tailscale:
  enabled: true
  tags:
    - tag:k8s
    - tag:ci
```

**Step 3: Enable in Helmfile**

Edit `helmfile/config/enabled.yaml`:

```yaml
enabled:
  githubRunner: true
```

**Step 4: Deploy**

```bash
cd helmfile
helmfile -l name=github-runner apply
```

**Step 5: Verify**

```bash
# Check pod status
kubectl get pods -n github-runner

# Check runner logs
kubectl logs -n github-runner github-runner-0 -c runner

# Check Tailscale connectivity
kubectl exec -n github-runner github-runner-0 -c tailscale -- tailscale status

# Test kubectl access
kubectl exec -n github-runner github-runner-0 -c runner -- kubectl get nodes
```

**📚 Full Documentation:** See [helmfile/charts/github-runner/README.md](helmfile/charts/github-runner/README.md) for detailed configuration options.

---

### Option 2: Host-Based Deployment

**Install the runner directly on the worker node using Ansible.**

✅ **Advantages:**
- Direct host access (no containerization overhead)
- Simpler for single-runner setups
- Full system access if needed
- Traditional deployment model

⚠️ **Considerations:**
- Requires host-level changes
- Manual scaling (multiple nodes needed for multiple runners)
- Less portable than Kubernetes approach

#### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                       GitHub Actions                     │
│  Workflow (runs-on: [self-hosted, tailscale])          │
└────────────────────┬────────────────────────────────────┘
                     │ HTTPS (GitHub API)
          ┌──────────▼──────────┐
          │  Worker Node        │
          │  (Public IP)        │
          │  ┌──────────────┐   │
          │  │ GitHub       │   │
          │  │ Runner       │   │
          │  │ Service      │   │
          │  └──────────────┘   │
          │  ┌──────────────┐   │
          │  │ Tailscale    │   │
          │  │ Client       │   │
          │  └──────────────┘   │
          └─────────┬───────────┘
                    │ Tailscale Mesh
          ┌─────────▼───────────┐
          │ Control Plane       │
          │ (Behind CGNAT)      │
          │ K3s API: 6443       │
          └─────────────────────┘
```

#### Quick Start

**Prerequisites:**
- Tailscale and k3s already deployed via Ansible
- SSH access to worker node
- Ansible installed locally

**Step 1: Generate GitHub Runner Token**

Get a registration token from:
- GitHub UI: `https://github.com/OWNER/REPO/settings/actions/runners/new`
- Or via GitHub CLI:
  ```bash
  gh api --method POST /repos/OWNER/REPO/actions/runners/registration-token --jq .token
  ```

**Step 2: Configure Inventory**

Edit `ansible/inventory.ini`:

```ini
[k3s_agents]
worker-01 ansible_host=x.x.x.x ansible_user=ubuntu

[all:vars]
github_runner_repository_url=https://github.com/YOUR_ORG/YOUR_REPO
```

**Step 3: Run Ansible Playbook**

```bash
cd ansible

# Deploy runner
ansible-playbook -i inventory.ini \
  playbooks/setup-github-runner.yaml \
  -e "github_runner_token=YOUR_REGISTRATION_TOKEN"
```

**Step 4: Verify Installation**

```bash
# SSH to worker node
ssh user@worker-node

# Check runner service
sudo systemctl status actions.runner.*.service

# Verify Tailscale connectivity
tailscale status

# Test kubectl access
sudo -u github-runner kubectl get nodes
```

**📚 Full Documentation:** See the detailed host-based setup instructions in the sections below.

---

## Comparison: Kubernetes vs Host-Based

| Feature | Kubernetes Deployment | Host-Based Deployment |
|---------|----------------------|----------------------|
| **Deployment** | Helm/Helmfile (declarative) | Ansible (imperative) |
| **Scaling** | Easy (adjust replicas) | Manual (add nodes) |
| **Updates** | Rolling updates | Manual restart |
| **Isolation** | Pod-level | User-level |
| **Portability** | High (runs anywhere Kubernetes runs) | Moderate (tied to host) |
| **Resource Management** | Kubernetes resource limits | Host resources |
| **High Availability** | Built-in (replicas) | Requires multiple nodes |
| **GitOps Ready** | ✅ Yes | Partial |
| **Security** | Pod security policies | Host-level permissions |
| **Recommended For** | Production, multi-runner | Development, single runner |

**Recommendation:** Use **Kubernetes deployment** for production environments. Use **host-based** for development or if you prefer traditional deployment.

---

## Security Configuration

### Tailscale ACL Configuration

Configure Tailscale ACLs to restrict runner access to only necessary services:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:github-runner", "tag:ci"],
      "dst": ["tag:k8s-control-plane:6443,10250"]
    },
    {
      "action": "accept",
      "src": ["tag:k8s-control-plane"],
      "dst": ["tag:github-runner:*", "tag:ci:*"]
    },
    {
      "action": "accept",
      "src": ["tag:github-runner", "tag:ci"],
      "dst": ["tag:k8s-worker:*"]
    }
  ],
  "tagOwners": {
    "tag:github-runner": ["autogroup:admin"],
    "tag:ci": ["autogroup:admin"],
    "tag:k8s-control-plane": ["autogroup:admin"],
    "tag:k8s-worker": ["autogroup:admin"]
  }
}
```

**Key ACL Rules:**
- Runners can access control plane on port 6443 (Kubernetes API) and 10250 (kubelet)
- Control plane can respond to runners
- Runners can access worker nodes for service endpoints
- All other traffic is implicitly denied

### GitHub Repository Security

#### 1. Use Runner Groups (GitHub Enterprise/Organizations)

For better control, create a runner group:

1. Go to **Organization Settings** → **Actions** → **Runner groups**
2. Create a new group (e.g., "Production Kubernetes")
3. Limit which repositories can use this group
4. Assign runners to this group during setup

#### 2. Limit Runner Scope with Labels

Configure runners with specific labels:

```yaml
# Kubernetes deployment
runner:
  labels:
    - self-hosted
    - kubernetes
    - tailscale
    - production  # Environment-specific

# Host-based deployment
github_runner_labels: "self-hosted,tailscale,k8s,production"
```

Then in workflows, be specific:

```yaml
runs-on: [self-hosted, tailscale, kubernetes, production]
```

#### 3. Use GitHub Secrets for Sensitive Data

Never hardcode sensitive information. Use GitHub Secrets:

```yaml
env:
  SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
  CUSTOM_TOKEN: ${{ secrets.CUSTOM_TOKEN }}
```

#### 4. Use Environment Protection Rules

For production deployments, enable environment protection:

1. Go to **Repository Settings** → **Environments**
2. Create environment (e.g., "production")
3. Configure:
   - Required reviewers
   - Wait timer
   - Deployment branches
4. Use in workflow:
   ```yaml
   jobs:
     deploy:
       environment: production
       runs-on: [self-hosted, tailscale]
   ```

#### 5. Rotate Tokens Regularly

**GitHub Runner Tokens:**
- Registration tokens expire after 1 hour (secure by default)
- For long-term runners, use GitHub Apps or PATs
- Rotate PATs quarterly

**Tailscale Auth Keys:**
- Set expiration (90 days recommended)
- Use reusable, non-ephemeral keys for runners
- Rotate before expiration
- Store in Kubernetes secrets or Ansible Vault

### Kubernetes RBAC Security

#### Principle of Least Privilege

The default ClusterRole provides broad permissions. For production:

**Option 1: Namespace-Scoped Permissions**

```yaml
# In values file
kubernetes:
  rbac:
    clusterRole: false  # Use Role instead of ClusterRole
```

**Option 2: Custom ClusterRole**

Create a custom role with minimal permissions:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: github-runner-limited
rules:
  # Read-only cluster access
  - apiGroups: [""]
    resources: ["nodes", "namespaces"]
    verbs: ["get", "list", "watch"]
  
  # Full access to specific namespaces only
  - apiGroups: ["", "apps", "batch"]
    resources: ["*"]
    verbs: ["*"]
    # Restrict to specific namespaces via RoleBinding
```

#### Audit Logging

Enable audit logging to track runner actions:

```bash
# View runner service account activity
kubectl get events -n github-runner

# Check pod logs
kubectl logs -n github-runner github-runner-0 -c runner

# View API server audit logs (if enabled)
kubectl logs -n kube-system kube-apiserver-* | grep github-runner
```

### Network Security

#### Firewall Rules

**On Worker Node:**
```bash
# Allow outbound to Tailscale control plane
sudo ufw allow out to 100.64.0.0/10

# Allow outbound HTTPS to GitHub
sudo ufw allow out 443/tcp

# Deny all other outbound by default (optional, very strict)
# sudo ufw default deny outgoing
```

**On Control Plane:**
```bash
# Allow from Tailscale network only
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp

# Deny public access to API server
sudo ufw deny 6443/tcp
```

#### Network Policies

Use Kubernetes Network Policies to restrict pod traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: github-runner-policy
  namespace: github-runner
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: github-runner
  policyTypes:
    - Egress
  egress:
    # Allow DNS
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53
    
    # Allow Tailscale
    - to:
        - ipBlock:
            cidr: 100.64.0.0/10
    
    # Allow GitHub API
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
    
    # Allow Kubernetes API
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 6443
```

### Security Checklist

Before deploying to production:

- [ ] **Tailscale ACLs** configured to restrict runner access
- [ ] **GitHub runner tokens** stored securely (Kubernetes secrets or Ansible Vault)
- [ ] **Tailscale auth keys** have expiration set (90 days max)
- [ ] **RBAC permissions** follow least privilege principle
- [ ] **Environment protection** rules enabled for production deployments
- [ ] **Runner labels** are specific and meaningful
- [ ] **Firewall rules** configured on worker and control plane
- [ ] **Network policies** applied (Kubernetes deployment)
- [ ] **Audit logging** enabled for runner actions
- [ ] **Secrets rotation** schedule established (quarterly)
- [ ] **Runner ephemeral mode** enabled (Kubernetes) for one-time jobs
- [ ] **Control plane** not exposed to public internet
- [ ] **Workflow approval** required for sensitive operations
- [ ] **Service account** has minimal necessary permissions
- [ ] **Pod security** standards applied (Kubernetes deployment)

---

```
┌─────────────────────────────────────────────────────────────────┐
│                       GitHub Actions                             │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  Workflow (runs-on: [self-hosted, tailscale])            │ │
│  │  - Deploy with Helm                                       │ │
│  │  - Run kubectl commands                                   │ │
│  │  - Access cluster via Tailscale                           │ │
│  └────────────────────────┬─────────────────────────────────┘ │
└─────────────────────────────┼────────────────────────────────────┘
                              │
                              │ HTTPS (GitHub API)
                              │
                    ┌─────────▼──────────┐
                    │  Worker Node       │
                    │  (Public IP)       │
                    │                    │
                    │  ┌──────────────┐  │
                    │  │ GitHub       │  │
                    │  │ Actions      │  │
                    │  │ Runner       │  │
                    │  └──────┬───────┘  │
                    │         │          │
                    │  ┌──────▼───────┐  │
                    │  │ Tailscale    │  │
                    │  │ Client       │  │
                    │  └──────┬───────┘  │
                    └─────────┼──────────┘
                              │
                              │ Tailscale Mesh
                              │ (100.64.x.x)
                              │
                    ┌─────────▼──────────┐
                    │ Control Plane      │
                    │ (Behind CGNAT)     │
                    │                    │
                    │  ┌──────────────┐  │
                    │  │ K3s Server   │  │
                    │  │ Port 6443    │  │
                    │  └──────────────┘  │
                    │                    │
                    │  ┌──────────────┐  │
                    │  │ Tailscale    │  │
                    │  │ Client       │  │
                    │  └──────────────┘  │
                    └────────────────────┘
```

### Traffic Flow

1. **GitHub Actions** triggers workflow
2. **Self-hosted runner** on worker node picks up job
3. Runner executes **kubectl/helm commands**
4. Commands connect to control plane via **Tailscale IP** (100.64.x.x:6443)
5. **Tailscale mesh** encrypts and routes traffic through CGNAT
6. **Control plane** receives and processes requests
7. Responses flow back through same secure channel

## Prerequisites

### Infrastructure Requirements

- **Worker Node**: Public VPS with Tailscale and k3s agent installed
- **Control Plane**: k3s server with Tailscale (can be behind CGNAT)
- **Tailscale**: Both nodes connected to same Tailscale network
- **GitHub Repository**: Where you want to run workflows

### Completed Setup Steps

Before setting up the runner, ensure you have completed:

1. ✅ Tailscale deployed on all nodes ([TAILSCALE_SETUP.md](TAILSCALE_SETUP.md))
2. ✅ k3s cluster deployed ([HYBRID_CLUSTER_SETUP.md](HYBRID_CLUSTER_SETUP.md))
3. ✅ Worker nodes can access control plane via Tailscale

Verify prerequisites:

```bash
# On worker node - verify Tailscale connectivity
tailscale status
ping <control-plane-tailscale-ip>

# On worker node - verify k3s is running
systemctl status k3s

# Test kubectl access (should work from worker node)
kubectl get nodes
```

## Setup Instructions

### Step 1: Generate GitHub Runner Token

You need a registration token to authenticate the runner with your GitHub repository.

#### Option A: Via GitHub Web UI (Recommended for first-time setup)

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Actions** → **Runners**
3. Click **New self-hosted runner**
4. Select **Linux** as the operating system
5. Copy the token from the configuration command (it looks like `AABBCC...`)

**Note**: These tokens expire after 1 hour, so generate them just before running the Ansible playbook.

#### Option B: Via GitHub CLI (Recommended for automation)

```bash
# Install GitHub CLI if not already installed
# macOS: brew install gh
# Linux: See https://github.com/cli/cli#installation

# Authenticate
gh auth login

# Generate a registration token
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/OWNER/REPO/actions/runners/registration-token \
  --jq .token
```

#### Option C: Via GitHub API (For CI/CD)

```bash
# Using a personal access token with 'repo' scope
curl -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer YOUR_PAT_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/OWNER/REPO/actions/runners/registration-token
```

### Step 2: Store Token in Ansible Vault (Recommended)

For security, store the runner token in Ansible Vault:

```bash
cd ansible

# Edit encrypted vault
ansible-vault edit group_vars/all/vault.yml

# Add the following line (replace with your token):
vault_github_runner_token: "YOUR_REGISTRATION_TOKEN"
```

### Step 3: Configure Inventory

Edit your inventory file to specify which node should run the GitHub Actions runner:

```bash
cd ansible
vim inventory.ini
```

Example inventory:

```ini
[k3s_servers]
control-plane ansible_host=192.168.1.100 ansible_user=ubuntu

[k3s_agents]
worker-01 ansible_host=x.x.x.x ansible_user=ubuntu

[all:vars]
ansible_python_interpreter=/usr/bin/python3

# GitHub runner configuration
github_runner_repository_url=https://github.com/YOUR_ORG/YOUR_REPO
```

### Step 4: Run the Ansible Playbook

Deploy the GitHub Actions runner:

```bash
cd ansible

# If using Ansible Vault for token
ansible-playbook -i inventory.ini \
  playbooks/setup-github-runner.yaml \
  -e "github_runner_token={{ vault_github_runner_token }}"

# Or pass token directly (less secure - token visible in shell history)
ansible-playbook -i inventory.ini \
  playbooks/setup-github-runner.yaml \
  -e "github_runner_repository_url=https://github.com/OWNER/REPO" \
  -e "github_runner_token=YOUR_REGISTRATION_TOKEN"
```

The playbook will:
- ✅ Install runner dependencies
- ✅ Create dedicated runner user
- ✅ Download and configure GitHub Actions runner
- ✅ Install as systemd service
- ✅ Configure kubectl with Tailscale connectivity
- ✅ Test connectivity to control plane
- ✅ Verify kubectl access

### Step 5: Verify Installation

Check the runner status:

```bash
# On the worker node
sudo systemctl status actions.runner.YOUR_ORG-YOUR_REPO.*.service

# View runner logs
sudo journalctl -u actions.runner.YOUR_ORG-YOUR_REPO.*.service -f
```

Verify in GitHub UI:
1. Go to your repository **Settings** → **Actions** → **Runners**
2. You should see your runner listed as "Idle" (green) or "Active" (green)

## Security Configuration

### Tailscale ACL Configuration

Configure Tailscale ACLs to allow the runner to access the control plane:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:k8s-worker"],
      "dst": ["tag:k8s-control-plane:6443,10250"]
    },
    {
      "action": "accept",
      "src": ["tag:k8s-control-plane"],
      "dst": ["tag:k8s-worker:*"]
    }
  ],
  "tagOwners": {
    "tag:k8s-worker": ["autogroup:admin"],
    "tag:k8s-control-plane": ["autogroup:admin"]
  }
}
```

Key ports:
- **6443**: Kubernetes API server
- **10250**: Kubelet API

### GitHub Repository Security

#### Use Runner Groups (GitHub Enterprise/Organizations)

For better control, create a runner group:

1. Go to **Organization Settings** → **Actions** → **Runner groups**
2. Create a new group (e.g., "Production Kubernetes")
3. Limit which repositories can use this group
4. Assign the runner to this group during setup

#### Limit Runner Scope

Configure runners with minimal necessary labels:

```yaml
github_runner_labels: "self-hosted,linux,x64,tailscale,k8s,production"
```

Then in workflows, be specific:

```yaml
runs-on: [self-hosted, tailscale, k8s, production]
```

#### Use GitHub Secrets for Sensitive Data

Never hardcode sensitive information in workflows. Use GitHub Secrets:

```yaml
env:
  KUBECONFIG: ${{ secrets.KUBECONFIG }}  # If needed
  SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
```

### Runner User Permissions

The runner user needs specific permissions:

```bash
# The Ansible role automatically configures this, but for reference:

# 1. Runner user can execute kubectl/helm
# 2. kubeconfig copied to /home/github-runner/.kube/config
# 3. kubeconfig server URL points to Tailscale IP of control plane

# Verify permissions
sudo -u github-runner kubectl get nodes
```

### Firewall Rules

Ensure firewall allows:

```bash
# On worker node - allow outbound to Tailscale control plane
sudo ufw allow out to 100.64.0.0/10  # Tailscale CGNAT range

# On control plane - allow from Tailscale network
sudo ufw allow from 100.64.0.0/10 to any port 6443
```

## Usage in Workflows

### Basic Example

Create `.github/workflows/deploy.yaml`:

```yaml
name: Deploy to Kubernetes

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: [self-hosted, tailscale]
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Test kubectl access
        run: |
          kubectl get nodes
          kubectl get pods -A
      
      - name: Deploy with kubectl
        run: |
          kubectl apply -f kubernetes/
```

### Helm Deployment Example

```yaml
name: Helm Deploy

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        type: choice
        options:
          - dev
          - staging
          - production

jobs:
  helm-deploy:
    runs-on: [self-hosted, tailscale, kubernetes]
    environment: ${{ github.event.inputs.environment }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Setup Helm
        run: |
          # Helm should already be installed on runner
          helm version
      
      - name: Setup SOPS
        run: |
          # If SOPS is not pre-installed
          wget -O /tmp/sops https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
          chmod +x /tmp/sops
          sudo mv /tmp/sops /usr/local/bin/
      
      - name: Configure SOPS Age Key
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: |
          mkdir -p ~/.config/sops/age
          echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
          chmod 600 ~/.config/sops/age/keys.txt
      
      - name: Deploy with Helmfile
        working-directory: helmfile
        run: |
          helmfile -e ${{ github.event.inputs.environment }} apply
```

### Testing Connectivity Example

```yaml
name: Test Cluster Connectivity

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:

jobs:
  connectivity-test:
    runs-on: [self-hosted, tailscale]
    
    steps:
      - name: Test Tailscale connectivity
        run: |
          echo "Testing Tailscale status..."
          tailscale status
          
          # Get control plane IP
          CONTROL_IP=$(tailscale status --json | jq -r '.Peer[] | select(.HostName | contains("control")) | .TailscaleIPs[0]' | head -1)
          echo "Control plane Tailscale IP: $CONTROL_IP"
          
          # Ping control plane
          ping -c 3 $CONTROL_IP
      
      - name: Test Kubernetes API access
        run: |
          echo "Testing Kubernetes API..."
          kubectl cluster-info
          kubectl get nodes -o wide
          kubectl get pods -A
      
      - name: Test cluster health
        run: |
          echo "Checking cluster health..."
          kubectl get componentstatuses
          kubectl top nodes || echo "Metrics server not available"
```

### Complete CI/CD Pipeline Example

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest  # Use GitHub-hosted for tests
    steps:
      - uses: actions/checkout@v4
      - name: Run tests
        run: |
          # Your tests here
          npm test
  
  deploy:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: [self-hosted, tailscale]  # Use self-hosted for deployment
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Build Docker image
        run: |
          docker build -t myapp:${{ github.sha }} .
      
      - name: Push to registry
        run: |
          docker push myapp:${{ github.sha }}
      
      - name: Deploy to Kubernetes
        run: |
          kubectl set image deployment/myapp \
            myapp=myapp:${{ github.sha }}
          
          kubectl rollout status deployment/myapp
```

## Testing and Validation

### Test 1: Basic Connectivity

```bash
# On worker node, test as runner user
sudo -u github-runner bash

# Test Tailscale connectivity
tailscale status

# Get control plane IP
CONTROL_IP=$(tailscale status --json | jq -r '.Peer[] | select(.HostName | contains("control")) | .TailscaleIPs[0]')
echo "Control plane IP: $CONTROL_IP"

# Ping control plane
ping -c 3 $CONTROL_IP

# Test API port
nc -zv $CONTROL_IP 6443
```

### Test 2: Kubectl Access

```bash
# As runner user
sudo -u github-runner kubectl get nodes
sudo -u github-runner kubectl get pods -A
sudo -u github-runner kubectl cluster-info
```

### Test 3: Helm Access

```bash
# As runner user
sudo -u github-runner helm version
sudo -u github-runner helm list -A
```

### Test 4: Run Test Workflow

Create `.github/workflows/test-runner.yaml`:

```yaml
name: Test Self-Hosted Runner

on:
  workflow_dispatch:

jobs:
  test:
    runs-on: [self-hosted, tailscale]
    
    steps:
      - name: Check environment
        run: |
          echo "Runner: $(hostname)"
          echo "User: $(whoami)"
          echo "Working dir: $(pwd)"
      
      - name: Test Tailscale
        run: |
          tailscale status
      
      - name: Test kubectl
        run: |
          kubectl version --client
          kubectl get nodes
      
      - name: Test Helm
        run: |
          helm version
      
      - name: Success
        run: |
          echo "✅ All tests passed!"
```

## Troubleshooting

### Runner Not Appearing in GitHub

**Symptoms**: Runner doesn't show up in GitHub UI after installation.

**Solutions**:

```bash
# Check runner service status
sudo systemctl status actions.runner.*.service

# View logs
sudo journalctl -u actions.runner.*.service -f

# Verify runner configuration
sudo -u github-runner cat /home/github-runner/actions-runner/.runner

# Check network connectivity to GitHub
curl -I https://github.com

# Re-register runner (get new token first)
cd /home/github-runner/actions-runner
sudo -u github-runner ./config.sh remove
# Then re-run Ansible playbook with new token
```

### kubectl Connection Refused

**Symptoms**: `kubectl get nodes` fails with "connection refused" or timeout.

**Solutions**:

```bash
# 1. Verify Tailscale connectivity
tailscale status
ping <control-plane-tailscale-ip>
nc -zv <control-plane-tailscale-ip> 6443

# 2. Check kubeconfig
cat /home/github-runner/.kube/config
# Server should be: https://<tailscale-ip>:6443

# 3. Check control plane is accessible
ssh control-plane
sudo systemctl status k3s
sudo journalctl -u k3s -f

# 4. Test from worker node directly
kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes

# 5. Update kubeconfig server URL
CONTROL_IP=$(tailscale status --json | jq -r '.Peer[] | select(.HostName | contains("control")) | .TailscaleIPs[0]')
sed -i "s|https://.*:6443|https://$CONTROL_IP:6443|g" /home/github-runner/.kube/config
```

### Workflow Jobs Not Starting

**Symptoms**: Workflows queue but jobs never start on self-hosted runner.

**Solutions**:

```bash
# 1. Check runner service is running
sudo systemctl status actions.runner.*.service
sudo systemctl restart actions.runner.*.service

# 2. Check runner logs
sudo journalctl -u actions.runner.*.service -f

# 3. Verify labels match
# In workflow: runs-on: [self-hosted, tailscale]
# Runner should have: self-hosted,tailscale

# 4. Check runner is idle (not already running a job)
# Look for "Listening for Jobs" in logs

# 5. Restart runner
sudo systemctl restart actions.runner.*.service
```

### Permission Denied Errors

**Symptoms**: kubectl/helm commands fail with permission errors.

**Solutions**:

```bash
# 1. Check kubeconfig permissions
ls -la /home/github-runner/.kube/config
sudo chown github-runner:github-runner /home/github-runner/.kube/config
sudo chmod 600 /home/github-runner/.kube/config

# 2. Verify runner user exists
id github-runner

# 3. Test as runner user
sudo -u github-runner kubectl get nodes

# 4. Check kubeconfig content
sudo -u github-runner cat /home/github-runner/.kube/config
```

### Tailscale Authentication Issues

**Symptoms**: Tailscale not connected or authentication errors.

**Solutions**:

```bash
# Check Tailscale status
sudo tailscale status

# Re-authenticate
sudo tailscale up --authkey=<new-auth-key>

# Check Tailscale logs
sudo journalctl -u tailscaled -f

# Verify node appears in Tailscale admin
# Visit: https://login.tailscale.com/admin/machines
```

## Maintenance

### Updating the Runner

GitHub Actions runners auto-update by default. To manually update:

```bash
# Stop runner
sudo systemctl stop actions.runner.*.service

# As runner user, update
cd /home/github-runner/actions-runner
sudo -u github-runner ./run.sh update

# Start runner
sudo systemctl start actions.runner.*.service
```

### Rotating Runner Token

Runner tokens are only needed during initial registration. Once registered, the runner uses a different authentication mechanism. However, to re-register:

```bash
# 1. Remove current registration
cd /home/github-runner/actions-runner
sudo -u github-runner ./config.sh remove

# 2. Generate new token (see Step 1 above)

# 3. Re-run Ansible playbook with new token
cd ansible
ansible-playbook -i inventory.ini playbooks/setup-github-runner.yaml \
  -e "github_runner_token=NEW_TOKEN"
```

### Monitoring Runner Health

Set up automated health checks:

```yaml
# .github/workflows/runner-health.yaml
name: Runner Health Check

on:
  schedule:
    - cron: '0 */2 * * *'  # Every 2 hours

jobs:
  health-check:
    runs-on: [self-hosted, tailscale]
    steps:
      - name: Health check
        run: |
          # Check Tailscale
          tailscale status || exit 1
          
          # Check kubectl
          kubectl get nodes || exit 1
          
          # Check disk space
          df -h | grep -v "100%"
          
          # Check memory
          free -h
          
          echo "✅ Health check passed"
```

### Backup and Disaster Recovery

The runner configuration is stored in:
- `/home/github-runner/actions-runner/.runner` - Runner registration
- `/home/github-runner/actions-runner/.credentials` - Runner credentials
- `/home/github-runner/.kube/config` - Kubernetes config

To backup:

```bash
# Backup runner config
sudo tar czf github-runner-backup.tar.gz \
  /home/github-runner/actions-runner/.runner \
  /home/github-runner/actions-runner/.credentials \
  /home/github-runner/.kube/config

# Store securely
```

To restore, re-run the Ansible playbook. The runner will re-register automatically.

### Decommissioning a Runner

To remove a runner:

```bash
# 1. Stop and disable service
sudo systemctl stop actions.runner.*.service
sudo systemctl disable actions.runner.*.service

# 2. Remove from GitHub
cd /home/github-runner/actions-runner
sudo -u github-runner ./config.sh remove --token <removal-token>

# 3. Clean up files
sudo rm -rf /home/github-runner/actions-runner
sudo userdel -r github-runner
```

## Best Practices

1. **Use Runner Groups**: Organize runners by environment (dev, staging, prod)
2. **Label Specifically**: Use descriptive labels (e.g., `k8s-prod`, `tailscale-east`)
3. **Monitor Resources**: Keep an eye on disk, memory, and CPU usage
4. **Regular Updates**: Keep runner, kubectl, and Helm updated
5. **Security Scanning**: Use tools like CodeQL and Dependabot
6. **Least Privilege**: Runner should have minimal necessary permissions
7. **Audit Logs**: Review runner logs regularly for suspicious activity
8. **Backup Regularly**: Backup runner config and credentials
9. **Use Environments**: GitHub environment protection rules for production
10. **Rotate Secrets**: Regularly rotate Tailscale keys and GitHub tokens

## Security Checklist

- [ ] Runner installed on worker node (not control plane)
- [ ] Tailscale ACLs configured to restrict access
- [ ] Runner user has minimal necessary permissions
- [ ] GitHub repository has appropriate access controls
- [ ] Secrets stored in GitHub Secrets, not in code
- [ ] SOPS age keys rotated regularly
- [ ] Runner service runs as dedicated user
- [ ] Firewall rules configured correctly
- [ ] Audit logs monitored
- [ ] Control plane not exposed to internet
- [ ] Workflow approval required for production deployments

## References

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Helm Security](https://helm.sh/docs/topics/provenance/)
- [GitHub Actions Security](https://docs.github.com/en/actions/security-guides)
