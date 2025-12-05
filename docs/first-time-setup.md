# First-Time Setup Guide

This guide provides detailed step-by-step instructions for setting up the complete Kubernetes infrastructure from scratch.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Phase 1: Provisioning k3s](#phase-1-provisioning-k3s)
- [Phase 2: HAProxy Setup](#phase-2-haproxy-setup)
- [Phase 3: Deploy Core Services](#phase-3-deploy-core-services)
- [Phase 4: Secret Management](#phase-4-secret-management)
- [Phase 5: Validation](#phase-5-validation)

## Prerequisites

### Required Infrastructure
- **k3s Servers**: Minimum 1 control plane node (recommended: 3 for HA)
- **k3s Agents**: Minimum 1 worker node (recommended: 3+ for production)
- **HAProxy Server**: 1 dedicated load balancer (can be co-located with control plane for dev)
- **Control Machine**: Your local machine with Ansible, Helmfile, and kubectl

### Required Software
- **Ansible** 2.9 or later
- **Helm** 3.x
- **Helmfile** 0.150.0 or later
- **kubectl** matching your k3s version
- **cloudflared** CLI (for Cloudflare tunnels)
- **sops** (for secret encryption)

### Required Access
- SSH access to all servers with sudo privileges
- GitHub account (for GitOps workflows)
- Cloudflare account with domain (for Cloudflared tunnels)
- Cloud storage account (AWS S3/Azure Blob/GCS) for backups

### Installation Commands

**macOS:**
```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install ansible helm helmfile kubectl sops age
brew install cloudflare/cloudflare/cloudflared

# Install helm-diff plugin
helm plugin install https://github.com/databus23/helm-diff
```

**Linux (Ubuntu/Debian):**
```bash
# Install Ansible
sudo apt update
sudo apt install -y ansible python3-pip

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install helm-diff plugin
helm plugin install https://github.com/databus23/helm-diff

# Install Helmfile
wget https://github.com/helmfile/helmfile/releases/download/v0.159.0/helmfile_0.159.0_linux_amd64.tar.gz
tar -xzf helmfile_0.159.0_linux_amd64.tar.gz
sudo mv helmfile /usr/local/bin/
rm helmfile_0.159.0_linux_amd64.tar.gz

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install SOPS
wget https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Install age
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/

# Install cloudflared
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
```

## Phase 1: Provisioning k3s

### Step 1.1: Prepare Inventory

```bash
cd ansible
cp inventory.ini.example inventory.ini
```

Edit `inventory.ini` with your server details:

```ini
[k3s_servers]
k3s-master-01 ansible_host=192.168.1.10 ansible_user=ubuntu hostname=k3s-master-01

[k3s_agents]
k3s-worker-01 ansible_host=192.168.1.11 ansible_user=ubuntu hostname=k3s-worker-01
k3s-worker-02 ansible_host=192.168.1.12 ansible_user=ubuntu hostname=k3s-worker-02
k3s-worker-03 ansible_host=192.168.1.13 ansible_user=ubuntu hostname=k3s-worker-03

[haproxy_servers]
haproxy-lb-01 ansible_host=192.168.1.5 ansible_user=ubuntu hostname=haproxy-lb-01

[all:vars]
ansible_python_interpreter=/usr/bin/python3

[k3s_servers:vars]
domain=k3s.example.com

[k3s_agents:vars]
domain=k3s.example.com

[haproxy_servers:vars]
domain=lb.example.com
```

### Step 1.2: Generate k3s Token

```bash
# Generate a secure random token
openssl rand -hex 32

# Save the output, you'll need it for the next step
```

### Step 1.3: Configure k3s Variables

Create `ansible/group_vars/all.yml`:

```yaml
---
# k3s cluster configuration
k3s_token: "YOUR_GENERATED_TOKEN_HERE"
k3s_version: "v1.28.5+k3s1"

# Additional TLS SANs (optional)
k3s_tls_san:
  - "k3s.example.com"
  - "192.168.1.10"
```

### Step 1.4: Test Connectivity

```bash
# Test SSH access to all hosts
ansible all -i inventory.ini -m ping

# Expected output: SUCCESS for all hosts
```

### Step 1.5: Deploy k3s Cluster

```bash
# Deploy k3s (Traefik disabled)
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# This takes approximately 10-15 minutes
```

### Step 1.6: Verify k3s Installation

```bash
# Check nodes from control plane
ansible k3s_servers -i inventory.ini -m shell -a "kubectl get nodes"

# Retrieve kubeconfig
scp ubuntu@192.168.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config-k3s

# Update kubeconfig server address
sed -i 's/127.0.0.1/192.168.1.10/g' ~/.kube/config-k3s

# Set KUBECONFIG
export KUBECONFIG=~/.kube/config-k3s

# Verify from local machine
kubectl get nodes -o wide
```

Expected output:
```
NAME            STATUS   ROLES                  AGE   VERSION
k3s-master-01   Ready    control-plane,master   5m    v1.28.5+k3s1
k3s-worker-01   Ready    <none>                 3m    v1.28.5+k3s1
k3s-worker-02   Ready    <none>                 3m    v1.28.5+k3s1
k3s-worker-03   Ready    <none>                 3m    v1.28.5+k3s1
```

## Phase 2: HAProxy Setup

### Step 2.1: HAProxy Load Balancer (NodePort)

HAProxy is deployed in two modes:
1. **Kubernetes HAProxy Ingress Controller** (via Helmfile) - for HTTP/HTTPS traffic
2. **External HAProxy Load Balancer** (via Ansible) - for NodePort TCP/UDP services

For the external HAProxy setup, see [haproxy-setup.md](haproxy-setup.md).

### Step 2.2: Deploy HAProxy via Ansible (Optional)

If you want HAProxy to load balance NodePort services (MySQL, WireGuard, etc.):

```bash
# Deploy HAProxy
ansible-playbook -i inventory.ini playbooks/deploy-haproxy.yaml

# This configures HAProxy to load balance traffic to k3s worker nodes
```

## Phase 3: Deploy Core Services

### Step 3.1: Configure Helmfile

```bash
cd helmfile

# Review enabled applications
cat config/enabled.yaml
```

Ensure the following are enabled:
```yaml
enabled:
  prometheus: true
  haproxyIngress: true
  grafana: true
  externalSecrets: true
  cloudflared: false  # Enable later after tunnel setup
  velero: false  # Enable later after storage configuration
```

### Step 3.2: Review Helmfile Configuration

```bash
# Validate Helmfile syntax
helmfile lint

# Preview what will be deployed
helmfile diff --suppress-secrets
```

### Step 3.3: Deploy Core Services

```bash
# Deploy all enabled services
helmfile apply

# This takes approximately 15-20 minutes
```

### Step 3.4: Verify Deployments

```bash
# Check all namespaces
kubectl get namespaces

# Check HAProxy Ingress
kubectl get pods -n haproxy-ingress
kubectl get svc -n haproxy-ingress

# Check Prometheus
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Check Grafana
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Check External Secrets
kubectl get pods -n external-secrets-system
```

Expected namespaces:
- `haproxy-ingress`: HAProxy Ingress Controller
- `monitoring`: Prometheus and Grafana
- `external-secrets-system`: External Secrets Operator

## Phase 4: Secret Management

### Step 4.1: Set Up SOPS with age

```bash
# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Display public key (save this)
cat ~/.config/sops/age/keys.txt | grep "public key:"

# Example output:
# Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### Step 4.2: Configure SOPS

Create `.sops.yaml` in repository root:

```yaml
creation_rules:
  - path_regex: .*/secrets/.*\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
  - path_regex: .*/.*\.enc\.yaml$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### Step 4.3: Create and Encrypt Secrets

```bash
# Create secrets directory
mkdir -p secrets

# Create a secret file
cat > secrets/example-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: example-secret
  namespace: default
type: Opaque
stringData:
  username: admin
  password: changeme123
EOF

# Encrypt the secret
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -e -i secrets/example-secret.yaml

# The file is now encrypted
cat secrets/example-secret.yaml
```

### Step 4.4: Deploy Encrypted Secrets

```bash
# Decrypt and apply
sops -d secrets/example-secret.yaml | kubectl apply -f -

# Verify
kubectl get secret example-secret -n default
```

For more details, see [secrets-management.md](secrets-management.md).

## Phase 5: Validation

### Step 5.1: Verify k3s Cluster

```bash
# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -A

# Check API server
kubectl cluster-info
```

### Step 5.2: Verify HAProxy Ingress

```bash
# Check HAProxy pods
kubectl get pods -n haproxy-ingress

# Check HAProxy service
kubectl get svc -n haproxy-ingress

# Check ingress resources
kubectl get ingress -A
```

### Step 5.3: Verify Monitoring Stack

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80 &

# Open browser to http://localhost:9090
# Check "Status > Targets" - should show all targets

# Port forward Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80 &

# Open browser to http://localhost:3000
# Default credentials: admin/admin (change on first login)
```

### Step 5.4: Run Health Checks

```bash
# Check all deployments
kubectl get deployments -A

# Check all services
kubectl get svc -A

# Check for any unhealthy pods
kubectl get pods -A | grep -v Running | grep -v Completed
```

### Step 5.5: Test Secret Management

```bash
# Create test secret
cat > /tmp/test-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
  namespace: default
type: Opaque
stringData:
  test: value
EOF

# Apply
kubectl apply -f /tmp/test-secret.yaml

# Verify
kubectl get secret test-secret -n default -o yaml

# Clean up
kubectl delete secret test-secret -n default
rm /tmp/test-secret.yaml
```

## Post-Setup Tasks

### Configure Cloudflared Tunnel

See [../helmfile/CLOUDFLARED_SETUP.md](../helmfile/CLOUDFLARED_SETUP.md) for complete instructions.

### Configure Backup with Velero

See [disaster-recovery.md](disaster-recovery.md) for Velero setup.

### Set Up CI/CD Automation

See [gitops-workflows.md](gitops-workflows.md) for GitHub Actions configuration.

### Apply NetworkPolicies

```bash
# Review network policies
kubectl apply -f helmfile/manifests/network-policies.yaml

# Verify
kubectl get networkpolicies -A
```

## Troubleshooting

### k3s Installation Failed

```bash
# Check k3s logs on server
ssh ubuntu@192.168.1.10 "sudo journalctl -u k3s -f"

# Check k3s logs on agent
ssh ubuntu@192.168.1.11 "sudo journalctl -u k3s-agent -f"
```

### Helmfile Apply Failed

```bash
# Check specific release
helmfile -l name=haproxy-ingress status

# Check pod logs
kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress

# Re-apply specific release
helmfile -l name=haproxy-ingress apply
```

### Cannot Access Services

```bash
# Check service endpoints
kubectl get endpoints -A

# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check service
kubectl describe svc <service-name> -n <namespace>
```

## Next Steps

1. **Configure DNS**: Set up DNS records for your domain
2. **Enable Cloudflared**: Deploy Cloudflare tunnels for secure access
3. **Configure Backups**: Set up Velero for disaster recovery
4. **Apply NetworkPolicies**: Implement network segmentation
5. **Set Up Monitoring Alerts**: Configure Prometheus alerting rules
6. **Deploy Applications**: Start deploying your workloads

## Additional Resources

- [HAProxy Setup Guide](haproxy-setup.md)
- [Secrets Management Guide](secrets-management.md)
- [Disaster Recovery Guide](disaster-recovery.md)
- [GitOps Workflows Guide](gitops-workflows.md)
- [HAProxy Advanced Configuration](haproxy-advanced.md)
