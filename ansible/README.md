# Ansible Configuration

This directory contains Ansible playbooks and roles for infrastructure automation.

## Structure

```
ansible/
├── ansible.cfg                      # Ansible configuration
├── inventory.ini.example            # Inventory template
├── inventory-dev.ini.example        # Development inventory
├── inventory-staging.ini.example    # Staging inventory
├── inventory-prod.ini.example       # Production inventory
├── playbooks/                       # Ansible playbooks
│   ├── configure-base-system.yaml  # Hostname + Tailscale setup
│   ├── configure-hostname.yaml     # Set system hostname
│   ├── setup-tailscale.yaml        # Install and configure Tailscale
│   ├── deploy-k3s.yaml             # k3s cluster deployment
│   └── deploy-haproxy.yaml         # HAProxy load balancer deployment
└── roles/                           # Ansible roles
    ├── hostname/                    # Hostname configuration role
    │   ├── defaults/                # Default variables
    │   └── tasks/                   # Main tasks
    ├── tailscale/                   # Tailscale VPN role
    │   ├── defaults/                # Default variables
    │   ├── handlers/                # Service handlers
    │   └── tasks/                   # Main tasks
    ├── haproxy/                     # HAProxy load balancer role
    │   ├── defaults/                # Default variables
    │   ├── handlers/                # Service handlers
    │   ├── tasks/                   # Main tasks
    │   └── templates/               # Configuration templates
    └── k3s/                         # k3s role (Traefik disabled)
        ├── defaults/                # Default variables
        ├── handlers/                # Service handlers
        └── tasks/                   # Main tasks
```

## Quick Start

### 1. Prepare Inventory

```bash
# Copy the appropriate inventory template
cp inventory.ini.example inventory.ini

# Or use environment-specific templates
cp inventory-dev.ini.example inventory-dev.ini
cp inventory-staging.ini.example inventory-staging.ini
cp inventory-prod.ini.example inventory-prod.ini

# Edit with your server details
vim inventory.ini
```

### 2. Deploy Infrastructure

```bash
# Deploy k3s cluster
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml

# Deploy HAProxy load balancer
ansible-playbook -i inventory.ini playbooks/deploy-haproxy.yaml

# Or both at once
ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml playbooks/deploy-haproxy.yaml
```

## HAProxy Role

The HAProxy role deploys and configures HAProxy as a load balancer for Kubernetes NodePort services.

### Key Features

- **TCP/UDP Load Balancing**: Support for both TCP and UDP protocols
- **Health Checks**: Automatic backend health monitoring
- **NodePort Integration**: Load balance traffic across k3s worker nodes
- **Stats Interface**: Built-in statistics dashboard
- **Flexible Configuration**: Easy to add new services

### Usage

1. **Configure inventory** with HAProxy servers and k3s workers:

   ```ini
   [haproxy_servers]
   haproxy-01 ansible_host=192.168.1.5 ansible_user=ubuntu

   [haproxy_servers:vars]
   # k3s worker nodes for backend pool
   k3s_workers:
     - host: 192.168.1.11
       name: worker-01
     - host: 192.168.1.12
       name: worker-02
     - host: 192.168.1.13
       name: worker-03

   # Services to load balance
   haproxy_services:
     - name: mysql
       frontend_port: 3306
       backend_port: 30306
       mode: tcp
       balance: leastconn
       check_interval: 2s
   ```

2. **Deploy HAProxy**:

   ```bash
   ansible-playbook -i inventory.ini playbooks/deploy-haproxy.yaml
   ```

3. **Access stats interface**:

   ```
   http://<haproxy-host>:8404/stats
   ```

### Configuration Options

Edit `roles/haproxy/defaults/main.yaml` or set in inventory:

- `k3s_workers`: List of k3s worker nodes
- `haproxy_services`: Services to load balance
- `haproxy_stats_enabled`: Enable/disable stats interface
- `haproxy_stats_port`: Stats interface port (default: 8404)
- `haproxy_global_maxconn`: Maximum concurrent connections
- `haproxy_defaults_timeout_*`: Timeout settings

### Example Services

```yaml
haproxy_services:
  # MySQL database
  - name: mysql
    frontend_port: 3306
    backend_port: 30306
    mode: tcp
    balance: leastconn
    check_interval: 2s
    check_timeout: 1s
  
  # PostgreSQL database
  - name: postgres
    frontend_port: 5432
    backend_port: 30432
    mode: tcp
    balance: leastconn
    check_interval: 2s
  
  # WireGuard VPN
  - name: wireguard
    frontend_port: 51820
    backend_port: 30820
    mode: tcp
    balance: roundrobin
    check_interval: 5s
  
  # Redis cache
  - name: redis
    frontend_port: 6379
    backend_port: 30379
    mode: tcp
    balance: leastconn
```

### Verification

```bash
# Check HAProxy status
ansible haproxy_servers -i inventory.ini -m shell -a "systemctl status haproxy"

# Test service connectivity
mysql -h <haproxy-host> -P 3306 -u root -p

# View configuration
ansible haproxy_servers -i inventory.ini -m shell -a "cat /etc/haproxy/haproxy.cfg"
```

For more details, see [HAProxy Setup Guide](../docs/haproxy-setup.md).

## Hostname Role

The hostname role configures system hostnames across your infrastructure.

### Usage

1. **Set hostname per host** in inventory:
   ```ini
   [k3s_servers]
   server-01 ansible_host=192.168.1.10 hostname=k3s-master-01
   
   [k3s_servers:vars]
   domain=k3s.example.com
   ```

2. **Run the playbook**:
   ```bash
   ansible-playbook playbooks/configure-hostname.yaml
   ```

3. **Or set inline**:
   ```bash
   ansible-playbook playbooks/configure-hostname.yaml -e "hostname=my-server domain=example.com"
   ```

## Tailscale Role

The Tailscale role installs and configures Tailscale VPN on your servers.

### Key Features

- **Zero-config VPN**: Automatic mesh networking
- **Secure**: WireGuard-based encryption
- **Cross-platform**: Works on Linux, macOS, Windows
- **SSH support**: Optional Tailscale SSH

### Usage

1. **Get auth key** from [Tailscale Admin](https://login.tailscale.com/admin/settings/keys)

2. **Set auth key** in group_vars/all.yml:
   ```yaml
   tailscale_auth_key: "tskey-auth-xxxxx-yyyyy"
   tailscale_args: "--accept-routes"
   tailscale_enable_ssh: false
   ```

3. **Deploy Tailscale**:
   ```bash
   ansible-playbook playbooks/setup-tailscale.yaml
   ```

4. **Or pass auth key inline**:
   ```bash
   ansible-playbook playbooks/setup-tailscale.yaml -e "tailscale_auth_key=tskey-auth-xxxxx"
   ```

### Configuration Options

Edit `roles/tailscale/defaults/main.yaml`:

- `tailscale_auth_key`: Authentication key (required)
- `tailscale_args`: Additional arguments for `tailscale up`
- `tailscale_enable_ssh`: Enable Tailscale SSH (default: false)
- `tailscale_accept_dns`: Accept Tailscale DNS (default: true)
- `tailscale_advertise_tags`: Tags for ACL rules (default: [])

Example with tags:
```yaml
tailscale_advertise_tags:
  - "tag:server"
  - "tag:k3s"
```

## k3s Role

The k3s role deploys a Kubernetes cluster with Traefik disabled, allowing HAProxy Ingress Controller (deployed via Helmfile) to function as the ingress controller.

### Key Features

- **Traefik Disabled**: HAProxy Ingress Controller (deployed via Helmfile) serves as the ingress controller
- **Lightweight**: k3s is a minimal Kubernetes distribution
- **Server/Agent Support**: Deploy control plane and worker nodes
- **Configurable**: Customize network settings, components, etc.
- **Secret Seeding**: Optionally seed initial secrets from SOPS-encrypted files

### Usage

1. **Create an inventory file**:
   ```bash
   cp inventory.ini.example inventory.ini
   # Edit inventory.ini - add servers to [k3s_servers] and [k3s_agents]
   ```

2. **Set k3s token** (in playbook or group_vars):
   ```yaml
   k3s_token: "your-secure-random-token"
   ```
   
   Generate token: `openssl rand -hex 32`

3. **Deploy k3s**:
   ```bash
   ansible-playbook playbooks/deploy-k3s.yaml
   ```

4. **Verify installation**:
   ```bash
   ansible k3s_servers -m shell -a "kubectl get nodes"
   ```

### Secret Seeding (Optional)

The deploy-k3s playbook can automatically deploy SOPS-encrypted secrets to the cluster during initial setup.

1. **Prepare encrypted secrets**:

   ```bash
   # Create secrets directory
   mkdir -p secrets/prod
   
   # Create a secret
   cat > secrets/prod/database.yaml <<EOF
   apiVersion: v1
   kind: Secret
   metadata:
     name: database-credentials
     namespace: production
   type: Opaque
   stringData:
     username: dbuser
     password: supersecret123
   EOF
   
   # Encrypt with SOPS
   export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
   sops -e -i secrets/prod/database.yaml
   ```

2. **Enable secret seeding** in playbook:

   ```bash
   ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml \
     -e "seed_secrets=true" \
     -e "secrets_dir=../secrets/prod"
   ```

3. **Or configure in inventory**:

   ```yaml
   [k3s_servers:vars]
   seed_secrets: true
   secrets_dir: "../secrets/prod"
   ```

**Note**: Ensure SOPS age key is available on the control machine at `~/.config/sops/age/keys.txt`

For more details on secret management, see [Secrets Management Guide](../docs/secrets-management.md).
   
   Generate token: `openssl rand -hex 32`

3. **Deploy k3s**:
   ```bash
   ansible-playbook playbooks/deploy-k3s.yaml
   ```

4. **Verify installation**:
   ```bash
   ansible k3s_servers -m shell -a "kubectl get nodes"
   ```

### Configuration Options

Edit `roles/k3s/defaults/main.yaml`:

- `k3s_version`: k3s version to install (default: v1.28.5+k3s1)
- `k3s_server_args`: Additional server arguments (Traefik disabled by default)
- `k3s_cluster_cidr`: Pod network CIDR (default: 10.42.0.0/16)
- `k3s_service_cidr`: Service network CIDR (default: 10.43.0.0/16)
- `k3s_tls_san`: Additional TLS SANs for API server certificate

After k3s is deployed, use Helmfile to install HAProxy ingress controller and other services.

## Prerequisites

- Ansible 2.9 or later
- Python 3.6 or later on control node and managed nodes
- SSH access to target servers
- Sudo privileges on target servers

## Next Steps

After deploying infrastructure with Ansible:

1. **Configure kubectl access**: Copy kubeconfig from the k3s server
2. **Deploy services via Helmfile**: See [helmfile/README.md](../helmfile/README.md)
3. **Set up monitoring**: Deploy Prometheus and Grafana via Helmfile
4. **Configure ingress**: Deploy HAProxy Ingress Controller via Helmfile
