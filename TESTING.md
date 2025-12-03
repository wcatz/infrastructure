# Testing and Validation Guide

This guide provides comprehensive testing procedures for validating infrastructure deployments.

## Table of Contents

- [Pre-Deployment Testing](#pre-deployment-testing)
- [HAProxy Testing](#haproxy-testing)
- [Cloudflared Testing](#cloudflared-testing)
- [End-to-End Testing](#end-to-end-testing)
- [Failover Testing](#failover-testing)
- [Performance Testing](#performance-testing)
- [Security Testing](#security-testing)

## Pre-Deployment Testing

### 1. YAML Validation

Validate all YAML files before deployment:

```bash
# Lint all YAML files
yamllint helmfile/ ansible/

# Validate Helmfile configuration
cd helmfile
helmfile lint

# Test Helmfile templates
helmfile template > /tmp/rendered-manifests.yaml
kubectl apply --dry-run=client -f /tmp/rendered-manifests.yaml
```

### 2. Ansible Validation

Validate Ansible playbooks and templates:

```bash
cd ansible

# Check syntax
ansible-playbook playbooks/deploy-haproxy.yaml --syntax-check

# Validate HAProxy configuration
ansible haproxy_servers -m shell -a "haproxy -c -f /etc/haproxy/haproxy.cfg"

# Test connectivity to worker nodes
ansible haproxy_servers -m shell -a "nc -zv 192.168.1.11 30306"
```

## HAProxy Testing

### 1. Service Health Checks

```bash
# Check HAProxy status
systemctl status haproxy

# View statistics page
curl http://<haproxy-ip>:8404/stats

# Check backend server health
curl http://<haproxy-ip>:8404/stats | grep -A 10 "mysql_backend"
```

### 2. TCP Service Testing

**MySQL Example:**
```bash
# Test connection to MySQL via HAProxy
mysql -h <haproxy-ip> -P 3306 -u testuser -p

# Test from multiple clients simultaneously
for i in {1..10}; do
  mysql -h <haproxy-ip> -P 3306 -u testuser -p -e "SELECT 'Connection $i' as test;" &
done
wait

# Verify load distribution in HAProxy stats
curl http://<haproxy-ip>:8404/stats | grep -A 20 "mysql_backend"
```

**PostgreSQL Example:**
```bash
# Test connection to PostgreSQL via HAProxy
psql -h <haproxy-ip> -p 5432 -U testuser -d testdb

# Test connection pool
for i in {1..10}; do
  psql -h <haproxy-ip> -p 5432 -U testuser -d testdb -c "SELECT 'Connection $i' as test;" &
done
wait
```

**Redis Example:**
```bash
# Test Redis connection
redis-cli -h <haproxy-ip> -p 6379 ping

# Test commands
redis-cli -h <haproxy-ip> -p 6379 set testkey "testvalue"
redis-cli -h <haproxy-ip> -p 6379 get testkey

# Benchmark Redis performance
redis-benchmark -h <haproxy-ip> -p 6379 -q -n 10000
```

### 3. UDP Service Testing

**WireGuard Example:**
```bash
# Configure WireGuard client
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = <your-private-key>
Address = 10.0.0.2/24

[Peer]
PublicKey = <server-public-key>
Endpoint = <haproxy-ip>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF

# Start WireGuard
wg-quick up wg0

# Test connectivity
ping 10.0.0.1

# Check WireGuard status
wg show

# Stop WireGuard
wg-quick down wg0
```

### 4. Load Balancing Verification

```bash
# Monitor connections to each backend
watch -n 1 'curl -s http://<haproxy-ip>:8404/stats | grep -A 20 "mysql_backend"'

# Generate load and verify distribution
for i in {1..100}; do
  mysql -h <haproxy-ip> -P 3306 -u testuser -p -e "SELECT CONNECTION_ID();" &
done
wait
```

## Cloudflared Testing

### 1. Tunnel Status

```bash
# Check tunnel status (from machine with cloudflared CLI)
cloudflared tunnel info infrastructure-prod-tunnel

# Check tunnel logs in Kubernetes
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared -f

# Check pod status
kubectl get pods -n cloudflare
kubectl describe pod -n cloudflare <pod-name>
```

### 2. HTTP/HTTPS Service Testing

**Web Application:**
```bash
# Test HTTP endpoint
curl -I https://app.example.com

# Test with verbose output
curl -v https://app.example.com

# Test from multiple locations
for loc in us-east us-west eu-west; do
  echo "Testing from $loc"
  curl -s -o /dev/null -w "Time: %{time_total}s\n" https://app.example.com
done
```

**API Testing:**
```bash
# Test REST API
curl https://api.example.com/health

# Test with authentication
curl -H "Authorization: Bearer <token>" https://api.example.com/users

# Load test API
ab -n 1000 -c 10 https://api.example.com/health
```

### 3. Ingress Rule Validation

```bash
# Test specific ingress rules
curl -H "Host: app.example.com" http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local

# Test from within cluster
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl -v http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
```

### 4. Cloudflare Access Testing

```bash
# Test protected endpoint (should redirect to login)
curl -I https://monitoring.example.com

# Test with valid token
curl -H "CF-Access-Token: <token>" https://monitoring.example.com
```

## End-to-End Testing

### 1. Full Traffic Flow

```bash
# HTTP/HTTPS path: Client → Cloudflare → Cloudflared → HAProxy Ingress → Service
curl -v https://app.example.com
kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress --tail=20
kubectl logs -n default -l app=myapp --tail=20

# TCP path: Client → HAProxy LB → Worker NodePort → Service
mysql -h db.example.com -P 3306 -u testuser -p -e "SELECT 'Connected via HAProxy' as status;"
kubectl logs -n databases -l app=mysql --tail=20
```

### 2. DNS Resolution Testing

```bash
# Test DNS resolution for Cloudflare tunnel
dig app.example.com
nslookup app.example.com

# Test DNS resolution for HAProxy
dig db.example.com
nslookup db.example.com

# Verify DNS from multiple nameservers
dig @8.8.8.8 app.example.com
dig @1.1.1.1 app.example.com
dig @9.9.9.9 db.example.com
```

### 3. Multi-Environment Testing

```bash
# Development
curl https://app.dev.example.com
mysql -h db.dev.example.com -P 3306 -u devuser -p

# Staging
curl https://app.staging.example.com
mysql -h db.staging.example.com -P 3306 -u staginguser -p

# Production
curl https://app.example.com
mysql -h db.example.com -P 3306 -u produser -p
```

## Failover Testing

### 1. HAProxy Backend Failover

**Simulate worker node failure:**
```bash
# On a worker node, block traffic to NodePort
sudo iptables -A INPUT -p tcp --dport 30306 -j DROP

# Verify HAProxy marks server as down
curl http://<haproxy-ip>:8404/stats | grep k8s-worker-1

# Test connectivity (should still work via other workers)
mysql -h <haproxy-ip> -P 3306 -u testuser -p -e "SELECT 'Failover test' as status;"

# Restore traffic
sudo iptables -D INPUT -p tcp --dport 30306 -j DROP

# Verify HAProxy marks server as up
curl http://<haproxy-ip>:8404/stats | grep k8s-worker-1
```

**Simulate complete node failure:**
```bash
# Shutdown a worker node
ssh k8s-worker-1 "sudo shutdown -h now"

# Wait for health check to fail (6 seconds with fall=3, inter=2s)
sleep 10

# Verify server marked down
curl http://<haproxy-ip>:8404/stats | grep k8s-worker-1

# Test connectivity (should work via remaining workers)
for i in {1..20}; do
  mysql -h <haproxy-ip> -P 3306 -u testuser -p -e "SELECT CONNECTION_ID();" &
done
wait

# Bring node back up
# ... restart node ...

# Wait for health check to pass (4 seconds with rise=2, inter=2s)
sleep 10

# Verify server marked up
curl http://<haproxy-ip>:8404/stats | grep k8s-worker-1
```

### 2. Cloudflared Pod Failover

```bash
# Delete a cloudflared pod
kubectl delete pod -n cloudflare -l app.kubernetes.io/name=cloudflared --force --grace-period=0

# Verify new pod starts
kubectl get pods -n cloudflare -w

# Test connectivity during failover
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" https://app.example.com
  sleep 1
done
```

### 3. HAProxy Graceful Reload

```bash
# Update HAProxy configuration
# Edit ansible/roles/haproxy/defaults/main.yaml

# Apply changes with graceful reload
cd ansible
ansible-playbook playbooks/deploy-haproxy.yaml

# Verify no connection drops
while true; do
  mysql -h <haproxy-ip> -P 3306 -u testuser -p -e "SELECT NOW();" 2>&1 | grep -E "(ERROR|NOW)"
  sleep 0.5
done
```

## Performance Testing

### 1. HAProxy Performance

```bash
# TCP performance test (MySQL)
sysbench mysql \
  --mysql-host=<haproxy-ip> \
  --mysql-port=3306 \
  --mysql-user=testuser \
  --mysql-password=testpass \
  --mysql-db=testdb \
  --threads=16 \
  --time=60 \
  run

# Connection rate test
for i in {1..1000}; do
  mysql -h <haproxy-ip> -P 3306 -u testuser -p -e "SELECT 1;" &
done
wait
```

### 2. Cloudflared Performance

```bash
# HTTP load test
ab -n 10000 -c 100 https://app.example.com/

# API performance test
wrk -t 12 -c 400 -d 60s https://api.example.com/health

# WebSocket test
wscat -c wss://app.example.com/ws
```

### 3. Network Latency

```bash
# Measure latency to HAProxy
ping -c 100 <haproxy-ip>

# Measure HTTP latency via Cloudflare
curl -o /dev/null -s -w "Time: %{time_total}s\n" https://app.example.com

# Measure TCP latency
time echo "SELECT 1;" | mysql -h <haproxy-ip> -P 3306 -u testuser -p
```

## Security Testing

### 1. TLS/SSL Testing

```bash
# Test SSL configuration
nmap --script ssl-enum-ciphers -p 443 app.example.com

# Check certificate
echo | openssl s_client -connect app.example.com:443 2>/dev/null | openssl x509 -noout -text

# Verify HTTP to HTTPS redirect
curl -I http://app.example.com
```

### 2. Access Control Testing

```bash
# Test Cloudflare Access (should redirect to login)
curl -I https://monitoring.example.com

# Test IP-based restrictions (if configured)
curl --interface <unauthorized-ip> https://app.example.com

# Test rate limiting
for i in {1..1000}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://api.example.com/
done
```

### 3. Vulnerability Scanning

```bash
# Scan HAProxy server
nmap -sV -sC <haproxy-ip>

# Scan exposed services
nmap -p 3306,5432,6379,51820 <haproxy-ip>

# Check for open ports
nmap -p- <haproxy-ip>
```

## Automated Testing

### 1. CI/CD Integration

The repository includes GitHub Actions workflows for automated testing:

**On Pull Request:**
- YAML linting
- Helmfile diff
- Configuration validation

**On Deployment:**
- Pre-deployment validation
- Helmfile template rendering
- Post-deployment health checks

### 2. Monitoring and Alerting

Set up automated monitoring:

```bash
# Prometheus metrics
curl http://<haproxy-ip>:9101/metrics  # HAProxy exporter
curl http://<cloudflared-pod>:2000/metrics  # Cloudflared metrics

# Grafana dashboards
# - HAProxy dashboard
# - Cloudflared tunnel metrics
# - Kubernetes service health
```

### 3. Scheduled Testing

```bash
# Create a cron job for regular health checks
cat > /etc/cron.d/infrastructure-health <<EOF
*/5 * * * * root /usr/local/bin/test-haproxy.sh
*/5 * * * * root /usr/local/bin/test-cloudflared.sh
EOF
```

## Troubleshooting Failed Tests

### HAProxy Issues

```bash
# Check HAProxy logs
journalctl -u haproxy -f

# Verify configuration
haproxy -c -f /etc/haproxy/haproxy.cfg

# Test backend connectivity
nc -zv <worker-ip> 30306
```

### Cloudflared Issues

```bash
# Check tunnel logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Verify tunnel credentials
kubectl get secret -n cloudflare cloudflared-credentials -o yaml

# Test from within cluster
kubectl run -it curl --image=curlimages/curl -- curl http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local
```

### Network Issues

```bash
# Check DNS resolution
dig +trace app.example.com

# Test connectivity
traceroute <haproxy-ip>
mtr -r -c 100 <haproxy-ip>

# Check firewall rules
sudo iptables -L -n -v
sudo ufw status verbose
```

## Best Practices

1. **Test in staging first**: Always validate changes in staging before production
2. **Automate tests**: Use CI/CD for automated validation
3. **Monitor continuously**: Set up alerts for failures
4. **Document failures**: Keep a runbook of common issues and solutions
5. **Load test regularly**: Validate performance under realistic load
6. **Security scan frequently**: Run vulnerability scans on regular schedule
7. **Practice failover**: Regular failover drills ensure readiness

## References

- [HAProxy Documentation](https://www.haproxy.org/documentation.html)
- [Cloudflared Testing](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/remote/)
- [Kubernetes Testing Best Practices](https://kubernetes.io/docs/tasks/debug/)
- [Load Testing Tools](https://github.com/topics/load-testing)
