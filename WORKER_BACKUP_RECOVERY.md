# Worker Node Backup and Recovery

This document provides specific backup and recovery procedures for services and data hosted on worker nodes in the hybrid cluster architecture.

## Overview

In the hybrid cluster architecture:
- **Control Plane**: Home/CGNAT environment (tainted, no workloads)
- **Worker Nodes**: Public IP (VPS) - hosts all application workloads
- **Critical Data**: Resides on worker node persistent volumes

## Critical Services on Workers

### 1. Application Workloads
- User-facing applications
- API services
- Databases (MySQL, PostgreSQL, etc.)
- Message queues
- Caching layers

### 2. Infrastructure Services
- Cloudflared tunnels (ingress)
- Monitoring stack (Prometheus, Grafana)
- cert-manager certificates
- External Secrets Operator

### 3. Persistent Data
- Database volumes
- Application state
- Uploaded files/media
- Configuration data

## Backup Strategy for Worker Services

### Automated Backups (Velero)

All worker services are backed up automatically via Velero schedules:

#### Daily Full Backup
```bash
# Runs at 2 AM UTC daily
# Includes: all namespaces except system namespaces
# Retention: 30 days
# See: helmfile/manifests/velero-schedules.yaml
```

#### Hourly Production Backup
```bash
# Runs every hour for production namespace
# Retention: 7 days
```

#### Database Backup (Every 4 hours)
```bash
# Runs every 4 hours for database namespace
# Retention: 14 days
# Includes pre/post hooks for consistency
```

### Manual Backup Before Changes

Before any major changes to worker nodes:

```bash
# 1. Create immediate backup
BACKUP_NAME="pre-change-$(date +%Y%m%d-%H%M%S)"
velero backup create $BACKUP_NAME \
  --include-namespaces production,databases,monitoring,cloudflare \
  --snapshot-volumes \
  --wait

# 2. Verify backup completion
velero backup describe $BACKUP_NAME

# 3. Download backup manifest for offline storage (optional)
velero backup download $BACKUP_NAME
```

## Recovery Procedures

### Scenario 1: Single Worker Node Failure

**Impact**: One worker node is down, pods rescheduling to other workers

**RTO**: 5-10 minutes (automatic)

**Procedure**:
1. Kubernetes automatically reschedules pods to healthy workers
2. Persistent volumes may need to be manually detached/reattached
3. Monitor pod status:
   ```bash
   kubectl get pods -A | grep -v Running
   ```

**Prevention**:
- Run multiple worker nodes
- Use pod anti-affinity rules
- Test node failure scenarios

### Scenario 2: All Worker Nodes Failure

**Impact**: Complete service outage, no workloads running

**RTO**: 2-4 hours

**RPO**: Up to 24 hours (daily backups)

**Procedure**:

#### Step 1: Provision New Worker Nodes
```bash
# Using your VPS provider (Netcup, DigitalOcean, etc.)
# Ensure nodes have:
# - Public IP addresses
# - Minimum specs (2 CPU, 4GB RAM)
# - Tailscale installed
```

#### Step 2: Join Workers to Cluster
```bash
cd ansible

# Update inventory with new worker IPs
vim inventory.ini

# Deploy k3s agent on workers
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --tags workers

# Verify nodes joined
kubectl get nodes
```

#### Step 3: Restore from Velero Backup
```bash
# 1. Ensure Velero is running
kubectl get pods -n velero

# 2. List available backups
velero backup get

# 3. Restore from latest backup
LATEST_BACKUP=$(velero backup get --output json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
velero restore create worker-restore-$(date +%Y%m%d-%H%M%S) \
  --from-backup $LATEST_BACKUP \
  --include-namespaces production,databases,monitoring,cloudflare

# 4. Monitor restore progress
velero restore describe worker-restore-*
velero restore logs worker-restore-*
```

#### Step 4: Verify Service Recovery
```bash
# Check pods
kubectl get pods -A

# Check persistent volumes
kubectl get pv
kubectl get pvc -A

# Check services
kubectl get svc -A

# Test critical endpoints
curl -I https://app.example.com
```

### Scenario 3: Database Corruption on Worker

**Impact**: Database data corrupted or lost

**RTO**: 1-2 hours

**RPO**: Up to 4 hours (database backup frequency)

**Procedure**:

#### Option A: Restore from Velero
```bash
# 1. Scale down database to prevent writes
kubectl scale statefulset mysql -n databases --replicas=0

# 2. Delete corrupted PVC
kubectl delete pvc mysql-data-mysql-0 -n databases

# 3. Restore from Velero
velero restore create mysql-restore \
  --from-backup database-backup-TIMESTAMP \
  --include-namespaces databases \
  --include-resources persistentvolumeclaims,persistentvolumes

# 4. Scale database back up
kubectl scale statefulset mysql -n databases --replicas=1

# 5. Verify data
kubectl exec -it mysql-0 -n databases -- mysql -u root -p -e "SHOW DATABASES;"
```

#### Option B: Restore from Database-specific Backup
```bash
# 1. Download backup from S3/storage
aws s3 cp s3://backups/mysql/mysql-backup-TIMESTAMP.sql.gz /tmp/

# 2. Extract backup
gunzip /tmp/mysql-backup-TIMESTAMP.sql.gz

# 3. Restore to database
kubectl exec -it mysql-0 -n databases -- bash
mysql -u root -p < /tmp/mysql-backup-TIMESTAMP.sql
```

### Scenario 4: Cloudflared Tunnel Failure

**Impact**: HTTP/HTTPS traffic cannot reach cluster

**RTO**: 10 minutes

**Procedure**:

```bash
# 1. Check Cloudflared status
kubectl get pods -n cloudflare

# 2. Check tunnel credentials
kubectl get secret cloudflared-credentials -n cloudflare

# 3. Restart Cloudflared
kubectl rollout restart deployment cloudflared -n cloudflare

# 4. If credentials lost, restore from SOPS
sops -d secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -

# 5. Verify tunnel
cloudflared tunnel info <tunnel-id>
```

### Scenario 5: Certificate Loss

**Impact**: TLS certificates missing or expired

**RTO**: 15 minutes

**Procedure**:

```bash
# 1. Check certificate status
kubectl get certificates -A

# 2. Force renewal
kubectl annotate certificate <cert-name> -n <namespace> \
  cert-manager.io/issue-temporary-certificate="true" --overwrite

# 3. If cert-manager lost configuration, restore issuers
kubectl apply -f helmfile/manifests/cert-manager-resources.yaml

# 4. Verify certificate issuance
kubectl describe certificate <cert-name> -n <namespace>
```

## Worker Node Replacement Procedure

When replacing a worker node (upgrade, migration, etc.):

### Step 1: Drain Node
```bash
# Mark node as unschedulable and evict pods
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=300

# Verify pods rescheduled
kubectl get pods -A -o wide | grep <node-name>
```

### Step 2: Create Backup
```bash
# Backup before node removal
velero backup create pre-replacement-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces '*' \
  --snapshot-volumes
```

### Step 3: Remove Old Node
```bash
# Delete from cluster
kubectl delete node <node-name>

# Decommission VPS (via provider)
```

### Step 4: Add New Node
```bash
# Provision new VPS with public IP

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey <auth-key>

# Add to inventory
vim ansible/inventory.ini

# Deploy k3s agent
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --limit <new-node>

# Verify node joined
kubectl get nodes
```

### Step 5: Verify Workload Distribution
```bash
# Check pod distribution across nodes
kubectl get pods -A -o wide

# Check PV binding
kubectl get pv -o wide
```

## Persistent Volume Migration

When moving persistent data between worker nodes:

```bash
# 1. Create backup
velero backup create pv-migration-backup \
  --include-namespaces <namespace> \
  --snapshot-volumes

# 2. Scale down workload
kubectl scale deployment <app> -n <namespace> --replicas=0

# 3. Delete PVC (keeps PV with Retain policy)
kubectl delete pvc <pvc-name> -n <namespace>

# 4. Recreate PVC on new node (if using local volumes)
# Or restore from Velero backup

# 5. Scale up workload
kubectl scale deployment <app> -n <namespace> --replicas=1
```

## Monitoring Worker Health

### Key Metrics to Monitor

```bash
# Node resource usage
kubectl top nodes

# Pod status on workers
kubectl get pods -A -o wide

# PV capacity
kubectl get pv -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,USED:.status.used

# Worker node conditions
kubectl describe nodes | grep -A 5 "Conditions:"
```

### Alerts to Configure

See `helmfile/values/prometheus-values.yaml` for worker-specific alerts:
- High CPU/Memory on workers
- Disk space low
- Pod crash looping
- PV nearing capacity

## Best Practices

### 1. Regular Backup Verification
```bash
# Monthly: Test restore from backup
velero restore create test-restore-$(date +%Y%m) \
  --from-backup <recent-backup> \
  --namespace-mappings production:production-test
```

### 2. Multiple Workers
- Run at least 2 worker nodes for redundancy
- Distribute workloads with pod anti-affinity
- Use topology spread constraints

### 3. Backup Storage
- Store Velero backups in different region/provider
- Maintain offline backup copies for critical data
- Encrypt backup storage

### 4. Documentation
- Keep inventory.ini updated
- Document custom configurations
- Maintain runbook for specific applications

### 5. Testing
- Quarterly DR drills
- Test worker node failure scenarios
- Verify backup/restore procedures

## Emergency Contacts

For worker node issues:
- VPS Provider Support: [Contact Info]
- On-call Engineer: [PagerDuty/Phone]
- Backup Access: [Who has access to backups]

## See Also

- [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) - Complete DR guide
- [SECRETS.md](SECRETS.md) - Secret management and rotation
- [helmfile/manifests/velero-schedules.yaml](helmfile/manifests/velero-schedules.yaml) - Backup schedules
- [HYBRID_CLUSTER_SETUP.md](HYBRID_CLUSTER_SETUP.md) - Cluster architecture

## Revision History

- 2024-12-05: Initial documentation
- Update this file when procedures change
