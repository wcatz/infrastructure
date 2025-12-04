# Infrastructure Management

This repository contains infrastructure management tools and GitOps workflows for Kubernetes and non-Kubernetes infrastructure.

## Traffic Flow Architecture

```
                         Internet Users
                                │
                                ▼
                              DNS
                                │
                ┌───────────────┴───────────────┐
                │                               │
                ▼                               ▼
        ┌───────────────┐              ┌───────────────┐
        │  Cloudflare   │              │    HAProxy    │
        │    Tunnel     │              │ Load Balancer │
        │   (HTTP/S)    │              │  (TCP/UDP)    │
        └───────────────┘              └───────────────┘
                │                               │
                │                               │
                └───────────────┬───────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │      HAProxy LB       │
                    │ Ingress Controller    │
                    └───────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Kubernetes Cluster (k3s)                               │
│                                                                              │
│         ┌────────────────────────┬────────────────────────┐                 │
│         │                        │                        │                 │
│         ▼                        ▼                        ▼                 │
│  ┌──────────┐            ┌──────────┐            ┌──────────┐              │
│  │   Web    │            │  MySQL   │            │WireGuard │              │
│  │   Pods   │            │   Pod    │            │   Pod    │              │
│  │          │            │ :30306   │            │ :51820   │              │
│  └──────────┘            └──────────┘            └──────────┘              │
│                                                                              │
└────────────────────────────────────┬────────────────────────────────────────┘
                                     │
                                     ▼
                                  GitOps
```

### Traffic Routing Strategy

- **HTTP/HTTPS Traffic via Cloudflared**: 
  - Flow: Internet → DNS → Cloudflare Tunnel → HAProxy Ingress Controller → Kubernetes Services
  - Benefits: DDoS protection, global CDN, SSL/TLS termination, Zero Trust security, no exposed ports
  - Use cases: Web applications, APIs, dashboards (Grafana), admin interfaces
  - Configuration: Managed via Helmfile, credentials stored in Kubernetes secrets

- **TCP/UDP Traffic via HAProxy Load Balancer**: 
  - Flow: Internet → DNS → HAProxy Load Balancer → Kubernetes Worker NodePorts → Pod Services
  - Benefits: High performance, health checking, protocol flexibility, automatic failover, standard ports
  - Use cases: MySQL databases (3306), WireGuard VPN (51820), DNS servers (53), Redis, PostgreSQL
  - Configuration: Deployed via Ansible, balances across multiple worker nodes
  - See [ansible/HAPROXY_NODEPORT.md](ansible/HAPROXY_NODEPORT.md) for detailed configuration

## Infrastructure Stack Components

### Core Infrastructure
- **Kubernetes Distribution**: k3s (lightweight, production-ready)
- **Load Balancing**: 
  - HAProxy TCP/UDP load balancer (external, Ansible-deployed)
  - HAProxy Ingress Controller (internal, Helmfile-deployed)
- **Secure Access**: Cloudflared tunnels for Zero Trust HTTP/HTTPS access
- **Automation**: GitHub Actions for GitOps workflows

### Monitoring & Observability
- **Prometheus**: Metrics collection and alerting (namespace: `monitoring`)
- **Grafana**: Visualization dashboards (accessible via Cloudflared tunnel)
- **HAProxy Stats**: Built-in statistics page for load balancer monitoring
- **Health Checks**: Automated health checking across all services

### Security & Secrets Management
- **Kubernetes Secrets**: Native secret storage for sensitive data
- **Cloudflared Credentials**: Stored as Kubernetes secrets in `cloudflare` namespace
- **NetworkPolicy**: Network segmentation and pod-to-pod communication control
- **Zero Trust Access**: Cloudflare Access for authentication and authorization
- **Secret Suppression**: GitHub Actions workflows configured with `--suppress-secrets`

### Backup & Disaster Recovery
- **Configuration Backup**: All configurations in Git (GitOps approach)
- **Helm Release State**: Managed by Helmfile with declarative specifications
- **Database Backups**: Integration-ready for external backup solutions
- **Infrastructure as Code**: Complete reproducibility via Ansible and Helmfile

### Multi-Environment Support
- **Environments**: Development, Staging, and Production configurations
- **Environment-Specific Values**: Separate configurations per environment
- **Isolated Deployments**: Dedicated tunnels and resources per environment
- **Easy Promotion**: Consistent structure for smooth environment promotions

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

## Quick Start Guide

This section provides a prioritized setup sequence for deploying the complete infrastructure stack.

### Prerequisites

- Target servers for k3s cluster (minimum 1 server + 1 agent, recommended 1 server + 2+ agents)
- HAProxy load balancer server (can be separate or on server node)
- Ansible installed on control machine
- SSH access to all target servers
- Domain name managed by Cloudflare (for Cloudflared tunnels)
- GitHub account with Actions enabled

### Setup Sequence

#### Phase 1: Core Infrastructure (Required)

**1. Deploy Kubernetes (k3s) Cluster**
```bash
cd ansible
cp inventory.ini.example inventory.ini
# Edit inventory.ini - add servers to [k3s_servers] and [k3s_agents] groups
# Set k3s_token in group_vars or playbook
ansible-playbook playbooks/deploy-k3s.yaml
```
- ⏱️ Time: 10-15 minutes
- 📚 Details: See [ansible/README.md](ansible/README.md)

**2. Deploy HAProxy TCP/UDP Load Balancer**
```bash
cd ansible
# Edit inventory.ini - add HAProxy server to [haproxy] group
# Configure backends in roles/haproxy/defaults/main.yaml or playbook vars
ansible-playbook playbooks/deploy-haproxy.yaml
```
- ⏱️ Time: 5-10 minutes
- 📚 Details: See [ansible/HAPROXY_NODEPORT.md](ansible/HAPROXY_NODEPORT.md)

**3. Install Helmfile Prerequisites**
```bash
# Install Helm
brew install helm  # macOS
# or: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install helm-diff plugin
helm plugin install https://github.com/databus23/helm-diff --version v3.6.0

# Install Helmfile
brew install helmfile  # macOS
# or: Download from https://github.com/helmfile/helmfile/releases
```
- ⏱️ Time: 5 minutes
- 📚 Details: See [helmfile/README.md](helmfile/README.md)

**4. Deploy Core Services (Prometheus, HAProxy Ingress)**
```bash
cd helmfile
# Verify kubeconfig is set
export KUBECONFIG=/path/to/kubeconfig

# Review what will be deployed
helmfile diff

# Deploy
helmfile apply
```
- ⏱️ Time: 10-15 minutes
- 📚 Details: See [helmfile/README.md](helmfile/README.md)

#### Phase 2: Secure Access (Recommended)

**5. Configure Cloudflared Tunnel**
```bash
# Install cloudflared CLI
brew install cloudflare/cloudflare/cloudflared  # macOS

# Create tunnel
cloudflared tunnel login
cloudflared tunnel create infrastructure-tunnel

# Create Kubernetes secret
kubectl create namespace cloudflare
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
  -n cloudflare

# Configure DNS
cloudflared tunnel route dns infrastructure-tunnel app.example.com
```
- ⏱️ Time: 15-20 minutes
- 📚 Details: See [helmfile/CLOUDFLARED_SETUP.md](helmfile/CLOUDFLARED_SETUP.md)

**6. Enable and Deploy Cloudflared**
```bash
cd helmfile
# Edit config/enabled.yaml and set cloudflared: true
# Edit values/cloudflared-values.yaml with tunnel details

helmfile -l name=cloudflared apply
```
- ⏱️ Time: 5 minutes

#### Phase 3: GitOps Automation (Recommended)

**7. Configure GitHub Actions**
```bash
# In GitHub repository settings:
# 1. Add KUBECONFIG secret (base64-encoded kubeconfig)
# 2. Configure branch protection for main/master
# 3. Enable Actions workflows
```
- ⏱️ Time: 10 minutes
- 📚 Details: Workflows are in `.github/workflows/`

**8. Test GitOps Workflow**
```bash
# Make a change to helmfile/config/enabled.yaml
# Create a pull request
# Review the automatic diff comment
# Merge PR
# Manually trigger helmfile-apply workflow from Actions tab
```
- ⏱️ Time: 5-10 minutes

#### Phase 4: Monitoring & Security (Optional but Recommended)

**9. Access Prometheus & Grafana**
```bash
# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# If Grafana is deployed, access via Cloudflared tunnel
# Add ingress rule in cloudflared-values.yaml:
# - hostname: grafana.example.com
#   service: http://grafana.monitoring.svc.cluster.local:80
```
- ⏱️ Time: 5 minutes
- 📚 Note: Grafana deployment optional, can be added to helmfile

**10. Configure NetworkPolicy (Optional)**
```bash
# Create NetworkPolicy resources for pod-to-pod communication control
# Example policies should be added to namespace-specific configurations
```
- ⏱️ Time: Variable, depends on security requirements

### Post-Setup Validation

```bash
# Verify k3s cluster
kubectl get nodes -o wide

# Verify Helmfile deployments
helmfile status

# Check HAProxy load balancer
curl http://<haproxy-ip>:8404/stats

# Test Cloudflared tunnel
curl https://app.example.com

# Verify monitoring
kubectl get pods -n monitoring
```

### Next Steps

1. **Configure DNS**: See [DNS_SETUP.md](DNS_SETUP.md)
2. **Add Applications**: Follow [helmfile/README.md](helmfile/README.md#adding-new-applications)
3. **Set Up Backups**: Configure backup solutions for databases and persistent volumes
4. **Review Security**: Implement NetworkPolicies and review secret management
5. **Monitor**: Set up Grafana dashboards and Prometheus alerts

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

This repository uses GitHub Actions to implement GitOps practices with Helmfile, providing automated validation, deployment previews, and controlled releases.

### Automation Benefits

- **Continuous Validation**: Every PR is automatically validated for YAML syntax and Helmfile correctness
- **Deployment Preview**: See exactly what changes will be applied before merging
- **Audit Trail**: All changes tracked in Git with full history
- **Controlled Deployments**: Manual approval required for production deployments
- **Secret Security**: Workflows use `--suppress-secrets` to prevent credential exposure
- **Multi-Environment**: Support for dev, staging, and production environments

### Helmfile Diff Workflow

The `helmfile-diff` workflow automatically runs on all pull requests that modify the `helmfile/` or `ansible/` directories. It provides detailed validation and preview of changes.

**Features:**
- YAML linting for syntax validation
- Helmfile template rendering verification
- Detailed diff of changes that would be applied
- Automatic PR comment with diff output
- No cluster modifications (read-only operation)

**How it works:**
1. Create a pull request with changes to Helmfile or Ansible configurations
2. The workflow automatically triggers and runs validation
3. YAML files are linted for syntax errors
4. `helmfile diff` generates a preview of changes
5. A comment is posted to the PR showing the proposed changes
6. Review the diff output and address any issues
7. Iterate until the diff looks correct
8. Merge the PR after approval

### Manual Helmfile Apply Workflow

The `helmfile-apply` workflow allows authorized users to manually deploy changes to the Kubernetes cluster after PR approval and merge.

**Features:**
- Pre-deployment validation with YAML linting
- Pre-deployment diff preview
- Environment selection (default, dev, staging, production)
- Post-deployment verification
- Deployment audit trail with commit SHA and timestamp

**How to trigger:**
1. Ensure PR is merged to main branch
2. Navigate to the "Actions" tab in GitHub
3. Select "Helmfile Apply" workflow
4. Click "Run workflow"
5. Select the target environment (default, dev, staging, or production)
6. Click "Run workflow" to start the deployment
7. Monitor the workflow execution logs
8. Verify successful deployment

**Prerequisites:**
- Kubernetes cluster accessible from GitHub Actions
- Configure `KUBECONFIG` secret with base64-encoded kubeconfig content
- Ensure proper RBAC permissions are configured in the cluster
- Branch protection rules configured for production environment

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

This repository includes configurations for the following core services:

### Monitoring Stack
- **Prometheus**: Metrics collection and alerting (namespace: `monitoring`)
  - Collects metrics from all Kubernetes resources
  - Configured with service discovery
  - Alerting rules can be customized in values files
  - Accessible via port-forward or Cloudflared tunnel
  
- **Grafana** (Optional): Visualization dashboards
  - Can be added to helmfile by creating values/grafana-values.yaml
  - Integrates with Prometheus for metrics visualization
  - Access via Cloudflared tunnel for secure remote access
  - Pre-built dashboards for k8s, HAProxy, and system metrics

### Ingress & Load Balancing
- **HAProxy Ingress Controller**: Kubernetes HTTP/HTTPS ingress (namespace: `haproxy-ingress`)
  - High-performance Layer 7 load balancing
  - SSL/TLS termination
  - Advanced routing rules
  - Horizontal pod autoscaling enabled
  - Prometheus metrics integration

- **HAProxy TCP/UDP Load Balancer** (External): NodePort load balancing
  - Deployed via Ansible on dedicated server(s)
  - Balances traffic across Kubernetes worker nodes
  - Supports both TCP and UDP protocols
  - Health checks and automatic failover
  - Statistics dashboard on port 8404

### Secure Access
- **Cloudflared**: Cloudflare tunnel for secure HTTP/HTTPS ingress (namespace: `cloudflare`)
  - Disabled by default, enable in config/enabled.yaml after setup
  - Provides Zero Trust security and DDoS protection
  - No exposed ports required (outbound-only connections)
  - Multi-environment support (dev/staging/prod tunnels)
  - Tunnel credentials stored in Kubernetes secrets

### GitOps & Automation
- **GitHub Actions Workflows**:
  - `helmfile-diff`: Automatic PR validation and diff preview
  - `helmfile-apply`: Manual deployment to cluster
  - YAML linting and validation
  - Secret suppression for security

### Security Features
- **Kubernetes Secrets**: Secure storage for sensitive data
- **NetworkPolicy**: Network segmentation (add as needed per namespace)
- **Cloudflare Access**: Authentication layer for Cloudflared tunnels
- **RBAC**: Kubernetes role-based access control
- **TLS/SSL**: Automated certificate management via ingress

### Backup & Disaster Recovery
- **GitOps Approach**: All configurations version-controlled in Git
- **Helmfile State**: Declarative release management
- **Database Backups**: Ready for integration with backup solutions like Velero
- **Documentation**: Comprehensive setup and recovery procedures

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

### Best Practices

- **Never commit sensitive data**: Secrets, API keys, passwords, and certificates must never be committed to Git
- **Use Kubernetes Secrets**: Store sensitive data in Kubernetes secrets, created via kubectl or external secret managers
- **Secret Suppression**: All GitHub Actions workflows use `--suppress-secrets` flag to prevent credential exposure in logs
- **Branch Protection**: Configure repository protection rules for production deployments
- **Environment Secrets**: Use GitHub environment secrets for environment-specific credentials

### Secret Management

**Kubernetes Secrets Creation:**
```bash
# Create secret from file
kubectl create secret generic app-secret \
  --from-file=config.json=/path/to/config.json \
  -n namespace

# Create secret from literal values
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=securepassword \
  -n namespace

# Cloudflared tunnel credentials
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=$HOME/.cloudflared/<TUNNEL-ID>.json \
  -n cloudflare
```

**External Secret Management:**
- Consider integrating with external secret managers like HashiCorp Vault, AWS Secrets Manager, or Azure Key Vault
- Use Kubernetes External Secrets Operator for automatic secret synchronization
- Rotate secrets regularly and update references in deployments

### NetworkPolicy

NetworkPolicy resources provide network segmentation and control pod-to-pod communication:

```yaml
# Example: Deny all ingress traffic by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress

# Example: Allow traffic only from ingress controller
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-ingress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: haproxy-ingress
```

**NetworkPolicy Best Practices:**
- Implement default-deny policies for production namespaces
- Allow only necessary traffic between pods
- Use namespace selectors for cross-namespace communication
- Test policies in dev/staging before production deployment
- Document network flow requirements
- Note: The namespace selector uses the standard Kubernetes label `kubernetes.io/metadata.name` (available in K8s 1.22+)

### Access Control

- **RBAC**: Kubernetes role-based access control configured per namespace
- **Cloudflare Access**: Zero Trust authentication for Cloudflared tunnels
- **SSH Access**: Use SSH keys, disable password authentication on servers
- **kubeconfig**: Protect kubeconfig files with appropriate file permissions (600)
- **Service Accounts**: Use dedicated service accounts with minimal required permissions

### Security Monitoring

- **Prometheus Alerts**: Configure alerts for security-relevant events
- **Audit Logs**: Enable Kubernetes audit logging for compliance
- **Network Monitoring**: Monitor network traffic for anomalies
- **HAProxy Logs**: Review HAProxy access logs for suspicious activity
- **Regular Updates**: Keep k3s, Helm charts, and system packages updated

## License
This project is licensed under the MIT License.