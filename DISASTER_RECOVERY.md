# Disaster Recovery Guide

This document outlines the disaster recovery strategy, procedures, and best practices for the infrastructure stack.

## Table of Contents

- [Overview](#overview)
- [Recovery Objectives](#recovery-objectives)
- [Backup Strategy](#backup-strategy)
- [Velero Backup Solution](#velero-backup-solution)
- [Disaster Recovery Scenarios](#disaster-recovery-scenarios)
- [Restore Procedures](#restore-procedures)
- [Testing and Validation](#testing-and-validation)
- [Runbooks](#runbooks)

## Overview

Disaster recovery (DR) ensures business continuity in the event of catastrophic failures. This guide covers:

- **Backup strategies** for all critical components
- **Recovery procedures** for various failure scenarios
- **RTO/RPO objectives** and expectations
- **Testing protocols** to validate DR readiness

### Key Principles

1. **Defense in Depth**: Multiple backup strategies (GitOps, snapshots, Velero)
2. **Regular Testing**: Quarterly DR drills to validate procedures
3. **Automation**: Automated backups to reduce human error
4. **Documentation**: Comprehensive runbooks for recovery operations
5. **Monitoring**: Alerts for backup failures

## Recovery Objectives

### Recovery Time Objective (RTO)

**RTO** is the maximum acceptable downtime for services.

| Component | RTO Target | Notes |
|-----------|------------|-------|
| k3s Control Plane | 30 minutes | Time to rebuild control plane from scratch |
| Stateless Workloads | 20 minutes | Time to redeploy via Helmfile |
| Stateful Workloads (with PV) | 1-2 hours | Includes volume restore from backup |
| MySQL Database | 1-2 hours | Includes restore and validation |
| Monitoring Stack | 30 minutes | Non-critical, acceptable longer downtime |
| cert-manager | 15 minutes | Fast recovery, certificates auto-renew |

### Recovery Point Objective (RPO)

**RPO** is the maximum acceptable data loss.

| Data Type | RPO Target | Backup Frequency | Notes |
|-----------|------------|------------------|-------|
| Infrastructure Config | 0 (zero) | Continuous (Git) | All configs in Git via GitOps |
| Application State (PVs) | 24 hours | Daily snapshots | Velero scheduled backups |
| MySQL Database | 4 hours | Every 4 hours | Automated backups to S3/Azure |
| Prometheus Metrics | 24 hours | Daily snapshots | Optional, can rebuild |
| Secrets | 0 (zero) | Version controlled | SOPS-encrypted in Git or external store |

### Service Priority Levels

**Priority 1 (Critical)**: Must be restored within 1 hour
- k3s control plane
- MySQL databases
- Cloudflared tunnels
- MySQL databases
- cert-manager (for TLS certificates)

**Priority 2 (Important)**: Restore within 2-4 hours
- Stateful applications with persistent volumes
- External Secrets Operator
- Tailscale Operator

**Priority 3 (Standard)**: Restore within 8-24 hours
- Monitoring stack (Prometheus, Grafana)
- Non-production environments
- Development tools

## Backup Strategy

### Multi-Layer Backup Approach

#### Layer 1: GitOps Configuration Backup

**What**: All infrastructure and application configurations
**How**: Version controlled in Git
**Frequency**: Continuous (every commit)
**Storage**: GitHub (with optional mirrors)
**RPO**: Zero data loss
**RTO**: Minutes (re-apply from Git)

**Backed up components**:
- Helmfile configurations
- Helm chart values
- Ansible playbooks and roles
- Kubernetes manifests
- CI/CD workflows

**Recovery**:
```bash
# Clone repository
git clone https://github.com/org/infrastructure.git
cd infrastructure

# Redeploy infrastructure
cd ansible
ansible-playbook playbooks/deploy-k3s.yaml

# Redeploy applications
cd ../helmfile
helmfile apply
```

#### Layer 2: Velero Cluster Backups

**What**: Kubernetes resources and persistent volumes
**How**: Velero with cloud storage backend
**Frequency**: Daily full backups, hourly incremental
**Storage**: S3, Azure Blob, GCS, or MinIO
**RPO**: 24 hours (adjustable)
**RTO**: 1-2 hours

**Backed up components**:
- All Kubernetes resources (pods, services, deployments, etc.)
- Persistent Volume Claims and data
- Namespace configurations
- RBAC policies
- ConfigMaps and Secrets (encrypted)

#### Layer 3: Database Backups

**What**: MySQL and other database data
**How**: Native database dumps + Velero PV snapshots
**Frequency**: Every 4 hours
**Storage**: S3/Azure with encryption
**RPO**: 4 hours
**RTO**: 1-2 hours

**Backup methods**:
- Automated mysqldump to cloud storage
- Velero PV snapshots
- Database replication (for critical DBs)

#### Layer 4: Application-Specific Backups

**What**: Application data and state
**How**: Application-native backup mechanisms
**Frequency**: Varies by application
**Storage**: Application-specific

#### Layer 5: Worker Node Critical Services

**What**: Critical services and data on worker nodes
**How**: Combination of PVC snapshots, application backups, and configuration in Git
**Frequency**: Daily for PVCs, continuous for configs
**Storage**: Velero backend (S3/Azure/GCS)
**RPO**: 24 hours for data, zero for configs
**RTO**: 1-2 hours

**Critical Worker Services to Backup**:
1. **Persistent Volume Claims (PVCs)**:
   - All stateful workloads use PVCs
   - Velero automatically backs up PVCs with snapshots
   - Ensure PVC storage class supports snapshots

2. **Application Databases**:
   - MySQL/PostgreSQL running on workers
   - Use native database backup tools (mysqldump, pg_dump)
   - Automated CronJobs for regular dumps to S3/Azure

3. **Service Configurations**:
   - All Kubernetes manifests in Git (zero RPO)
   - Cloudflared tunnel credentials in Kubernetes secrets
   - Back up secrets with Velero (encrypted)

4. **P2P/Direct TCP Services**:
   - Document NodePort configurations
   - Back up service data via PVCs
   - Configuration stored in Git/Helmfile

**Worker Node Backup Verification**:
```bash
# Verify PVC backups exist
velero backup get | grep -E "daily|worker"

# List all PVCs on worker nodes
kubectl get pvc -A -o wide

# Check backup schedules for critical namespaces
kubectl get schedule -n velero -o yaml
```

## Velero Backup Solution

Velero is the primary tool for backing up Kubernetes resources and persistent volumes.

### Installation

Velero is included in the Helmfile configuration:

```bash
cd helmfile
# Enable Velero in config/enabled.yaml
# Set: velero: true

# Configure Velero values (see helmfile/values/velero-values.yaml)
helmfile -l name=velero apply
```

### Configuration

#### AWS S3 Backend

Create an S3 bucket and IAM user:

```bash
# Create S3 bucket
aws s3 mb s3://my-velero-backups --region us-west-2

# Create IAM policy
cat > velero-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::my-velero-backups/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::my-velero-backups"
            ]
        }
    ]
}
EOF

aws iam create-policy \
  --policy-name VeleroBackupPolicy \
  --policy-document file://velero-policy.json

# Create IAM user
aws iam create-user --user-name velero

# Attach policy
aws iam attach-user-policy \
  --user-name velero \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/VeleroBackupPolicy

# Create access key
aws iam create-access-key --user-name velero
```

Create credentials secret:

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=YOUR_ACCESS_KEY_ID
aws_secret_access_key=YOUR_SECRET_ACCESS_KEY
EOF

kubectl create secret generic cloud-credentials \
  --from-file=cloud=credentials-velero \
  -n velero

rm credentials-velero
```

#### Azure Blob Backend

```bash
# Create storage account
az storage account create \
  --name velerobackups \
  --resource-group my-rg \
  --location eastus \
  --sku Standard_GRS

# Create blob container
az storage container create \
  --name velero \
  --account-name velerobackups

# Create service principal
az ad sp create-for-rbac \
  --name velero \
  --role Contributor \
  --scopes /subscriptions/{subscription-id}

# Create credentials
cat > credentials-velero <<EOF
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
EOF

kubectl create secret generic cloud-credentials \
  --from-file=cloud=credentials-velero \
  -n velero
```

### Backup Schedules

Configure automated backup schedules:

```yaml
# Daily full backup
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  template:
    includedNamespaces:
      - '*'
    excludedNamespaces:
      - kube-system
      - kube-public
    storageLocation: default
    volumeSnapshotLocations:
      - default
    ttl: 720h  # 30 days retention

---
# Hourly backup for critical namespaces
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: hourly-critical
  namespace: velero
spec:
  schedule: "0 * * * *"  # Every hour
  template:
    includedNamespaces:
      - production
      - databases
    storageLocation: default
    volumeSnapshotLocations:
      - default
    ttl: 168h  # 7 days retention
```

Apply schedules:

```bash
kubectl apply -f backup-schedules.yaml
```

### Manual Backups

Create on-demand backups:

```bash
# Backup entire cluster
velero backup create full-backup-$(date +%Y%m%d-%H%M%S)

# Backup specific namespace
velero backup create mysql-backup \
  --include-namespaces databases

# Backup with PV snapshots
velero backup create app-backup \
  --include-namespaces production \
  --snapshot-volumes

# Backup excluding certain resources
velero backup create selective-backup \
  --include-namespaces default \
  --exclude-resources pods,replicasets
```

### Verify Backups

```bash
# List all backups
velero backup get

# Describe a backup
velero backup describe backup-name

# Check backup logs
velero backup logs backup-name

# Download backup for offline storage
velero backup download backup-name
```

### MySQL Backup Strategy

#### Using mysqldump with CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mysql-backup
  namespace: databases
spec:
  schedule: "0 */4 * * *"  # Every 4 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: mysql:8.0
              env:
                - name: MYSQL_HOST
                  value: mysql.databases.svc.cluster.local
                - name: MYSQL_USER
                  valueFrom:
                    secretKeyRef:
                      name: mysql-credentials
                      key: username
                - name: MYSQL_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: mysql-credentials
                      key: password
                - name: AWS_ACCESS_KEY_ID
                  valueFrom:
                    secretKeyRef:
                      name: s3-credentials
                      key: access-key-id
                - name: AWS_SECRET_ACCESS_KEY
                  valueFrom:
                    secretKeyRef:
                      name: s3-credentials
                      key: secret-access-key
              command:
                - /bin/sh
                - -c
                - |
                  BACKUP_NAME="mysql-backup-$(date +%Y%m%d-%H%M%S).sql.gz"
                  mysqldump -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD \
                    --all-databases --single-transaction --quick | \
                    gzip > /tmp/$BACKUP_NAME
                  
                  # Upload to S3
                  apt-get update && apt-get install -y awscli
                  aws s3 cp /tmp/$BACKUP_NAME s3://my-backups/mysql/$BACKUP_NAME
                  
                  # Cleanup old backups (keep last 30 days)
                  aws s3 ls s3://my-backups/mysql/ | \
                    awk '{print $4}' | \
                    sort -r | \
                    tail -n +31 | \
                    xargs -I {} aws s3 rm s3://my-backups/mysql/{}
          restartPolicy: OnFailure
```

## Disaster Recovery Scenarios

### Scenario 1: Single Node Failure

**Impact**: One k3s worker node is down
**RTO**: 5-10 minutes (automatic)
**RPO**: Zero data loss

**Recovery**:
1. k3s automatically reschedules pods to healthy nodes
2. Traffic automatically routes to healthy nodes via Cloudflared or direct service access
3. Replace failed node when convenient

**Prevention**:
- Multiple worker nodes for redundancy
- Pod anti-affinity rules
- Health checks and readiness probes

### Scenario 2: Control Plane Failure

**Impact**: k3s server node is down
**RTO**: 30 minutes
**RPO**: Zero (configuration in Git)

**Recovery**:
1. Restore from etcd backup or rebuild
2. Redeploy k3s server via Ansible
3. Verify cluster connectivity
4. Rejoin worker nodes if needed

**Detailed steps**:
```bash
# Option 1: Restore from etcd backup (if available)
sudo k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/etcd-snapshot.db

# Option 2: Rebuild from scratch
cd ansible
ansible-playbook playbooks/deploy-k3s.yaml

# Verify
kubectl get nodes
```

### Scenario 3: Complete Cluster Loss

**Impact**: Entire cluster is destroyed
**RTO**: 2-4 hours
**RPO**: Up to 24 hours for PV data

**Recovery**:
1. Rebuild infrastructure servers
2. Deploy k3s via Ansible
3. Restore from Velero backup
4. Restore databases from backups
5. Redeploy applications via Helmfile
6. Validate all services

**Detailed steps**: See [Complete Cluster Restore](#complete-cluster-restore) runbook

### Scenario 4: Database Corruption

**Impact**: MySQL database corrupted or data loss
**RTO**: 1-2 hours
**RPO**: Up to 4 hours

**Recovery**:
1. Stop application pods
2. Restore MySQL from latest backup
3. Validate data integrity
4. Restart application pods
5. Verify functionality

**Detailed steps**: See [MySQL Restore](#mysql-restore) runbook

### Scenario 5: Accidental Deletion

**Impact**: Namespace or resources accidentally deleted
**RTO**: 30 minutes
**RPO**: Up to 24 hours

**Recovery**:
```bash
# Restore from Velero
velero restore create --from-backup backup-name

# Or redeploy from Git
cd helmfile
helmfile apply
```

### Scenario 6: Ransomware/Security Breach

**Impact**: Systems compromised, data encrypted
**RTO**: 4-8 hours (full rebuild)
**RPO**: Up to 24 hours

**Recovery**:
1. **Isolate**: Disconnect affected systems
2. **Assess**: Determine scope of compromise
3. **Rebuild**: Fresh infrastructure deployment
4. **Restore**: From verified clean backups
5. **Harden**: Apply security patches and updates
6. **Audit**: Review logs and implement additional controls

## Restore Procedures

### Complete Cluster Restore

Full cluster restoration from catastrophic failure:

#### Step 1: Prepare Infrastructure

```bash
# Ensure servers are available and accessible
# Update inventory files if IP addresses changed
cd ansible
vi inventory.ini
```

#### Step 2: Deploy k3s Cluster

```bash
cd ansible
ansible-playbook playbooks/deploy-k3s.yaml

# Verify cluster is running
kubectl get nodes
```

#### Step 3: Deploy Core Services

```bash
# Verify kubeconfig
export KUBECONFIG=/path/to/kubeconfig
kubectl cluster-info

# Deploy Cloudflared and other services via Helmfile
cd helmfile
helmfile apply
```

#### Step 4: Install Velero

```bash
cd helmfile
# Ensure velero is enabled
helmfile -l name=velero apply

# Verify Velero is running
kubectl get pods -n velero
```

#### Step 5: Restore from Velero Backup

```bash
# List available backups
velero backup get

# Restore from most recent backup
velero restore create cluster-restore \
  --from-backup daily-backup-20231215

# Monitor restore progress
velero restore describe cluster-restore

# Check logs
velero restore logs cluster-restore
```

#### Step 6: Verify Critical Services

```bash
# Check all namespaces
kubectl get ns

# Check pods in all namespaces
kubectl get pods -A

# Verify persistent volumes
kubectl get pv
kubectl get pvc -A

# Check services
kubectl get svc -A
```

#### Step 7: Restore Secrets (if not in Velero backup)

```bash
# Restore from SOPS-encrypted files
cd infrastructure
sops -d secrets/db-credentials.yaml | kubectl apply -f -
sops -d secrets/cloudflared-credentials.yaml | kubectl apply -f -

# Or recreate manually
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=/path/to/credentials.json \
  -n cloudflare
```

#### Step 8: Redeploy Missing Applications

```bash
cd helmfile
helmfile diff
helmfile apply
```

#### Step 9: Validate Functionality

```bash
# Test Cloudflared tunnels
curl https://app.example.com

# Check monitoring
kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# Test database connectivity
kubectl run mysql-client --rm -it --image=mysql:8.0 -- \
  mysql -h mysql.databases.svc.cluster.local -u root -p
```

### MySQL Restore

Restore MySQL database from backup:

#### From mysqldump Backup

```bash
# Download backup from S3
aws s3 cp s3://my-backups/mysql/mysql-backup-20231215.sql.gz /tmp/

# Extract
gunzip /tmp/mysql-backup-20231215.sql.gz

# Restore to MySQL
kubectl exec -it mysql-0 -n databases -- \
  mysql -u root -p < /tmp/mysql-backup-20231215.sql

# Or using port-forward
kubectl port-forward -n databases svc/mysql 3306:3306
mysql -h 127.0.0.1 -u root -p < /tmp/mysql-backup-20231215.sql
```

#### From Velero Backup

```bash
# Restore just the database namespace
velero restore create mysql-restore \
  --from-backup daily-backup-20231215 \
  --include-namespaces databases

# Wait for completion
velero restore describe mysql-restore

# Verify
kubectl get pods -n databases
kubectl get pvc -n databases
```

### Partial Namespace Restore

Restore specific namespace without affecting others:

```bash
# Restore single namespace
velero restore create app-restore \
  --from-backup daily-backup-20231215 \
  --include-namespaces production

# Restore with resource filtering
velero restore create config-restore \
  --from-backup daily-backup-20231215 \
  --include-namespaces default \
  --include-resources configmaps,secrets
```

## Testing and Validation

### Regular DR Drills

Conduct quarterly disaster recovery drills:

#### Q1: Single Service Restore
- Delete a non-critical application
- Restore from Velero backup
- Validate functionality
- Document time and issues

#### Q2: Database Restore
- Restore MySQL to test environment
- Validate data integrity
- Test application connectivity
- Measure RTO/RPO

#### Q3: Namespace Restore
- Restore entire namespace
- Verify all resources
- Test inter-service communication
- Document lessons learned

#### Q4: Full Cluster Restore
- Complete cluster rebuild simulation
- Restore from backups
- Validate all services
- Update runbooks based on findings

### Test Checklist

Before each test:
- [ ] Schedule during maintenance window
- [ ] Notify stakeholders
- [ ] Backup current state
- [ ] Document start time
- [ ] Prepare rollback plan

During test:
- [ ] Follow runbook procedures
- [ ] Document each step
- [ ] Note any issues or delays
- [ ] Time each phase

After test:
- [ ] Validate all services
- [ ] Calculate actual RTO/RPO
- [ ] Document findings
- [ ] Update procedures
- [ ] Schedule follow-up actions

### Validation Procedures

#### Infrastructure Validation

```bash
# Check all nodes
kubectl get nodes -o wide

# Verify system pods
kubectl get pods -n kube-system

# Check cluster health
kubectl get componentstatuses
```

#### Application Validation

```bash
# Check all pods
kubectl get pods -A | grep -v Running

# Verify services
kubectl get svc -A

# Test ingress
curl -v https://app.example.com

# Check logs for errors
kubectl logs -n namespace deployment/app --tail=100
```

#### Data Validation

```bash
# Verify PVs
kubectl get pv

# Check PVC bindings
kubectl get pvc -A

# Test database access
kubectl exec -it mysql-0 -n databases -- mysql -u root -p -e "SHOW DATABASES;"

# Validate data integrity
kubectl exec -it mysql-0 -n databases -- \
  mysqlcheck -u root -p --all-databases
```

## Runbooks

### Emergency Contact List

| Role | Primary | Secondary | Contact |
|------|---------|-----------|---------|
| Infrastructure Lead | Name 1 | Name 2 | phone/email |
| Database Admin | Name 3 | Name 4 | phone/email |
| Security Lead | Name 5 | Name 6 | phone/email |
| On-Call Engineer | Rotation | Backup | pagerduty |

### Escalation Procedures

**Level 1** (0-30 min): On-call engineer
- Assess situation
- Begin initial recovery
- Update status page

**Level 2** (30-60 min): Infrastructure lead
- Escalate if not resolved
- Coordinate team response
- Make architectural decisions

**Level 3** (60+ min): Full team activation
- All hands on deck
- External vendor engagement
- Executive notification

### Communication Templates

#### Incident Notification

```
SUBJECT: [INCIDENT] Service Outage - [Service Name]

SEVERITY: [Critical/High/Medium]
IMPACT: [Description of user impact]
START TIME: [Timestamp]
ESTIMATED RESOLUTION: [Timestamp or TBD]

DETAILS:
[Brief description of the issue]

CURRENT STATUS:
[What is being done to resolve]

NEXT UPDATE: [When next update will be provided]
```

#### Recovery Completion

```
SUBJECT: [RESOLVED] Service Restored - [Service Name]

The incident affecting [service] has been resolved.

START TIME: [Timestamp]
END TIME: [Timestamp]
DURATION: [Duration]

ROOT CAUSE:
[Brief explanation]

RESOLUTION:
[What was done to fix]

NEXT STEPS:
[Any follow-up actions]

POST-MORTEM:
[Link to detailed post-mortem document]
```

## Continuous Improvement

### Post-Incident Review

After each incident or DR drill:

1. **Document Timeline**
   - What happened when
   - Who did what
   - How long each step took

2. **Identify Issues**
   - What went wrong
   - What went right
   - What was unexpected

3. **Action Items**
   - Update runbooks
   - Fix automation
   - Improve monitoring
   - Adjust RTO/RPO targets

4. **Share Learnings**
   - Team review meeting
   - Update documentation
   - Training sessions

### Metrics to Track

- **Mean Time to Detect (MTTD)**: How quickly issues are identified
- **Mean Time to Resolve (MTTR)**: How quickly issues are fixed
- **Backup Success Rate**: Percentage of successful backups
- **Restore Success Rate**: Percentage of successful restores
- **RTO Achievement**: Actual vs target RTO
- **RPO Achievement**: Actual vs target RPO

### Backup Monitoring

Configure alerts for backup failures:

```yaml
# Prometheus alert for failed backups
groups:
  - name: velero
    rules:
      - alert: VeleroBackupFailed
        expr: velero_backup_failure_total > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Velero backup failed"
          description: "Backup {{ $labels.schedule }} failed"
      
      - alert: VeleroBackupTooOld
        expr: time() - velero_backup_last_successful_timestamp > 86400
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Velero backup is too old"
          description: "Last successful backup was over 24 hours ago"
```

## Additional Resources

- [Velero Documentation](https://velero.io/docs/)
- [Kubernetes Backup Best Practices](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)
- [MySQL Backup and Recovery](https://dev.mysql.com/doc/refman/8.0/en/backup-and-recovery.html)
- [GitOps Best Practices](https://www.weave.works/technologies/gitops/)
