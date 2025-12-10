# Cloudflare Tunnel Setup Guide

This guide provides comprehensive instructions for integrating Cloudflare Tunnel into your Kubernetes infrastructure cluster, with a focus on **reusing existing tunnel credentials** for seamless integration.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Using Existing Tunnel Credentials](#using-existing-tunnel-credentials)
- [Creating a New Tunnel](#creating-a-new-tunnel)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [DNS Setup](#dns-setup)
- [Validation](#validation)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

## Overview

Cloudflare Tunnel (formerly Argo Tunnel) creates a secure, outbound-only connection from your Kubernetes cluster to Cloudflare's edge network. This eliminates the need for:

- Public IP addresses for the control plane
- Inbound firewall rules
- Load balancers (for HTTP/HTTPS traffic)
- Port forwarding

**Key Benefits:**
- ✅ Zero Trust network access
- ✅ DDoS protection via Cloudflare edge
- ✅ Automatic SSL/TLS termination
- ✅ No exposed ports on origin
- ✅ Works behind CGNAT/firewall

## Prerequisites

Before starting, ensure you have:

- **Cloudflare Account**: Free tier is sufficient
- **Domain**: Managed by Cloudflare DNS
- **Kubernetes Cluster**: k3s cluster deployed and accessible
- **Tools Installed**:
  - `kubectl` - Kubernetes CLI
  - `cloudflared` - Cloudflare Tunnel client
  - `sops` - Secrets encryption
  - `age` - Encryption keys
  - `helmfile` - Chart deployment

### Install cloudflared

```bash
# macOS
brew install cloudflared

# Linux (amd64)
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared

# Linux (arm64)
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
chmod +x cloudflared-linux-arm64
sudo mv cloudflared-linux-arm64 /usr/local/bin/cloudflared

# Verify installation
cloudflared --version
```

## Using Existing Tunnel Credentials

If you already have a Cloudflare Tunnel created and want to reuse its credentials in your infrastructure cluster, follow this workflow.

### Step 1: Locate Existing Credentials

Existing tunnel credentials are typically stored in one of these locations:

```bash
# Default location after tunnel creation
~/.cloudflared/<TUNNEL-ID>.json

# Alternative location (if moved)
/etc/cloudflared/<TUNNEL-ID>.json

# Or check your Cloudflare dashboard for tunnel details
# https://one.dash.cloudflare.com/
```

**Credentials file structure:**
```json
{
  "AccountTag": "abc123def456ghi789jkl012mno345pq",
  "TunnelSecret": "secretbase64encodedstring==",
  "TunnelID": "12345678-1234-1234-1234-123456789abc",
  "TunnelName": "my-infrastructure-tunnel"
}
```

### Step 2: Retrieve Tunnel Information

```bash
# Login to Cloudflare
cloudflared tunnel login

# List existing tunnels
cloudflared tunnel list

# Get tunnel details (note down Tunnel ID and Name)
cloudflared tunnel info <TUNNEL-NAME or TUNNEL-ID>
```

**Example output:**
```
ID:         12345678-1234-1234-1234-123456789abc
Name:       infrastructure-prod-tunnel
Created:    2024-01-15 10:30:00 +0000 UTC
Connections: 2 active
```

### Step 3: Copy Credentials to Working Directory

```bash
# Create temporary directory for credentials processing
mkdir -p /tmp/cloudflared-setup
cd /tmp/cloudflared-setup

# Copy existing credentials (replace TUNNEL-ID with your actual ID)
TUNNEL_ID="12345678-1234-1234-1234-123456789abc"
cp ~/.cloudflared/${TUNNEL_ID}.json ./credentials.json

# Verify the credentials file
cat credentials.json | jq .
```

### Step 4: Create Kubernetes Secret YAML

```bash
# Create unencrypted Kubernetes secret manifest
cat > cloudflared-credentials.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-credentials
  namespace: cloudflare
type: Opaque
stringData:
  credentials.json: |
$(cat credentials.json | sed 's/^/    /')
EOF

# Verify the secret structure
cat cloudflared-credentials.yaml
```

### Step 5: Encrypt Credentials with SOPS

```bash
# Ensure your age key is configured
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Encrypt the secret
sops -e cloudflared-credentials.yaml > cloudflared-credentials.enc.yaml

# Move to repository secrets directory
mv cloudflared-credentials.enc.yaml \
  /home/runner/work/infrastructure/infrastructure/helmfile/secrets/

# Securely delete plaintext files
shred -u cloudflared-credentials.yaml credentials.json
cd -
rm -rf /tmp/cloudflared-setup
```

### Step 6: Update Tunnel Configuration

Create or update the Helmfile values with your tunnel details:

```bash
# Edit the cloudflared values file
vim helmfile/values/cloudflared-values.yaml
```

Update the tunnel information:

```yaml
# Cloudflare tunnel configuration
cloudflare:
  # Your existing tunnel name
  tunnelName: "infrastructure-prod-tunnel"
  
  # Your existing tunnel ID
  tunnelId: "12345678-1234-1234-1234-123456789abc"

# Ingress rules for routing traffic
ingress:
  # Add your service routes
  - hostname: app.example.com
    service: http://my-app.default.svc.cluster.local:80
  - hostname: api.example.com
    service: http://api-service.default.svc.cluster.local:8080
  # Required catch-all rule
  - service: http_status:404
```

### Step 7: Deploy the Encrypted Secret

```bash
# Create the cloudflare namespace
kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -

# Deploy the encrypted secret
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -

# Verify secret creation
kubectl get secret cloudflared-credentials -n cloudflare
kubectl describe secret cloudflared-credentials -n cloudflare
```

### Step 8: Configure DNS Routes

If you're reusing an existing tunnel, you may already have DNS routes configured. To add new routes:

```bash
# Add DNS route for a new hostname
cloudflared tunnel route dns infrastructure-prod-tunnel app.example.com
cloudflared tunnel route dns infrastructure-prod-tunnel api.example.com

# List existing routes
cloudflared tunnel route list
```

## Creating a New Tunnel

If you don't have an existing tunnel or want to create a new one for this cluster:

### Step 1: Authenticate with Cloudflare

```bash
# Login to Cloudflare (opens browser)
cloudflared tunnel login
```

This creates a certificate at `~/.cloudflared/cert.pem`.

### Step 2: Create Tunnel

```bash
# Create a new tunnel
cloudflared tunnel create infrastructure-cluster-tunnel

# Save the output - you'll need the Tunnel ID
# Example output:
# Tunnel credentials written to /home/user/.cloudflared/12345678-1234-1234-1234-123456789abc.json
# Created tunnel infrastructure-cluster-tunnel with id 12345678-1234-1234-1234-123456789abc
```

### Step 3: Follow Steps 3-7 from "Using Existing Tunnel Credentials"

The process is identical once you have the credentials file.

## Configuration

### Basic Configuration Template

```yaml
# helmfile/values/cloudflared-values.yaml
replicaCount: 2

cloudflare:
  tunnelName: "infrastructure-cluster-tunnel"
  tunnelId: "<YOUR-TUNNEL-ID>"

ingress:
  # Route HTTP/HTTPS traffic to services
  - hostname: grafana.example.com
    service: http://prometheus-grafana.monitoring.svc.cluster.local:80
  - hostname: prometheus.example.com
    service: http://prometheus-server.monitoring.svc.cluster.local:80
  - hostname: app.example.com
    service: http://app-service.default.svc.cluster.local:8080
  # Catch-all (required)
  - service: http_status:404

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
```

### Environment-Specific Configuration

For production environments, create environment-specific overrides:

```yaml
# helmfile/environments/prod/cloudflared-values.yaml
cloudflare:
  tunnelName: "infrastructure-prod-tunnel"
  tunnelId: "production-tunnel-id"

ingress:
  - hostname: app.production.example.com
    service: http://app-service.production.svc.cluster.local:80
  - service: http_status:404

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

autoscaling:
  minReplicas: 3
  maxReplicas: 20
```

### Advanced Configuration Options

```yaml
# Additional environment variables for fine-tuning
env:
  - name: TUNNEL_LOGLEVEL
    value: "info"  # debug, info, warn, error
  - name: TUNNEL_TRANSPORT_PROTOCOL
    value: "quic"  # quic or http2
  - name: TUNNEL_NO_AUTOUPDATE
    value: "true"
  - name: TUNNEL_RETRIES
    value: "5"
  - name: TUNNEL_MAX_RETRIES
    value: "5"

# Custom metrics configuration
metrics:
  enabled: true
  port: 2000

# Security context
securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  fsGroup: 65532
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true

# Pod anti-affinity for high availability
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - cloudflared
        topologyKey: kubernetes.io/hostname
```

## Deployment

### Deploy with Helmfile

```bash
# Navigate to helmfile directory
cd helmfile

# Preview changes (recommended)
helmfile diff

# Deploy cloudflared
helmfile apply

# Or deploy to specific environment
helmfile -e prod apply
```

### Enable Cloudflared in Helmfile

Edit `helmfile/config/enabled.yaml`:

```yaml
enabled:
  cloudflared: true
```

Or environment-specific:

```yaml
# helmfile/environments/prod/enabled.yaml
enabled:
  cloudflared: true
```

### Manual Deployment (without Helmfile)

If deploying manually with helm:

```bash
# Create namespace
kubectl create namespace cloudflare

# Deploy secret
sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -

# Install/upgrade cloudflared chart
helm upgrade --install cloudflared ./charts/cloudflared \
  -n cloudflare \
  -f helmfile/values/cloudflared-values.yaml
```

## DNS Setup

### Configure DNS Records

For each hostname in your ingress configuration:

```bash
# Method 1: Using cloudflared CLI (recommended)
cloudflared tunnel route dns infrastructure-cluster-tunnel app.example.com
cloudflared tunnel route dns infrastructure-cluster-tunnel api.example.com
cloudflared tunnel route dns infrastructure-cluster-tunnel grafana.example.com

# Method 2: Using Cloudflare Dashboard
# 1. Go to https://dash.cloudflare.com/
# 2. Select your domain
# 3. Navigate to DNS → Records
# 4. Add CNAME record:
#    Type: CNAME
#    Name: app (or subdomain)
#    Target: <TUNNEL-ID>.cfargotunnel.com
#    Proxy: ON (orange cloud)
```

### Verify DNS Routes

```bash
# List all routes for the tunnel
cloudflared tunnel route list

# Check DNS propagation
dig app.example.com
nslookup api.example.com
```

### Wildcard DNS

For wildcard subdomains:

```bash
# Create wildcard route
cloudflared tunnel route dns infrastructure-cluster-tunnel "*.apps.example.com"

# Or via dashboard: Add CNAME for *.apps pointing to tunnel
```

## Validation

### Check Pod Status

```bash
# Verify cloudflared pods are running
kubectl get pods -n cloudflare

# Expected output:
# NAME                          READY   STATUS    RESTARTS   AGE
# cloudflared-xxxxxxxxx-xxxxx   1/1     Running   0          5m
# cloudflared-xxxxxxxxx-xxxxx   1/1     Running   0          5m

# Check pod logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Logs should show successful connection:
# INFO Connection established with Cloudflare edge
# INFO Registered tunnel connection
```

### Test Tunnel Connectivity

```bash
# Check tunnel status from Cloudflare side
cloudflared tunnel info infrastructure-cluster-tunnel

# Should show active connections (matches replica count)
# Connections: 2 active
```

### Test HTTP Access

```bash
# Test external access to your services
curl -I https://app.example.com
curl -I https://api.example.com
curl -I https://grafana.example.com

# Expected: 200 OK or redirect to login page (depending on service)
```

### Verify Secret Mounting

```bash
# Check if secret is properly mounted in pods
kubectl exec -n cloudflare deployment/cloudflared -- \
  ls -la /etc/cloudflared/

# Should show credentials.json file
```

### Monitor Metrics

```bash
# Forward metrics port
kubectl port-forward -n cloudflare deployment/cloudflared 2000:2000

# Access metrics endpoint
curl http://localhost:2000/metrics

# Or add to Prometheus scrape config for monitoring
```

## Troubleshooting

### Pods Not Starting

**Issue**: Pods stuck in `Pending` or `CrashLoopBackOff`

```bash
# Check pod events
kubectl describe pod -n cloudflare <pod-name>

# Common causes:
# 1. Missing credentials secret
kubectl get secret cloudflared-credentials -n cloudflare

# 2. Invalid credentials
kubectl logs -n cloudflare <pod-name>

# 3. Resource constraints
kubectl get nodes
kubectl describe nodes
```

**Solution**: Verify secret exists and contains valid credentials.

### Connection Issues

**Issue**: Tunnel not connecting to Cloudflare edge

```bash
# Check pod logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared --tail=50

# Look for errors:
# - "authentication failed" → Invalid credentials
# - "tunnel not found" → Tunnel doesn't exist or was deleted
# - "connection refused" → Network/firewall issues
```

**Solution**:
```bash
# Verify tunnel exists
cloudflared tunnel list

# Test connectivity from pod
kubectl exec -n cloudflare deployment/cloudflared -- \
  cloudflared tunnel info <TUNNEL-ID>

# Check network policies
kubectl get networkpolicies -n cloudflare
```

### DNS Resolution Issues

**Issue**: Hostname not resolving or pointing to wrong location

```bash
# Check DNS records
dig app.example.com
nslookup app.example.com @1.1.1.1

# Verify tunnel routes
cloudflared tunnel route list
```

**Solution**:
```bash
# Re-add DNS route
cloudflared tunnel route dns infrastructure-cluster-tunnel app.example.com

# Wait for DNS propagation (usually < 5 minutes)
# Clear local DNS cache if needed
```

### Service Not Accessible

**Issue**: Tunnel connected but service returns 502/503

```bash
# Test service connectivity from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://app-service.default.svc.cluster.local:80

# Check service and endpoints
kubectl get svc -n default
kubectl get endpoints -n default
```

**Solution**:
- Verify service name and port in cloudflared-values.yaml
- Ensure service is using correct namespace
- Check if service pods are running

### Invalid Credentials

**Issue**: "authentication failed" errors in logs

```bash
# Verify secret content (be careful - contains sensitive data)
kubectl get secret cloudflared-credentials -n cloudflare -o yaml

# Check credentials structure
sops -d helmfile/secrets/cloudflared-credentials.enc.yaml
```

**Solution**:
```bash
# Re-create secret with correct credentials
cloudflared tunnel info <TUNNEL-NAME>  # Get correct tunnel ID

# Delete old secret and re-create
kubectl delete secret cloudflared-credentials -n cloudflare
sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -

# Restart pods
kubectl rollout restart deployment/cloudflared -n cloudflare
```

### High CPU/Memory Usage

**Issue**: Pods consuming excessive resources

```bash
# Check resource usage
kubectl top pods -n cloudflare

# Check HPA status
kubectl get hpa -n cloudflare
```

**Solution**:
```yaml
# Adjust resources in cloudflared-values.yaml
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

## Security Best Practices

### Credential Protection

1. **Never commit unencrypted credentials**
   ```bash
   # Always use SOPS encryption
   sops -e credentials.yaml > credentials.enc.yaml
   
   # Verify .gitignore excludes plaintext
   cat .gitignore | grep "credentials.yaml"
   ```

2. **Securely delete original credentials**
   ```bash
   # Use shred to overwrite file before deletion
   shred -u ~/.cloudflared/<TUNNEL-ID>.json
   ```

3. **Rotate credentials regularly**
   ```bash
   # Delete old tunnel
   cloudflared tunnel delete old-tunnel-name
   
   # Create new tunnel
   cloudflared tunnel create new-tunnel-name
   
   # Update secrets and redeploy
   ```

### Access Control

1. **Limit namespace access**
   ```yaml
   # Create RBAC policy limiting cloudflare namespace access
   apiVersion: rbac.authorization.k8s.io/v1
   kind: RoleBinding
   metadata:
     name: cloudflared-admin
     namespace: cloudflare
   subjects:
   - kind: User
     name: platform-admin
   roleRef:
     kind: ClusterRole
     name: admin
   ```

2. **Use service accounts with minimal permissions**
   ```yaml
   serviceAccount:
     create: true
     name: cloudflared
     annotations:
       # Add security annotations
   ```

3. **Enable audit logging**
   ```bash
   # Monitor secret access
   kubectl get events -n cloudflare --sort-by='.lastTimestamp'
   ```

### Network Security

1. **Use NetworkPolicies**
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: cloudflared-egress
     namespace: cloudflare
   spec:
     podSelector:
       matchLabels:
         app.kubernetes.io/name: cloudflared
     policyTypes:
     - Egress
     egress:
     - to:
       - namespaceSelector: {}
       ports:
       - protocol: TCP
         port: 443  # Allow HTTPS to Cloudflare
       - protocol: UDP
         port: 7844  # QUIC protocol
   ```

2. **Enable Pod Security Standards**
   ```yaml
   podSecurityContext:
     runAsNonRoot: true
     runAsUser: 65532
     fsGroup: 65532
     seccompProfile:
       type: RuntimeDefault
   
   securityContext:
     allowPrivilegeEscalation: false
     capabilities:
       drop:
       - ALL
     readOnlyRootFilesystem: true
   ```

### Monitoring and Alerting

1. **Set up Prometheus alerts**
   ```yaml
   # Alert on tunnel disconnections
   - alert: CloudflaredTunnelDown
     expr: up{job="cloudflared"} == 0
     for: 5m
     annotations:
       summary: "Cloudflared tunnel is down"
   ```

2. **Monitor credential expiration**
   - Set calendar reminders for credential rotation
   - Use secret expiration tracker (see `.github/secret-rotation-tracker.yaml`)

3. **Review logs regularly**
   ```bash
   # Check for authentication failures
   kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared | grep -i "error\|failed"
   ```

### Backup and Recovery

1. **Backup tunnel credentials**
   ```bash
   # Encrypted backup of credentials
   sops -d helmfile/secrets/cloudflared-credentials.enc.yaml > /secure/backup/location/credentials.yaml
   
   # Store in password manager or secure vault
   ```

2. **Document tunnel IDs**
   - Keep record of tunnel IDs in secure documentation
   - Store in password manager notes

3. **Test recovery procedure**
   ```bash
   # Simulate credential loss and recovery
   kubectl delete secret cloudflared-credentials -n cloudflare
   sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -
   kubectl rollout restart deployment/cloudflared -n cloudflare
   ```

## Additional Resources

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Tunnel Guide](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/)
- [SOPS Encryption Guide](../SECRETS.md#sops-with-age)
- [DNS Setup Guide](../DNS_SETUP.md)
- [Hybrid Cluster Architecture](../README.md#architecture)
- [Security Best Practices](../SECURITY.md)

---

**Need Help?**
- Review [Troubleshooting](#troubleshooting) section
- Check [GitHub Issues](https://github.com/wcatz/infrastructure/issues)
- Consult [Cloudflare Community](https://community.cloudflare.com/)
