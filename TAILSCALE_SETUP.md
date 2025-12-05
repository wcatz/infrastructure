# Tailscale Setup Guide

This guide explains how to set up Tailscale for secure L3 mesh networking in the hybrid Kubernetes cluster.

## Overview

Tailscale provides:
- **Host-level VPN**: Secure communication between cluster nodes (home control plane and Netcup workers)
- **Kubernetes Operator**: Manages Tailscale resources for pods and services
- **L3 Mesh Networking**: Replaces traditional CNI plugins like Flannel for inter-node communication
- **Zero Trust Access**: Secure access to cluster resources without exposing them to the public internet

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Tailscale Mesh Network                    │
│                                                              │
│  ┌──────────────────┐              ┌──────────────────┐    │
│  │  Control Node    │              │  Worker Node     │    │
│  │  (Home/CGNAT)    │◄────────────►│  (Netcup)        │    │
│  │                  │   Tailscale  │  Public IP       │    │
│  │  - K3s Server    │     Mesh     │  - K3s Agent     │    │
│  │  - Cloudflared   │              │  - Cardano Node  │    │
│  └──────────────────┘              └──────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Tailscale account (free tier works for personal use)
- Access to Tailscale admin console: https://login.tailscale.com/admin
- Ansible installed on your local machine
- kubectl configured for cluster access

## Part 1: Host-level Tailscale (via Ansible)

### 1. Generate Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Click "Generate auth key"
3. Configure:
   - **Reusable**: Yes (for multiple nodes)
   - **Ephemeral**: No (nodes should persist)
   - **Tags**: Add `tag:k8s` for organization
   - **Expiration**: Set appropriate expiration (e.g., 90 days)
4. Copy the generated key (starts with `tskey-auth-`)

### 2. Update Ansible Vault

Add the Tailscale auth key to your encrypted vault:

```bash
cd ansible

# Edit encrypted vault file
ansible-vault edit group_vars/all/vault.yml

# Add the following line:
vault_tailscale_key: "tskey-auth-YOUR-KEY-HERE"
```

### 3. Configure Tailscale Role

The Tailscale role is already configured in the playbooks. You can customize settings in inventory:

```ini
# inventory.ini
[k3s_servers]
control-node ansible_host=192.168.1.100

[k3s_agents]
netcup-worker ansible_host=NETCUP_PUBLIC_IP

[all:vars]
ansible_user=your_user
ansible_become=true

# Tailscale configuration
tailscale_enable_ssh=true
tailscale_accept_dns=false
tailscale_advertise_tags=tag:k8s,tag:control-plane  # For control node
# tailscale_advertise_tags=tag:k8s,tag:worker  # For worker nodes
```

### 4. Deploy Tailscale on Hosts

```bash
cd ansible

# Deploy Tailscale to all nodes
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# Verify Tailscale status
ansible -i inventory.ini all -m shell -a "tailscale status"
```

### 5. Configure Tailscale ACLs

Configure access control lists in Tailscale admin console for secure inter-node communication:

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
    }
  ],
  "tagOwners": {
    "tag:k8s": ["autogroup:admin"],
    "tag:control-plane": ["autogroup:admin"],
    "tag:worker": ["autogroup:admin"]
  }
}
```

**Key ACL Rules:**
- All k8s nodes can communicate with each other
- Workers can access control plane on port 6443 (Kubernetes API)
- Control plane can access workers on port 10250 (kubelet)

## Part 2: Tailscale Kubernetes Operator (via Helmfile)

The Tailscale Kubernetes Operator manages Tailscale resources for pods and services.

### 1. Create OAuth Client

1. Go to https://login.tailscale.com/admin/settings/oauth
2. Click "Generate OAuth client"
3. Configure:
   - **Description**: "K3s Cluster Operator"
   - **Scopes**: Select `devices:read` and `devices:write`
4. Copy the **Client ID** and **Client Secret**

### 2. Create Kubernetes Secret

```bash
# Create secret for Tailscale operator
kubectl create namespace tailscale

kubectl create secret generic operator-oauth \
  --from-literal=client_id=YOUR_OAUTH_CLIENT_ID \
  --from-literal=client_secret=YOUR_OAUTH_CLIENT_SECRET \
  -n tailscale
```

**Or use Ansible Vault for CI/CD:**

```bash
# Add to ansible/group_vars/all/vault.yml
vault_tailscale_oauth_client_id: "YOUR_OAUTH_CLIENT_ID"
vault_tailscale_oauth_client_secret: "YOUR_OAUTH_CLIENT_SECRET"
```

**Or use SOPS for GitOps:**

```bash
# Create secret manifest
cat > /tmp/tailscale-oauth-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: operator-oauth
  namespace: tailscale
type: Opaque
stringData:
  client_id: "YOUR_OAUTH_CLIENT_ID"
  client_secret: "YOUR_OAUTH_CLIENT_SECRET"
EOF

# Encrypt with SOPS
sops -e /tmp/tailscale-oauth-secret.yaml > helmfile/manifests/tailscale-oauth-secret.enc.yaml

# Apply encrypted secret
sops -d helmfile/manifests/tailscale-oauth-secret.enc.yaml | kubectl apply -f -
```

### 3. Enable Tailscale Operator in Helmfile

The operator is already enabled in `helmfile/config/enabled.yaml`:

```yaml
enabled:
  tailscaleOperator: true
```

### 4. Deploy Tailscale Operator

```bash
cd helmfile

# Deploy Tailscale operator
helmfile -l name=tailscale-operator apply

# Verify deployment
kubectl get pods -n tailscale
kubectl logs -n tailscale -l app=tailscale-operator
```

### 5. Verify Operator Functionality

The operator should automatically register itself in your Tailscale network:

```bash
# Check Tailscale status on control plane
tailscale status

# You should see the operator pod listed
```

## Part 3: Configure K3s for Tailscale Networking

The K3s configuration has been updated to disable Flannel and use Tailscale for inter-node communication.

### Verify K3s Configuration

```bash
# On control plane node
sudo cat /etc/systemd/system/k3s.service

# Should include:
# --disable=traefik
# --disable=servicelb
# --flannel-backend=none
# --disable-network-policy
```

### Node Labels for Workload Placement

Nodes are labeled automatically based on inventory configuration:

```bash
# Check node labels
kubectl get nodes --show-labels

# Expected labels:
# - topology.kubernetes.io/zone=home (control node)
# - topology.kubernetes.io/zone=netcup (worker node)
# - workload.kubernetes.io/cardano=true (for Cardano workload)
```

## Part 4: Testing Tailscale Connectivity

### Test Inter-Node Communication

```bash
# From control plane, ping worker via Tailscale IP
tailscale ip -4 netcup-worker
ping $(tailscale ip -4 netcup-worker)

# From worker, ping control plane
tailscale ip -4 control-node
ping $(tailscale ip -4 control-node)
```

### Test Kubernetes API Access

```bash
# From worker node, test API server access via Tailscale
curl -k https://$(tailscale ip -4 control-node):6443/livez

# Should return: ok
```

### Test Pod-to-Pod Communication

```bash
# Create test pods on different nodes
kubectl run test-control --image=nginx --overrides='{"spec":{"nodeName":"control-node"}}'
kubectl run test-worker --image=nginx --overrides='{"spec":{"nodeName":"netcup-worker"}}'

# Get pod IPs
kubectl get pods -o wide

# Exec into test-control and ping test-worker
kubectl exec -it test-control -- ping <test-worker-ip>

# Clean up
kubectl delete pod test-control test-worker
```

## Part 5: Tailscale for Services

### Expose Service via Tailscale

You can expose Kubernetes services to your Tailscale network:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "my-service"
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

This creates a Tailscale hostname `my-service.tailnet-name.ts.net` accessible from any device on your Tailscale network.

## Troubleshooting

### Tailscale Not Connecting

```bash
# Check Tailscale status
sudo tailscale status

# Check Tailscaled service
sudo systemctl status tailscaled

# Check logs
sudo journalctl -u tailscaled -f

# Re-authenticate
sudo tailscale up --authkey=YOUR_AUTH_KEY
```

### Operator Pod Not Starting

```bash
# Check pod status
kubectl get pods -n tailscale
kubectl describe pod -n tailscale <pod-name>

# Check logs
kubectl logs -n tailscale <pod-name>

# Verify secret
kubectl get secret operator-oauth -n tailscale -o yaml
```

### Nodes Not Communicating

```bash
# Check Tailscale connectivity
tailscale ping <node-name>

# Check ACLs in Tailscale admin console
# Ensure k8s tags have proper permissions

# Check firewall rules
sudo iptables -L -n | grep 41641
sudo ufw status
```

### Pods Not Getting IPs

```bash
# Check CNI configuration
ls -la /etc/cni/net.d/

# Verify K3s is not running Flannel
kubectl get pods -n kube-system

# Check pod network
kubectl get pods -A -o wide
```

## Security Best Practices

1. **Use Tags**: Tag all cluster nodes with `tag:k8s` for easy ACL management
2. **Restrict ACLs**: Only allow necessary ports between nodes
3. **Rotate Keys**: Regularly rotate Tailscale auth keys and OAuth credentials
4. **Enable MagicDNS**: Use Tailscale MagicDNS for easy hostname resolution
5. **Monitor Access**: Regularly review Tailscale audit logs
6. **Backup Config**: Keep ACL configuration in version control

## Advanced Configuration

### Subnet Routing

Expose specific subnets through Tailscale:

```bash
# On control node, advertise Kubernetes service subnet
sudo tailscale up --advertise-routes=10.43.0.0/16

# Approve route in Tailscale admin console
```

### Exit Nodes

Configure worker node as exit node for external traffic:

```bash
# On worker node
sudo tailscale up --advertise-exit-node

# Approve in Tailscale admin console
```

### Custom DNS

Configure custom DNS for cluster services:

```bash
# Add to Tailscale DNS settings
*.k8s.example.com -> 10.43.0.10
```

## References

- [Tailscale Documentation](https://tailscale.com/kb/)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [Tailscale ACLs](https://tailscale.com/kb/1018/acls)
- [K3s Networking](https://docs.k3s.io/networking)
