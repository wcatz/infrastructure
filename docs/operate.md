# Infrastructure Operations Guide

Complete guide for operating, testing, monitoring, and maintaining the hybrid Kubernetes infrastructure.

## Table of Contents

- [Testing and Validation](#testing-and-validation)
- [Deployment Audit](#deployment-audit)
- [Monitoring and Alerting](#monitoring-and-alerting)
- [Disaster Recovery](#disaster-recovery)
- [Worker Backup Recovery](#worker-backup-recovery)
- [Kubernetes Workload Examples](#kubernetes-workload-examples)
- [Maintenance and Upgrades](#maintenance-and-upgrades)
- [Troubleshooting](#troubleshooting)

## Testing and Validation

### Pre-Deployment Testing

#### YAML Validation

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

#### Ansible Validation

```bash
cd ansible

# Check k3s playbook syntax
ansible-playbook playbooks/deploy-k3s.yaml --syntax-check

# Check hostname playbook syntax
ansible-playbook playbooks/configure-hostname.yaml --syntax-check

# Check tailscale playbook syntax
ansible-playbook playbooks/setup-tailscale.yaml --syntax-check

# Dry run (check mode)
ansible-playbook playbooks/deploy-k3s.yaml --check
```

### Helmfile Testing

#### Preview Changes

```bash
cd helmfile

# Show diff of changes
helmfile diff --suppress-secrets

# Sync without applying
helmfile sync --suppress-secrets
```

#### Template Validation

```bash
# Render all templates
helmfile template --suppress-secrets > /tmp/all-manifests.yaml

# Validate with kubectl
kubectl apply --dry-run=client -f /tmp/all-manifests.yaml

# Check for issues
kubectl apply --dry-run=server -f /tmp/all-manifests.yaml
```

### Cloudflared Testing

#### Test Tunnel Connectivity

```bash
# Check tunnel status
cloudflared tunnel info infrastructure-tunnel

# List tunnel routes
cloudflared tunnel route list

# Test tunnel connection (run locally for testing)
cloudflared tunnel run infrastructure-tunnel
```

#### Test Service Accessibility

```bash
# Test HTTP endpoint
curl -I https://app.example.com

# Test with verbose output
curl -v https://app.example.com

# Check DNS resolution
dig app.example.com
nslookup app.example.com
```

### End-to-End Testing

#### Deploy Test Application

```bash
# Deploy test nginx
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-nginx
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test-nginx
  template:
    metadata:
      labels:
        app: test-nginx
    spec:
      containers:
      - name: nginx
        image: nginxdemos/hello:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-nginx
  namespace: default
spec:
  selector:
    app: test-nginx
  ports:
  - port: 80
    targetPort: 80
EOF
```

#### Test Internal Connectivity

```bash
# Test pod-to-pod communication
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://test-nginx.default.svc.cluster.local

# Test DNS resolution from pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  nslookup test-nginx.default.svc.cluster.local
```

#### Test External Access

```bash
# Via Cloudflared tunnel (if configured)
curl https://test.example.com

# Via NodePort (if configured)
curl http://<worker-public-ip>:<nodeport>
```

#### Cleanup

```bash
kubectl delete deployment test-nginx
kubectl delete service test-nginx
```

### Failover Testing

#### Test Worker Node Failover

```bash
# Cordon a worker node
kubectl cordon k3s-worker-01

# Drain pods from node
kubectl drain k3s-worker-01 --ignore-daemonsets --delete-emptydir-data

# Verify pods rescheduled
kubectl get pods -A -o wide

# Uncordon node
kubectl uncordon k3s-worker-01
```

#### Test Control Plane Failover (HA Setup)

```bash
# Stop k3s on primary control plane
ssh user@control-plane-01
sudo systemctl stop k3s

# Verify other control planes took over
kubectl get nodes

# Restart k3s
sudo systemctl start k3s
```

### Performance Testing

#### Load Test Application

```bash
# Install hey (HTTP load testing tool)
go install github.com/rakyll/hey@latest

# Run load test
hey -z 30s -c 50 https://app.example.com

# Monitor during test
kubectl top pods -n default
kubectl top nodes
```

#### Benchmark Storage

```bash
# Deploy fio for storage benchmarking
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: fio-test
spec:
  containers:
  - name: fio
    image: wallnerryan/fiotools-aio
    command: ["sleep", "3600"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    emptyDir: {}
EOF

# Run benchmark
kubectl exec -it fio-test -- fio --name=test --rw=randwrite --size=1G --directory=/data
```

### Security Testing

#### Scan for Vulnerabilities

```bash
# Scan container images with Trivy
trivy image nginx:latest

# Scan Helm charts
trivy config helmfile/

# Check for security issues in cluster
kubectl get psp  # Pod Security Policies
kubectl get networkpolicies -A
```

#### Test Network Policies

```bash
# Create test network policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Test connectivity (should fail)
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://test-nginx.default.svc.cluster.local

# Remove test policy
kubectl delete networkpolicy test-deny-all
```

## Deployment Audit

### Verification Checklist

After deployment, verify all components are functioning correctly:

#### Cluster Health

```bash
# Check node status
kubectl get nodes
# Expected: All nodes Ready

# Check system pods
kubectl get pods -n kube-system
# Expected: All Running

# Check API server health
kubectl get --raw /healthz
# Expected: ok

# Check component status
kubectl get componentstatuses
```

#### Networking

```bash
# Verify Tailscale connectivity
tailscale status

# Check Tailscale IPs
tailscale ip -4

# Test inter-node communication
ping <tailscale-ip-of-other-node>

# Verify no Flannel/CNI conflicts
kubectl get pods -n kube-system | grep -i flannel
# Expected: No results (Flannel disabled)
```

#### Workload Scheduling

```bash
# Verify control plane taint
kubectl describe node <control-plane-name> | grep Taints
# Expected: node-role.kubernetes.io/control-plane:NoSchedule

# Deploy test pod and verify it's on worker
kubectl run test --image=nginx --restart=Never
kubectl get pod test -o wide
# Expected: NODE should be worker, not control plane
kubectl delete pod test
```

#### Storage

```bash
# Check storage classes
kubectl get storageclass

# Create test PVC
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Verify PVC bound
kubectl get pvc test-pvc
# Expected: STATUS Bound

# Cleanup
kubectl delete pvc test-pvc
```

#### Services and Ingress

```bash
# Check Cloudflared pods
kubectl get pods -n cloudflare
# Expected: All Running

# Check Cloudflared logs
kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared --tail=50

# Verify tunnel status
cloudflared tunnel info infrastructure-tunnel

# Test external access
curl -I https://app.example.com
```

#### Monitoring Stack

```bash
# Check Prometheus
kubectl get pods -n monitoring -l app=prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:80
# Open http://localhost:9090

# Check Grafana
kubectl get pods -n monitoring -l app=grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open http://localhost:3000
```

### Common Deployment Issues

#### Issue: Pods Not Scheduling

```bash
# Check events
kubectl get events -A --sort-by='.lastTimestamp'

# Check pod events
kubectl describe pod <pod-name>

# Common causes:
# 1. Control plane not tainted - verify taint
# 2. Insufficient resources - check node capacity
# 3. Image pull errors - check image name and credentials
```

#### Issue: Services Not Accessible

```bash
# Check service endpoints
kubectl get endpoints

# Check service details
kubectl describe service <service-name>

# Test internal connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://<service-name>.<namespace>.svc.cluster.local
```

#### Issue: Persistent Volumes Not Binding

```bash
# Check PV and PVC status
kubectl get pv,pvc -A

# Check storage class
kubectl describe storageclass

# Check events
kubectl describe pvc <pvc-name>
```

## Monitoring and Alerting

### Prometheus Setup

Prometheus is deployed via Helmfile and collects metrics from:
- Kubernetes nodes
- Pods and containers
- Cluster components
- Applications with `/metrics` endpoints

#### Access Prometheus

```bash
# Port forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:80

# Open in browser
open http://localhost:9090
```

#### Useful Prometheus Queries

```promql
# Node CPU usage
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod memory usage
sum(container_memory_working_set_bytes) by (pod, namespace)

# Pod restart count
sum(kube_pod_container_status_restarts_total) by (pod, namespace)

# Available disk space
100 - ((node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100)
```

### Grafana Setup

#### Access Grafana

```bash
# Port forward to Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80

# Open in browser
open http://localhost:3000

# Default credentials: admin / admin (change on first login)
```

#### Import Dashboards

1. Go to **+** → **Import**
2. Import common dashboard IDs:
   - **315**: Kubernetes cluster monitoring
   - **6417**: Kubernetes cluster (Prometheus)
   - **1860**: Node Exporter Full
   - **12006**: Kubernetes apiserver

### Alerting

Configure alerts for critical conditions:

```yaml
# Example PrometheusRule for alerts
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: infrastructure-alerts
  namespace: monitoring
spec:
  groups:
  - name: cluster
    rules:
    - alert: NodeDown
      expr: up{job="node-exporter"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Node {{ $labels.instance }} is down"
    
    - alert: HighCPUUsage
      expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage on {{ $labels.instance }}"
    
    - alert: HighMemoryUsage
      expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High memory usage on {{ $labels.instance }}"
```

## Disaster Recovery

### Recovery Objectives

| Component | RTO | RPO | Notes |
|-----------|-----|-----|-------|
| k3s Control Plane | 30 min | 0 (GitOps) | Rebuild from scratch |
| Stateless Workloads | 20 min | 0 (GitOps) | Redeploy via Helmfile |
| Stateful Workloads | 1-2 hrs | 4 hrs | Includes volume restore |
| MySQL Database | 1-2 hrs | 4 hrs | From backup + transaction logs |
| Monitoring Stack | 30 min | 24 hrs | Historical data loss acceptable |

### Backup Strategy

#### GitOps Backup (Infrastructure as Code)

All infrastructure configuration is stored in Git:
- Ansible playbooks and inventory
- Helmfile configurations
- Kubernetes manifests
- Terraform configurations (if used)

**Backup Procedure:**
```bash
# Repository is automatically backed up to GitHub
# Additional backup to S3 (if configured)
git bundle create infrastructure-backup.bundle --all
aws s3 cp infrastructure-backup.bundle s3://backups/infrastructure/
```

#### Kubernetes Backup with Velero

Velero provides backup and restore for Kubernetes resources and persistent volumes.

**Install Velero (if not already installed):**
```bash
# Velero is included in Helmfile
# Enable in helmfile/config/enabled.yaml
enabled:
  velero: true

# Apply
helmfile apply
```

**Create Backup:**
```bash
# Full cluster backup
velero backup create full-backup-$(date +%Y%m%d) \
  --include-namespaces '*' \
  --exclude-namespaces kube-system,kube-public,kube-node-lease \
  --snapshot-volumes \
  --wait

# Namespace-specific backup
velero backup create production-backup-$(date +%Y%m%d) \
  --include-namespaces production \
  --snapshot-volumes \
  --wait

# Verify backup
velero backup describe full-backup-$(date +%Y%m%d)
velero backup logs full-backup-$(date +%Y%m%d)
```

**Automated Backup Schedules:**
```bash
# Daily full backup (retention: 30 days)
velero schedule create daily-full \
  --schedule="0 2 * * *" \
  --include-namespaces '*' \
  --exclude-namespaces kube-system,kube-public \
  --ttl 720h

# Hourly production backup (retention: 7 days)
velero schedule create hourly-production \
  --schedule="0 * * * *" \
  --include-namespaces production \
  --ttl 168h

# List schedules
velero schedule get
```

### Restore Procedures

#### Scenario 1: Single Pod Failure

**RTO**: Immediate (automatic)

**Procedure**: Kubernetes automatically recreates the pod.

```bash
# Monitor pod recreation
kubectl get pods -w

# If pod doesn't recreate automatically
kubectl delete pod <pod-name>
```

#### Scenario 2: Namespace Deletion

**RTO**: 15-30 minutes

**Procedure**: Restore from Velero backup.

```bash
# List available backups
velero backup get

# Restore entire namespace
velero restore create --from-backup production-backup-20241206 \
  --include-namespaces production \
  --wait

# Monitor restore
velero restore describe <restore-name>
velero restore logs <restore-name>

# Verify resources
kubectl get all -n production
```

#### Scenario 3: Control Plane Failure

**RTO**: 30 minutes

**Procedure**: Rebuild control plane from scratch.

```bash
# 1. Provision new control plane node
# 2. Configure Tailscale
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# 3. Deploy K3s control plane
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --tags control_plane

# 4. Update kubeconfig on workers
# 5. Verify cluster connectivity
kubectl get nodes

# 6. Workloads should still be running on workers
kubectl get pods -A
```

#### Scenario 4: Complete Cluster Failure

**RTO**: 2-3 hours

**Procedure**: Full cluster rebuild and restore.

```bash
# 1. Provision new nodes (control plane + workers)

# 2. Deploy Tailscale
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# 3. Deploy K3s cluster
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# 4. Install Velero
helmfile -l name=velero apply

# 5. Configure Velero with backup location
# 6. Restore from backup
velero restore create --from-backup full-backup-20241206 --wait

# 7. Verify all resources
kubectl get all -A
kubectl get pv,pvc -A
```

#### Scenario 5: Database Corruption

**RTO**: 1-2 hours

**Procedure**: Restore database from Velero snapshot.

```bash
# 1. Scale down application to prevent writes
kubectl scale deployment my-app --replicas=0 -n production

# 2. Delete corrupted PVC
kubectl delete pvc mysql-data -n production

# 3. Restore from backup
velero restore create --from-backup database-backup-20241206 \
  --include-namespaces production \
  --include-resources pvc,pv \
  --wait

# 4. Restart database pod
kubectl delete pod mysql-0 -n production

# 5. Verify database is healthy
kubectl exec -it mysql-0 -n production -- mysql -u root -p -e "SHOW DATABASES;"

# 6. Scale application back up
kubectl scale deployment my-app --replicas=3 -n production
```

### Backup Testing

**Test restores quarterly** to ensure backups are valid:

```bash
# 1. Create test namespace
kubectl create namespace restore-test

# 2. Restore backup to test namespace
velero restore create test-restore-$(date +%Y%m%d) \
  --from-backup production-backup-20241206 \
  --namespace-mappings production:restore-test \
  --wait

# 3. Verify resources
kubectl get all -n restore-test

# 4. Test application functionality
# 5. Cleanup
kubectl delete namespace restore-test
```

## Worker Backup Recovery

### Critical Services on Workers

Worker nodes host all application workloads and critical infrastructure services:

1. **Application Workloads**: User-facing applications, APIs, databases
2. **Infrastructure Services**: Cloudflared tunnels, monitoring, cert-manager
3. **Persistent Data**: Database volumes, application state, uploaded files

### Automated Backups

Velero schedules automatically back up worker services:

```bash
# View backup schedules
velero schedule get

# View recent backups
velero backup get

# Check backup status
velero backup describe <backup-name>
```

### Manual Backup Before Changes

Before any major changes to worker nodes:

```bash
BACKUP_NAME="pre-change-$(date +%Y%m%d-%H%M%S)"
velero backup create $BACKUP_NAME \
  --include-namespaces production,databases,monitoring,cloudflare \
  --snapshot-volumes \
  --wait

# Verify backup
velero backup describe $BACKUP_NAME
```

### Worker Node Recovery Scenarios

#### Scenario 1: Single Worker Node Failure

**RTO**: 5-10 minutes (automatic)

**Impact**: Pods reschedule to other workers automatically.

```bash
# Monitor pod rescheduling
kubectl get pods -A -o wide | grep <failed-node>

# Check pod status
kubectl get pods -A | grep -v Running

# If PVs stuck, manually detach and reattach
```

#### Scenario 2: All Worker Nodes Failure

**RTO**: 1-2 hours

**Procedure**: Provision new workers and restore from backup.

```bash
# 1. Provision new worker nodes
# 2. Deploy Tailscale and K3s agent
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --tags agents

# 3. Restore workloads from Velero
velero restore create full-restore-$(date +%Y%m%d) \
  --from-backup daily-full-20241206 \
  --wait

# 4. Verify services
kubectl get all -A
```

## Kubernetes Workload Examples

### Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      # Ensure pods run on worker nodes only (control plane is tainted)
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
        # Pod anti-affinity for high availability
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - my-app
              topologyKey: kubernetes.io/hostname
      containers:
      - name: app
        image: my-app:v1.0.0
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: database-credentials
              key: url
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
```

### Service Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: production
spec:
  type: ClusterIP
  selector:
    app: my-app
  ports:
  - port: 80
    targetPort: 8080
    name: http
---
# NodePort example for direct TCP access
apiVersion: v1
kind: Service
metadata:
  name: my-app-nodeport
  namespace: production
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30080  # Accessible via worker-public-ip:30080
    name: tcp
```

### StatefulSet Example

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: production
spec:
  serviceName: mysql
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        ports:
        - containerPort: 3306
          name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi
```

### ConfigMap and Secret Example

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  app.conf: |
    server {
      listen 8080;
      server_name _;
    }
  log_level: "info"
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secret
  namespace: production
type: Opaque
stringData:
  api-key: "your-api-key-here"
  database-password: "your-db-password"
```

**Note**: Encrypt secrets with SOPS before committing to Git:

```bash
sops -e secret.yaml > secret.enc.yaml
```

## Maintenance and Upgrades

### Kubernetes Version Upgrades

```bash
# Check current version
kubectl version

# Upgrade K3s via Ansible (updates playbook version first)
# Edit ansible/group_vars/all/main.yml
# Update k3s_version: "v1.29.0+k3s1"

# Run upgrade playbook
ansible-playbook -i inventory.ini playbooks/upgrade-k3s.yaml

# Verify upgrade
kubectl get nodes
```

### Helm Chart Upgrades

```bash
cd helmfile

# Check for chart updates
helmfile deps

# Preview upgrades
helmfile diff

# Apply upgrades
helmfile apply

# Rollback if needed
helmfile delete --purge <release-name>
helmfile apply
```

### Node Maintenance

```bash
# Cordon node (prevent new pods)
kubectl cordon <node-name>

# Drain node (evict existing pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Perform maintenance (OS updates, hardware changes, etc.)
ssh user@<node>
sudo apt update && sudo apt upgrade -y
sudo reboot

# Uncordon node (allow scheduling)
kubectl uncordon <node-name>
```

## Troubleshooting

### Debug Pod Not Starting

```bash
# Get pod status
kubectl get pod <pod-name> -o yaml

# Check events
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Check previous logs (if crashed)
kubectl logs <pod-name> --previous

# Run debug container in pod
kubectl debug <pod-name> -it --image=busybox
```

### Debug Network Issues

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Test service connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://<service-name>.<namespace>.svc.cluster.local

# Check network policies
kubectl get networkpolicies -A

# Describe network policy
kubectl describe networkpolicy <policy-name> -n <namespace>
```

### Debug Storage Issues

```bash
# Check PV and PVC status
kubectl get pv,pvc -A

# Describe PVC
kubectl describe pvc <pvc-name> -n <namespace>

# Check storage class
kubectl describe storageclass

# Check volume mounts in pod
kubectl describe pod <pod-name> | grep -A 10 Mounts
```

### Check Resource Usage

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -A

# Detailed node resources
kubectl describe node <node-name> | grep -A 5 "Allocated resources"
```

---

[⬅ Back to Setup Guide](setup.md) | [Next: Ansible Guide ➡](ansible.md)
