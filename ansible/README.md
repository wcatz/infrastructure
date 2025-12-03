# Ansible Configuration

This directory contains Ansible playbooks and roles for infrastructure automation.

## Structure

```
ansible/
├── ansible.cfg                      # Ansible configuration
├── inventory.ini.example            # Inventory template
├── playbooks/                       # Ansible playbooks
│   ├── configure-base-system.yaml  # Hostname + Tailscale setup
│   ├── configure-hostname.yaml     # Set system hostname
│   ├── setup-tailscale.yaml        # Install and configure Tailscale
│   ├── deploy-k3s.yaml             # k3s cluster deployment
│   └── deploy-haproxy.yaml         # HAProxy deployment playbook
└── roles/                           # Ansible roles
    ├── hostname/                    # Hostname configuration role
    │   ├── defaults/                # Default variables
    │   └── tasks/                   # Main tasks
    ├── tailscale/                   # Tailscale VPN role
    │   ├── defaults/                # Default variables
    │   ├── handlers/                # Service handlers
    │   └── tasks/                   # Main tasks
    ├── k3s/                         # k3s role (Traefik disabled)
    │   ├── defaults/                # Default variables
    │   ├── handlers/                # Service handlers
    │   └── tasks/                   # Main tasks
    └── haproxy/                     # HAProxy role
        ├── defaults/                # Default variables
        ├── handlers/                # Service handlers
        ├── tasks/                   # Main tasks
        └── templates/               # Configuration templates
```

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

The k3s role deploys a Kubernetes cluster with Traefik disabled, allowing HAProxy to function as the ingress controller.

### Key Features

- **Traefik Disabled**: HAProxy serves as the ingress controller
- **Lightweight**: k3s is a minimal Kubernetes distribution
- **Server/Agent Support**: Deploy control plane and worker nodes
- **Configurable**: Customize network settings, components, etc.

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

### Configuration Options

Edit `roles/k3s/defaults/main.yaml`:

- `k3s_version`: k3s version to install (default: v1.28.5+k3s1)
- `k3s_server_args`: Additional server arguments (Traefik disabled by default)
- `k3s_cluster_cidr`: Pod network CIDR (default: 10.42.0.0/16)
- `k3s_service_cidr`: Service network CIDR (default: 10.43.0.0/16)
- `k3s_tls_san`: Additional TLS SANs for API server certificate

After k3s is deployed, use Helmfile to install HAProxy ingress controller.

## HAProxy Role

The HAProxy role deploys and configures HAProxy as a TCP/UDP load balancer for non-HTTP services.

### Supported Services

- **TCP Services**: MySQL (3306), PostgreSQL, Redis, etc.
- **UDP Services**: WireGuard (51820), DNS, etc.

### Usage

1. **Create an inventory file**:
   ```bash
   cp inventory.ini.example inventory.ini
   # Edit inventory.ini with your HAProxy server details
   ```

2. **Customize HAProxy configuration** (optional):
   
   Edit `roles/haproxy/defaults/main.yaml` or override in the playbook:
   
   ```yaml
   haproxy_tcp_backends:
     - name: mysql
       port: 3306
       mode: tcp
       balance: roundrobin
       servers:
         - name: mysql-1
           address: 192.168.1.10
           port: 3306
           check: true
           check_interval: 2s
         - name: mysql-2
           address: 192.168.1.11
           port: 3306
           check: true
           check_interval: 2s
   
   haproxy_udp_backends:
     - name: wireguard
       port: 51820
       mode: udp
       balance: roundrobin
       servers:
         - name: wireguard-1
           address: 192.168.1.20
           port: 51820
   ```

3. **Deploy HAProxy**:
   ```bash
   cd ansible
   ansible-playbook playbooks/deploy-haproxy.yaml
   ```

4. **Verify deployment**:
   ```bash
   # Check HAProxy status
   ansible haproxy_servers -m shell -a "systemctl status haproxy"
   
   # View HAProxy stats
   curl http://<haproxy-server>:8404/stats
   ```

### Configuration Options

#### Global Settings
- `haproxy_global.maxconn`: Maximum connections (default: 4096)
- `haproxy_global.log_level`: Log level (default: info)

#### Default Settings
- `haproxy_defaults.timeout_connect`: Connection timeout (default: 5s)
- `haproxy_defaults.timeout_client`: Client timeout (default: 50s)
- `haproxy_defaults.timeout_server`: Server timeout (default: 50s)

#### Backend Configuration
Each backend supports:
- `name`: Backend service name
- `port`: Frontend listening port
- `mode`: tcp or udp
- `balance`: Load balancing algorithm (roundrobin, leastconn, source)
- `servers`: List of backend servers
  - `name`: Server identifier
  - `address`: Server IP address
  - `port`: Server port
  - `check`: Enable health checks (TCP only)
  - `check_interval`: Health check interval (TCP only)

### Monitoring

HAProxy provides a statistics page at `http://<haproxy-server>:8404/stats` showing:
- Backend server status
- Connection statistics
- Health check results
- Traffic metrics

### Security Considerations

1. **Firewall Rules**: The role automatically opens required ports using UFW (Debian-based systems)
2. **Access Control**: Configure IP whitelisting in the haproxy.cfg template if needed
3. **Stats Page**: Consider restricting access to the stats page (port 8404) using firewall rules

## Prerequisites

- Ansible 2.9 or later
- Python 3.6 or later on control node and managed nodes
- SSH access to target servers
- Sudo privileges on target servers

## Example: MySQL Load Balancing

```yaml
haproxy_tcp_backends:
  - name: mysql
    port: 3306
    mode: tcp
    balance: roundrobin
    servers:
      - name: mysql-primary
        address: 10.0.1.10
        port: 3306
        check: true
        check_interval: 2s
      - name: mysql-replica-1
        address: 10.0.1.11
        port: 3306
        check: true
        check_interval: 2s
      - name: mysql-replica-2
        address: 10.0.1.12
        port: 3306
        check: true
        check_interval: 2s
```

## Example: WireGuard VPN Load Balancing

```yaml
haproxy_udp_backends:
  - name: wireguard
    port: 51820
    mode: udp
    balance: roundrobin
    servers:
      - name: wireguard-server-1
        address: 10.0.2.10
        port: 51820
      - name: wireguard-server-2
        address: 10.0.2.11
        port: 51820
```

## Troubleshooting

### Check HAProxy Configuration
```bash
ansible haproxy_servers -m shell -a "haproxy -c -f /etc/haproxy/haproxy.cfg"
```

### View HAProxy Logs
```bash
ansible haproxy_servers -m shell -a "journalctl -u haproxy -n 50"
```

### Test Backend Connectivity
```bash
# TCP test
nc -zv <backend-server> 3306

# UDP test
nc -zvu <backend-server> 51820
```
