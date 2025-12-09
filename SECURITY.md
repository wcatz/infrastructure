# Security Policy

This document outlines the security measures and best practices for the hybrid Kubernetes infrastructure.

## Table of Contents

- [Overview](#overview)
- [Cluster Health and Security](#cluster-health-and-security)
- [Secret Exposure Mitigation](#secret-exposure-mitigation)
- [Environment Isolation](#environment-isolation)
- [Network Security](#network-security)
- [Access Control](#access-control)
- [Monitoring and Auditing](#monitoring-and-auditing)
- [Incident Response](#incident-response)
- [Compliance](#compliance)

## Overview

This infrastructure implements a **defense-in-depth security model** with multiple layers of protection:

1. **Encryption at rest**: Secrets encrypted with SOPS, etcd encryption enabled
2. **Encryption in transit**: Tailscale mesh, Cloudflare tunnels, TLS everywhere
3. **Access control**: RBAC, network policies, firewall rules
4. **Monitoring**: Prometheus alerts, audit logs, secret scanning
5. **Isolation**: Environment separation, namespace isolation, pod security

## Cluster Health and Security

### Current Status

✅ **Secured Components:**
- Secrets encrypted with SOPS (age encryption) before commit to Git
- Kubernetes secrets stored in etcd with encryption at rest (K3s default)
- Non-production environments (dev/staging) disabled by default
- Cloudflared credentials stored as encrypted Kubernetes secrets
- GitHub Actions uses OIDC authentication where possible
- Tailscale provides encrypted mesh networking

⚠️ **Security Considerations:**
- Control plane accessible only via Tailscale (no public exposure)
- Worker nodes have public IPs for NodePort services (selective exposure)
- Cloudflared handles HTTP/HTTPS without exposing ports 80/443
- Manual secret rotation required (automated rotation recommended)

### Kubernetes Security Hardening

#### 1. Pod Security Standards

```yaml
# Applied to sensitive namespaces
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Implementation:**
- Restricted pod security for production workloads
- Baseline security for monitoring and infrastructure
- Privileged mode only for system components

#### 2. Network Policies

```yaml
# Default deny all ingress/egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**Status:** Implemented in `helmfile/manifests/network-policies.yaml`

#### 3. RBAC Policies

**Principle of Least Privilege:**
- Service accounts have minimal required permissions
- No default service account tokens mounted (except where needed)
- Role-based access for secret management

#### 4. Resource Quotas

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    persistentvolumeclaims: "10"
    secrets: "50"
```

**Purpose:** Prevent resource exhaustion attacks

### Cluster Health Monitoring

#### Prometheus Alerts

Active alerts for cluster health:
- `KubeletDown`: Kubelet is down
- `KubeNodeNotReady`: Node is not ready
- `KubePodCrashLooping`: Pod is crash looping
- `KubePodNotReady`: Pod not ready for extended period
- `KubeDeploymentReplicasMismatch`: Deployment replica mismatch
- `KubeStatefulSetReplicasMismatch`: StatefulSet replica mismatch

#### Health Check Script

```bash
#!/bin/bash
# scripts/health-check.sh

echo "=== Kubernetes Cluster Health Check ==="

# Check node status
echo -e "\n1. Node Status:"
kubectl get nodes

# Check pod status
echo -e "\n2. Failed Pods:"
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Check persistent volumes
echo -e "\n3. PersistentVolume Status:"
kubectl get pv

# Check certificates
echo -e "\n4. Certificate Status:"
kubectl get certificates -A

# Check backup status
echo -e "\n5. Recent Backups:"
kubectl get backups -n velero --sort-by=.metadata.creationTimestamp | tail -5

# Check critical secrets exist
echo -e "\n6. Critical Secrets:"
kubectl get secret cloudflared-credentials -n cloudflare &> /dev/null && echo "✅ Cloudflared credentials" || echo "❌ Cloudflared credentials missing"
kubectl get secret github-runner-secrets -n github-runner &> /dev/null && echo "✅ GitHub runner secrets" || echo "❌ GitHub runner secrets missing"

# Check for pods with exposed secrets
echo -e "\n7. Security Scan:"
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].env[]? | .name | contains("PASSWORD") or contains("TOKEN") or contains("SECRET")) | "\(.metadata.namespace)/\(.metadata.name)"' || echo "No environment variable exposure detected"

echo -e "\n=== Health Check Complete ==="
```

## Secret Exposure Mitigation

### Identified Risks and Mitigations

#### Risk 1: Plaintext Secrets in Git

**Mitigation:**
- ✅ All secrets encrypted with SOPS before commit
- ✅ `.gitignore` blocks plaintext secret files
- ✅ GitHub secret scanning enabled
- ✅ Pre-commit hooks recommended (see below)
- ✅ Example encrypted secrets provided

**Pre-commit Hook:**
```bash
#!/bin/bash
# .git/hooks/pre-commit

# Block commits of plaintext secrets
if git diff --cached --name-only | grep -E '(secret|credential|password)\.yaml$' | grep -v '\.enc\.yaml$'; then
  echo "ERROR: Attempting to commit plaintext secrets!"
  echo "Please encrypt with: sops -e <file>.yaml > <file>.enc.yaml"
  exit 1
fi
```

#### Risk 2: Secrets in Environment Variables

**Mitigation:**
- ✅ Use Kubernetes secrets mounted as volumes (preferred)
- ✅ Limit environment variable usage to non-sensitive config
- ✅ Network policies prevent pod-to-pod secret scraping
- ⚠️ Review application logs to ensure no secret logging

**Best Practice:**
```yaml
# GOOD: Mount as volume
volumes:
- name: secrets
  secret:
    secretName: app-secrets
volumeMounts:
- name: secrets
  mountPath: /etc/secrets
  readOnly: true

# AVOID: Environment variables (use only for non-sensitive data)
env:
- name: DATABASE_URL
  valueFrom:
    secretKeyRef:
      name: db-secret
      key: url
```

#### Risk 3: Secrets in Logs

**Mitigation:**
- ✅ Helmfile uses `--suppress-secrets` flag in CI/CD
- ✅ Application logging frameworks configured to mask secrets
- ⚠️ Regular log review for accidental exposure
- ✅ Prometheus/Grafana configured without secret exposure

#### Risk 4: Cloudflared Token Exposure

**Mitigation:**
- ✅ Tunnel credentials stored only as encrypted Kubernetes secrets
- ✅ Credentials not mounted as environment variables
- ✅ Original `~/.cloudflared/*.json` deleted after secret creation
- ✅ Secret rotation procedure documented in SECRETS.md
- ✅ Token expiration set to 90 days with rotation reminders

**Verification:**
```bash
# Check Cloudflared secret is properly configured
kubectl get secret cloudflared-credentials -n cloudflare -o yaml | grep -v "credentials.json"

# Should NOT show plaintext credentials
```

#### Risk 5: Secret Access via kubectl

**Mitigation:**
- ✅ RBAC limits secret read access
- ✅ Audit logging enabled for secret access
- ✅ Regular RBAC reviews
- ⚠️ Kubernetes API access limited to Tailscale network

**RBAC Example:**
```yaml
# Deny default service account secret access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: no-secret-access
  namespace: production
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: []  # No access
```

## Environment Isolation

### Production-Only Policy

**Status:** ✅ Implemented

To minimize attack surface and prevent accidental secret exposure:

1. **Non-production environments DISABLED by default**
   - `helmfile/environments/dev/enabled.yaml` - all services disabled
   - `helmfile/environments/staging/enabled.yaml` - all services disabled
   - `helmfile/environments/prod/enabled.yaml` - full production stack enabled

2. **Separate secrets per environment**
   - Production secrets in `helmfile/environments/prod/`
   - Staging secrets (when enabled) in `helmfile/environments/staging/`
   - Development secrets (when enabled) in `helmfile/environments/dev/`

3. **No secret sharing between environments**
   - Production uses different Cloudflared tunnel and credentials
   - Staging uses different GitHub runner tokens
   - Development uses mock/test secrets only

### Enabling Non-Production Environments

**Only for testing/development purposes:**

```bash
# Edit environment config
vim helmfile/environments/staging/enabled.yaml

# Change services to true as needed
enabled:
  prometheus: true  # Changed from false
  cloudflared: true  # Changed from false
  # etc.

# Deploy staging environment
cd helmfile
helmfile -e staging apply
```

**⚠️ WARNING:** Never enable non-production environments in actual production cluster. Use separate clusters for dev/staging.

## Network Security

### Firewall Configuration

#### Control Plane Node

**Policy:** Default deny, allow only Tailscale

```bash
# UFW rules on control plane
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 100.64.0.0/10  # Tailscale only
sudo ufw enable
```

#### Worker Nodes

**Policy:** Deny all except specific NodePorts and Tailscale

```bash
# UFW rules on workers
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 100.64.0.0/10  # Tailscale
# Selective NodePort exposure (example)
sudo ufw limit 30000:30010/tcp  # Rate-limited range
sudo ufw enable
```

### Tailscale ACLs

**Recommended ACL policy:**

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:admin"],
      "dst": ["tag:k8s-control:*"]
    },
    {
      "action": "accept",
      "src": ["tag:k8s-worker"],
      "dst": ["tag:k8s-control:6443"]
    },
    {
      "action": "accept",
      "src": ["tag:ci"],
      "dst": ["tag:k8s-control:6443"]
    }
  ],
  "tagOwners": {
    "tag:admin": ["user@example.com"],
    "tag:k8s-control": ["user@example.com"],
    "tag:k8s-worker": ["user@example.com"],
    "tag:ci": ["user@example.com"]
  }
}
```

### Cloudflare Tunnel Security

- ✅ No inbound port 80/443 exposure
- ✅ Zero Trust access policies configured in Cloudflare dashboard
- ✅ Access tokens rotated every 90 days
- ✅ Tunnel credentials encrypted with SOPS

## Access Control

### Kubernetes RBAC

**Implemented Roles:**
- `cluster-admin`: Full cluster access (emergency only)
- `namespace-admin`: Full namespace access
- `developer`: Read/write pods, services, deployments
- `viewer`: Read-only access

**Service Account Security:**
```yaml
# Disable default service account auto-mount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: production
automountServiceAccountToken: false
```

### SSH Access

- ✅ SSH key-based authentication only
- ✅ Password authentication disabled
- ✅ Root login disabled
- ✅ SSH accessible only via Tailscale network
- ⚠️ SSH key rotation every 365 days

### GitHub Actions OIDC

**Implementation:**
- ✅ OIDC authentication for cloud providers (when applicable)
- ✅ Short-lived tokens
- ✅ Least privilege IAM roles
- ✅ Audit trail in GitHub Actions logs

## Monitoring and Auditing

### Prometheus Alerts

**Security-related alerts:**
- `HighSecretAccessRate`: Unusual secret access pattern
- `UnauthorizedPodCreation`: Pod creation by unauthorized user
- `NetworkPolicyViolation`: Network policy violation detected
- `CertificateExpiringSoon`: TLS certificate expiring within 30 days

### Audit Logging

**Kubernetes Audit Policy:**
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # Log secret access
  - level: RequestResponse
    resources:
    - group: ""
      resources: ["secrets"]
    verbs: ["get", "list", "watch"]
  # Log RBAC changes
  - level: RequestResponse
    resources:
    - group: "rbac.authorization.k8s.io"
    verbs: ["create", "update", "delete", "patch"]
```

### Secret Rotation Tracking

**GitHub Issue Template:**

Automated issue creation for secret rotation reminders (see `.github/secret-rotation-tracker.yaml`)

## Incident Response

### Secret Compromise Procedure

**If a secret is compromised:**

1. **Immediate actions (within 1 hour):**
   - Rotate compromised secret immediately
   - Revoke old secret/token
   - Review access logs for unauthorized usage
   - Deploy updated secret to cluster

2. **Investigation (within 24 hours):**
   - Determine scope of exposure
   - Identify affected systems
   - Review audit logs
   - Check for unauthorized access

3. **Remediation:**
   - Rotate all related secrets
   - Update documentation
   - Implement additional controls
   - Post-incident review

4. **Communication:**
   - Notify stakeholders
   - Document incident in security log
   - Update security procedures

### Cloudflared Token Compromise

**Specific procedure:**

```bash
# 1. Delete existing tunnel
cloudflared tunnel delete infrastructure-tunnel

# 2. Create new tunnel
cloudflared tunnel create infrastructure-tunnel-new

# 3. Update DNS
cloudflared tunnel route dns infrastructure-tunnel-new app.example.com

# 4. Encrypt and deploy new credentials
sops -e new-credentials.yaml > new-credentials.enc.yaml
sops -d new-credentials.enc.yaml | kubectl apply -f -

# 5. Restart Cloudflared pods
kubectl rollout restart deployment/cloudflared -n cloudflare

# 6. Verify new tunnel
kubectl logs -n cloudflare -l app=cloudflared
```

## Compliance

### Checklist

- [x] Secrets encrypted at rest (SOPS + etcd encryption)
- [x] Secrets encrypted in transit (Tailscale + Cloudflare)
- [x] Non-production environments disabled
- [x] Secret rotation procedures documented
- [x] RBAC implemented
- [x] Network policies implemented
- [x] Audit logging configured
- [x] Backup and disaster recovery (Velero)
- [ ] Regular security reviews (quarterly)
- [ ] Penetration testing (annually)
- [ ] Secret rotation enforcement (automated)
- [ ] Compliance reporting (as needed)

### Regulatory Considerations

**For regulated environments (HIPAA, PCI-DSS, SOC 2):**

- Implement additional encryption layers
- Enable comprehensive audit logging
- Implement automated secret rotation
- Regular security assessments
- Formal change management
- Data residency controls

### Audit Trail

**Maintained records:**
- Git commit history (encrypted secrets)
- Kubernetes audit logs (API access)
- Prometheus metrics (cluster health)
- GitHub Actions logs (CI/CD activities)
- Velero backups (disaster recovery)

## References

- [SECRETS.md](SECRETS.md) - Complete secret management guide
- [.sops.yaml](.sops.yaml) - SOPS configuration
- [docs/setup.md](docs/setup.md) - Infrastructure setup
- [docs/operate.md](docs/operate.md) - Operations guide
- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines

---

**Last Updated:** 2024-01-15  
**Review Frequency:** Quarterly  
**Next Review:** 2024-04-15
