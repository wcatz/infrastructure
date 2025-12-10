# Quick Start: Cloudflare Tunnel with Existing Credentials

This guide provides a quick walkthrough for integrating existing Cloudflare Tunnel credentials into your infrastructure cluster.

## Prerequisites

✅ Existing Cloudflare Tunnel (created previously)
✅ Tunnel credentials file (`~/.cloudflared/<TUNNEL-ID>.json`)
✅ SOPS age key configured
✅ Kubernetes cluster running
✅ `kubectl`, `cloudflared`, `sops` installed

## 5-Minute Setup

### 1. Import Credentials

```bash
# Run the automated import script
./scripts/import-cloudflared-credentials.sh \
  -t 12345678-1234-1234-1234-123456789abc \
  -n infrastructure-prod-tunnel \
  -e prod
```

**What this does:**
- ✅ Validates your tunnel and credentials
- ✅ Creates encrypted Kubernetes secret
- ✅ Saves to `helmfile/secrets/cloudflared-credentials.enc.yaml`
- ✅ Securely deletes plaintext files

### 2. Configure DNS

```bash
# Add DNS routes for your domains
./scripts/configure-tunnel-dns.sh \
  -t infrastructure-prod-tunnel \
  -d "app.example.com,api.example.com,grafana.example.com" \
  -v
```

**What this does:**
- ✅ Creates CNAME records pointing to your tunnel
- ✅ Verifies DNS propagation

### 3. Update Configuration

Edit `helmfile/values/cloudflared-values.yaml`:

```yaml
cloudflare:
  tunnelName: "infrastructure-prod-tunnel"
  tunnelId: "12345678-1234-1234-1234-123456789abc"

ingress:
  - hostname: app.example.com
    service: http://webapp.default.svc.cluster.local:80
  - hostname: api.example.com
    service: http://api-service.default.svc.cluster.local:8080
  - hostname: grafana.example.com
    service: http://prometheus-grafana.monitoring.svc.cluster.local:80
  - service: http_status:404
```

**Customize:**
- Replace hostnames with your actual domains
- Update service names and namespaces to match your cluster
- Add/remove ingress rules as needed

### 4. Deploy

```bash
# Deploy credentials to cluster
kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -
sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -

# Deploy cloudflared with Helmfile
cd helmfile
helmfile diff   # Preview changes
helmfile apply  # Deploy
```

### 5. Validate

```bash
# Run validation script
cd ..
./scripts/validate-tunnel-setup.sh \
  -t infrastructure-prod-tunnel \
  -d "app.example.com,api.example.com,grafana.example.com"
```

**Expected output:**
```
✅ All critical checks passed!

Next steps:
  • Monitor pod logs: kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared -f
  • Check tunnel status: cloudflared tunnel info infrastructure-prod-tunnel
  • View metrics: kubectl port-forward -n cloudflare deployment/cloudflared 2000:2000
```

### 6. Test Access

```bash
# Test your applications
curl -I https://app.example.com
curl -I https://api.example.com
curl -I https://grafana.example.com
```

**Expected:** HTTP 200 OK or redirect to login page (depending on your service)

## Troubleshooting

### Pods not starting?

```bash
# Check pod status
kubectl get pods -n cloudflare

# View logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared

# Describe deployment
kubectl describe deployment cloudflared -n cloudflare
```

**Common issues:**
- ❌ Missing credentials secret → Re-run step 1 and 4
- ❌ Invalid credentials → Verify tunnel ID and credentials file
- ❌ Network issues → Check cluster egress to Cloudflare

### DNS not resolving?

```bash
# Check DNS configuration
dig app.example.com
nslookup app.example.com @1.1.1.1

# List tunnel routes
cloudflared tunnel route list
```

**Common issues:**
- ❌ CNAME not created → Re-run step 2
- ❌ DNS not propagated → Wait 5-10 minutes
- ❌ Wrong tunnel target → Verify tunnel ID in DNS

### Service returns 502/503?

```bash
# Test service from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://webapp.default.svc.cluster.local:80

# Check service and endpoints
kubectl get svc -A
kubectl get endpoints -A
```

**Common issues:**
- ❌ Wrong service name in values.yaml
- ❌ Service not running
- ❌ Incorrect port number

## Next Steps

✅ **Set up monitoring**: Add Prometheus alerts for tunnel health
✅ **Configure backups**: Ensure credentials are backed up securely
✅ **Document**: Update your runbook with tunnel details
✅ **Test failover**: Verify HA with multiple replicas
✅ **Security review**: Run security scan with `./scripts/validate.sh`

## Resources

📚 **Detailed Documentation:**
- [Complete Setup Guide](helmfile/CLOUDFLARED_SETUP.md)
- [Secret Management](SECRETS.md)
- [DNS Configuration](DNS_SETUP.md)
- [Troubleshooting](helmfile/CLOUDFLARED_SETUP.md#troubleshooting)

🔧 **Helper Scripts:**
- `import-cloudflared-credentials.sh` - Import credentials
- `configure-tunnel-dns.sh` - Configure DNS
- `validate-tunnel-setup.sh` - Validate deployment

🔗 **External Resources:**
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [SOPS Encryption](https://github.com/mozilla/sops)

---

**Questions?** Open an issue at [GitHub Issues](https://github.com/wcatz/infrastructure/issues)
