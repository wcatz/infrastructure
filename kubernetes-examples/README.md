# Kubernetes Examples

> **📚 Complete Documentation**: See [docs/operate.md#kubernetes-workload-examples](../docs/operate.md#kubernetes-workload-examples) for comprehensive workload examples.

This directory contains modular YAML templates for deploying applications to the hybrid Kubernetes cluster. These examples follow best practices and are designed to work with the control plane + worker node architecture.

## Architecture Overview

- **Control Plane Node**: Behind CGNAT, runs only K3s control plane (tainted to prevent workload scheduling)
- **Worker Nodes**: Public IP (e.g., Netcup VPS), runs all application workloads
- **Ingress**: Cloudflared on worker nodes routes HTTP/HTTPS traffic through Cloudflare
- **Networking**: Tailscale provides secure inter-node communication

## Available Examples

### 1. Deployment (`deployment.yaml`)
- Standard application deployment template
- Configured with resource limits, health checks, and security contexts
- Automatically scheduled on worker nodes (control plane is tainted)
- Includes pod anti-affinity for high availability

### 2. Service (`service.yaml`)
- ClusterIP: Internal cluster communication
- NodePort: Direct access via worker node IP
- Headless: For StatefulSets requiring stable network identities
- LoadBalancer example (commented out - not typically used in this setup)

### 3. Ingress (`ingress.yaml`)
- Standard Kubernetes Ingress examples (optional)
- Cloudflared can route directly to services without Ingress resources
- Examples of host-based and path-based routing if using Ingress

### 4. ConfigMap (`configmap.yaml`)
- Non-sensitive configuration data
- Examples of key-value pairs and file content
- Different methods to consume ConfigMaps (env vars, volumes)

### 5. Secret (`secret.yaml`)
- Sensitive data storage (passwords, API keys, certificates)
- **Important**: Use SOPS to encrypt before committing to Git
- Examples of different secret types and usage patterns

## Usage

### Basic Deployment

1. **Copy and customize a template**:
   ```bash
   cp kubernetes-examples/deployment.yaml my-app-deployment.yaml
   # Edit my-app-deployment.yaml with your application details
   ```

2. **Apply the manifest**:
   ```bash
   kubectl apply -f my-app-deployment.yaml
   ```

3. **Verify deployment**:
   ```bash
   kubectl get deployments
   kubectl get pods
   kubectl describe deployment my-app
   ```

### Working with Secrets

Secrets should be encrypted using SOPS before committing to Git:

1. **Create your secret**:
   ```bash
   cp kubernetes-examples/secret.yaml my-app-secret.yaml
   # Edit with actual credentials
   ```

2. **Encrypt with SOPS**:
   ```bash
   sops -e my-app-secret.yaml > my-app-secret.enc.yaml
   rm my-app-secret.yaml  # Remove plaintext version
   ```

3. **Deploy encrypted secret**:
   ```bash
   sops -d my-app-secret.enc.yaml | kubectl apply -f -
   ```

See [docs/setup.md#3-secret-management](../docs/setup.md#3-secret-management) for detailed secret management instructions.

### Exposing Services

#### Internal Access (ClusterIP)
```bash
# Services are accessible within the cluster
kubectl apply -f service.yaml
```

#### External Access via Cloudflared
```bash
# 1. Deploy your application and service
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# 2. Configure Cloudflared to route directly to your service
# Edit helmfile/values/cloudflared-values.yaml:
#   ingress:
#     - hostname: app.example.com
#       service: http://my-app.default.svc.cluster.local:80

# 3. Apply Helmfile changes
cd helmfile
helmfile apply

# 4. Access via Cloudflare tunnel
curl https://app.example.com
```

**Note**: Cloudflared routes directly to Kubernetes services. You don't need Ingress resources unless you want path-based routing or other advanced features.

## Best Practices

### Resource Management
- **Always set resource requests and limits** to prevent resource contention
- Start conservative and adjust based on actual usage
- Use `kubectl top pods` to monitor resource consumption

### High Availability
- **Set replicas ≥ 2** for production workloads
- Use pod anti-affinity to distribute pods across nodes
- Configure appropriate health checks

### Security
- **Run as non-root user** whenever possible
- Drop all capabilities and add only what's needed
- Use read-only root filesystem when feasible
- Enable seccomp profiles
- Never commit plaintext secrets to Git

### Health Checks
- **Liveness probes**: Restart unhealthy containers
- **Readiness probes**: Control when pods receive traffic
- Set appropriate timeouts and thresholds

### Labels and Annotations
- Use consistent labeling for organization
- Include environment, version, and component labels
- Use annotations for metadata and tool-specific configuration

## Workload Scheduling

Workloads are automatically scheduled on worker nodes because:
1. Control plane has `node-role.kubernetes.io/control-plane:NoSchedule` taint
2. No explicit `nodeSelector` is needed in most cases
3. Pods will only schedule on untainted worker nodes

To explicitly target worker nodes (optional):
```yaml
spec:
  nodeSelector:
    node-role: worker
```

## Namespace Organization

Organize applications by namespace for better isolation:

```bash
# Create namespace
kubectl create namespace my-app

# Deploy to namespace
kubectl apply -f deployment.yaml -n my-app

# Set default namespace
kubectl config set-context --current --namespace=my-app
```

## Monitoring

All examples include annotations for Prometheus monitoring:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

## Further Reading

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Setup Guide](../docs/setup.md) - Complete setup including Cloudflared and secrets
- [Operations Guide](../docs/operate.md) - Testing, monitoring, and workload examples
- [Helmfile Guide](../docs/helmfile.md) - Service deployment and configuration
