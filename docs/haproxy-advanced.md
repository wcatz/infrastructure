# HAProxy Advanced Configuration

Advanced configuration patterns and optimizations for HAProxy Ingress Controller and external load balancer.

## Table of Contents

- [Performance Tuning](#performance-tuning)
- [Advanced Load Balancing](#advanced-load-balancing)
- [SSL/TLS Configuration](#ssltls-configuration)
- [Security Hardening](#security-hardening)
- [High Availability](#high-availability)
- [Logging and Debugging](#logging-and-debugging)

## Performance Tuning

### Connection Pooling

Optimize connection reuse for better performance:

```yaml
# helmfile/values/haproxy-ingress.yaml
controller:
  config:
    # Keep-alive settings
    timeout-keep-alive: "5m"
    timeout-http-keep-alive: "5m"
    
    # Connection limits
    maxconn-server: "2000"
    
    # Backend health checks
    backend-check-interval: "2s"
```

### Buffer Sizes

Adjust buffer sizes for large requests/responses:

```yaml
controller:
  config:
    # Request/response buffers (default 16KB)
    tune-bufsize: "32768"  # 32KB
    
    # Maximum request size
    client-body-buffer-size: "10m"
```

### Compression

Enable compression to reduce bandwidth:

```yaml
controller:
  config:
    # Enable gzip compression
    use-gzip: "true"
    
    # Compression level (1-9, 9 is max)
    gzip-level: "6"
    
    # Minimum size to compress
    gzip-min-length: "1024"
```

### HTTP/2

Enable HTTP/2 for better performance:

```yaml
controller:
  config:
    use-http-2: "true"
```

### Resource Limits

Set appropriate resource limits:

```yaml
controller:
  resources:
    requests:
      cpu: "500m"
      memory: "512Mi"
    limits:
      cpu: "2000m"
      memory: "2Gi"
  
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
```

## Advanced Load Balancing

### Sticky Sessions

Enable session affinity:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/cookie-persistence: "SERVERID"
    haproxy.org/load-balance: "leastconn"
spec:
  # ...
```

### Custom Load Balancing Algorithms

```yaml
controller:
  config:
    # Global default
    load-balance: "leastconn"
```

Available algorithms:
- `roundrobin`: Distribute evenly
- `leastconn`: Least connections (best for long-lived connections)
- `source`: Hash source IP (sticky sessions without cookies)
- `uri`: Hash URI (cache-friendly)

### Health Check Configuration

```yaml
controller:
  config:
    backend-check-interval: "2s"
    backend-check-timeout: "1s"
    
    # Custom health check path
    health-check-uri: "/health"
    health-check-port: "8080"
```

### Circuit Breaking

Protect backends from overload:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # Max queue size
    haproxy.org/maxconn: "1000"
    
    # Rate limiting
    haproxy.org/rate-limit: "100"  # requests per minute
spec:
  # ...
```

## SSL/TLS Configuration

### TLS Version and Ciphers

```yaml
controller:
  config:
    # Minimum TLS version
    ssl-min-ver: "TLSv1.2"
    
    # Cipher suites
    ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"
    
    # Disable insecure ciphers
    ssl-options: "no-sslv3 no-tlsv10 no-tlsv11"
```

### HSTS (HTTP Strict Transport Security)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/hsts: "true"
    haproxy.org/hsts-max-age: "31536000"
    haproxy.org/hsts-include-subdomains: "true"
    haproxy.org/hsts-preload: "true"
spec:
  # ...
```

### Certificate Management

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tls-certificate
  namespace: default
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-key>
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
spec:
  tls:
    - hosts:
        - app.example.com
      secretName: tls-certificate
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-service
                port:
                  number: 80
```

### Client Certificate Authentication

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/auth-tls-cert-header: "true"
    haproxy.org/auth-tls-verify-client: "required"
    haproxy.org/auth-tls-secret: "client-ca-cert"
spec:
  # ...
```

## Security Hardening

### Rate Limiting

Per-IP and global rate limiting:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    # Limit requests per IP
    haproxy.org/rate-limit: "100"  # per minute
    
    # Burst size
    haproxy.org/rate-limit-size: "1000"
    
    # Response code for rate-limited requests
    haproxy.org/rate-limit-status-code: "429"
spec:
  # ...
```

### IP Whitelisting

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/whitelist: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
spec:
  # ...
```

### Request Size Limits

```yaml
controller:
  config:
    # Maximum client body size
    proxy-body-size: "10m"
```

### DDoS Protection

```yaml
controller:
  config:
    # Connection limits
    maxconn-server: "1000"
    
    # Timeout aggressive clients
    timeout-client: "30s"
    timeout-http-request: "10s"
```

### Security Headers

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/request-set-header: |
      X-Frame-Options SAMEORIGIN
      X-Content-Type-Options nosniff
      X-XSS-Protection "1; mode=block"
      Referrer-Policy strict-origin-when-cross-origin
      Permissions-Policy "geolocation=(), microphone=(), camera=()"
spec:
  # ...
```

## High Availability

### Multi-Replica Deployment

```yaml
controller:
  replicaCount: 3
  
  # Anti-affinity to spread across nodes
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
                - key: app.kubernetes.io/name
                  operator: In
                  values:
                    - haproxy-ingress
            topologyKey: kubernetes.io/hostname
```

### Pod Disruption Budget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: haproxy-ingress-pdb
  namespace: haproxy-ingress
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: haproxy-ingress
```

### Health Checks

```yaml
controller:
  livenessProbe:
    httpGet:
      path: /healthz
      port: 10254
    initialDelaySeconds: 10
    periodSeconds: 10
    
  readinessProbe:
    httpGet:
      path: /healthz
      port: 10254
    initialDelaySeconds: 5
    periodSeconds: 5
```

### External HAProxy HA with Keepalived

```haproxy
# /etc/haproxy/haproxy.cfg on both HAProxy servers

global
    stats socket /var/lib/haproxy/stats
    
defaults
    mode tcp
    timeout connect 5s
    timeout client 50s
    timeout server 50s

# Virtual IP managed by Keepalived
frontend mysql_frontend
    bind 192.168.1.100:3306  # VIP
    default_backend mysql_backend

backend mysql_backend
    balance leastconn
    option tcp-check
    server worker-01 192.168.1.11:30306 check
    server worker-02 192.168.1.12:30306 check
    server worker-03 192.168.1.13:30306 check
```

Keepalived configuration:

```
# /etc/keepalived/keepalived.conf

vrrp_instance VI_1 {
    state MASTER  # or BACKUP on secondary
    interface eth0
    virtual_router_id 51
    priority 100  # Higher on master
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass secret123
    }
    
    virtual_ipaddress {
        192.168.1.100
    }
    
    track_script {
        chk_haproxy
    }
}

vrrp_script chk_haproxy {
    script "killall -0 haproxy"
    interval 2
    weight 2
}
```

## Logging and Debugging

### Access Logs

```yaml
controller:
  config:
    # Enable access logs
    syslog-endpoint: "stdout"
    syslog-format: "rfc5424"
    
    # Custom log format
    http-log-format: '%ci:%cp [%t] %ft %b/%s %Tq/%Tw/%Tc/%Tr/%Tt %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r'
```

### Debug Logging

```yaml
controller:
  # Enable debug mode
  extraArgs:
    - --v=4  # Verbosity level (0-5)
    
  config:
    # HAProxy debug mode
    global-log-format: "%ci:%cp [%t] %ft %b/%s %Tq/%Tw/%Tc/%Tr/%Tt %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"
```

### Prometheus Metrics

```yaml
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      namespace: monitoring
      interval: 30s
```

Available metrics:
- `haproxy_frontend_http_requests_total`
- `haproxy_backend_up`
- `haproxy_backend_response_time_average_seconds`
- `haproxy_frontend_connections_total`
- `haproxy_backend_current_queue`

### Traffic Capture

```bash
# Capture traffic for debugging
kubectl exec -it -n haproxy-ingress <pod-name> -- tcpdump -i any -w /tmp/capture.pcap port 80

# Download capture
kubectl cp haproxy-ingress/<pod-name>:/tmp/capture.pcap ./capture.pcap

# Analyze with Wireshark
wireshark capture.pcap
```

### HAProxy Stats Socket

```bash
# Connect to stats socket
kubectl exec -it -n haproxy-ingress <pod-name> -- sh

# Inside pod
echo "show stat" | socat stdio /var/run/haproxy.sock
echo "show info" | socat stdio /var/run/haproxy.sock
echo "show servers state" | socat stdio /var/run/haproxy.sock
```

## Advanced Patterns

### A/B Testing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/backend-config-snippet: |
      acl is_beta_user req.hdr(Cookie) -m sub beta=true
      use-server app-v2 if is_beta_user
spec:
  # ...
```

### Canary Deployments

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/backend-config-snippet: |
      # 10% of traffic to canary
      acl is_canary_sample rand(100) lt 10
      use_backend canary-backend if is_canary_sample
spec:
  # ...
```

### Geographic Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    haproxy.org/backend-config-snippet: |
      # Route based on CloudFlare geolocation header
      acl is_eu req.hdr(CF-IPCountry) -i DE FR GB IT ES
      use_backend eu-backend if is_eu
spec:
  # ...
```

### Custom Error Pages

```yaml
controller:
  config:
    # Custom error page ConfigMap
    error-files: "custom-errors"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-errors
  namespace: haproxy-ingress
data:
  "404.http": |
    HTTP/1.1 404 Not Found
    Content-Type: text/html
    
    <html><body><h1>Page Not Found</h1></body></html>
```

## Performance Benchmarking

### Load Testing

```bash
# Install k6
brew install k6

# Create test script
cat > load-test.js <<EOF
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '5m', target: 200 },
    { duration: '2m', target: 0 },
  ],
};

export default function () {
  let res = http.get('https://app.example.com');
  check(res, { 'status was 200': (r) => r.status == 200 });
  sleep(1);
}
EOF

# Run test
k6 run load-test.js
```

### Monitoring During Load Test

```bash
# Watch pod metrics
kubectl top pods -n haproxy-ingress --watch

# Watch HPA
kubectl get hpa -n haproxy-ingress --watch

# Check Prometheus metrics
# Access Grafana dashboard during test
```

## Best Practices

1. **Always use TLS 1.2+**: Disable older protocols
2. **Enable HTTP/2**: Better performance for modern browsers
3. **Configure timeouts**: Match your application's needs
4. **Use health checks**: Ensure traffic goes to healthy backends
5. **Enable metrics**: Monitor performance and errors
6. **Set resource limits**: Prevent resource exhaustion
7. **Use anti-affinity**: Distribute pods across nodes
8. **Configure PDB**: Maintain availability during updates
9. **Enable logging**: Debug issues quickly
10. **Test failover**: Regularly test HA configurations

## Additional Resources

- [HAProxy Ingress Documentation](https://haproxy-ingress.github.io/)
- [HAProxy Configuration Manual](http://cbonte.github.io/haproxy-dconv/)
- [Kubernetes Ingress Best Practices](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [TLS Best Practices](https://wiki.mozilla.org/Security/Server_Side_TLS)
