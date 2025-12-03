# HAProxy Load Balancer for Kubernetes NodePorts

This guide covers deploying HAProxy as a TCP/UDP load balancer for Kubernetes NodePort services, enabling external access to cluster services with high availability and failover capabilities.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [How NodePort Load Balancing Works](#how-nodeport-load-balancing-works)
- [Deployment Guide](#deployment-guide)
- [Configuration Examples](#configuration-examples)
- [Failover Configuration](#failover-configuration)
- [Monitoring and Health Checks](#monitoring-and-health-checks)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

## Architecture Overview

```
                    External Traffic
                           |
                           v
                    ┌──────────┐
                    |  HAProxy |
                    | TCP/UDP  |
                    |    LB    |
                    └──────────┘
                           |
         ┌────────────────┼────────────────┐
         |                |                |
         v                v                v
   ┌─────────┐      ┌─────────┐      ┌─────────┐
   | Worker1 |      | Worker2 |      | Worker3 |
   | :30306  |      | :30306  |      | :30306  |
   | :31820  |      | :31820  |      | :31820  |
   └─────────┘      └─────────┘      └─────────┘
         |                |                |
         v                v                v
   ┌─────────────────────────────────────────┐
   |        Kubernetes Cluster               |
   |  ┌──────────┐  ┌──────────┐            |
   |  |  MySQL   |  |WireGuard |            |
   |  | Service  |  | Service  |            |
   |  └──────────┘  └──────────┘            |
   └─────────────────────────────────────────┘
```

### Traffic Flow

1. **Client connects** to HAProxy on standard port (e.g., MySQL 3306, WireGuard 51820)
2. **HAProxy load balances** across all Kubernetes worker NodePort endpoints
3. **NodePort service** routes to appropriate Pod in the cluster
4. **Health checks** ensure only healthy backends receive traffic
5. **Automatic failover** if a worker node becomes unavailable

## How NodePort Load Balancing Works

### NodePort Service Basics

A Kubernetes NodePort service exposes a service on a static port on each worker node:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: databases
spec:
  type: NodePort
  ports:
    - port: 3306          # Service port
      targetPort: 3306    # Container port
      nodePort: 30306     # NodePort (30000-32767 range)
  selector:
    app: mysql
```

### Why Use HAProxy with NodePorts?

1. **Standard Ports**: Expose services on standard ports (3306, 51820) instead of NodePort range
2. **Load Balancing**: Distribute traffic across multiple worker nodes
3. **Health Checks**: Automatic failover when nodes are unhealthy
4. **High Availability**: Multiple HAProxy instances possible
5. **Protocol Support**: Both TCP and UDP protocols
6. **Advanced Features**: Connection pooling, rate limiting, monitoring

## Deployment Guide

### Prerequisites

- Kubernetes cluster with worker nodes
- Ansible installed on control machine
- SSH access to HAProxy server(s)
- Firewall rules allowing traffic to HAProxy server

### Step 1: Identify Worker Nodes

Get the IP addresses of your Kubernetes worker nodes:

```bash
kubectl get nodes -o wide
```

Example output:
```
NAME              STATUS   ROLES    INTERNAL-IP     EXTERNAL-IP
k8s-worker-1      Ready    <none>   192.168.1.11    <none>
k8s-worker-2      Ready    <none>   192.168.1.12    <none>
k8s-worker-3      Ready    <none>   192.168.1.13    <none>
```

### Step 2: Deploy Services with NodePorts

Create your Kubernetes services with NodePort type. See [Configuration Examples](#configuration-examples) for service definitions.

### Step 3: Configure HAProxy Backend

Edit `ansible/roles/haproxy/defaults/main.yaml` or create a custom vars file:

```yaml
haproxy_tcp_backends:
  - name: mysql
    port: 3306
    mode: tcp
    balance: roundrobin
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
      - name: k8s-worker-3
        address: 192.168.1.13
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
```

### Step 4: Deploy HAProxy

```bash
cd ansible

# Configure inventory
cp inventory.ini.example inventory.ini
vim inventory.ini  # Add HAProxy server

# Deploy HAProxy
ansible-playbook playbooks/deploy-haproxy.yaml

# Verify deployment
ansible haproxy_servers -m shell -a "systemctl status haproxy"
```

### Step 5: Test Connectivity

```bash
# Test TCP connection (MySQL example)
mysql -h <haproxy-ip> -P 3306 -u user -p

# Test UDP connection (WireGuard example)
wg-quick up wg0  # With endpoint set to <haproxy-ip>:51820
```

## Configuration Examples

### Example 1: MySQL Database NodePort

**Kubernetes Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: databases
spec:
  type: NodePort
  ports:
    - name: mysql
      port: 3306
      targetPort: 3306
      nodePort: 30306  # Accessible on all worker nodes at port 30306
  selector:
    app: mysql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  namespace: databases
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
              key: root-password
```

**HAProxy Configuration:**
```yaml
haproxy_tcp_backends:
  - name: mysql
    port: 3306  # HAProxy listens on standard port
    mode: tcp
    balance: leastconn  # Use least connections for database
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
      - name: k8s-worker-3
        address: 192.168.1.13
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
```

### Example 2: WireGuard VPN NodePort

**Kubernetes Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: wireguard
  namespace: vpn
spec:
  type: NodePort
  ports:
    - name: wireguard
      port: 51820
      targetPort: 51820
      nodePort: 31820
      protocol: UDP
  selector:
    app: wireguard
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wireguard
  namespace: vpn
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wireguard
  template:
    metadata:
      labels:
        app: wireguard
    spec:
      containers:
      - name: wireguard
        image: linuxserver/wireguard
        ports:
        - containerPort: 51820
          protocol: UDP
        securityContext:
          capabilities:
            add:
              - NET_ADMIN
              - SYS_MODULE
```

**HAProxy Configuration:**
```yaml
haproxy_udp_backends:
  - name: wireguard
    port: 51820  # HAProxy listens on standard WireGuard port
    mode: udp
    balance: roundrobin  # Round-robin for VPN connections
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 31820
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 31820
      - name: k8s-worker-3
        address: 192.168.1.13
        port: 31820
```

**Note**: UDP health checks are not supported by HAProxy, so `check` is omitted for UDP backends.

### Example 3: PostgreSQL Database NodePort

**Kubernetes Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: databases
spec:
  type: NodePort
  ports:
    - name: postgresql
      port: 5432
      targetPort: 5432
      nodePort: 30432
  selector:
    app: postgresql
```

**HAProxy Configuration:**
```yaml
haproxy_tcp_backends:
  - name: postgresql
    port: 5432
    mode: tcp
    balance: leastconn
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 30432
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 30432
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
```

### Example 4: Redis Cache NodePort

**Kubernetes Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: cache
spec:
  type: NodePort
  ports:
    - name: redis
      port: 6379
      targetPort: 6379
      nodePort: 30379
  selector:
    app: redis
```

**HAProxy Configuration:**
```yaml
haproxy_tcp_backends:
  - name: redis
    port: 6379
    mode: tcp
    balance: roundrobin
    servers:
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 30379
        check: true
        check_interval: 1s
        rise: 2
        fall: 2
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 30379
        check: true
        check_interval: 1s
        rise: 2
        fall: 2
```

## Failover Configuration

### Understanding Health Check Parameters

- **check**: Enable health checks for the backend
- **check_interval** (inter): Time between health checks (e.g., `2s`)
- **rise**: Number of successful checks before marking server UP (default: 2)
- **fall**: Number of failed checks before marking server DOWN (default: 3)

### Example Failover Configuration

```yaml
haproxy_tcp_backends:
  - name: mysql
    port: 3306
    mode: tcp
    balance: leastconn
    servers:
      # Primary worker - faster to come back online
      - name: k8s-worker-1
        address: 192.168.1.11
        port: 30306
        check: true
        check_interval: 2s
        rise: 1        # Faster recovery
        fall: 3        # Slower to mark down
      # Secondary workers - standard settings
      - name: k8s-worker-2
        address: 192.168.1.12
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
      - name: k8s-worker-3
        address: 192.168.1.13
        port: 30306
        check: true
        check_interval: 2s
        rise: 2
        fall: 3
```

### Failover Testing

Test failover by simulating node failures:

```bash
# On a worker node, stop accepting traffic
sudo iptables -A INPUT -p tcp --dport 30306 -j DROP

# Watch HAProxy stats page
curl http://<haproxy-ip>:8404/stats

# Restore traffic
sudo iptables -D INPUT -p tcp --dport 30306 -j DROP
```

### Graceful HAProxy Reloads

HAProxy supports graceful configuration reloads without dropping connections:

```bash
# On HAProxy server
sudo systemctl reload haproxy

# Or using Ansible
ansible haproxy_servers -m service -a "name=haproxy state=reloaded"
```

## Monitoring and Health Checks

### HAProxy Statistics Page

Access the stats page at `http://<haproxy-ip>:8404/stats`

**Key Metrics to Monitor:**
- Backend server status (UP/DOWN)
- Active connections
- Queued connections
- Error rates
- Response times

### Prometheus Metrics

Export HAProxy metrics for Prometheus:

1. **Install HAProxy exporter**:
   ```bash
   # Using Docker
   docker run -d -p 9101:9101 \
     -e HAPROXY_SCRAPE_URI="http://localhost:8404/stats;csv" \
     prom/haproxy-exporter:latest
   ```

2. **Add Prometheus scrape config**:
   ```yaml
   - job_name: 'haproxy'
     static_configs:
       - targets: ['<haproxy-ip>:9101']
   ```

### Health Check Commands

```bash
# Check HAProxy status
sudo systemctl status haproxy

# View HAProxy logs
sudo journalctl -u haproxy -f

# Test backend connectivity
nc -zv 192.168.1.11 30306

# Check HAProxy configuration
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

## Troubleshooting

### Connection Refused

**Symptom**: Connections to HAProxy are refused

**Solutions**:
1. Check HAProxy is running: `systemctl status haproxy`
2. Verify firewall allows traffic: `sudo ufw status`
3. Check HAProxy is listening: `sudo netstat -tlnp | grep haproxy`

### Backend Servers Down

**Symptom**: All backend servers marked as DOWN in stats

**Solutions**:
1. Verify NodePort services are running: `kubectl get svc -A`
2. Test connectivity from HAProxy to workers: `nc -zv 192.168.1.11 30306`
3. Check Kubernetes pod status: `kubectl get pods -A`
4. Review HAProxy logs: `journalctl -u haproxy -n 50`

### Intermittent Failures

**Symptom**: Some requests fail, others succeed

**Solutions**:
1. Check backend server health in stats page
2. Verify all worker nodes are healthy: `kubectl get nodes`
3. Adjust health check parameters (rise/fall)
4. Check for network issues between HAProxy and workers

### Configuration Errors

**Symptom**: HAProxy fails to start or reload

**Solutions**:
1. Validate configuration: `haproxy -c -f /etc/haproxy/haproxy.cfg`
2. Check Ansible template syntax
3. Review HAProxy logs for specific errors
4. Ensure all required ports are not in use

## Best Practices

### High Availability

1. **Deploy Multiple HAProxy Instances**:
   - Use keepalived for VIP failover
   - Configure HAProxy in active/passive or active/active mode
   
2. **Use Multiple Worker Nodes**:
   - Minimum 3 worker nodes for production
   - Distribute workloads across availability zones

3. **Configure Proper Health Checks**:
   - Short intervals for quick failover (2-5s)
   - Appropriate rise/fall values for stability

### Security

1. **Restrict Access**:
   - Use firewall rules to limit access to HAProxy
   - Restrict stats page access: configure authentication
   
2. **Use TLS Where Possible**:
   - For TCP services that support TLS, configure SSL passthrough
   
3. **Monitor Logs**:
   - Regularly review HAProxy logs for suspicious activity
   - Set up alerting for unusual traffic patterns

### Performance

1. **Choose Appropriate Load Balancing Algorithm**:
   - `roundrobin`: Simple, fair distribution
   - `leastconn`: Best for long-lived connections (databases)
   - `source`: Sticky sessions based on client IP

2. **Tune Timeouts**:
   - Adjust based on application requirements
   - Longer timeouts for databases and streaming

3. **Monitor Resource Usage**:
   - CPU and memory on HAProxy server
   - Network bandwidth utilization
   - Connection limits

### Operational

1. **Document Configuration**:
   - Keep inventory of worker nodes and NodePorts
   - Document service dependencies
   - Maintain runbook for common issues

2. **Test Failover Regularly**:
   - Simulate node failures
   - Verify automatic recovery
   - Time failover duration

3. **Plan for Scaling**:
   - Add worker nodes as needed
   - Update HAProxy configuration dynamically
   - Consider automation for node discovery

## Advanced Scenarios

### Dynamic Backend Configuration

For dynamic environments, consider using DNS-based service discovery or HAProxy's runtime API to add/remove backends without reloading.

### Multi-Site Deployments

Deploy HAProxy instances in multiple locations with GeoDNS for geographic load balancing:

```
Client Request
      ↓
   GeoDNS
      ↓
   ┌──────────────────┐
   ↓                  ↓
HAProxy US       HAProxy EU
   ↓                  ↓
K8s Cluster US   K8s Cluster EU
```

### Backup and Disaster Recovery

1. Backup HAProxy configuration regularly
2. Document worker node IP addresses
3. Keep runbooks for disaster recovery scenarios
4. Test recovery procedures

## References

- [HAProxy Documentation](https://www.haproxy.org/documentation.html)
- [Kubernetes NodePort Services](https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport)
- [HAProxy Best Practices](https://www.haproxy.com/documentation/hapee/latest/traffic-management/health-checks/)
- [Load Balancing Algorithms](https://www.haproxy.com/documentation/hapee/latest/load-balancing/layer7/algorithms/)
