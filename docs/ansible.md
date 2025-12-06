# Ansible Automation Guide

Complete guide for using Ansible playbooks to deploy and manage the hybrid Kubernetes infrastructure.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Playbooks](#playbooks)
- [Roles](#roles)
- [Inventory Management](#inventory-management)
- [Variables and Configuration](#variables-and-configuration)
- [Secret Management](#secret-management)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)

## Overview

Ansible automation provides:
- **K3s deployment** with hybrid cluster support (control plane + workers)
- **Tailscale VPN** setup on all nodes for secure inter-node communication
- **Automated configuration** of hostnames, firewalls, and system settings
- **Encrypted secrets** via Ansible Vault for K3s tokens and Tailscale keys

### What Gets Deployed

- **Control Plane**: K3s server with no workload scheduling (tainted)
- **Worker Nodes**: K3s agents running all application workloads
- **Tailscale**: Secure mesh network for cluster communication
- **System Configuration**: Hostnames, firewalls, performance tuning

## Architecture

This setup deploys a **hybrid Kubernetes cluster**:

- **Control Plane Node** (Behind CGNAT/Home network):
  - Runs K3s server only
  - Tainted to prevent workload scheduling  
  - Uses Tailscale for cluster communication
  - No public IP required

- **Worker Node(s)** (Public IP, e.g., VPS):
  - Runs all application workloads
  - Handles ingress traffic via Cloudflared
  - Uses Tailscale to connect to control plane
  - Can use NodePort or hostNetwork for TCP services

## Quick Start

### 1. Setup Secrets with Ansible Vault

```bash
# Navigate to ansible directory
cd ansible

# Create vault password file
cp .vault_pass.example .vault_pass
echo "your-secure-vault-password" > .vault_pass
chmod 600 .vault_pass

# Create vault variables
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit vault file with your secrets
vim group_vars/all/vault.yml
```

Add your secrets to `vault.yml`:

```yaml
---
# K3s cluster token (generate with: openssl rand -hex 32)
vault_k3s_token: "your-k3s-token-here"

# Tailscale auth key (from https://login.tailscale.com/admin/settings/keys)
vault_tailscale_key: "tskey-auth-your-key-here"
```

Encrypt the vault:

```bash
ansible-vault encrypt group_vars/all/vault.yml
```

### 2. Configure Inventory

```bash
# Copy inventory template
cp inventory.ini.example inventory.ini

# Edit with your server details
vim inventory.ini
```

Example `inventory.ini`:

```ini
[k3s_servers]
# Control plane - tainted to prevent workload scheduling
k3s-control ansible_host=192.168.1.100 ansible_user=ubuntu k3s_node_taint=true

[k3s_agents]
# Worker nodes - run all workloads
k3s-worker-01 ansible_host=1.2.3.4 ansible_user=ubuntu k3s_node_label="node-role=worker"

[all:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 3. Test Connectivity

```bash
ansible all -i inventory.ini -m ping
```

### 4. Deploy Infrastructure

```bash
# Deploy Tailscale first (required for hybrid cluster)
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml

# After Tailscale deployment, update inventory with Tailscale IPs
# SSH to control plane and get Tailscale IP:
ssh ubuntu@192.168.1.100
tailscale ip -4  # Note this IP (e.g., 100.64.1.10)

# Update inventory.ini:
# k3s-control ansible_host=100.64.1.10 ...

# Deploy k3s cluster
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Configure hostnames (optional)
ansible-playbook -i inventory.ini playbooks/configure-hostname.yaml

# Get kubeconfig
scp ubuntu@100.64.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update server URL in kubeconfig to use Tailscale IP
sed -i 's/127.0.0.1/100.64.1.10/' ~/.kube/config
```

## Playbooks

### setup-tailscale.yaml

Installs and configures Tailscale on all nodes.

**What it does:**
- Installs Tailscale package
- Authenticates with Tailscale using vault auth key
- Enables Tailscale service
- Configures Tailscale settings (SSH, DNS, tags)

**Usage:**

```bash
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml
```

**Variables:**
- `vault_tailscale_key`: Tailscale auth key (from vault)
- `tailscale_enable_ssh`: Enable Tailscale SSH (default: true)
- `tailscale_accept_dns`: Accept Tailscale DNS (default: false)
- `tailscale_advertise_tags`: Tags for ACL management

### deploy-k3s.yaml

Deploys K3s cluster with control plane and worker nodes.

**What it does:**
- Installs K3s server on control plane nodes
- Applies NoSchedule taint to control plane
- Installs K3s agent on worker nodes
- Configures cluster networking (Tailscale-based)
- Sets up kubeconfig

**Usage:**

```bash
# Full deployment
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Deploy only control plane
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --tags control_plane

# Deploy only workers
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --tags agents

# Dry run (check what would change)
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --check
```

**Variables:**
- `vault_k3s_token`: Cluster token for secure join (from vault)
- `k3s_version`: K3s version to install (default: latest)
- `k3s_node_taint`: Whether to taint node (control plane only)
- `k3s_node_label`: Labels to apply to node

### configure-hostname.yaml

Configures hostnames on nodes.

**What it does:**
- Sets hostname based on inventory
- Updates `/etc/hosts`
- Persists hostname across reboots

**Usage:**

```bash
ansible-playbook -i inventory.ini playbooks/configure-hostname.yaml
```

### upgrade-k3s.yaml

Upgrades K3s to a new version.

**What it does:**
- Updates K3s version on control plane
- Rolling upgrade of worker nodes
- Verifies cluster health after upgrade

**Usage:**

```bash
# Edit group_vars/all/main.yml to set new version
# k3s_version: "v1.29.0+k3s1"

ansible-playbook -i inventory.ini playbooks/upgrade-k3s.yaml
```

## Roles

### common

Common tasks for all nodes:
- System package updates
- Essential tool installation
- Timezone configuration
- NTP setup

### k3s-server

K3s control plane installation and configuration:
- K3s server installation
- API server configuration
- Control plane tainting
- kubeconfig generation

### k3s-agent

K3s worker node installation and configuration:
- K3s agent installation
- Cluster join configuration
- Node labeling
- Container runtime setup

### tailscale

Tailscale VPN installation and configuration:
- Package installation
- Authentication
- Service management
- ACL tag configuration

## Inventory Management

### Inventory Structure

```ini
[k3s_servers]
# Control plane nodes
control-01 ansible_host=100.64.1.10 ansible_user=ubuntu k3s_node_taint=true
control-02 ansible_host=100.64.1.11 ansible_user=ubuntu k3s_node_taint=true

[k3s_agents]
# Worker nodes
worker-01 ansible_host=1.2.3.4 ansible_user=ubuntu k3s_node_label="zone=us-east"
worker-02 ansible_host=5.6.7.8 ansible_user=ubuntu k3s_node_label="zone=eu-west"

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_become=true
```

### Host Variables

Set per-host variables in inventory:

```ini
[k3s_servers]
control-01 ansible_host=100.64.1.10 k3s_node_taint=true custom_var=value

[k3s_agents]
worker-01 ansible_host=1.2.3.4 k3s_node_label="zone=us,type=compute"
```

### Group Variables

Shared variables for all hosts in a group:

```bash
# Create group vars file
vim group_vars/k3s_agents.yml
```

```yaml
---
k3s_agent_args:
  - "--node-label=environment=production"
  - "--node-label=managed-by=ansible"
```

## Variables and Configuration

### Global Variables

Located in `group_vars/all/main.yml`:

```yaml
---
# K3s configuration
k3s_version: "v1.28.5+k3s1"
k3s_server_args:
  - "--disable=traefik"
  - "--disable=servicelb"
  - "--flannel-backend=none"
  - "--disable-network-policy"

# Tailscale configuration
tailscale_enable_ssh: true
tailscale_accept_dns: false
```

### Vault Variables

Encrypted secrets in `group_vars/all/vault.yml`:

```yaml
---
vault_k3s_token: "your-encrypted-token"
vault_tailscale_key: "your-encrypted-key"
```

### Overriding Variables

**Command line:**

```bash
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml \
  -e "k3s_version=v1.29.0+k3s1"
```

**Extra vars file:**

```bash
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml \
  -e @extra-vars.yml
```

## Secret Management

### Ansible Vault

#### Create and Encrypt Vault

```bash
# Create vault file
cp group_vars/all/vault.yml.example group_vars/all/vault.yml

# Edit vault
vim group_vars/all/vault.yml

# Encrypt vault
ansible-vault encrypt group_vars/all/vault.yml
```

#### Edit Encrypted Vault

```bash
ansible-vault edit group_vars/all/vault.yml
```

#### View Encrypted Vault

```bash
ansible-vault view group_vars/all/vault.yml
```

#### Change Vault Password

```bash
ansible-vault rekey group_vars/all/vault.yml
```

#### Run Playbook with Vault

```bash
# Using password file (automatic if .vault_pass exists)
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Using password prompt
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --ask-vault-pass

# Using specific password file
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml \
  --vault-password-file=/path/to/password
```

### CI/CD Integration

For GitHub Actions or other CI/CD:

1. Store vault password as secret: `ANSIBLE_VAULT_PASSWORD`
2. In workflow:

```yaml
- name: Setup Ansible Vault
  run: echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > ansible/.vault_pass

- name: Run Ansible Playbook
  run: |
    cd ansible
    ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml
```

## Common Tasks

### Add a New Worker Node

1. **Add to inventory:**

```ini
[k3s_agents]
worker-new ansible_host=9.10.11.12 ansible_user=ubuntu k3s_node_label="zone=us-west"
```

2. **Deploy Tailscale:**

```bash
ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml --limit worker-new
```

3. **Get Tailscale IP and update inventory:**

```bash
ssh ubuntu@9.10.11.12
tailscale ip -4  # e.g., 100.64.1.30

# Update inventory with Tailscale IP
```

4. **Deploy K3s agent:**

```bash
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --tags agents --limit worker-new
```

5. **Verify:**

```bash
kubectl get nodes
```

### Remove a Worker Node

1. **Drain node:**

```bash
kubectl drain worker-old --ignore-daemonsets --delete-emptydir-data
```

2. **Delete from cluster:**

```bash
kubectl delete node worker-old
```

3. **Uninstall K3s on node:**

```bash
ssh ubuntu@worker-old
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

4. **Remove from inventory**

### Update System Packages

```bash
# Update all nodes
ansible all -i inventory.ini -m apt -a "update_cache=yes upgrade=dist" -b

# Update specific group
ansible k3s_agents -i inventory.ini -m apt -a "update_cache=yes upgrade=dist" -b

# Reboot if required
ansible all -i inventory.ini -m reboot -b
```

### Gather Facts

```bash
# Gather all facts
ansible all -i inventory.ini -m setup

# Gather specific facts
ansible all -i inventory.ini -m setup -a "filter=ansible_distribution*"

# Save facts to file
ansible all -i inventory.ini -m setup --tree /tmp/facts
```

### Run Ad-Hoc Commands

```bash
# Check disk space
ansible all -i inventory.ini -m shell -a "df -h"

# Check memory usage
ansible all -i inventory.ini -m shell -a "free -m"

# Check Tailscale status
ansible all -i inventory.ini -m shell -a "tailscale status"

# Check K3s service status
ansible k3s_servers -i inventory.ini -m systemd -a "name=k3s state=started" -b
```

## Troubleshooting

### Connection Issues

```bash
# Test connectivity
ansible all -i inventory.ini -m ping

# Test with verbose output
ansible all -i inventory.ini -m ping -vvv

# Test SSH connection
ssh -vvv ubuntu@100.64.1.10
```

### Playbook Debugging

```bash
# Dry run (check mode)
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --check

# Step through tasks
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --step

# Start at specific task
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --start-at-task="Install K3s"

# Verbose output
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml -vvv
```

### Vault Issues

```bash
# Verify vault is encrypted
file group_vars/all/vault.yml
# Expected output: ASCII text (if encrypted)

# Decrypt for debugging (BE CAREFUL)
ansible-vault decrypt group_vars/all/vault.yml
# Edit, then re-encrypt:
ansible-vault encrypt group_vars/all/vault.yml
```

### K3s Installation Issues

```bash
# Check K3s logs on control plane
ssh ubuntu@control-plane
sudo journalctl -u k3s -f

# Check K3s logs on worker
ssh ubuntu@worker
sudo journalctl -u k3s-agent -f

# Manually check K3s installation script
curl -sfL https://get.k3s.io | sh -s - --dry-run
```

### Common Error Messages

**Error: "Failed to connect to the host via ssh"**

```bash
# Check SSH key is added
ssh-add -l

# Test manual SSH connection
ssh ubuntu@host

# Check inventory hostname/IP
```

**Error: "Authentication failure"**

```bash
# Verify SSH key permissions
chmod 600 ~/.ssh/id_rsa

# Verify correct user in inventory
# ansible_user=ubuntu (not root)
```

**Error: "Vault password incorrect"**

```bash
# Verify .vault_pass content
cat .vault_pass

# Try with prompt instead
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --ask-vault-pass
```

**Error: "K3s failed to start"**

```bash
# Check system requirements
ssh ubuntu@host
sudo systemctl status k3s
sudo journalctl -u k3s -xe

# Common causes:
# - Firewall blocking ports
# - Insufficient resources
# - Conflicting services
```

---

[⬅ Back to Setup Guide](setup.md) | [Next: Helmfile Guide ➡](helmfile.md)
