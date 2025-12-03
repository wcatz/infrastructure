# Cloudflared Tunnel Setup Guide

This guide explains how to set up Cloudflared tunnels for HTTP/HTTPS ingress traffic.

## Overview

Cloudflared creates secure tunnels from your Kubernetes cluster to Cloudflare's edge network, allowing you to expose HTTP/HTTPS services without opening firewall ports or using traditional load balancers.

## Prerequisites

- A Cloudflare account with a domain configured
- `cloudflared` CLI installed (for tunnel creation)
- Access to your Kubernetes cluster
- kubectl configured

## Setup Steps

### 1. Install Cloudflared CLI

**macOS:**
```bash
brew install cloudflare/cloudflare/cloudflared
```

**Linux:**
```bash
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
chmod +x cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
```

**Windows:**
Download from: https://github.com/cloudflare/cloudflared/releases

### 2. Authenticate with Cloudflare

```bash
cloudflared tunnel login
```

This opens a browser window to authenticate and select your domain.

### 3. Create a Tunnel

```bash
cloudflared tunnel create infrastructure-tunnel
```

This command:
- Creates a new tunnel named `infrastructure-tunnel`
- Generates credentials in `~/.cloudflared/<TUNNEL-ID>.json`
- Returns a Tunnel ID (save this!)

**Save the output:**
- Tunnel ID: `<TUNNEL-ID>`
- Credentials file: `~/.cloudflared/<TUNNEL-ID>.json`

### 4. Create Kubernetes Secret

Store the tunnel credentials as a Kubernetes secret:

```bash
# Create the cloudflare namespace
kubectl create namespace cloudflare

# Create the secret from the credentials file
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
  -n cloudflare
```

Or create from literal JSON (if you have the credentials):

```bash
kubectl create secret generic cloudflared-credentials \
  --from-literal=credentials.json='{"AccountTag":"<account-id>","TunnelSecret":"<secret>","TunnelID":"<tunnel-id>"}' \
  -n cloudflare
```

### 5. Configure DNS Records

Create DNS records pointing to your tunnel. You can do this via:

**Option A: Cloudflared CLI**
```bash
# Route a hostname to your tunnel
cloudflared tunnel route dns infrastructure-tunnel app.example.com
cloudflared tunnel route dns infrastructure-tunnel api.example.com
cloudflared tunnel route dns infrastructure-tunnel monitoring.example.com
```

**Option B: Cloudflare Dashboard**
1. Go to https://dash.cloudflare.com/
2. Select your domain
3. Go to DNS → Records
4. Add CNAME records:
   - Name: `app` (or subdomain)
   - Target: `<TUNNEL-ID>.cfargotunnel.com`
   - Proxy status: Proxied (orange cloud)

**Option C: Terraform/IaC**
```hcl
resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "app"
  value   = "${var.tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
```

### 6. Update Helmfile Values

Edit `helmfile/values/cloudflared-values.yaml`:

```yaml
cloudflare:
  tunnelName: "infrastructure-tunnel"
  tunnelId: "<TUNNEL-ID>"  # From step 3
  
ingress:
  # Route app.example.com to NGINX ingress controller
  - hostname: app.example.com
    service: http://nginx-ingress-controller.ingress-nginx.svc.cluster.local:80
  
  # Route api.example.com to API service
  - hostname: api.example.com
    service: http://api-service.default.svc.cluster.local:8080
  
  # Route monitoring.example.com to Prometheus
  - hostname: monitoring.example.com
    service: http://prometheus-server.monitoring.svc.cluster.local:80
  
  # Default catch-all (required)
  - service: http_status:404
```

### 7. Deploy with Helmfile

```bash
cd helmfile
helmfile apply
```

Or deploy only Cloudflared:

```bash
helmfile -l name=cloudflared apply
```

### 8. Verify Deployment

```bash
# Check pods
kubectl get pods -n cloudflare

# Check logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Check tunnel status
cloudflared tunnel info infrastructure-tunnel
```

## Configuration Options

### Ingress Rules

The `ingress` section in `cloudflared-values.yaml` defines routing rules:

```yaml
ingress:
  # Route specific hostname to a service
  - hostname: myapp.example.com
    service: http://service-name.namespace.svc.cluster.local:port
  
  # With path-based routing
  - hostname: api.example.com
    path: /v1/*
    service: http://api-v1.default.svc.cluster.local:8080
  
  # HTTPS backend
  - hostname: secure.example.com
    service: https://secure-service.default.svc.cluster.local:443
    originRequest:
      noTLSVerify: true  # For self-signed certs
  
  # WebSocket support
  - hostname: ws.example.com
    service: http://websocket-service.default.svc.cluster.local:8080
    originRequest:
      noTLSVerify: false
  
  # Catch-all (required as last rule)
  - service: http_status:404
```

### Origin Request Options

Customize how Cloudflared connects to your services:

```yaml
ingress:
  - hostname: app.example.com
    service: http://app.default.svc.cluster.local:80
    originRequest:
      connectTimeout: 30s
      tlsTimeout: 10s
      tcpKeepAlive: 30s
      noHappyEyeballs: false
      keepAliveConnections: 100
      keepAliveTimeout: 90s
      httpHostHeader: app.example.com
      originServerName: app.example.com
      caPool: /etc/ssl/certs/ca-certificates.crt
      noTLSVerify: false
      disableChunkedEncoding: false
      bastionMode: false
      proxyAddress: ""
      proxyPort: 0
      proxyType: ""
```

## DNS Management

### Updating DNS Records

When you add or remove services, update DNS records accordingly:

**Add new service:**
```bash
cloudflared tunnel route dns infrastructure-tunnel newapp.example.com
```

**List current routes:**
```bash
cloudflared tunnel route dns list
```

**Delete route:**
```bash
cloudflared tunnel route dns delete <ROUTE-ID>
```

### Wildcard DNS

For wildcard subdomains:

```bash
cloudflared tunnel route dns infrastructure-tunnel "*.apps.example.com"
```

Then configure ingress rules:
```yaml
ingress:
  - hostname: "*.apps.example.com"
    service: http://nginx-ingress-controller.ingress-nginx.svc.cluster.local:80
```

## Cloudflare Access Integration

Protect services with Cloudflare Access (Zero Trust):

1. **Create Access Policy** in Cloudflare Dashboard
2. **No changes needed** in Helmfile - Access is applied at Cloudflare edge
3. Users will be prompted to authenticate before accessing the service

## Monitoring

### Metrics

Cloudflared exposes Prometheus metrics on port 2000:

```bash
kubectl port-forward -n cloudflare deployment/cloudflared 2000:2000
curl http://localhost:2000/metrics
```

### Logs

View tunnel logs:

```bash
# All logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Follow logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared -f

# Specific pod
kubectl logs -n cloudflare cloudflared-<pod-id>
```

## Troubleshooting

### Tunnel Not Connecting

Check credentials:
```bash
kubectl get secret cloudflared-credentials -n cloudflare -o yaml
```

Verify tunnel info:
```bash
cloudflared tunnel info infrastructure-tunnel
```

### DNS Not Resolving

Check DNS records:
```bash
dig app.example.com
nslookup app.example.com
```

Verify CNAME points to `<TUNNEL-ID>.cfargotunnel.com`

### Service Unreachable

Test service connectivity from within cluster:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://service-name.namespace.svc.cluster.local:port
```

Check ingress rules in Cloudflared config:
```bash
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared | grep "ingress"
```

### Certificate Errors

For self-signed certificates, add to ingress rule:
```yaml
originRequest:
  noTLSVerify: true
```

## Security Best Practices

1. **Secret Management**: Never commit tunnel credentials to git
2. **Access Control**: Use Cloudflare Access to protect services
3. **TLS Verification**: Enable `noTLSVerify: false` for production
4. **Network Policies**: Restrict pod-to-pod communication
5. **RBAC**: Limit access to cloudflare namespace
6. **Audit Logs**: Enable Cloudflare audit logs for compliance

## Rotating Tunnel Credentials

To rotate credentials:

1. **Create new tunnel**:
   ```bash
   cloudflared tunnel create infrastructure-tunnel-v2
   ```

2. **Update secret**:
   ```bash
   kubectl create secret generic cloudflared-credentials \
     --from-file=credentials.json=$HOME/.cloudflared/<NEW-TUNNEL-ID>.json \
     -n cloudflare \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

3. **Update DNS records** to point to new tunnel
4. **Update Helmfile values** with new tunnel ID
5. **Deploy changes**:
   ```bash
   helmfile -l name=cloudflared apply
   ```

6. **Delete old tunnel** after verification:
   ```bash
   cloudflared tunnel delete infrastructure-tunnel
   ```

## Multi-Environment Setup

For staging/production environments:

**Create separate tunnels:**
```bash
cloudflared tunnel create infrastructure-staging
cloudflared tunnel create infrastructure-production
```

**Use environment-specific values:**
```bash
helmfile -f helmfile.yaml -e staging apply
helmfile -f helmfile.yaml -e production apply
```

## References

- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Helm Chart](https://github.com/cloudflare/helm-charts)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
- [Tunnel Configuration](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/remote/)
