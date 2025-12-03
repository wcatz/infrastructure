# Ansible Configuration

This directory contains Ansible playbooks and roles for infrastructure automation.

## Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── inventory.ini.example    # Inventory template
├── playbooks/              # Ansible playbooks
│   └── deploy-haproxy.yaml # HAProxy deployment playbook
└── roles/                  # Ansible roles
    └── haproxy/           # HAProxy role
        ├── defaults/      # Default variables
        ├── handlers/      # Service handlers
        ├── tasks/         # Main tasks
        └── templates/     # Configuration templates
```

## HAProxy Role

The HAProxy role deploys and configures HAProxy as a TCP/UDP load balancer for non-HTTP services.

### Supported Services

- **TCP Services**: MySQL (3306), PostgreSQL, Redis, etc.
- **UDP Services**: WireGuard (51820), DNS, etc.

### Usage

1. **Create an inventory file**:
   ```bash
   cp inventory.ini.example inventory.ini
   # Edit inventory.ini with your server details
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
