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
│   └── deploy-k3s.yaml             # k3s cluster deployment
└── roles/                           # Ansible roles
    ├── hostname/                    # Hostname configuration role
    │   ├── defaults/                # Default variables
    │   └── tasks/                   # Main tasks
    ├── tailscale/                   # Tailscale VPN role
    │   ├── defaults/                # Default variables
    │   ├── handlers/                # Service handlers
    │   └── tasks/                   # Main tasks
    └── k3s/                         # k3s role (Traefik disabled)
        ├── defaults/                # Default variables
        ├── handlers/                # Service handlers
        └── tasks/                   # Main tasks
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

The k3s role deploys a Kubernetes cluster with Traefik disabled, allowing HAProxy Ingress Controller (deployed via Helmfile) to function as the ingress controller.

### Key Features

- **Traefik Disabled**: HAProxy Ingress Controller (deployed via Helmfile) serves as the ingress controller
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
