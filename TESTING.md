# Testing and Validation Guide

This guide provides comprehensive testing procedures for validating infrastructure deployments.

## Table of Contents

- [Pre-Deployment Testing](#pre-deployment-testing)
- [Helmfile Testing](#helmfile-testing)
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

# Check k3s playbook syntax
ansible-playbook playbooks/deploy-k3s.yaml --syntax-check

# Check hostname playbook syntax
ansible-playbook playbooks/configure-hostname.yaml --syntax-check

# Check tailscale playbook syntax
ansible-playbook playbooks/setup-tailscale.yaml --syntax-check
```

## Helmfile Testing

### 1. Template Validation

```bash
cd helmfile

# Render templates without applying
helmfile template --suppress-secrets > /dev/null

# Check for errors
helmfile diff --suppress-secrets
```

### 2. Values File Validation

```bash
# Validate YAML syntax
yamllint values/*.yaml

# Check specific values
helm template prometheus prometheus-community/prometheus -f values/prometheus-values.yaml > /dev/null
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
# Test specific service access
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl -v http://app-service.default.svc.cluster.local:8080
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
# HTTP/HTTPS path: Client → Cloudflare → Cloudflared → Services
curl -v https://app.example.com
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared --tail=20
kubectl logs -n default -l app=myapp --tail=20
```

### 2. DNS Resolution Testing

```bash
# Test DNS resolution for Cloudflare tunnel
dig app.example.com
nslookup app.example.com

# Verify DNS from multiple nameservers
dig @8.8.8.8 app.example.com
dig @1.1.1.1 app.example.com
```

### 3. Multi-Environment Testing

```bash
# Development
curl https://app.dev.example.com

# Staging
curl https://app.staging.example.com

# Production
curl https://app.example.com
```

## Failover Testing

### 1. Pod Failover

**Simulate pod failure:**
```bash
# Delete a pod to test Kubernetes self-healing
kubectl delete pod -n default -l app=myapp --force --grace-period=0

# Verify new pod starts
kubectl get pods -n default -l app=myapp -w

# Test connectivity during failover
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" https://app.example.com
  sleep 1
done
```

**Simulate node failure:**
```bash
# Drain a worker node
kubectl drain k8s-worker-1 --ignore-daemonsets --delete-emptydir-data

# Verify pods reschedule to other nodes
kubectl get pods -A -o wide | grep k8s-worker-1

# Test service availability
curl https://app.example.com

# Uncordon the node
kubectl uncordon k8s-worker-1
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

### 3. Cloudflared Failover

```bash
# Delete cloudflared pod
kubectl delete pod -n cloudflare -l app.kubernetes.io/name=cloudflared --force --grace-period=0

# Verify new pod starts
kubectl get pods -n cloudflare -w

# Test connectivity during failover
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" https://app.example.com
  sleep 1
done
```

## Performance Testing

### 1. Ingress Performance

```bash
# HTTP load test via Cloudflared
ab -n 10000 -c 100 https://app.example.com/

# Sustained load test
wrk -t 12 -c 400 -d 30s https://app.example.com/

# Check service metrics
kubectl top pods -n default
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
# Measure HTTP latency via Cloudflare
curl -o /dev/null -s -w "Time: %{time_total}s\n" https://app.example.com

# Measure to multiple endpoints
for url in https://app.example.com https://api.example.com; do
  echo "Testing $url"
  curl -o /dev/null -s -w "  Total: %{time_total}s\n  Connect: %{time_connect}s\n  StartTransfer: %{time_starttransfer}s\n" $url
done
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
# Scan web application
nmap -sV -sC app.example.com

# Check SSL/TLS vulnerabilities
testssl.sh https://app.example.com

# Check for common web vulnerabilities
nikto -h https://app.example.com
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
# Cloudflared metrics
kubectl port-forward -n cloudflare svc/cloudflared 2000:2000
curl http://localhost:2000/metrics

# Grafana dashboards
# - Cloudflared tunnel metrics
# - Kubernetes service health
```

### 3. Scheduled Testing

```bash
# Create a Kubernetes CronJob for regular health checks
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: infrastructure-health-check
  namespace: default
spec:
  schedule: "*/5 * * * *"
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
            - curl -f https://app.example.com/health || exit 1
          restartPolicy: OnFailure
EOF
```

## Troubleshooting Failed Tests

### Service Access Issues

```bash
# Check service logs
kubectl logs -n default -l app=myapp --tail=100

# Check service status
kubectl get pods -n default
kubectl describe pod -n default <pod-name>

# Check service endpoints
kubectl get svc -A
kubectl get endpoints -A
```

### Cloudflared Issues

```bash
# Check tunnel logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Verify tunnel credentials
kubectl get secret -n cloudflare cloudflared-credentials -o yaml

# Test from within cluster
kubectl run -it curl --image=curlimages/curl -- curl http://app-service.default.svc.cluster.local
```

### Network Issues

```bash
# Check DNS resolution
dig +trace app.example.com

# Test connectivity to services
ping app.example.com
traceroute app.example.com

# Test network path
mtr -r -c 100 app.example.com

# Check Kubernetes network
kubectl get svc -A
kubectl get endpoints -A
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

- [Cloudflared Testing](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/remote/)
- [Kubernetes Testing Best Practices](https://kubernetes.io/docs/tasks/debug/)
- [Load Testing Tools](https://github.com/topics/load-testing)
