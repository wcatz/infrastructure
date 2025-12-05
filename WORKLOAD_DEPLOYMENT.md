# Workload Deployment Guide

This guide explains how to deploy and manage stateful workloads in the hybrid Kubernetes cluster.

## Overview

The hybrid cluster architecture supports:
- **Control Node (Home)**: Behind CGNAT, runs control plane and lightweight workloads
- **Worker Node (Netcup)**: Public IP, runs stateful workloads requiring direct TCP access
- **Workload Failover**: PVC-based storage with automatic pod rescheduling
- **Direct TCP Exposure**: NodePort and hostNetwork for external connectivity

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Hybrid K3s Cluster                      │
│                                                           │
│  Control Node (CGNAT)          Worker Node (Public IP)   │
│  ┌────────────────┐            ┌──────────────────┐     │
│  │ K3s Server     │            │ K3s Agent        │     │
│  │ Cloudflared    │            │ Cardano Node     │     │
│  │ Monitoring     │            │ (PVC + NodePort) │     │
│  └────────────────┘            └──────────────────┘     │
│         ▲                              ▲                 │
│         │                              │                 │
│         └──────── Tailscale Mesh ──────┘                 │
│                                                           │
└──────────────────────────────────────────────────────────┘
         │                               │
         │                               │
    Cloudflared                     NodePort 30001
     (HTTP/S)                        (TCP Direct)
```

## Workload Types

### 1. HTTP/S Workloads
- Exposed via Cloudflared tunnel
- Can run on any node (control or worker)
- Examples: Web apps, APIs, dashboards

### 2. TCP Workloads
- Require public IP for direct access
- Must run on worker nodes
- Use NodePort or hostNetwork
- Examples: Cardano node, database servers, game servers

### 3. Internal Workloads
- Only accessible within cluster
- Can run on any node
- Use ClusterIP services
- Examples: Background workers, cache servers

## Cardano Node Deployment

The Cardano node is a stateful workload requiring persistent storage and direct TCP access.

### Prerequisites

1. **Worker node labeled correctly**:
```bash
kubectl label node <netcup-worker-name> workload.kubernetes.io/cardano=true
kubectl label node <netcup-worker-name> topology.kubernetes.io/zone=netcup
```

2. **Storage class available**:
```bash
kubectl get storageclass

# K3s default is 'local-path'
# For production, consider using a networked storage solution
```

3. **Public IP configured**:
- Ensure worker node has public IP
- Firewall allows port 30001 (or configured NodePort)

### Deployment Options

#### Option 1: Via kubectl

```bash
# Deploy Cardano node
kubectl apply -f helmfile/manifests/workloads/cardano-node.yaml

# Verify deployment
kubectl get all -n cardano
kubectl describe deployment cardano-node -n cardano

# Check logs
kubectl logs -n cardano -l app=cardano-node -f
```

#### Option 2: Via GitHub Workflow

1. Go to Actions → Deploy Workloads
2. Select environment (dev/staging/production)
3. Select workload (cardano-node)
4. Run workflow

#### Option 3: Via Helmfile (if integrated)

```bash
cd helmfile

# Add to helmfile.yaml or create separate helmfile for workloads
helmfile apply
```

### Configuration

Edit `helmfile/manifests/workloads/cardano-node.yaml` to customize:

**Network Selection:**
```yaml
data:
  network: "mainnet"  # or "preprod", "preview"
```

**Resource Limits:**
```yaml
resources:
  requests:
    cpu: 2000m      # 2 CPU cores
    memory: 8Gi     # 8 GB RAM
  limits:
    cpu: 4000m      # 4 CPU cores max
    memory: 16Gi    # 16 GB RAM max
```

**Storage Size:**
```yaml
spec:
  resources:
    requests:
      storage: 100Gi  # Adjust based on network (mainnet needs more)
```

**NodePort:**
```yaml
nodePort: 30001  # External port for P2P connections
```

### Verifying Deployment

```bash
# Check pod status
kubectl get pods -n cardano
kubectl describe pod -n cardano <pod-name>

# Check service
kubectl get svc -n cardano

# Check PVC
kubectl get pvc -n cardano

# Check logs
kubectl logs -n cardano -l app=cardano-node -f

# Exec into pod
kubectl exec -it -n cardano <pod-name> -- /bin/bash

# Inside pod, check Cardano node status
cardano-cli query tip --mainnet
```

### External Access

The Cardano node is accessible on the worker node's public IP:

```bash
# From external machine
telnet <NETCUP_PUBLIC_IP> 30001

# Should connect to Cardano P2P port
```

## Workload Failover

### Automatic Failover

When a node fails, Kubernetes automatically reschedules pods:

1. **Node goes down**: Kubernetes detects node failure
2. **Pod marked Terminating**: After grace period (default 5 minutes)
3. **New pod scheduled**: On available worker node with matching labels
4. **PVC reattached**: Persistent data preserved

### Testing Failover

```bash
# Simulate node failure by draining
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Watch pod reschedule
kubectl get pods -n cardano -w

# Verify pod on new node
kubectl get pods -n cardano -o wide

# Uncordon node when ready
kubectl uncordon <node-name>
```

### Failover Considerations

**For Single-Node Workloads:**
- Cannot failover if only one worker node
- Consider adding additional worker nodes for HA
- PVC must be accessible from multiple nodes (use networked storage)

**For Multi-Node Workloads:**
- Use `ReadWriteMany` (RWX) PVCs if supported
- Configure pod anti-affinity to spread across nodes
- Use StatefulSets for ordered deployment

## Adding Additional Worker Nodes

To support failover and horizontal scaling:

### 1. Prepare New Node

```bash
# Add to Ansible inventory
[k3s_agents]
netcup-worker-1 ansible_host=WORKER1_PUBLIC_IP
netcup-worker-2 ansible_host=WORKER2_PUBLIC_IP
```

### 2. Deploy K3s Agent

```bash
cd ansible

# Deploy to new workers
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --limit k3s_agents

# Setup Tailscale on new workers
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml --limit k3s_agents
```

### 3. Label New Nodes

```bash
# Label for workload placement
kubectl label node netcup-worker-2 workload.kubernetes.io/cardano=true
kubectl label node netcup-worker-2 topology.kubernetes.io/zone=netcup
kubectl label node netcup-worker-2 node-role.kubernetes.io/worker=true

# Verify labels
kubectl get nodes --show-labels
```

### 4. Test Workload Scheduling

```bash
# Scale deployment to test multi-node
kubectl scale deployment cardano-node -n cardano --replicas=2

# Check pod distribution
kubectl get pods -n cardano -o wide

# Scale back if needed
kubectl scale deployment cardano-node -n cardano --replicas=1
```

## Persistent Volume Management

### PVC Best Practices

1. **Use appropriate storage class**:
```yaml
storageClassName: local-path  # For local storage
# or
storageClassName: longhorn    # For distributed storage
```

2. **Set appropriate size**:
- Cardano mainnet: 100+ GB
- Other workloads: Size based on data requirements

3. **Backup PVC data**:
```bash
# Create snapshot or backup
kubectl exec -n cardano <pod-name> -- tar czf /tmp/backup.tar.gz /data

# Copy from pod
kubectl cp cardano/<pod-name>:/tmp/backup.tar.gz ./backup.tar.gz
```

### PVC Expansion

If storage fills up:

```bash
# Edit PVC to increase size
kubectl edit pvc cardano-data -n cardano

# Update storage request
spec:
  resources:
    requests:
      storage: 200Gi  # Increase as needed

# Verify expansion
kubectl get pvc -n cardano
```

## Monitoring Workloads

### Prometheus Metrics

Expose metrics from workloads:

```yaml
# Add to pod annotations
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "12798"  # Cardano metrics port
  prometheus.io/path: "/metrics"
```

### Grafana Dashboards

Import dashboards for monitoring:

```bash
# Access Grafana (if deployed)
kubectl port-forward -n monitoring svc/grafana 3000:80

# Open http://localhost:3000
# Import Cardano node dashboard
```

### Logs

Centralized logging:

```bash
# View logs
kubectl logs -n cardano -l app=cardano-node -f

# Export logs
kubectl logs -n cardano -l app=cardano-node --since=1h > cardano-logs.txt
```

### Alerts

Set up alerts for critical events:

```yaml
# Example: Alert on pod restart
- alert: CardanoNodeRestarting
  expr: rate(kube_pod_container_status_restarts_total{namespace="cardano"}[5m]) > 0
  annotations:
    summary: "Cardano node restarting frequently"
```

## Updating Workloads

### Rolling Updates

```bash
# Update image version
kubectl set image deployment/cardano-node cardano-node=inputoutput/cardano-node:8.7.4 -n cardano

# Watch rollout
kubectl rollout status deployment/cardano-node -n cardano

# Rollback if needed
kubectl rollout undo deployment/cardano-node -n cardano
```

### ConfigMap Updates

```bash
# Edit configuration
kubectl edit configmap cardano-node-config -n cardano

# Restart pods to pick up changes
kubectl rollout restart deployment/cardano-node -n cardano
```

## Security Considerations

### Network Policies

Restrict pod communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cardano-network-policy
  namespace: cardano
spec:
  podSelector:
    matchLabels:
      app: cardano-node
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}  # Allow from same namespace
      ports:
        - protocol: TCP
          port: 3001
  egress:
    - to:
        - namespaceSelector: {}  # Allow to all namespaces
```

### Pod Security

Use security contexts:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
      - ALL
```

### Secrets Management

Use SOPS for sensitive data:

```bash
# Create secret manifest
cat > /tmp/cardano-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cardano-secrets
  namespace: cardano
stringData:
  api-key: "your-secret-key"
EOF

# Encrypt
sops -e /tmp/cardano-secrets.yaml > helmfile/manifests/workloads/cardano-secrets.enc.yaml

# Apply
sops -d helmfile/manifests/workloads/cardano-secrets.enc.yaml | kubectl apply -f -
```

## Troubleshooting

### Pod Not Scheduling

```bash
# Check pod events
kubectl describe pod -n cardano <pod-name>

# Common issues:
# - Node labels missing
# - Insufficient resources
# - PVC not available
# - Image pull errors

# Check node capacity
kubectl describe node <node-name>
```

### PVC Not Mounting

```bash
# Check PVC status
kubectl get pvc -n cardano
kubectl describe pvc cardano-data -n cardano

# Check storage class
kubectl get storageclass

# Verify PV
kubectl get pv
```

### NodePort Not Accessible

```bash
# Check service
kubectl get svc -n cardano

# Verify port is open
sudo netstat -tlnp | grep 30001

# Check firewall
sudo ufw status
sudo ufw allow 30001/tcp

# Test from external
telnet <PUBLIC_IP> 30001
```

### Performance Issues

```bash
# Check resource usage
kubectl top pod -n cardano
kubectl top node

# Check disk I/O
kubectl exec -n cardano <pod-name> -- df -h
kubectl exec -n cardano <pod-name> -- iostat
```

## Best Practices

1. **Always use PVCs** for stateful workloads
2. **Label nodes** appropriately for workload placement
3. **Set resource limits** to prevent resource exhaustion
4. **Use liveness/readiness probes** for health checks
5. **Implement backups** for critical data
6. **Monitor metrics** and set up alerts
7. **Test failover** regularly
8. **Document configurations** and update procedures
9. **Use GitOps** for reproducible deployments
10. **Encrypt secrets** with SOPS or similar tools

## References

- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Cardano Node Documentation](https://docs.cardano.org/cardano-node/)
- [K3s Storage](https://docs.k3s.io/storage)
