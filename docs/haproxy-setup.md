# HAProxy Setup Guide

This guide covers the deployment and configuration of HAProxy for both Kubernetes Ingress Controller and external NodePort load balancing.

## Table of Contents

- [Overview](#overview)
- [HAProxy Ingress Controller (Kubernetes)](#haproxy-ingress-controller-kubernetes)
- [HAProxy Load Balancer (NodePort)](#haproxy-load-balancer-nodeport)
- [Advanced Configuration](#advanced-configuration)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## Overview

This infrastructure uses HAProxy in two distinct modes:

1. **HAProxy Ingress Controller**: Deployed via Helmfile inside Kubernetes for HTTP/HTTPS traffic routing
2. **External HAProxy Load Balancer**: Deployed via Ansible on dedicated servers for NodePort TCP/UDP load balancing

### Traffic Flow

```
                    Internet
                       │
                       ▼
              ┌────────────────┐
              │   Cloudflare   │
              │     Tunnel     │
              └────────────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │   HAProxy Ingress        │
        │   Controller (K8s)       │
        │   HTTP/HTTPS Routing     │
        └──────────────────────────┘
                       │
            ┌──────────┴──────────┐
            │                     │
            ▼                     ▼
    ┌──────────────┐      ┌──────────────┐
    │  Web Apps    │      │  APIs        │
    │  (Pods)      │      │  (Pods)      │
    └──────────────┘      └──────────────┘


                    Internet
                       │
                       ▼
        ┌──────────────────────────┐
        │   External HAProxy       │
        │   Load Balancer          │
        │   TCP/UDP Balancing      │
        └──────────────────────────┘
                       │
            ┌──────────┴──────────┐
            │                     │
            ▼                     ▼
    ┌──────────────┐      ┌──────────────┐
    │  MySQL       │      │  WireGuard   │
    │  :30306      │      │  :51820      │
    └──────────────┘      └──────────────┘
```

## HAProxy Ingress Controller (Kubernetes)

The HAProxy Ingress Controller is deployed inside Kubernetes via Helmfile and handles all HTTP/HTTPS traffic routing.

### Deployment via Helmfile

#### Step 1: Review Configuration

```bash
cd helmfile
cat values/haproxy-ingress.yaml
```

Key configuration options:
- **Replicas**: Default 2 (auto-scales to 10)
- **Service Type**: ClusterIP (accessed via Cloudflared)
- **Timeouts**: Optimized for web applications
- **Metrics**: Prometheus integration enabled

#### Step 2: Environment-Specific Overrides

Create environment-specific overrides:

**Development** (`environments/dev/haproxy-ingress.yaml`):
```yaml
controller:
  replicaCount: 1
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
  autoscaling:
    enabled: false
```

**Staging** (`environments/staging/haproxy-ingress.yaml`):
```yaml
controller:
  replicaCount: 2
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

**Production** (`environments/prod/haproxy-ingress.yaml`):
```yaml
controller:
  replicaCount: 3
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

#### Step 3: Deploy

```bash
cd helmfile

# Preview changes
helmfile -e dev diff -l name=haproxy-ingress

# Deploy to dev
helmfile -e dev apply -l name=haproxy-ingress

# Deploy to production
helmfile -e prod apply -l name=haproxy-ingress
```

#### Step 4: Verify

```bash
# Check pods
kubectl get pods -n haproxy-ingress

# Check service
kubectl get svc -n haproxy-ingress

# Check ingress controller logs
kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress --tail=50
```

### Creating Ingress Resources

Create ingress resources to route traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-app-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: haproxy
    # Force HTTPS redirect
    ingress.kubernetes.io/ssl-redirect: "true"
    # Custom timeout
    haproxy.org/timeout-client: "60s"
    haproxy.org/timeout-server: "60s"
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-app-service
                port:
                  number: 80
```

## HAProxy Load Balancer (NodePort)

External HAProxy load balancer for TCP/UDP services exposed via NodePort.

### Prerequisites

- Dedicated server for HAProxy (Ubuntu 20.04/22.04 recommended)
- Network access from HAProxy to all k3s worker nodes
- Port 3306 (MySQL), 51820 (WireGuard), or other service ports available

### Ansible Deployment

#### Step 1: Create HAProxy Role

The HAProxy role is included in this repository. It installs and configures HAProxy for NodePort load balancing.

#### Step 2: Update Inventory

Add HAProxy servers to your inventory:

```ini
[haproxy_servers]
haproxy-lb-01 ansible_host=192.168.1.5 ansible_user=ubuntu hostname=haproxy-lb-01

[haproxy_servers:vars]
domain=lb.example.com
```

#### Step 3: Configure HAProxy Backend Servers

Edit `ansible/group_vars/haproxy_servers.yml`:

```yaml
---
# HAProxy configuration

# List of k3s worker nodes (for NodePort backends)
k3s_workers:
  - host: 192.168.1.11
    name: worker-01
  - host: 192.168.1.12
    name: worker-02
  - host: 192.168.1.13
    name: worker-03

# Services to load balance
haproxy_services:
  - name: mysql
    frontend_port: 3306
    backend_port: 30306
    mode: tcp
    balance: leastconn
    check_interval: 2s
    
  - name: wireguard
    frontend_port: 51820
    backend_port: 30820
    mode: tcp
    balance: roundrobin
    check_interval: 5s
```

#### Step 4: Deploy HAProxy

```bash
cd ansible

# Deploy HAProxy
ansible-playbook -i inventory.ini playbooks/deploy-haproxy.yaml

# Verify
ansible haproxy_servers -i inventory.ini -m shell -a "systemctl status haproxy"
```

#### Step 5: Verify Load Balancer

```bash
# Check HAProxy stats
curl http://192.168.1.5:8404/stats

# Test MySQL connection through load balancer
mysql -h 192.168.1.5 -P 3306 -u root -p

# Test WireGuard (from client)
wg-quick up wg0  # Configure endpoint as 192.168.1.5:51820
```

### HAProxy Configuration Template

The Ansible role generates HAProxy configuration from Jinja2 templates.

Example `/etc/haproxy/haproxy.cfg`:

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # Default SSL material locations
    ca-base /etc/ssl/certs
    crt-base /etc/ssl/private

    # Modern SSL configuration
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

# HAProxy stats interface
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if LOCALHOST

# MySQL Load Balancer
frontend mysql_frontend
    bind *:3306
    mode tcp
    default_backend mysql_backend

backend mysql_backend
    mode tcp
    balance leastconn
    option tcp-check
    server worker-01 192.168.1.11:30306 check inter 2s fall 3 rise 2
    server worker-02 192.168.1.12:30306 check inter 2s fall 3 rise 2
    server worker-03 192.168.1.13:30306 check inter 2s fall 3 rise 2

# WireGuard Load Balancer
frontend wireguard_frontend
    bind *:51820
    mode tcp
    default_backend wireguard_backend

backend wireguard_backend
    mode tcp
    balance roundrobin
    option tcp-check
    server worker-01 192.168.1.11:30820 check inter 5s fall 3 rise 2
    server worker-02 192.168.1.12:30820 check inter 5s fall 3 rise 2
    server worker-03 192.168.1.13:30820 check inter 5s fall 3 rise 2
```

## Advanced Configuration

### SSL/TLS Termination

For HTTPS termination on external HAProxy:

```haproxy
frontend https_frontend
    bind *:443 ssl crt /etc/haproxy/certs/
    mode http
    default_backend web_backend

backend web_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    server worker-01 192.168.1.11:30080 check
    server worker-02 192.168.1.12:30080 check
    server worker-03 192.168.1.13:30080 check
```

### Custom Timeouts

Adjust timeouts based on application needs:

```yaml
controller:
  config:
    timeout-client: "120s"         # Long-polling clients
    timeout-server: "120s"         # Slow backend APIs
    timeout-tunnel: "24h"          # WebSocket connections
    timeout-keep-alive: "5m"       # Connection pooling
```

### Rate Limiting

Enable rate limiting in HAProxy Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/rate-limit: "100"  # 100 requests per minute per IP
```

### Connection Limits

Limit concurrent connections:

```yaml
controller:
  config:
    maxconn-server: "2000"         # Max connections per backend
```

## Monitoring

### Prometheus Metrics

HAProxy Ingress exports metrics to Prometheus:

```bash
# Check metrics endpoint
kubectl port-forward -n haproxy-ingress svc/haproxy-ingress-metrics 9101:9101
curl http://localhost:9101/metrics
```

Key metrics:
- `haproxy_frontend_http_requests_total`: Total HTTP requests
- `haproxy_backend_up`: Backend server health
- `haproxy_frontend_connections_total`: Total connections
- `haproxy_backend_response_time_average_seconds`: Response times

### Grafana Dashboard

Import pre-built HAProxy Ingress dashboard:

1. Access Grafana
2. Go to Dashboards → Import
3. Enter dashboard ID: `12693`
4. Select Prometheus datasource
5. Import

### External HAProxy Stats

Access HAProxy stats page:

```bash
# Enable stats in haproxy.cfg
listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s

# Access stats
http://haproxy-lb-01:8404/stats
```

## Troubleshooting

### HAProxy Ingress Not Starting

```bash
# Check pod status
kubectl get pods -n haproxy-ingress
kubectl describe pod -n haproxy-ingress <pod-name>

# Check logs
kubectl logs -n haproxy-ingress <pod-name>

# Check configuration
kubectl get cm -n haproxy-ingress
kubectl get cm -n haproxy-ingress haproxy-ingress -o yaml
```

### Backend Servers Unavailable

```bash
# Check endpoints
kubectl get endpoints -n haproxy-ingress

# Test backend connectivity from HAProxy pod
kubectl exec -it -n haproxy-ingress <pod-name> -- wget -O- http://backend-service:80

# Check NetworkPolicies
kubectl get networkpolicies -A
```

### External HAProxy Not Load Balancing

```bash
# Check HAProxy status
ssh ubuntu@haproxy-lb-01 "sudo systemctl status haproxy"

# Check HAProxy logs
ssh ubuntu@haproxy-lb-01 "sudo journalctl -u haproxy -f"

# Validate configuration
ssh ubuntu@haproxy-lb-01 "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"

# Check backend connectivity
ssh ubuntu@haproxy-lb-01 "nc -zv 192.168.1.11 30306"
```

### Performance Issues

```bash
# Check resource usage
kubectl top pods -n haproxy-ingress

# Scale up replicas
kubectl scale deployment -n haproxy-ingress haproxy-ingress --replicas=5

# Adjust HPA settings
kubectl edit hpa -n haproxy-ingress haproxy-ingress
```

## Best Practices

1. **High Availability**: Deploy at least 2 HAProxy Ingress replicas
2. **Resource Limits**: Set appropriate CPU/memory limits based on traffic
3. **Monitoring**: Enable Prometheus metrics and Grafana dashboards
4. **Health Checks**: Configure proper health check intervals
5. **Timeouts**: Adjust timeouts based on application requirements
6. **SSL/TLS**: Use strong cipher suites and TLS 1.2+
7. **Rate Limiting**: Protect against abuse with rate limiting
8. **Load Balancing**: Choose appropriate algorithm (roundrobin, leastconn)
9. **Logging**: Enable detailed logging for troubleshooting
10. **Testing**: Test failover scenarios regularly

## Additional Resources

- [HAProxy Ingress Documentation](https://haproxy-ingress.github.io/)
- [HAProxy Documentation](http://www.haproxy.org/)
- [HAProxy Advanced Configuration](haproxy-advanced.md)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
