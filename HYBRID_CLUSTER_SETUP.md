# Hybrid Cluster Deployment Guide

This guide walks through deploying a production-ready hybrid Kubernetes cluster using the infrastructure framework.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Step 1: Tailscale Setup](#step-1-tailscale-setup)
- [Step 2: Prepare Ansible](#step-2-prepare-ansible)
- [Step 3: Deploy Control Plane](#step-3-deploy-control-plane)
- [Step 4: Deploy Worker Nodes](#step-4-deploy-worker-nodes)
- [Step 5: Verify Cluster](#step-5-verify-cluster)
- [Step 6: Deploy Infrastructure Services](#step-6-deploy-infrastructure-services)
- [Step 7: Configure Cloudflared Ingress](#step-7-configure-cloudflared-ingress)
- [Step 8: Deploy Applications](#step-8-deploy-applications)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                    ┌────▼─────┐
                    │Cloudflare│
                    └────┬─────┘
                         │
            ┌────────────▼────────────┐
            │  Cloudflared Tunnel     │
            │  (Worker Node)          │
            └────────────┬────────────┘
                         │
            ┌────────────▼────────────┐
            │   HAProxy Ingress       │
            │   (Worker Node)         │
            └────────────┬────────────┘
                         │
         ┌───────────────▼──────────────┐
         │    Kubernetes Services       │
         │         (Pods)               │
         └──────────────────────────────┘

Control Plane ←──→ Tailscale VPN ←──→ Worker Nodes
 (CGNAT/Home)                           (Public IP)
```

### Key Features

- **Control Plane**: Behind CGNAT/NAT, no public exposure required
- **Worker Nodes**: Public IP for ingress, Tailscale for cluster networking
- **No Port Forwarding**: Cloudflared handles all HTTP/HTTPS ingress
- **Secure Communication**: Tailscale encrypts all cluster traffic
- **Workload Isolation**: Control plane runs only K3s, workers run workloads

## Prerequisites

### Hardware/Infrastructure
- **Control Plane**: Home server/PC behind CGNAT (1GB RAM minimum)
- **Worker Node(s)**: VPS with public IP (2GB RAM minimum, e.g., Netcup)
- Both nodes need Ubuntu 20.04+ or similar Linux distribution

### Accounts & Services
- **Tailscale Account**: Free tier sufficient ([signup](https://login.tailscale.com/start))
- **Cloudflare Account**: Free tier for DNS and tunnels ([signup](https://dash.cloudflare.com/sign-up))
- **Domain**: Registered domain managed in Cloudflare DNS

### Local Tools
```bash
# macOS
brew install ansible age sops cloudflared

# Linux (Ubuntu/Debian)
sudo apt install ansible
# Install age, sops, and cloudflared manually (see SECRETS.md)
```

## Step 1: Tailscale Setup

Tailscale provides secure networking for the hybrid cluster.

### 1.1. Create Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Configure:
   - **Description**: `k3s-hybrid-cluster`
   - **Reusable**: ✓ (to use for multiple nodes)
   - **Ephemeral**: ✗ (keep nodes persistent)
   - **Tags**: `tag:k3s-node` (optional, for ACLs)
4. Copy the auth key (starts with `tskey-auth-`)

### 1.2. Configure Tailscale ACLs (Optional)

For better security, configure ACLs to allow only cluster communication:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:k3s-node"],
      "dst": ["tag:k3s-node:*"]
    }
  ],
  "tagOwners": {
    "tag:k3s-node": ["your-email@example.com"]
  }
}
```

Apply in: **Tailscale Admin Console** → **Access Controls**

## Step 2: Prepare Ansible

### 2.1. Clone Repository

```bash
git clone https://github.com/wcatz/infrastructure.git
cd infrastructure/ansible
```

### 2.2. Configure Ansible Vault

```bash
# Create vault password file
cp .vault_pass.example .vault_pass
echo "your-secure-vault-password" > .vault_pass
chmod 600 .vault_pass

# Create vault variables
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
```

Edit `group_vars/all/vault.yml`:
```yaml
---
# K3s cluster token (generate with: openssl rand -hex 32)
vault_k3s_token: "abc123def456..."

# Tailscale auth key from step 1.1
vault_tailscale_key: "tskey-auth-..."
```

Encrypt the vault:
```bash
ansible-vault encrypt group_vars/all/vault.yml
```

### 2.3. Configure Inventory

```bash
cp inventory.ini.example inventory.ini
```

Edit `inventory.ini`:
```ini
[k3s_servers]
# Control plane - use hostname, Tailscale IP will be set after Tailscale install
k3s-control ansible_host=192.168.1.100 ansible_user=youruser k3s_node_taint=true

[k3s_agents]
# Worker node(s) - use public IP initially
k3s-worker-01 ansible_host=1.2.3.4 ansible_user=youruser k3s_node_label="node-role=worker"

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

**Note**: After Tailscale is installed, you'll update the control plane IP to its Tailscale IP.

### 2.4. Test Connectivity

```bash
ansible all -i inventory.ini -m ping
```

## Step 3: Deploy Control Plane

### 3.1. Install Tailscale on All Nodes

```bash
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml
```

**Important**: After Tailscale installation, get the Tailscale IPs:
```bash
# SSH to each node
ssh user@control-plane
tailscale ip -4  # Note this IP (e.g., 100.64.1.10)

ssh user@worker-01
tailscale ip -4  # Note this IP (e.g., 100.64.1.20)
```

### 3.2. Update Inventory with Tailscale IPs

Edit `inventory.ini` to use Tailscale IP for control plane:
```ini
[k3s_servers]
k3s-control ansible_host=100.64.1.10 ansible_user=youruser k3s_node_taint=true
```

This ensures the K3s API server is accessible via Tailscale.

### 3.3. Deploy K3s Cluster

```bash
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml
```

This will:
- Install K3s server on control plane
- Install K3s agent on worker nodes
- Apply NoSchedule taint to control plane
- Label worker nodes

## Step 4: Deploy Worker Nodes

Worker nodes are deployed as part of Step 3, but verify they're connected:

```bash
# SSH to control plane
ssh user@100.64.1.10

# Check node status
kubectl get nodes -o wide
```

Expected output:
```
NAME          STATUS   ROLES                  AGE   VERSION
k3s-control   Ready    control-plane,master   5m    v1.28.5+k3s1
k3s-worker-01 Ready    <none>                 3m    v1.28.5+k3s1
```

Check taint on control plane:
```bash
kubectl describe node k3s-control | grep Taints
# Expected: node-role.kubernetes.io/control-plane:NoSchedule
```

## Step 5: Verify Cluster

### 5.1. Get Kubeconfig

```bash
# From your local machine
scp youruser@100.64.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update server URL to use Tailscale IP
sed -i 's/127.0.0.1/100.64.1.10/' ~/.kube/config
```

**Important**: Your local machine needs Tailscale installed and connected to access the cluster!

### 5.2. Test Cluster Access

```bash
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### 5.3. Deploy Test Pod

```bash
kubectl run test-nginx --image=nginx:alpine --port=80

# Wait for pod to be running
kubectl get pods -w

# Verify it's on a worker node, not control plane
kubectl get pod test-nginx -o wide
```

Cleanup:
```bash
kubectl delete pod test-nginx
```

## Step 6: Deploy Infrastructure Services

### 6.1. Install Helmfile Prerequisites

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Helmfile
brew install helmfile  # macOS
# or download from: https://github.com/helmfile/helmfile/releases
```

### 6.2. Deploy Services

```bash
cd ../helmfile

# Deploy HAProxy Ingress, Prometheus, and Grafana
helmfile apply
```

This deploys:
- **HAProxy Ingress**: HTTP/HTTPS routing (NodePort 30080/30443)
- **Prometheus**: Metrics collection
- **Grafana**: Metrics visualization

### 6.3. Verify Deployments

```bash
kubectl get pods -n haproxy-ingress
kubectl get pods -n monitoring
kubectl get svc -n haproxy-ingress
```

## Step 7: Configure Cloudflared Ingress

### 7.1. Install Cloudflared CLI

```bash
# macOS
brew install cloudflare/cloudflare/cloudflared

# Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
```

### 7.2. Authenticate with Cloudflare

```bash
cloudflared tunnel login
```

This opens a browser to select your domain.

### 7.3. Create Tunnel

```bash
cloudflared tunnel create k3s-hybrid-tunnel
```

Save the output:
- **Tunnel ID**: `abc123...`
- **Credentials file**: `~/.cloudflared/<TUNNEL-ID>.json`

### 7.4. Create Kubernetes Secret

```bash
kubectl create namespace cloudflare

kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
  -n cloudflare
```

### 7.5. Configure DNS Routes

```bash
# Route hostnames to your tunnel
cloudflared tunnel route dns k3s-hybrid-tunnel app.example.com
cloudflared tunnel route dns k3s-hybrid-tunnel api.example.com
```

### 7.6. Update Cloudflared Values

Edit `helmfile/values/cloudflared-values.yaml`:
```yaml
cloudflare:
  tunnelName: "k3s-hybrid-tunnel"
  tunnelId: "<TUNNEL-ID>"

ingress:
  # Route to HAProxy Ingress
  - hostname: app.example.com
    service: http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
  - hostname: api.example.com
    service: http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
  # Catch-all
  - service: http_status:404
```

### 7.7. Enable and Deploy Cloudflared

Edit `helmfile/config/enabled.yaml`:
```yaml
enabled:
  cloudflared: true  # Change from false to true
```

Deploy:
```bash
helmfile apply
```

### 7.8. Verify Cloudflared

```bash
kubectl get pods -n cloudflare
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared
```

## Step 8: Deploy Applications

### 8.1. Use Kubernetes Examples

```bash
cd ../kubernetes-examples

# Copy and customize deployment
cp deployment.yaml my-app-deployment.yaml
# Edit my-app-deployment.yaml

# Apply
kubectl apply -f my-app-deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
```

### 8.2. Example: Deploy NGINX

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
      - name: nginx
        image: nginxdemos/hello:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hello-world
  namespace: default
spec:
  selector:
    app: hello-world
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello-world
  namespace: default
  annotations:
    haproxy.org/ssl-redirect: "true"
spec:
  ingressClassName: haproxy
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: hello-world
            port:
              number: 80
EOF
```

### 8.3. Test Access

```bash
# Via Cloudflared
curl https://app.example.com

# Or directly via NodePort (for debugging)
curl http://<worker-public-ip>:30080 -H "Host: app.example.com"
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

# Common causes:
# 1. All nodes tainted (verify worker nodes are not tainted)
kubectl get nodes -o json | jq '.items[].spec.taints'

# 2. Insufficient resources
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
cloudflared tunnel info k3s-hybrid-tunnel

# Check DNS records
dig app.example.com
```

### Ingress Not Working

**Problem**: Cannot access services via ingress

```bash
# Check HAProxy pods
kubectl get pods -n haproxy-ingress

# Check ingress resources
kubectl get ingress -A

# Check service endpoints
kubectl get endpoints

# Test internal connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
```

## Next Steps

- Review [Kubernetes Examples README](../kubernetes-examples/README.md) for deployment patterns
- Configure monitoring dashboards in Grafana
- Set up secret encryption with SOPS (see [SECRETS.md](../SECRETS.md))
- Implement backup strategy (see [DISASTER_RECOVERY.md](../DISASTER_RECOVERY.md))
- Add more worker nodes as needed

## Additional Resources

- [K3s Documentation](https://docs.k3s.io/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [HAProxy Ingress Documentation](https://haproxy-ingress.github.io/)
