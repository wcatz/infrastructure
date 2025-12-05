# Firewall Rules Configuration Guide

This guide documents the expected firewall rules for each node type in the hybrid Kubernetes cluster architecture.

## Table of Contents

- [Overview](#overview)
- [Control Plane Node(s)](#control-plane-nodes)
- [Worker Nodes](#worker-nodes)
- [Monitoring and External Access](#monitoring-and-external-access)
- [CI/CD Runner Rules](#cicd-runner-rules)
- [Example Configurations](#example-configurations)
  - [UFW Configuration](#ufw-configuration)
  - [iptables Configuration](#iptables-configuration)
- [Port Reference](#port-reference)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

The hybrid cluster architecture uses:
- **Tailscale mesh network** (100.64.0.0/10) for secure inter-node communication
- **Cloudflared tunnels** for HTTP/HTTPS ingress without exposing ports
- **Public IPs on worker nodes** for direct TCP/UDP service access via NodePorts
- **Control plane behind CGNAT** with no public exposure required

### Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                    ┌────▼─────┐
                    │Cloudflare│
                    └────┬─────┘
                         │
            ┌────────────▼────────────┐
            │  Cloudflared Tunnel     │
            │  (Worker Node)          │
            └────────────┬────────────┘
                         │
         ┌───────────────▼──────────────┐
         │    Kubernetes Services       │
         │         (Pods)               │
         └──────────────────────────────┘

Control Plane ←──→ Tailscale VPN ←──→ Worker Nodes
 (CGNAT/Home)      (100.64.0.0/10)      (Public IP)
```

## Control Plane Node(s)

Control plane nodes run only the K3s server and are typically behind CGNAT/NAT without public IP exposure. All access is through Tailscale.

### Inbound Rules

| Source | Port/Protocol | Purpose | Required |
|--------|--------------|---------|----------|
| Tailscale network (100.64.0.0/10) | 6443/tcp | Kubernetes API server | ✅ Yes |
| Tailscale network (100.64.0.0/10) | 10250/tcp | Kubelet API | ✅ Yes |
| Tailscale network (100.64.0.0/10) | 2379-2380/tcp | etcd server client API | ⚠️ If using HA |
| Tailscale network (100.64.0.0/10) | 41641/udp | Tailscale WireGuard | ✅ Yes |
| localhost (127.0.0.1) | All | Local services | ✅ Yes |

### Outbound Rules

| Destination | Port/Protocol | Purpose | Required |
|-------------|--------------|---------|----------|
| Tailscale network (100.64.0.0/10) | All | Worker communication | ✅ Yes |
| 0.0.0.0/0 | 443/tcp | HTTPS (updates, downloads) | ✅ Yes |
| 0.0.0.0/0 | 80/tcp | HTTP (package managers) | ⚠️ Recommended |
| 0.0.0.0/0 | 53/udp | DNS | ✅ Yes |
| Tailscale coordination server | 443/tcp | Tailscale control plane | ✅ Yes |

### Key Security Constraints

- ✅ **NO public ingress allowed** - All access via Tailscale only
- ✅ **Deny Kubernetes API from public IPs** - Use `ufw deny 6443/tcp` before Tailscale allow rules
- ✅ **Taint control plane** - Prevent workload scheduling: `node-role.kubernetes.io/control-plane:NoSchedule`
- ⚠️ **Restrict Tailscale ACLs** - Limit access to specific tags (see [TAILSCALE_SETUP.md](TAILSCALE_SETUP.md))

### Example UFW Rules for Control Plane

```bash
# Reset firewall (⚠️ WARNING: This will clear ALL existing rules!)
# Ensure you have console/physical access before running this in case of lockout
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (adjust as needed)
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp

# Allow Kubernetes API from Tailscale network only
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp

# Allow Kubelet API from Tailscale network only
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp

# Allow etcd (if HA control plane)
# sudo ufw allow from 100.64.0.0/10 to any port 2379:2380 proto tcp

# Allow Tailscale
sudo ufw allow 41641/udp

# Explicitly deny public access to Kubernetes API
sudo ufw deny 6443/tcp

# Enable firewall
sudo ufw --force enable

# Verify rules
sudo ufw status numbered
```

## Worker Nodes

Worker nodes have public IPs and run all application workloads. They expose services via Cloudflared tunnels and NodePorts.

### Inbound Rules

| Source | Port/Protocol | Purpose | Required |
|--------|--------------|---------|----------|
| Tailscale network (100.64.0.0/10) | 6443/tcp | Kubernetes API (service discovery, pod lifecycle) | ✅ Yes |
| Tailscale network (100.64.0.0/10) | 10250/tcp | Kubelet API | ✅ Yes |
| Tailscale network (100.64.0.0/10) | 41641/udp | Tailscale WireGuard | ✅ Yes |
| 0.0.0.0/0 (Public) | 30000-32767/tcp | NodePort services | ⚠️ As needed per service |
| 0.0.0.0/0 (Public) | 30000-32767/udp | NodePort services | ⚠️ As needed per service |
| localhost (127.0.0.1) | All | Local services | ✅ Yes |

### Outbound Rules

| Destination | Port/Protocol | Purpose | Required |
|-------------|--------------|---------|----------|
| Tailscale network (100.64.0.0/10) | 6443/tcp | Connect to control plane | ✅ Yes |
| Tailscale network (100.64.0.0/10) | All | Inter-node communication | ✅ Yes |
| 0.0.0.0/0 | 443/tcp | HTTPS (updates, registries) | ✅ Yes |
| 0.0.0.0/0 | 80/tcp | HTTP (package managers) | ⚠️ Recommended |
| 0.0.0.0/0 | 53/udp | DNS | ✅ Yes |
| Tailscale coordination server | 443/tcp | Tailscale control plane | ✅ Yes |

### Key Security Constraints

- ⚠️ **Selective NodePort exposure** - Only open specific NodePorts needed for services (not entire range)
- ✅ **Cloudflared handles HTTP/S** - No need to expose ports 80/443 publicly
- ⚠️ **Rate limiting** - Use `ufw limit` for exposed NodePorts to prevent DoS
- ✅ **Monitoring exposure** - Restrict monitoring endpoints to Tailscale only

### Example UFW Rules for Worker Nodes

```bash
# Reset firewall (⚠️ WARNING: This will clear ALL existing rules!)
# Ensure you have console/physical access before running this in case of lockout
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (adjust as needed)
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp

# Allow Kubelet API from Tailscale network
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp

# Allow Tailscale
sudo ufw allow 41641/udp

# Example: Allow specific NodePort for a service (e.g., port 30080)
# Replace with your actual NodePort
sudo ufw allow 30080/tcp comment 'NodePort for app-service'

# Example: Allow NodePort range for specific services
# sudo ufw allow 30080:30090/tcp comment 'NodePort range for services'

# Example: Rate limit public NodePort to prevent DoS
# sudo ufw limit 30080/tcp

# Enable firewall
sudo ufw --force enable

# Verify rules
sudo ufw status numbered
```

### Cloudflared Considerations

Cloudflared pods running on worker nodes:
- ✅ **No firewall rules needed** - Cloudflared establishes outbound connections to Cloudflare (port 443)
- ✅ **Routes to internal services** - Traffic flows through tunnel to ClusterIP services
- ⚠️ **Access control via Cloudflare Access** - Use Cloudflare Zero Trust for authentication (see [CLOUDFLARED_SETUP.md](helmfile/CLOUDFLARED_SETUP.md#security-best-practices))

## Monitoring and External Access

### Prometheus/Grafana

Monitoring stack should be accessible only via Tailscale for security.

**Recommended approach:**
1. Deploy Prometheus/Grafana with ClusterIP services
2. Expose via Tailscale ingress or port-forward
3. **Do not expose via NodePort or public ingress**

```bash
# Access Grafana via port-forward through Tailscale
# From a machine on Tailscale network:
kubectl port-forward -n monitoring svc/grafana 3000:80

# Or expose via Tailscale service (if using Tailscale operator)
# See TAILSCALE_SETUP.md for configuration
```

### External Access Rules

| Service | Access Method | Firewall Rules |
|---------|--------------|----------------|
| HTTP/HTTPS apps | Cloudflared tunnel | None (outbound 443 only) |
| TCP/UDP services | NodePort on worker | Specific NodePort rule |
| Kubernetes API | Tailscale VPN | Tailscale network only |
| Monitoring dashboards | Tailscale VPN | Tailscale network only |
| SSH | Tailscale VPN | Tailscale network only |

## CI/CD Runner Rules

GitHub Actions runners need access to the Kubernetes API and other cluster services. See [GITHUB_RUNNER_SETUP.md](GITHUB_RUNNER_SETUP.md) for detailed setup.

### Runner Access Requirements

Runners deployed on worker nodes (or as Kubernetes pods) need:

| Destination | Port/Protocol | Purpose | Required |
|-------------|--------------|---------|----------|
| Control plane Tailscale IP | 6443/tcp | Kubernetes API | ✅ Yes |
| Worker nodes Tailscale IPs | 10250/tcp | Kubelet metrics | ⚠️ If monitoring |
| Tailscale network | All | Cluster communication | ✅ Yes |

### Firewall Rules for CI/CD

**On control plane** (where runners connect):
```bash
# Allow GitHub runner access to Kubernetes API via Tailscale
# Runners should be tagged in Tailscale (e.g., tag:github-runner)
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp comment 'K8s API for runners'
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp comment 'Kubelet for runners'
```

**On worker nodes** (where runners run):
```bash
# Outbound to control plane (already covered by default allow outgoing)
# Access to Tailscale network for cluster operations
sudo ufw allow out to 100.64.0.0/10 comment 'Tailscale network access'
```

### Tailscale ACLs for Runners

Configure Tailscale ACLs to restrict runner access (example from [TAILSCALE_SETUP.md](TAILSCALE_SETUP.md)):

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:ci", "tag:github-runner"],
      "dst": ["tag:control-plane:6443,10250"]
    },
    {
      "action": "accept",
      "src": ["tag:ci", "tag:github-runner"],
      "dst": ["tag:worker:*"]
    }
  ]
}
```

## Example Configurations

### UFW Configuration

UFW (Uncomplicated Firewall) is the recommended firewall for Ubuntu-based systems.

#### Installation

```bash
# UFW is pre-installed on Ubuntu, but if needed:
sudo apt update
sudo apt install ufw
```

#### Complete Control Plane UFW Setup

```bash
#!/bin/bash
# control-plane-firewall.sh - Complete UFW setup for control plane

set -e

echo "Configuring firewall for K3s control plane..."

# ⚠️ WARNING: This script will reset all firewall rules!
# Ensure you have console/physical access before running this.
read -p "This will reset ALL firewall rules. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Reset UFW (WARNING: This will clear all existing rules)
sudo ufw --force reset

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow loopback
sudo ufw allow in on lo
sudo ufw allow out on lo

# Allow SSH from Tailscale network (adjust if needed)
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH from Tailscale'

# Kubernetes API server (control plane)
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp comment 'K8s API server'

# Kubelet API
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp comment 'Kubelet API'

# etcd server client API (only for HA control plane)
# sudo ufw allow from 100.64.0.0/10 to any port 2379 proto tcp comment 'etcd client API'
# sudo ufw allow from 100.64.0.0/10 to any port 2380 proto tcp comment 'etcd peer API'

# Tailscale
sudo ufw allow 41641/udp comment 'Tailscale WireGuard'

# Explicitly deny public access to sensitive ports
sudo ufw deny 6443/tcp comment 'Block public K8s API'
sudo ufw deny 10250/tcp comment 'Block public Kubelet'
sudo ufw deny 2379:2380/tcp comment 'Block public etcd'

# Enable firewall
sudo ufw --force enable

# Show status
echo ""
echo "Firewall enabled. Current rules:"
sudo ufw status numbered

echo ""
echo "✅ Control plane firewall configured successfully"
```

#### Complete Worker Node UFW Setup

```bash
#!/bin/bash
# worker-firewall.sh - Complete UFW setup for worker node

set -e

echo "Configuring firewall for K3s worker node..."

# ⚠️ WARNING: This script will reset all firewall rules!
# Ensure you have console/physical access before running this.
read -p "This will reset ALL firewall rules. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Reset UFW (WARNING: This will clear all existing rules)
sudo ufw --force reset

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow loopback
sudo ufw allow in on lo
sudo ufw allow out on lo

# Allow SSH from Tailscale network
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH from Tailscale'

# Kubelet API (from control plane and monitoring)
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp comment 'Kubelet API'

# Tailscale
sudo ufw allow 41641/udp comment 'Tailscale WireGuard'

# NodePort range - ADD ONLY SPECIFIC PORTS YOU NEED
# Example: Web service on NodePort 30080
# sudo ufw allow 30080/tcp comment 'NodePort: web-service'

# Example: Game server on NodePort 30303 UDP
# sudo ufw allow 30303/udp comment 'NodePort: game-server'

# Example: Allow entire NodePort range (NOT RECOMMENDED)
# sudo ufw allow 30000:32767/tcp comment 'NodePort range TCP'
# sudo ufw allow 30000:32767/udp comment 'NodePort range UDP'

# Rate limiting for specific public NodePorts (recommended)
# sudo ufw limit 30080/tcp comment 'Rate-limited NodePort'

# Enable firewall
sudo ufw --force enable

# Show status
echo ""
echo "Firewall enabled. Current rules:"
sudo ufw status numbered

echo ""
echo "⚠️  Remember to add specific NodePort rules for your services"
echo "✅ Worker node firewall configured successfully"
```

#### UFW Common Operations

```bash
# Check firewall status
sudo ufw status verbose
sudo ufw status numbered

# Add a rule
sudo ufw allow from 100.64.0.0/10 to any port 8080 proto tcp comment 'My service'

# Delete a rule by number
sudo ufw status numbered
sudo ufw delete [number]

# Delete a rule by specification
sudo ufw delete allow 8080/tcp

# Enable/disable firewall
sudo ufw enable
sudo ufw disable

# Reset firewall (removes all rules)
sudo ufw --force reset

# Reload firewall
sudo ufw reload

# View logs
sudo tail -f /var/log/ufw.log
```

### iptables Configuration

For systems not using UFW or requiring more granular control, use iptables directly.

#### Control Plane iptables Setup

```bash
#!/bin/bash
# control-plane-iptables.sh - iptables setup for control plane

set -e

echo "Configuring iptables for K3s control plane..."

# ⚠️ WARNING: This script will flush all iptables rules!
# Ensure you have console/physical access before running this.
read -p "This will flush ALL iptables rules. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Backup existing rules
echo "Backing up existing iptables rules to /tmp/iptables-backup-$(date +%s).rules"
iptables-save > /tmp/iptables-backup-$(date +%s).rules

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from Tailscale network
iptables -A INPUT -p tcp -s 100.64.0.0/10 --dport 22 -j ACCEPT

# Allow Kubernetes API from Tailscale network
iptables -A INPUT -p tcp -s 100.64.0.0/10 --dport 6443 -j ACCEPT

# Allow Kubelet API from Tailscale network
iptables -A INPUT -p tcp -s 100.64.0.0/10 --dport 10250 -j ACCEPT

# Allow etcd (if HA control plane)
# iptables -A INPUT -p tcp -s 100.64.0.0/10 --dport 2379:2380 -j ACCEPT

# Allow Tailscale
iptables -A INPUT -p udp --dport 41641 -j ACCEPT
iptables -A OUTPUT -p udp --dport 41641 -j ACCEPT

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Explicitly reject public access to sensitive ports
iptables -A INPUT -p tcp --dport 6443 -j REJECT
iptables -A INPUT -p tcp --dport 10250 -j REJECT
iptables -A INPUT -p tcp --dport 2379:2380 -j REJECT

# Save rules
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif [ -f /etc/redhat-release ]; then
    service iptables save
else
    # Create directory if it doesn't exist
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo "⚠️  Rules saved to /etc/iptables/rules.v4"
    echo "⚠️  To restore on boot, install iptables-persistent: apt install iptables-persistent"
fi

echo "✅ Control plane iptables configured successfully"
```

#### Worker Node iptables Setup

```bash
#!/bin/bash
# worker-iptables.sh - iptables setup for worker node

set -e

echo "Configuring iptables for K3s worker node..."

# ⚠️ WARNING: This script will flush all iptables rules!
# Ensure you have console/physical access before running this.
read -p "This will flush ALL iptables rules. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Backup existing rules
echo "Backing up existing iptables rules to /tmp/iptables-backup-$(date +%s).rules"
iptables-save > /tmp/iptables-backup-$(date +%s).rules

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from Tailscale network
iptables -A INPUT -p tcp -s 100.64.0.0/10 --dport 22 -j ACCEPT

# Allow Kubelet API from Tailscale network
iptables -A INPUT -p tcp -s 100.64.0.0/10 --dport 10250 -j ACCEPT

# Allow Tailscale
iptables -A INPUT -p udp --dport 41641 -j ACCEPT

# Allow specific NodePorts (examples - adjust as needed)
# iptables -A INPUT -p tcp --dport 30080 -j ACCEPT
# iptables -A INPUT -p udp --dport 30303 -j ACCEPT

# Rate limiting for public NodePorts (example)
# iptables -A INPUT -p tcp --dport 30080 -m limit --limit 25/min --limit-burst 100 -j ACCEPT

# Save rules
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
elif [ -f /etc/redhat-release ]; then
    service iptables save
else
    iptables-save > /etc/iptables/rules.v4
fi

echo "⚠️  Remember to add specific NodePort rules for your services"
echo "✅ Worker node iptables configured successfully"
```

#### iptables Common Operations

```bash
# List current rules
sudo iptables -L -n -v --line-numbers

# List NAT rules
sudo iptables -t nat -L -n -v --line-numbers

# Add a rule
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# Insert a rule at specific position
sudo iptables -I INPUT 5 -p tcp --dport 8080 -j ACCEPT

# Delete a rule by number
sudo iptables -D INPUT 5

# Delete a rule by specification
sudo iptables -D INPUT -p tcp --dport 8080 -j ACCEPT

# Save rules (Ubuntu/Debian with netfilter-persistent)
sudo netfilter-persistent save

# Save rules (manual)
sudo iptables-save > /etc/iptables/rules.v4

# Restore rules
sudo iptables-restore < /etc/iptables/rules.v4

# Flush all rules (careful!)
sudo iptables -F
sudo iptables -X
```

## Port Reference

### Standard Kubernetes Ports

| Port | Protocol | Component | Description |
|------|----------|-----------|-------------|
| 6443 | TCP | API Server | Kubernetes API (control plane) |
| 2379-2380 | TCP | etcd | etcd server client API |
| 10250 | TCP | Kubelet | Kubelet API |
| 10251 | TCP | kube-scheduler | Scheduler (localhost only in k3s) |
| 10252 | TCP | kube-controller | Controller manager (localhost only in k3s) |
| 10255 | TCP | Kubelet | Read-only Kubelet API (deprecated) |
| 30000-32767 | TCP/UDP | NodePort | NodePort service range |

### Tailscale Ports

| Port | Protocol | Component | Description |
|------|----------|-----------|-------------|
| 41641 | UDP | Tailscale | WireGuard tunnel endpoint |
| 443 | TCP | Tailscale | Control plane (outbound) |

### Common Application Ports

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 80 | TCP | HTTP | HTTP traffic (via Cloudflared) |
| 443 | TCP | HTTPS | HTTPS traffic (via Cloudflared) |
| 9090 | TCP | Prometheus | Metrics (Tailscale only) |
| 3000 | TCP | Grafana | Dashboards (Tailscale only) |

## Security Best Practices

### 1. Principle of Least Privilege

- ✅ **Only open necessary ports** - Don't open entire NodePort range
- ✅ **Use Tailscale for internal access** - No public SSH, monitoring, or API access
- ✅ **Restrict by source** - Use `from <network>` in ufw or `-s <network>` in iptables
- ⚠️ **Regular audits** - Review firewall rules quarterly

### 2. Defense in Depth

- ✅ **Firewall + Tailscale ACLs** - Use both host firewall and Tailscale ACLs
- ✅ **Kubernetes Network Policies** - Add pod-level network restrictions
- ✅ **Cloudflare Access** - Protect public services with Zero Trust
- ⚠️ **Pod Security Standards** - Enforce restricted or baseline policies

### 3. Monitoring and Logging

```bash
# Enable UFW logging
sudo ufw logging on
sudo ufw logging medium

# View UFW logs
sudo tail -f /var/log/ufw.log

# View iptables logs (requires LOG target)
sudo journalctl -k | grep iptables
```

### 4. Rate Limiting

Protect public NodePorts from DoS attacks:

```bash
# UFW rate limiting (allows 6 connections per 30 seconds from same IP)
sudo ufw limit 30080/tcp

# iptables rate limiting (more configurable)
sudo iptables -A INPUT -p tcp --dport 30080 \
  -m limit --limit 25/minute --limit-burst 100 \
  -j ACCEPT
```

### 5. Automated Configuration

Consider using Ansible to manage firewall rules consistently:

```yaml
# ansible/roles/firewall/tasks/main.yaml
- name: Configure UFW for control plane
  community.general.ufw:
    rule: allow
    port: "{{ item.port }}"
    proto: "{{ item.proto }}"
    from_ip: "100.64.0.0/10"
    comment: "{{ item.comment }}"
  loop:
    - { port: '6443', proto: 'tcp', comment: 'K8s API' }
    - { port: '10250', proto: 'tcp', comment: 'Kubelet' }
```

## Troubleshooting

### Connection Issues

```bash
# Test connectivity to control plane from worker
tailscale ping control-node
curl -k https://$(tailscale ip -4 control-node):6443/livez

# Test if firewall is blocking
sudo ufw status verbose
sudo iptables -L -n -v | grep <port>

# Check if specific traffic is being blocked
sudo tcpdump -i any port 6443 -n

# Temporarily allow specific traffic for testing (safer than disabling firewall)
sudo ufw allow from <specific-ip> to any port 6443 proto tcp
# Test connection
# Then remove the temporary rule:
sudo ufw delete allow from <specific-ip> to any port 6443 proto tcp

# AVOID: Disabling firewall entirely creates security risks
# Only disable as last resort with console access:
# sudo ufw disable  # Test immediately, then: sudo ufw enable
```

### Debugging Firewall Rules

```bash
# UFW: Check if rule exists
sudo ufw status | grep <port>

# iptables: Check packet counters
sudo iptables -L -n -v
# Look for counters increasing on specific rules

# Monitor live traffic
sudo tcpdump -i any port 6443

# Check Tailscale connectivity
sudo tailscale status
sudo tailscale netcheck
```

### Common Issues

**Issue: Kubernetes API not accessible from worker**
```bash
# Solution: Verify control plane allows Tailscale network
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp
sudo ufw reload
```

**Issue: NodePort service not accessible**
```bash
# Solution: Add specific NodePort rule on worker
sudo ufw allow 30080/tcp comment 'My service'
kubectl get svc -A | grep NodePort  # Verify NodePort number
```

**Issue: Cloudflared tunnel not connecting**
```bash
# Solution: Ensure outbound 443 is allowed (should be by default allow outgoing)
sudo ufw status | grep 443
# Check cloudflared logs
kubectl logs -n cloudflare -l app=cloudflared
```

## Related Documentation

- [Tailscale Setup Guide](TAILSCALE_SETUP.md) - Tailscale VPN mesh configuration and ACLs
- [Cloudflared Setup Guide](helmfile/CLOUDFLARED_SETUP.md) - Cloudflare tunnel configuration
- [GitHub Runner Setup Guide](GITHUB_RUNNER_SETUP.md) - CI/CD runner with Tailscale access
- [Hybrid Cluster Setup Guide](HYBRID_CLUSTER_SETUP.md) - Overall cluster architecture
- [Security Best Practices](helmfile/CLOUDFLARED_SETUP.md#security-best-practices) - Additional security guidelines

## Quick Reference

### Control Plane Essential Rules
```bash
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp
sudo ufw allow 41641/udp
sudo ufw deny 6443/tcp
```

### Worker Node Essential Rules
```bash
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp
sudo ufw allow 41641/udp
# Add specific NodePorts as needed
```

### CI/CD Runner Essential Rules
```bash
# On control plane - allow runner access
sudo ufw allow from 100.64.0.0/10 to any port 6443 proto tcp
sudo ufw allow from 100.64.0.0/10 to any port 10250 proto tcp
```
