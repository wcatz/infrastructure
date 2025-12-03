# Ansible Infrastructure Management

This repository provides a complete Ansible-based framework for deploying and managing Kubernetes infrastructure using k3s and Helmfile. It includes automated setup for Tailscale networking, k3s clusters, HAProxy load balancing, and application deployments.

## Features

1. **Tailscale Configuration**: Install and configure Tailscale for secure private networking between nodes
2. **k3s Cluster Setup**: Automate k3s control plane and worker node configuration
3. **HAProxy**: Set up HAProxy as a load balancer/ingress for Kubernetes
4. **Helmfile Integration**: Deploy Kubernetes workloads using Helmfile
5. **Environment Isolation**: Separate inventory configurations for development and production
6. **Extensibility**: Modular roles allow easy extension or customization

## Repository Structure

```
.
├── inventories/           # Inventory files for different environments
│   ├── development/       # Development/staging environment
│   │   └── inventory.yaml
│   └── production/        # Production environment
│       └── inventory.yaml
├── roles/                 # Reusable Ansible roles
│   ├── common/            # Common tasks (updates, basic setup)
│   │   └── tasks/main.yml
│   ├── tailscale/         # Install and configure Tailscale
│   │   └── tasks/main.yml
│   ├── kubernetes-master/ # k3s control plane setup
│   │   └── tasks/main.yml
│   ├── kubernetes-worker/ # k3s worker node setup
│   │   └── tasks/main.yml
│   ├── haproxy/           # HAProxy load balancer configuration
│   │   └── tasks/main.yml
│   └── apps/              # Kubernetes workload deployments
│       └── tasks/main.yml
├── playbooks/             # High-level orchestration playbooks
│   ├── cluster-setup.yml  # Main playbook to set up the cluster
│   ├── deploy-apps.yml    # Playbook to deploy applications
│   └── teardown.yml       # Playbook to teardown the infrastructure
├── helmfile/              # Helmfile configuration
│   ├── Helmfile.yaml      # Helmfile release definitions
│   └── values/            # Values for Helmfile deployments
│       └── example-values.yaml
├── README.md              # This file
└── LICENSE                # MIT License
```

## Prerequisites

- Ansible 2.9 or higher installed on your control machine
- SSH access to all target nodes
- Python 3 installed on all target nodes
- Sudo privileges on all target nodes
- (Optional) Tailscale auth key for private networking

## Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/wcatz/infrastructure.git
cd infrastructure
```

### 2. Configure Inventories

Edit the inventory files for your target environment:

**For Development:**
```bash
vim inventories/development/inventory.yaml
```

**For Production:**
```bash
vim inventories/production/inventory.yaml
```

Update the following in your inventory files:
- Host IP addresses (`ansible_host`)
- SSH user (`ansible_user`)
- SSH key path (`ansible_ssh_private_key_file`)
- k3s configuration variables (version, token)
- HAProxy backend servers

### 3. Set Environment Variables

Export your Tailscale auth key (if using Tailscale):

```bash
export TAILSCALE_AUTH_KEY="your-tailscale-auth-key"
```

### 4. Run the Cluster Setup Playbook

Deploy the complete infrastructure stack:

**For Development:**
```bash
ansible-playbook -i inventories/development/inventory.yaml playbooks/cluster-setup.yml
```

**For Production:**
```bash
ansible-playbook -i inventories/production/inventory.yaml playbooks/cluster-setup.yml
```

This playbook will:
- Update and configure all nodes with common packages
- Install and configure Tailscale on all nodes
- Set up k3s control plane nodes
- Join worker nodes to the cluster
- Configure HAProxy load balancer

### 5. Deploy Applications

Deploy applications to your cluster using Helmfile:

```bash
ansible-playbook -i inventories/development/inventory.yaml playbooks/deploy-apps.yml
```

### 6. Verify the Setup

Check the cluster status:

```bash
# SSH into the control plane node
ssh ubuntu@<control-plane-ip>

# Check nodes
kubectl get nodes

# Check pods
kubectl get pods --all-namespaces

# Check services
kubectl get services --all-namespaces
```

## Customization

### Adding New Roles

Create a new role directory under `roles/`:

```bash
mkdir -p roles/my-new-role/tasks
touch roles/my-new-role/tasks/main.yml
```

### Modifying Helmfile Deployments

Edit `helmfile/Helmfile.yaml` to add or modify Helm releases:

```yaml
releases:
  - name: my-app
    namespace: default
    chart: bitnami/nginx
    version: 15.4.4
    values:
      - values/my-app-values.yaml
```

Add corresponding values in `helmfile/values/`:

```bash
vim helmfile/values/my-app-values.yaml
```

### Adding Environment-Specific Configuration

Create environment-specific values files:

```bash
touch helmfile/values/development-values.yaml
touch helmfile/values/production-values.yaml
```

## Playbook Descriptions

### cluster-setup.yml

The main playbook that orchestrates the complete cluster setup:
- Runs common setup on all nodes
- Configures Tailscale networking
- Sets up k3s control plane
- Joins worker nodes
- Configures HAProxy

### deploy-apps.yml

Deploys applications to the cluster using Helmfile:
- Installs Helm and Helmfile
- Syncs Helmfile releases
- Verifies deployments

### teardown.yml

Safely tears down the infrastructure:
- Uninstalls k3s from worker and control plane nodes
- Removes HAProxy configuration
- Optionally disconnects Tailscale

**Warning:** This will destroy your cluster and all data!

## Troubleshooting

### Check Ansible Connectivity

```bash
ansible -i inventories/development/inventory.yaml all -m ping
```

### Verify k3s Installation

```bash
# On control plane node
sudo k3s kubectl get nodes

# On worker node
sudo systemctl status k3s-agent
```

### Check HAProxy Status

```bash
# On HAProxy node
sudo systemctl status haproxy
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

### View Helmfile Deployments

```bash
# On control plane node
cd /opt/helmfile
helmfile list
```

## Security Considerations

1. **Change Default Tokens**: Update `k3s_token` in inventory files
2. **Use SSH Keys**: Configure SSH key-based authentication
3. **Secure Tailscale**: Use ephemeral auth keys or ACLs
4. **Network Policies**: Implement Kubernetes network policies
5. **Secrets Management**: Use Ansible Vault for sensitive data

## Contributing

Contributions are welcome! Please submit pull requests or open issues for any improvements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues or questions, please open an issue in the GitHub repository.