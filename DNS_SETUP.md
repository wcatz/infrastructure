# DNS Setup Guide for Cloudflare and HAProxy

This guide explains how to configure DNS for services exposed through both Cloudflare tunnels (HTTP/HTTPS) and HAProxy load balancer (TCP/UDP NodePorts).

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [DNS Records for Cloudflare Tunnel](#dns-records-for-cloudflare-tunnel)
- [DNS Records for HAProxy NodePorts](#dns-records-for-haproxy-nodeports)
- [Complete Setup Example](#complete-setup-example)
- [Multi-Environment DNS](#multi-environment-dns)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

```
                         DNS Resolution
                               |
              ┌────────────────┼────────────────┐
              |                                 |
        HTTP/HTTPS                         TCP/UDP
    (Cloudflare Tunnel)                 (HAProxy LB)
              |                                 |
              v                                 v
    ┌──────────────────┐            ┌──────────────────┐
    |  app.example.com |            | db.example.com   |
    |  api.example.com |            | vpn.example.com  |
    | *.apps.example.com|            | redis.example.com|
    └──────────────────┘            └──────────────────┘
              |                                 |
              v                                 v
    ┌──────────────────┐            ┌──────────────────┐
    |   Cloudflared    |            |     HAProxy      |
    |  (in cluster)    |            | 192.168.1.5:3306 |
    └──────────────────┘            | 192.168.1.5:51820|
              |                     └──────────────────┘
              v                                 |
    ┌──────────────────┐                       v
    |  HAProxy Ingress |            ┌──────────────────┐
    |   Controller     |            |   K8s Workers    |
    └──────────────────┘            | NodePort: 30306  |
              |                     | NodePort: 31820  |
              v                     └──────────────────┘
    ┌──────────────────┐                       |
    |  K8s Services    |                       v
    |  (via Ingress)   |            ┌──────────────────┐
    └──────────────────┘            |  K8s Services    |
                                    |  (via NodePort)  |
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

| Service Type | DNS Record | Points To | Cloudflared Ingress |
|-------------|------------|-----------|-------------------|
| Web App | `app.example.com` | Tunnel CNAME | HAProxy Ingress Controller |
| REST API | `api.example.com` | Tunnel CNAME | API Service |
| Monitoring | `grafana.example.com` | Tunnel CNAME | Grafana Service |
| Wildcard Apps | `*.apps.example.com` | Tunnel CNAME | HAProxy Ingress Controller |

## DNS Records for HAProxy NodePorts

HAProxy NodePort services use A records pointing to the HAProxy server's IP address.

### Creating HAProxy DNS Records

#### Method 1: Using Cloudflare Dashboard

1. Go to https://dash.cloudflare.com/
2. Select your domain
3. Navigate to **DNS** → **Records**
4. Click **Add record**
5. Configure:
   - **Type**: A
   - **Name**: subdomain (e.g., `db`, `vpn`, `redis`)
   - **IPv4 address**: HAProxy server IP (e.g., `192.168.1.5`)
   - **Proxy status**: DNS only (grey cloud) - **Important!**
   - **TTL**: 300 (5 minutes) or Auto

Example records:
```
Type    Name     Target          Proxy  TTL
A       db       192.168.1.5     ✗      300
A       vpn      192.168.1.5     ✗      300
A       redis    192.168.1.5     ✗      300
A       haproxy  192.168.1.5     ✗      300
```

**Important**: TCP/UDP services MUST have proxy disabled (grey cloud) as Cloudflare's proxy only supports HTTP/HTTPS traffic.

#### Method 2: Using Terraform

```hcl
# HAProxy server IP
variable "haproxy_ip" {
  description = "HAProxy server public IP"
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
HAPROXY_IP="192.168.1.5"

# Function to create DNS record
create_record() {
  local name=$1
  local ip=$2
  
  curl -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${name}\",\"content\":\"${ip}\",\"proxied\":false,\"ttl\":300}"
}

# Create records
create_record "db" "${HAPROXY_IP}"
create_record "vpn" "${HAPROXY_IP}"
create_record "redis" "${HAPROXY_IP}"
```

### TCP/UDP Service Examples

| Service Type | Port | DNS Record | Points To | HAProxy Backend |
|-------------|------|------------|-----------|-----------------|
| MySQL | 3306 | `db.example.com` | HAProxy IP | Worker NodePort 30306 |
| WireGuard | 51820 | `vpn.example.com` | HAProxy IP | Worker NodePort 31820 |
| PostgreSQL | 5432 | `postgres.example.com` | HAProxy IP | Worker NodePort 30432 |
| Redis | 6379 | `redis.example.com` | HAProxy IP | Worker NodePort 30379 |

## Complete Setup Example

### Scenario: Production Infrastructure

**Requirements:**
- Web application (HTTP/HTTPS)
- REST API (HTTP/HTTPS)
- MySQL database (TCP)
- WireGuard VPN (UDP)
- Redis cache (TCP)

### Step 1: DNS Records Setup

| Record | Type | Name | Target | Proxy | Purpose |
|--------|------|------|--------|-------|---------|
| 1 | CNAME | `app` | `abc123.cfargotunnel.com` | ✓ | Web application |
| 2 | CNAME | `api` | `abc123.cfargotunnel.com` | ✓ | REST API |
| 3 | CNAME | `www` | `abc123.cfargotunnel.com` | ✓ | Website |
| 4 | A | `db` | `192.168.1.5` | ✗ | MySQL database |
| 5 | A | `vpn` | `192.168.1.5` | ✗ | WireGuard VPN |
| 6 | A | `redis` | `192.168.1.5` | ✗ | Redis cache |

### Step 2: Cloudflared Configuration

Edit `helmfile/values/cloudflared-values.yaml`:

```yaml
ingress:
  # Web application
  - hostname: app.example.com
    service: http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
  
  # REST API
  - hostname: api.example.com
    service: http://api-service.default.svc.cluster.local:8080
  
  # Website
  - hostname: www.example.com
    service: http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
  
  # Catch-all
  - service: http_status:404
```

### Step 3: HAProxy Configuration

Edit `ansible/roles/haproxy/defaults/main.yaml`:

```yaml
haproxy_tcp_backends:
  # MySQL database
  - name: mysql
    port: 3306
    mode: tcp
    balance: leastconn
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
  
  # Redis cache
  - name: redis
    port: 6379
    mode: tcp
    balance: roundrobin
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 30379
        check: true
        check_interval: 2s
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 30379
        check: true
        check_interval: 2s

haproxy_udp_backends:
  # WireGuard VPN
  - name: wireguard
    port: 51820
    mode: udp
    balance: roundrobin
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 31820
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 31820
```

### Step 4: Testing Connectivity

```bash
# Test HTTP/HTTPS (via Cloudflare)
curl https://app.example.com
curl https://api.example.com

# Test MySQL (via HAProxy)
mysql -h db.example.com -P 3306 -u user -p

# Test Redis (via HAProxy)
redis-cli -h redis.example.com -p 6379

# Test WireGuard (via HAProxy)
# Edit WireGuard client config with Endpoint = vpn.example.com:51820
wg-quick up wg0
```

## Multi-Environment DNS

### Development Environment

**Domain**: `dev.example.com`

| Service | DNS Record | Target | Notes |
|---------|-----------|--------|-------|
| Web App | `app.dev.example.com` | Dev Tunnel | Cloudflare Tunnel |
| API | `api.dev.example.com` | Dev Tunnel | Cloudflare Tunnel |
| Database | `db.dev.example.com` | `192.168.2.5` | Dev HAProxy |
| VPN | `vpn.dev.example.com` | `192.168.2.5` | Dev HAProxy |

### Staging Environment

**Domain**: `staging.example.com`

| Service | DNS Record | Target | Notes |
|---------|-----------|--------|-------|
| Web App | `app.staging.example.com` | Staging Tunnel | Cloudflare Tunnel |
| API | `api.staging.example.com` | Staging Tunnel | Cloudflare Tunnel |
| Database | `db.staging.example.com` | `192.168.3.5` | Staging HAProxy |
| VPN | `vpn.staging.example.com` | `192.168.3.5` | Staging HAProxy |

### Production Environment

**Domain**: `example.com`

| Service | DNS Record | Target | Notes |
|---------|-----------|--------|-------|
| Web App | `app.example.com` | Prod Tunnel | Cloudflare Tunnel |
| API | `api.example.com` | Prod Tunnel | Cloudflare Tunnel |
| Database | `db.example.com` | `192.168.1.5` | Prod HAProxy |
| VPN | `vpn.example.com` | `192.168.1.5` | Prod HAProxy |

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
