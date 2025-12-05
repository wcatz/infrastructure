# DNS Setup Guide for Hybrid Kubernetes Cluster

This guide explains how to configure DNS for services exposed through Cloudflare tunnels (HTTP/HTTPS) and direct TCP via NodePort on worker nodes with public IPs.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [DNS Records for Cloudflare Tunnel](#dns-records-for-cloudflare-tunnel)
- [DNS Records for TCP Services](#dns-records-for-tcp-services)
- [Complete Setup Example](#complete-setup-example)
- [Multi-Environment DNS](#multi-environment-dns)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

```
                         DNS Resolution
                               |
              ┌────────────────┼────────────────┐
              |                                 |
        HTTP/HTTPS                          TCP/UDP
    (Cloudflare Tunnel)              (Direct NodePort)
              |                                 |
              v                                 v
    ┌──────────────────┐            ┌──────────────────┐
    |  app.example.com |            | cardano.example.com |
    |  api.example.com |            | node.example.com  |
    | *.apps.example.com|            └──────────────────┘
    └──────────────────┘                       |
              |                                 v
              v                     ┌──────────────────┐
    ┌──────────────────┐            | Worker Public IP |
    |   Cloudflared    |            | 123.45.67.89:30001|
    |  (in cluster)    |            └──────────────────┘
    └──────────────────┘                       |
              |                                 v
              v                     ┌──────────────────┐
    ┌──────────────────┐            |   K8s Workers    |
    |  K8s Services    |            | NodePort: 30001  |
    |  (ClusterIP)     |            | hostNetwork pods |
    └──────────────────┘            └──────────────────┘
                                               |
                                               v
                                    ┌──────────────────┐
                                    | Cardano Node Pod |
                                    | (stateful)       |
                                    └──────────────────┘
```

## DNS Records for Cloudflare Tunnel

Cloudflare tunnels use CNAME records pointing to the tunnel endpoint.

### Creating Tunnel DNS Records

#### Method 1: Using cloudflared CLI (Recommended)

```bash
# Login to Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create infrastructure-prod-tunnel

# Route DNS records to tunnel
cloudflared tunnel route dns infrastructure-prod-tunnel app.example.com
cloudflared tunnel route dns infrastructure-prod-tunnel api.example.com
cloudflared tunnel route dns infrastructure-prod-tunnel www.example.com

# For wildcard domains
cloudflared tunnel route dns infrastructure-prod-tunnel "*.apps.example.com"
```

#### Method 2: Using Cloudflare Dashboard

1. Go to https://dash.cloudflare.com/
2. Select your domain
3. Navigate to **DNS** → **Records**
4. Click **Add record**
5. Configure:
   - **Type**: CNAME
   - **Name**: subdomain (e.g., `app`, `api`, `www`)
   - **Target**: `<TUNNEL-ID>.cfargotunnel.com`
   - **Proxy status**: Proxied (orange cloud enabled)
   - **TTL**: Auto

Example records:
```
Type    Name    Target                                      Proxy  TTL
CNAME   app     abc123-def-456.cfargotunnel.com            ✓      Auto
CNAME   api     abc123-def-456.cfargotunnel.com            ✓      Auto
CNAME   www     abc123-def-456.cfargotunnel.com            ✓      Auto
CNAME   *.apps  abc123-def-456.cfargotunnel.com            ✓      Auto
```

#### Method 3: Using Terraform

```hcl
# variables.tf
variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "tunnel_id" {
  description = "Cloudflare Tunnel ID"
  type        = string
}

# main.tf
resource "cloudflare_record" "app" {
  zone_id = var.cloudflare_zone_id
  name    = "app"
  value   = "${var.tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = "api"
  value   = "${var.tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "wildcard_apps" {
  zone_id = var.cloudflare_zone_id
  name    = "*.apps"
  value   = "${var.tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
```

### HTTP/HTTPS Service Examples

| Service Type | DNS Record | Points To | Backend Service |
|-------------|------------|-----------|----------------|
| Web App | `app.example.com` | Tunnel CNAME | Application Service |
| REST API | `api.example.com` | Tunnel CNAME | API Service |
| Monitoring | `grafana.example.com` | Tunnel CNAME | Grafana Service |
| Wildcard Apps | `*.apps.example.com` | Tunnel CNAME | Application Services |

## DNS Records for TCP Services

TCP services (like Cardano node P2P) are exposed via NodePort on worker nodes with public IPs. Use A records pointing directly to the worker node's public IP.

### Creating TCP Service DNS Records

#### Method 1: Using Cloudflare Dashboard

1. Go to https://dash.cloudflare.com/
2. Select your domain
3. Navigate to **DNS** → **Records**
4. Click **Add record**
5. Configure:
   - **Type**: A
   - **Name**: subdomain (e.g., `cardano`, `node`)
   - **IPv4 address**: Worker node public IP (e.g., `123.45.67.89`)
   - **Proxy status**: DNS only (grey cloud) - **Important!**
   - **TTL**: 300 (5 minutes) or Auto

Example records:
```
Type    Name      Target          Proxy  TTL
A       cardano   123.45.67.89    ✗      300
A       node      123.45.67.89    ✗      300
```

**Important**: TCP/UDP services MUST have proxy disabled (grey cloud) as Cloudflare's proxy only supports HTTP/HTTPS traffic.

#### Method 2: Using Terraform

```hcl
# Worker node public IP
variable "worker_public_ip" {
  description = "Netcup worker node public IP"
  type        = string
  default     = "192.168.1.5"
}

# MySQL database
resource "cloudflare_record" "mysql" {
  zone_id = var.cloudflare_zone_id
  name    = "db"
  value   = var.haproxy_ip
  type    = "A"
  proxied = false  # MUST be false for TCP/UDP
  ttl     = 300
}

# WireGuard VPN
resource "cloudflare_record" "wireguard" {
  zone_id = var.cloudflare_zone_id
  name    = "vpn"
  value   = var.haproxy_ip
  type    = "A"
  proxied = false
  ttl     = 300
}

# Redis cache
resource "cloudflare_record" "redis" {
  zone_id = var.cloudflare_zone_id
  name    = "redis"
  value   = var.haproxy_ip
  type    = "A"
  proxied = false
  ttl     = 300
}
```

#### Method 3: Using Cloudflare API

```bash
#!/bin/bash
# Script to create DNS records via Cloudflare API

ZONE_ID="your-zone-id"
API_TOKEN="your-api-token"
WORKER_IP="123.45.67.89"

# Function to create DNS record
create_record() {
  local name=$1
  local ip=$2
  
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${ip}\",\"proxied\":false,\"ttl\":300}"
}

# Create records for TCP services
create_record "cardano" "${WORKER_IP}"
create_record "node" "${WORKER_IP}"
```

### TCP Service Examples

| Service Type | Port | DNS Record | Points To | Access Method |
|-------------|------|------------|-----------|---------------|
| Cardano P2P | 3001 | `cardano.example.com` | Worker IP | Direct NodePort 30001 |
| Custom TCP | varies | `node.example.com` | Worker IP | Direct NodePort |

## Complete Setup Example

### Scenario: Hybrid Production Infrastructure

**Requirements:**
- Web application (HTTP/HTTPS) - runs on any node
- REST API (HTTP/HTTPS) - runs on any node
- Cardano node P2P (TCP) - runs on worker with public IP
- Monitoring dashboards (HTTP/HTTPS) - runs on any node

### Step 1: DNS Records Setup

| Record | Type | Name | Target | Proxy | Purpose |
|--------|------|------|--------|-------|---------|
| 1 | CNAME | `app` | `abc123.cfargotunnel.com` | ✓ | Web application |
| 2 | CNAME | `api` | `abc123.cfargotunnel.com` | ✓ | REST API |
| 3 | CNAME | `monitoring` | `abc123.cfargotunnel.com` | ✓ | Grafana dashboard |
| 4 | A | `cardano` | `123.45.67.89` | ✗ | Cardano P2P node |
| 5 | A | `node` | `123.45.67.89` | ✗ | Worker node access |

**Note**: `123.45.67.89` is the Netcup worker node's public IP.

### Step 2: Cloudflared Configuration

Edit `helmfile/values/cloudflared-values.yaml`:

```yaml
ingress:
  # Web application
  - hostname: app.example.com
    service: http://app-service.default.svc.cluster.local:80
  
  # REST API
  - hostname: api.example.com
    service: http://api-service.default.svc.cluster.local:8080
  
  # Monitoring dashboard
  - hostname: monitoring.example.com
    service: http://grafana.monitoring.svc.cluster.local:80
  
  # Catch-all
  - service: http_status:404
```

### Step 3: Cardano Node Configuration

The Cardano node is deployed as a workload on the worker node with public IP.

See `helmfile/manifests/workloads/cardano-node.yaml` for full configuration.

Key points:
- NodePort 30001 exposes Cardano P2P on worker public IP
- `hostNetwork: true` allows direct binding to port 3001
- Node affinity ensures scheduling on worker with public IP

### Step 4: Testing Connectivity

#### HTTP/HTTPS Services (via Cloudflare)

```bash
# Test web application
curl https://app.example.com

# Test REST API
curl https://api.example.com/health

# Test monitoring dashboard
curl https://monitoring.example.com
```

#### TCP Services (Direct to Worker)

```bash
# Test Cardano node P2P (via DNS)
telnet cardano.example.com 30001

# Or using worker IP directly
telnet 123.45.67.89 30001

# Check if NodePort is accessible
nc -zv cardano.example.com 30001
```

## Multi-Environment DNS

### Development Environment

**Domain**: `dev.example.com`

| Service | DNS Record | Target | Notes |
|---------|-----------|--------|-------|
| Web App | `app.dev.example.com` | Dev Tunnel | Cloudflare Tunnel |
| API | `api.dev.example.com` | Dev Tunnel | Cloudflare Tunnel |
| Cardano | `cardano.dev.example.com` | Dev Worker IP | Direct NodePort |

### Staging Environment

**Domain**: `staging.example.com`

| Service | DNS Record | Target | Notes |
|---------|-----------|--------|-------|
| Web App | `app.staging.example.com` | Staging Tunnel | Cloudflare Tunnel |
| API | `api.staging.example.com` | Staging Tunnel | Cloudflare Tunnel |
| Cardano | `cardano.staging.example.com` | Staging Worker IP | Direct NodePort |

### Production Environment

**Domain**: `example.com`

| Service | DNS Record | Target | Notes |
|---------|-----------|--------|-------|
| Web App | `app.example.com` | Prod Tunnel | Cloudflare Tunnel |
| API | `api.example.com` | Prod Tunnel | Cloudflare Tunnel |
| Cardano | `cardano.example.com` | Prod Worker IP | Direct NodePort |

## Troubleshooting

### DNS Not Resolving

**Check DNS propagation:**
```bash
# Check from multiple DNS servers
dig app.example.com @8.8.8.8
dig app.example.com @1.1.1.1

# Check DNS propagation status
https://www.whatsmydns.net/
```

**Common issues:**
- DNS changes not propagated (wait 5-10 minutes)
- Incorrect target in CNAME/A record
- Typo in domain name

### Cloudflare Proxy Issues

**Symptom**: TCP/UDP services not working

**Solution**: Ensure proxy is **disabled** (grey cloud) for A records:
```bash
# Check if proxied
dig db.example.com

# Should return HAProxy IP, not Cloudflare IP
```

### Connection Timeouts

**For HTTP/HTTPS services:**
1. Verify Cloudflared is running: `kubectl get pods -n cloudflare`
2. Check tunnel ingress rules match DNS records
3. Test from within cluster: `kubectl run -it curl --image=curlimages/curl -- curl http://service`

**For TCP/UDP services:**
1. Verify HAProxy is running: `systemctl status haproxy`
2. Test connectivity: `nc -zv db.example.com 3306`
3. Check HAProxy stats: `http://<haproxy-ip>:8404/stats`
4. Verify firewall rules allow traffic

### Wrong IP Resolution

**Symptom**: DNS resolves to wrong IP address

**Solutions:**
1. Check Cloudflare dashboard for correct record
2. Flush local DNS cache:
   ```bash
   # Linux
   sudo systemd-resolve --flush-caches
   
   # macOS
   sudo dscacheutil -flushcache
   
   # Windows
   ipconfig /flushdns
   ```
3. Verify record type (A vs CNAME)
4. Check TTL and wait for propagation

## Best Practices

### DNS Configuration

1. **Use short TTLs during setup** (300s) for quick changes
2. **Increase TTLs after stabilization** (3600s or higher) for better caching
3. **Use descriptive subdomain names** (db, api, vpn, etc.)
4. **Document all DNS records** in inventory or IaC

### High Availability

1. **Use multiple HAProxy servers** with DNS round-robin or failover
2. **Configure health checks** for DNS-based failover services
3. **Monitor DNS resolution** from multiple locations
4. **Set up alerts** for DNS failures

### Security

1. **Enable DNSSEC** for domain security
2. **Use Cloudflare Access** for HTTP/HTTPS services requiring authentication
3. **Restrict HAProxy access** via firewall rules
4. **Use VPN** for sensitive TCP/UDP services

### Monitoring

1. **Monitor DNS resolution times**
2. **Track DNS query volumes**
3. **Set up alerts for DNS failures**
4. **Monitor SSL certificate expiration** for Cloudflare proxied domains

## Additional Resources

- [Cloudflare DNS Documentation](https://developers.cloudflare.com/dns/)
- [Cloudflare Tunnel DNS](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/routing-to-tunnel/dns/)
- [HAProxy Documentation](https://www.haproxy.org/)
- [DNS Best Practices](https://www.cloudflare.com/learning/dns/dns-records/)
