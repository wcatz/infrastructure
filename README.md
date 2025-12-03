# Infrastructure Management

This repository contains infrastructure management tools and GitOps workflows for Kubernetes and non-Kubernetes infrastructure.

## Traffic Flow Architecture

```
                    Internet Traffic
                           |
              ┌────────────┼────────────┐
              |                         |
         HTTP/HTTPS                  TCP/UDP
              |                         |
              v                         v
        ┌──────────┐             ┌──────────┐
        |Cloudflared|             | HAProxy  |
        | Tunnel   |             |TCP/UDP LB|
        └──────────┘             └──────────┘
              |                         |
              v                         v
        ┌──────────┐             ┌──────────┐
        | HAProxy  |             |  MySQL   |
        | Ingress  |             | :3306    |
        └──────────┘             └──────────┘
              |                         |
              v                         v
        ┌──────────┐             ┌──────────┐
        |   k8s    |             |WireGuard |
        | Services |             | :51820   |
        └──────────┘             └──────────┘
```

### Traffic Routing Strategy

- **HTTP/HTTPS Traffic**: 
  - Cloudflared tunnel → HAProxy Ingress Controller → Kubernetes Services
  - Benefits: DDoS protection, global CDN, SSL/TLS termination, Zero Trust security
  - Use cases: Web applications, APIs, dashboards

- **TCP/UDP Traffic**: 
  - HAProxy standalone load balancer → Kubernetes Worker NodePorts → Services
  - Benefits: High performance, health checking, protocol flexibility, automatic failover
  - Use cases: MySQL databases, WireGuard VPN, DNS servers, game servers, Redis
  - See [ansible/HAPROXY_NODEPORT.md](ansible/HAPROXY_NODEPORT.md) for detailed configuration

## Key Features

### HAProxy Load Balancing for NodePorts
- **NodePort Integration**: Load balance traffic across multiple Kubernetes worker nodes
- **Health Checks**: Automatic failover when worker nodes become unavailable
- **Standard Ports**: Expose services on standard ports (e.g., 3306 for MySQL, 51820 for WireGuard)
- **Scalability**: Add/remove worker nodes without service disruption
- **Protocol Support**: Both TCP and UDP protocols with optimized configurations

### Cloudflared Tunnel Integration
- **Zero Trust Security**: Built-in authentication and access control via Cloudflare Access
- **DDoS Protection**: Automatic protection through Cloudflare's global network
- **No Public Ports**: Outbound-only connections from cluster to Cloudflare edge
- **Multi-Environment**: Separate tunnels for dev, staging, and production
- **High Availability**: Multi-replica deployment with auto-scaling

### Multi-Environment Support
- **Dedicated Configurations**: Environment-specific values for dev, staging, and production
- **Resource Optimization**: Scaled resources based on environment requirements
- **Isolated Deployments**: Separate tunnels and configurations per environment
- **Easy Promotion**: Consistent structure across environments for smooth promotions

## Quick Links

### Documentation
- **[Helmfile Management Guide](helmfile/README.md)**: Complete guide for managing releases, environments, and deployments
- **[HAProxy NodePort Load Balancing](ansible/HAPROXY_NODEPORT.md)**: Detailed HAProxy configuration for Kubernetes NodePorts
- **[Cloudflared Setup Guide](helmfile/CLOUDFLARED_SETUP.md)**: Complete Cloudflared tunnel configuration and deployment
- **[DNS Setup Guide](DNS_SETUP.md)**: DNS configuration for both Cloudflare and HAProxy services
- **[Ansible Documentation](ansible/README.md)**: Ansible playbooks and role documentation

### Configuration Examples
- **MySQL NodePort**: See [HAPROXY_NODEPORT.md](ansible/HAPROXY_NODEPORT.md#example-1-mysql-database-nodeport)
- **WireGuard VPN**: See [HAPROXY_NODEPORT.md](ansible/HAPROXY_NODEPORT.md#example-2-wireguard-vpn-nodeport)
- **HTTP/HTTPS Services**: See [CLOUDFLARED_SETUP.md](helmfile/CLOUDFLARED_SETUP.md)
- **Multi-Environment**: See [Helmfile README](helmfile/README.md#environment-management)

### Testing and Validation
- **[Testing Guide](TESTING.md)**: Comprehensive testing procedures for all components
- **Pre-Deployment Testing**: YAML validation, template rendering, syntax checks
- **Service Testing**: HAProxy, Cloudflared, end-to-end flows
- **Failover Testing**: Simulate failures and verify automatic recovery
- **Performance Testing**: Load testing and benchmarking procedures

## Structure

- **ansible/**: Ansible playbooks and roles for infrastructure automation
  - **playbooks/**: Deployment playbooks
    - `deploy-k3s.yaml`: Deploy k3s without Traefik (for HAProxy ingress)
    - `deploy-haproxy.yaml`: Deploy HAProxy TCP/UDP load balancer for NodePorts
  - **roles/**: Ansible roles
    - `k3s/`: k3s installation role (Traefik disabled)
    - `haproxy/`: HAProxy TCP/UDP load balancer role with NodePort support
  - **README.md**: Ansible usage documentation
  - **HAPROXY_NODEPORT.md**: Complete guide for HAProxy NodePort load balancing
- **helmfile/**: Helmfile configurations for Kubernetes deployments
  - **helmfile.yaml**: Main Helmfile configuration
  - **config/**: Configuration templates (gotmpl)
    - `repositories.yaml.gotmpl`: Helm repository definitions
    - `releases.yaml.gotmpl`: Release definitions
    - `enabled.yaml`: Enable/disable specific applications
  - **values/**: Base Helm values files for each chart
  - **environments/**: Environment-specific values (dev, staging, prod)
    - `dev/`: Development environment overrides
    - `staging/`: Staging environment overrides
    - `prod/`: Production environment overrides
  - **README.md**: Helmfile management guide
  - **CLOUDFLARED_SETUP.md**: Cloudflared tunnel setup guide
- **DNS_SETUP.md**: DNS configuration guide for Cloudflare and HAProxy
- **.github/workflows/**: GitHub Actions workflows for GitOps automation
  - **helmfile-diff.yaml**: Automatic diff on pull requests
  - **helmfile-apply.yaml**: Manual deployment workflow

## GitOps Workflows

This repository uses GitHub Actions to implement GitOps practices with Helmfile.

### Helmfile Diff Workflow

The `helmfile-diff` workflow automatically runs on all pull requests that modify the `helmfile/` directory. It provides a detailed diff of changes that would be applied to the Kubernetes cluster.

**How it works:**
1. Create a pull request with changes to Helmfile configurations
2. The workflow automatically triggers and runs `helmfile diff`
3. A comment is posted to the PR showing the proposed changes
4. Review the diff output before merging

### Manual Helmfile Apply Workflow

The `helmfile-apply` workflow allows authorized users to manually deploy changes to the Kubernetes cluster after PR approval and merge.

**How to trigger:**
1. Navigate to the "Actions" tab in GitHub
2. Select "Helmfile Apply" workflow
3. Click "Run workflow"
4. Select the target environment (default, staging, or production)
5. Click "Run workflow" to start the deployment

**Prerequisites:**
- Configure Kubernetes credentials in repository secrets
- Set `KUBECONFIG` secret with base64-encoded kubeconfig content
- Ensure proper RBAC permissions are configured

## Helmfile Configuration

The Helmfile configuration is organized using gotmpl templates for better maintainability:

- `helmfile/config/repositories.yaml.gotmpl`: Helm chart repositories
- `helmfile/config/releases.yaml.gotmpl`: Application releases
- `helmfile/config/enabled.yaml`: Enable/disable applications

### Adding a New Chart

1. Add the chart repository to `helmfile/config/repositories.yaml.gotmpl`
2. Add a new release definition in `helmfile/config/releases.yaml.gotmpl`
3. Create a values file in `helmfile/values/` (e.g., `my-chart-values.yaml`)
4. Enable the app in `helmfile/config/enabled.yaml`

Example release in `releases.yaml.gotmpl`:
```yaml
{{- if $enabled.myApp | default false }}
  - name: my-app
    namespace: my-namespace
    createNamespace: true
    chart: my-repo/my-chart
    version: 1.0.0
    values:
      - values/my-app-values.yaml
{{- end }}
```

### Enabling/Disabling Applications

Edit `helmfile/config/enabled.yaml` to control which applications are deployed:

```yaml
enabled:
  prometheus: true
  haproxyIngress: true
  cloudflared: false  # Enable when tunnel credentials are configured
```

### Modifying Chart Values

1. Edit the corresponding values file in `helmfile/values/`
2. Create a pull request with your changes
3. Review the diff output posted by the workflow
4. Merge the PR after approval
5. Manually trigger the `helmfile-apply` workflow to deploy

## Deployed Applications

This repository includes configurations for:

- **Prometheus**: Monitoring and alerting stack (namespace: `monitoring`)
- **HAProxy Ingress Controller**: Kubernetes ingress controller (namespace: `haproxy-ingress`)
- **Cloudflared**: Cloudflare tunnel for secure HTTP/HTTPS ingress (namespace: `cloudflare`, disabled by default)

## k3s Installation

k3s is installed via Ansible with Traefik disabled, allowing HAProxy to serve as the ingress controller.

### Quick Start

1. **Configure inventory**:
   ```bash
   cd ansible
   cp inventory.ini.example inventory.ini
   # Edit inventory.ini - add servers to [k3s_servers] and [k3s_agents] groups
   ```

2. **Set k3s token** (in playbook or group_vars):
   ```yaml
   k3s_token: "your-secure-token-here"
   ```

3. **Deploy k3s**:
   ```bash
   ansible-playbook playbooks/deploy-k3s.yaml
   ```

4. **Verify installation**:
   ```bash
   ansible k3s_servers -m shell -a "kubectl get nodes"
   ```

The k3s cluster will be ready for HAProxy ingress controller deployment via Helmfile.

## HAProxy TCP/UDP Load Balancer

HAProxy is deployed as a standalone TCP/UDP load balancer for non-HTTP services using Ansible. This is separate from the HAProxy Ingress Controller used for Kubernetes HTTP traffic.

### Supported Services

- **TCP Services**: MySQL (3306), PostgreSQL (5432), Redis (6379), SSH, etc.
- **UDP Services**: WireGuard VPN (51820), DNS (53), QUIC, game servers, etc.

### Quick Start

1. **Configure your inventory**:
   ```bash
   cd ansible
   cp inventory.ini.example inventory.ini
   # Edit inventory.ini with your HAProxy server details
   ```

2. **Customize backend services** (edit `ansible/roles/haproxy/defaults/main.yaml` or override in playbook):
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

4. **Monitor HAProxy**:
   - Statistics page: `http://<haproxy-server>:8404/stats`
   - Check status: `systemctl status haproxy`

### Configuration Details

See [ansible/README.md](ansible/README.md) for detailed configuration options, examples, and troubleshooting.

## Cloudflared (Cloudflare Tunnel)

Cloudflared creates secure tunnels from your Kubernetes cluster to Cloudflare's edge network, providing HTTP/HTTPS ingress without exposing servers directly to the internet.

### Key Features

- **Zero Trust Security**: Built-in authentication and access control
- **DDoS Protection**: Automatic protection via Cloudflare's network
- **Global CDN**: Content delivery from Cloudflare's edge locations
- **No Open Ports**: Outbound-only connections from your cluster
- **SSL/TLS**: Automatic certificate management
- **High Availability**: Multi-replica deployment with auto-scaling

### Quick Start

1. **Install cloudflared CLI** and create a tunnel:
   ```bash
   # Install CLI (macOS)
   brew install cloudflare/cloudflare/cloudflared
   
   # Login and create tunnel
   cloudflared tunnel login
   cloudflared tunnel create infrastructure-tunnel
   ```

2. **Create Kubernetes secret** with tunnel credentials:
   ```bash
   kubectl create namespace cloudflare
   kubectl create secret generic cloudflared-credentials \
     --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
     -n cloudflare
   ```

3. **Configure DNS records**:
   ```bash
   cloudflared tunnel route dns infrastructure-tunnel app.example.com
   cloudflared tunnel route dns infrastructure-tunnel api.example.com
   ```

4. **Update Helmfile values** (`helmfile/values/cloudflared-values.yaml`):
   ```yaml
   cloudflare:
     tunnelName: "infrastructure-tunnel"
     tunnelId: "<TUNNEL-ID>"
   
   ingress:
     - hostname: app.example.com
       service: http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
     - hostname: api.example.com
       service: http://api-service.default.svc.cluster.local:8080
     - service: http_status:404
   ```

5. **Enable cloudflared** in `helmfile/config/enabled.yaml`:
   ```yaml
   enabled:
     cloudflared: true
   ```

6. **Deploy via Helmfile**:
   ```bash
   cd helmfile
   helmfile apply
   ```

### Detailed Setup

See [helmfile/CLOUDFLARED_SETUP.md](helmfile/CLOUDFLARED_SETUP.md) for:
- Complete setup instructions
- DNS configuration guide
- Ingress rule examples
- Cloudflare Access integration
- Monitoring and troubleshooting
- Security best practices

### Cloudflare DNS Management

#### Adding Services

When adding new services to expose via Cloudflare tunnel:

1. **Create DNS record**:
   ```bash
   cloudflared tunnel route dns infrastructure-tunnel newservice.example.com
   ```

2. **Add ingress rule** to `helmfile/values/cloudflared-values.yaml`:
   ```yaml
   ingress:
     - hostname: newservice.example.com
       service: http://service-name.namespace.svc.cluster.local:port
     # ... existing rules ...
     - service: http_status:404  # Keep as last rule
   ```

3. **Apply changes**:
   ```bash
   cd helmfile
   helmfile -l name=cloudflared apply
   ```

#### Wildcard Domains

For wildcard subdomains (e.g., `*.apps.example.com`):

```bash
cloudflared tunnel route dns infrastructure-tunnel "*.apps.example.com"
```

Add to ingress rules:
```yaml
ingress:
  - hostname: "*.apps.example.com"
    service: http://haproxy-ingress-controller.haproxy-ingress.svc.cluster.local:80
```

#### Managing DNS via Cloudflare Dashboard

Alternatively, manage DNS records via the Cloudflare dashboard:

1. Go to https://dash.cloudflare.com/
2. Select your domain
3. Navigate to **DNS** → **Records**
4. Add CNAME record:
   - **Name**: subdomain (e.g., `app`)
   - **Target**: `<TUNNEL-ID>.cfargotunnel.com`
   - **Proxy status**: Proxied (orange cloud icon)

### HAProxy Ingress Controller (Kubernetes)

The HAProxy Ingress Controller provides a robust alternative for managing ingress resources in the Kubernetes cluster. HAProxy is known for its high performance, reliability, and advanced load balancing features.

**Key Features:**
- High-performance Layer 7 load balancing
- Advanced traffic management with configurable timeouts
- Connection keep-alive optimization for reduced latency
- SSL/TLS termination with automatic redirects
- Prometheus metrics integration for monitoring
- Horizontal pod autoscaling for handling traffic spikes

**Configuration:**

The HAProxy ingress controller is configured via `helmfile/values/haproxy-ingress.yaml`. Key configuration options include:

- **Timeouts**: Customize client, server, and connection timeouts for optimal performance
  - `timeout-client`: Maximum time to wait for client (default: 50s)
  - `timeout-server`: Maximum time to wait for server response (default: 50s)
  - `timeout-connect`: Maximum time to establish backend connection (default: 5s)
  - `timeout-keep-alive`: Keep-alive timeout for persistent connections (default: 1m)
  - `timeout-tunnel`: Timeout for tunnel/WebSocket connections (default: 1h)

- **Keep-Alive Settings**: Configure connection pooling and health checks
  - `backend-check-interval`: Frequency of backend health checks (default: 2s)
  - `maxconn-server`: Maximum connections per backend server (default: 1000)

- **Service Configuration**:
  - `type: LoadBalancer`: Expose HAProxy as a cloud load balancer
  - `externalTrafficPolicy: Local`: Preserve client source IP addresses
  - Cloud-specific annotations can be added for provider-specific features

- **Scaling**: Horizontal pod autoscaling is enabled with:
  - Minimum 2 replicas for high availability
  - Maximum 10 replicas for handling traffic bursts
  - Auto-scaling based on CPU (80%) and memory (80%) utilization

**Modifying HAProxy Configuration:**

To customize the HAProxy ingress behavior:

1. Edit `helmfile/values/haproxy-ingress.yaml`
2. Adjust timeout values based on your application requirements
3. Configure service annotations for cloud-specific load balancer features
4. Update resource limits based on your traffic patterns
5. Modify autoscaling parameters for optimal scaling behavior
6. Create a pull request with your changes
7. Review the diff output from the automated workflow
8. Deploy changes using the `helmfile-apply` workflow after merge

**Example Use Cases:**

- **Long-running connections**: Increase `timeout-tunnel` for WebSocket applications
- **High-traffic APIs**: Adjust `maxconn-server` and autoscaling parameters
- **Strict security**: Enable SSL redirect and configure TLS settings
- **Cloud integration**: Add cloud provider annotations for advanced load balancer features

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes to the Helmfile configuration
4. Submit a pull request
5. Wait for the automatic diff workflow to complete
6. Address any review feedback
7. After merge, coordinate with maintainers to trigger deployment

## Security

- Never commit sensitive data or secrets to this repository
- Use Kubernetes secrets or external secret management tools
- The workflows use `--suppress-secrets` flag to avoid exposing sensitive data in logs
- Configure repository environments and protection rules for production deployments

## License
This project is licensed under the MIT License.