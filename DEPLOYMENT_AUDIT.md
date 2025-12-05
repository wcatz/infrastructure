# Deployment Audit and Testing Guide

This document provides a comprehensive procedure for auditing and testing infrastructure deployments on fresh bare-metal/VM instances.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Clean Deployment Procedure](#clean-deployment-procedure)
- [Verification Checklist](#verification-checklist)
- [Common Issues](#common-issues)
- [Rollback Procedures](#rollback-procedures)

## Overview

This guide ensures that infrastructure deployments work correctly from scratch, validating:
- Ansible playbooks deploy k3s and Tailscale correctly
- Helmfile deploys services without legacy ingress/LB dependencies
- Services are accessible via Cloudflared tunnels and direct TCP
- No HAProxy, MetalLB, or other load balancer components interfere

**Architecture Validation**:
- Control Plane: Internal-only (Tailscale, no public exposure)
- Worker: Public IP, Cloudflared for HTTP/S, NodePort for TCP/UDP
- Network: Tailscale mesh + public IPs (no load balancer required)

## Prerequisites

### Hardware/Infrastructure

**Control Plane Node**:
- Fresh Ubuntu 20.04+ or Debian 11+ installation
- Minimum 1GB RAM, 10GB disk
- Network access (can be behind CGNAT/NAT)
- SSH access configured

**Worker Node(s)**:
- Fresh Ubuntu 20.04+ or Debian 11+ installation
- Minimum 2GB RAM, 20GB disk
- **Public IP address** (required for direct service access)
- SSH access configured

### Accounts & Services

- [ ] Tailscale account with auth key ready
- [ ] Cloudflare account with domain configured
- [ ] Cloudflare tunnel created and credentials downloaded
- [ ] GitHub repository access for infrastructure code

### Local Tools

```bash
# Install required tools
# macOS
brew install ansible age sops cloudflared helmfile helm

# Linux (Ubuntu/Debian)
sudo apt update
sudo apt install -y ansible python3-pip
pip3 install jmespath  # Required for Ansible JSON queries

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Helmfile
wget https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64
chmod +x helmfile_linux_amd64
sudo mv helmfile_linux_amd64 /usr/local/bin/helmfile

# Install age and sops
wget https://github.com/FiloSottile/age/releases/latest/download/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age /usr/local/bin/

wget https://github.com/mozilla/sops/releases/latest/download/sops-v3.8.1.linux.amd64
chmod +x sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
```

## Clean Deployment Procedure

### Step 1: Prepare Local Environment

```bash
# Clone infrastructure repository
git clone https://github.com/wcatz/infrastructure.git
cd infrastructure

# Validate repository structure
bash scripts/validate.sh

# Expected output: "✅ Validation passed! ✨"
```

### Step 2: Configure Ansible

```bash
cd ansible

# Create vault password
cp .vault_pass.example .vault_pass
echo "YOUR_SECURE_PASSWORD" > .vault_pass
chmod 600 .vault_pass

# Create and encrypt vault variables
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit vault.yml with your credentials:
# - K3s cluster token (generate: openssl rand -hex 32)
# - Tailscale auth key (from Tailscale admin console)
vim group_vars/all/vault.yml

# Encrypt the vault
ansible-vault encrypt group_vars/all/vault.yml

# Create inventory
cp inventory.ini.example inventory.ini

# Edit inventory with your server IPs
vim inventory.ini
# Example:
# [k3s_servers]
# control-plane ansible_host=192.168.1.100 ansible_user=ubuntu
# 
# [k3s_agents]
# worker-01 ansible_host=1.2.3.4 ansible_user=ubuntu
```

### Step 3: Test Connectivity

```bash
# Test SSH access to all nodes
ansible all -i inventory.ini -m ping

# Expected output: SUCCESS for all nodes
```

### Step 4: Deploy Tailscale

```bash
# Deploy Tailscale to all nodes
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# Verify Tailscale installation
ansible all -i inventory.ini -m shell -a "tailscale ip -4"

# Note the Tailscale IPs for each node
# Control plane example: 100.64.1.10
# Worker example: 100.64.1.20
```

### Step 5: Update Inventory with Tailscale IPs

```bash
# Edit inventory to use Tailscale IP for control plane
vim inventory.ini

# Update control plane ansible_host to Tailscale IP
# [k3s_servers]
# control-plane ansible_host=100.64.1.10 ansible_user=ubuntu
```

### Step 6: Deploy K3s Cluster

```bash
# Deploy k3s to all nodes
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Expected: Control plane running k3s server, workers running k3s agent
```

### Step 7: Configure Kubeconfig

```bash
# Get kubeconfig from control plane
scp ubuntu@100.64.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update server URL to use Tailscale IP
sed -i 's/127.0.0.1/100.64.1.10/' ~/.kube/config

# Ensure your local machine has Tailscale installed and connected
tailscale status

# Test cluster access
kubectl get nodes
kubectl get pods -A
```

### Step 8: Verify Cluster Configuration

```bash
# Check nodes are ready
kubectl get nodes -o wide

# Expected output:
# - Control plane: Ready, with control-plane role
# - Workers: Ready, no specific role

# Verify control plane taint
kubectl describe node control-plane | grep Taints

# Expected: node-role.kubernetes.io/control-plane:NoSchedule

# Verify worker nodes have no taints
kubectl describe node worker-01 | grep Taints

# Expected: <none> or only daemonset-tolerating taints

# Check Traefik and servicelb are disabled
kubectl get pods -n kube-system | grep -E "traefik|svclb"

# Expected: No traefik or svclb pods (disabled in k3s deployment)
```

### Step 9: Deploy Infrastructure Services

```bash
cd ../helmfile

# Review enabled services
cat config/enabled.yaml

# Expected:
# - prometheus: true
# - cloudflared: true
# - grafana: true
# - externalSecrets: true
# - tailscaleOperator: true
# - haproxyIngress: false (LEGACY/OPTIONAL)

# Verify no HAProxy/MetalLB/load balancer components are enabled

# Configure Cloudflared credentials
kubectl create namespace cloudflare
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/TUNNEL-ID.json \
  -n cloudflare

# Deploy services
helmfile apply

# Monitor deployment
watch kubectl get pods -A
```

### Step 10: Verify Service Deployment

```bash
# Check all pods are running
kubectl get pods -A | grep -v Running

# Expected: No pods in error states

# Verify Cloudflared is running
kubectl get pods -n cloudflare
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Expected: Tunnel connected successfully

# Check monitoring stack
kubectl get pods -n monitoring

# Expected: Prometheus and Grafana pods running

# Verify NO HAProxy or MetalLB components
kubectl get pods -A | grep -i haproxy
kubectl get pods -A | grep -i metallb

# Expected: No output (these should not be deployed)
```

### Step 11: Test HTTP/S Access via Cloudflared

```bash
# Test Cloudflared tunnel connectivity
curl -I https://app.example.com

# Expected: HTTP 200 or 404 (depending on service deployment)

# Check tunnel logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared --tail=50

# Expected: No connection errors
```

### Step 12: Test Direct TCP Access (NodePort)

```bash
# Deploy a test service with NodePort
kubectl create deployment test-nginx --image=nginx:alpine
kubectl expose deployment test-nginx --type=NodePort --port=80

# Get the NodePort
NODEPORT=$(kubectl get svc test-nginx -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort: $NODEPORT"

# Get worker public IP
WORKER_IP=$(kubectl get nodes worker-01 -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
echo "Worker IP: $WORKER_IP"

# Test direct access
curl http://$WORKER_IP:$NODEPORT

# Expected: Nginx welcome page

# Cleanup test service
kubectl delete deployment test-nginx
kubectl delete svc test-nginx
```

## Verification Checklist

### Infrastructure Verification

- [ ] All nodes show as Ready in `kubectl get nodes`
- [ ] Control plane has NoSchedule taint
- [ ] Worker nodes have no blocking taints
- [ ] Traefik is not running (k3s deployed with --disable traefik)
- [ ] servicelb is not running (k3s deployed with --disable servicelb)
- [ ] Tailscale is running on all nodes
- [ ] Nodes can communicate via Tailscale mesh

### Network Configuration Verification

- [ ] NO HAProxy pods are running
- [ ] NO MetalLB pods are running
- [ ] NO traditional load balancer services exist
- [ ] Cloudflared pods are running and connected
- [ ] Cloudflared tunnel shows as healthy in logs
- [ ] Worker nodes have public IP addresses
- [ ] NodePort services are accessible via worker public IPs

### Service Deployment Verification

- [ ] Prometheus is running in monitoring namespace
- [ ] Grafana is running in monitoring namespace
- [ ] Cloudflared is running in cloudflare namespace
- [ ] External Secrets (if enabled) is running
- [ ] Tailscale Operator (if enabled) is running
- [ ] All pods are in Running state
- [ ] No CrashLoopBackOff or Error states

### Access Verification

- [ ] Can access cluster via kubectl (over Tailscale)
- [ ] Can access HTTP/S services via Cloudflared tunnels
- [ ] Can access NodePort services via worker public IPs
- [ ] Monitoring dashboards are accessible
- [ ] Cloudflare tunnel status shows healthy

### Configuration Verification

- [ ] helmfile/config/enabled.yaml has haproxyIngress: false
- [ ] No HAProxy references in cloudflared values files
- [ ] Cloudflared ingress rules route directly to services
- [ ] README.md reflects current architecture (no HAProxy/MetalLB)
- [ ] Documentation is accurate and up-to-date

## Common Issues

### Issue: Pods Stuck in Pending

**Symptoms**: Pods show Pending state and never schedule

**Diagnosis**:
```bash
kubectl describe pod <pod-name>

# Check events for scheduling errors
kubectl get events --sort-by='.lastTimestamp'
```

**Common Causes**:
1. Control plane taint preventing scheduling
   - Verify workers exist and are Ready
   - Check pod tolerations if needed

2. Insufficient resources
   - Check node resources: `kubectl describe node worker-01`
   - Add more workers or increase worker resources

**Resolution**:
```bash
# Verify workers are available
kubectl get nodes -o wide

# Check node capacity
kubectl describe node worker-01 | grep -A 5 "Allocated resources"
```

### Issue: Cloudflared Not Connecting

**Symptoms**: Cloudflared pods crash or tunnel shows disconnected

**Diagnosis**:
```bash
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared
kubectl describe pod -n cloudflare <pod-name>
```

**Common Causes**:
1. Invalid credentials
2. Tunnel not configured in Cloudflare dashboard
3. DNS not configured

**Resolution**:
```bash
# Verify credentials secret exists
kubectl get secret cloudflared-credentials -n cloudflare -o yaml

# Recreate credentials if needed
kubectl delete secret cloudflared-credentials -n cloudflare
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/TUNNEL-ID.json \
  -n cloudflare

# Restart cloudflared pods
kubectl rollout restart deployment/cloudflared -n cloudflare
```

### Issue: NodePort Not Accessible

**Symptoms**: Cannot access service via worker public IP and NodePort

**Diagnosis**:
```bash
# Check service
kubectl get svc <service-name>

# Verify pod is running
kubectl get pods -l app=<app-name>

# Test from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://<service-name>.<namespace>.svc.cluster.local:<port>
```

**Common Causes**:
1. Firewall blocking NodePort
2. Service not exposed as NodePort
3. Pod not running

**Resolution**:
```bash
# Check worker node firewall
ssh ubuntu@worker-01 "sudo ufw status"

# Allow NodePort range (30000-32767)
ssh ubuntu@worker-01 "sudo ufw allow 30000:32767/tcp"

# Verify service type
kubectl get svc <service-name> -o yaml | grep type

# Expected: type: NodePort
```

### Issue: Legacy HAProxy/Ingress References

**Symptoms**: HAProxy pods running when they shouldn't be

**Diagnosis**:
```bash
# Check for HAProxy pods
kubectl get pods -A | grep -i haproxy

# Check enabled.yaml configuration
cat helmfile/config/enabled.yaml | grep haproxy
```

**Resolution**:
```bash
# Ensure haproxyIngress is disabled
# Edit helmfile/config/enabled.yaml
# Set: haproxyIngress: false

# Remove HAProxy deployment if present
helmfile destroy

# Redeploy without HAProxy
helmfile apply
```

## Rollback Procedures

### Rollback to Previous Helmfile Deployment

```bash
cd helmfile

# Check Helm releases
helm list -A

# Rollback specific release
helm rollback <release-name> <revision> -n <namespace>

# Example: Rollback Cloudflared
helm rollback cloudflared 1 -n cloudflare
```

### Rollback to Previous Git Commit

```bash
# View recent commits
git log --oneline

# Checkout previous version
git checkout <commit-hash>

# Redeploy
cd helmfile
helmfile apply
```

### Complete Cluster Teardown

```bash
# Remove k3s from all nodes
cd ansible
ansible-playbook -i inventory.ini playbooks/teardown-k3s.yaml

# Note: You may need to create this playbook or manually uninstall:
ansible all -i inventory.ini -m shell -a "/usr/local/bin/k3s-uninstall.sh" -b

# Clean up local kubeconfig
rm ~/.kube/config
```

## Continuous Validation

### Automated Health Checks

```bash
# Create a CronJob for regular validation
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: infrastructure-health-check
  namespace: default
spec:
  schedule: "*/15 * * * *"  # Every 15 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: health-check
            image: curlimages/curl:latest
            command:
            - /bin/sh
            - -c
            - |
              # Check if we can reach services
              curl -f http://prometheus-server.monitoring.svc.cluster.local:80 || exit 1
              echo "Health check passed"
          restartPolicy: OnFailure
EOF
```

### Monitoring Deployment Status

```bash
# Monitor all pods
watch kubectl get pods -A

# Check for pod issues
kubectl get pods -A | grep -v Running | grep -v Completed

# Check events for errors
kubectl get events -A --sort-by='.lastTimestamp' | grep -i error

# Monitor Cloudflared logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared -f
```

## Best Practices

1. **Always use fresh instances**: Don't reuse servers with previous k3s installations
2. **Document deviations**: If you enable legacy components, document why and where
3. **Test incrementally**: Deploy services one at a time, verify each works
4. **Keep backups**: Before major changes, backup with Velero
5. **Validate configuration**: Run `scripts/validate.sh` before deploying
6. **Use version control**: Commit all configuration changes to Git
7. **Monitor continuously**: Set up alerts for pod failures and tunnel disconnections
8. **Document worker IPs**: Keep track of worker public IPs for NodePort services
9. **Test failover**: Periodically test pod and node failover scenarios
10. **Review architecture**: Ensure no load balancer components are running

## Related Documentation

- [README.md](README.md) - Architecture overview
- [HYBRID_CLUSTER_SETUP.md](HYBRID_CLUSTER_SETUP.md) - Detailed setup guide
- [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) - Backup and recovery procedures
- [TESTING.md](TESTING.md) - Comprehensive testing procedures
- [CLOUDFLARED_SETUP.md](helmfile/CLOUDFLARED_SETUP.md) - Cloudflared tunnel configuration
