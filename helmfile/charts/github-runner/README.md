# GitHub Actions Runner Helm Chart

This Helm chart deploys a self-hosted GitHub Actions runner as a Kubernetes pod with Tailscale connectivity to access the control plane behind CGNAT.

## Features

- **Kubernetes-native**: Runs as a StatefulSet in your cluster
- **Tailscale Integration**: Sidecar container for Tailscale connectivity
- **Secure**: Uses Kubernetes secrets and RBAC
- **Scalable**: Support for multiple runner replicas
- **Persistent Storage**: Optional persistent volumes for runner work directory
- **Full Cluster Access**: Service account with appropriate RBAC permissions

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Worker Node (Public IP)                     │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  Pod: github-runner-0                              │ │
│  │                                                     │ │
│  │  ┌──────────────────┐  ┌──────────────────┐       │ │
│  │  │  Tailscale       │  │  GitHub Runner   │       │ │
│  │  │  Sidecar         │  │  Container       │       │ │
│  │  │                  │  │                  │       │ │
│  │  │  - Connects to   │  │  - Polls GitHub  │       │ │
│  │  │    Tailnet       │  │    for jobs      │       │ │
│  │  │  - Provides VPN  │  │  - Executes      │       │ │
│  │  │    connectivity  │  │    workflows     │       │ │
│  │  │                  │  │  - Uses kubectl  │       │ │
│  │  └────────┬─────────┘  └────────┬─────────┘       │ │
│  │           │                     │                  │ │
│  │           │  Shared network     │                  │ │
│  │           │  namespace          │                  │ │
│  │           └─────────────────────┘                  │ │
│  └────────────────────────────────────────────────────┘ │
│                       │                                  │
└───────────────────────┼──────────────────────────────────┘
                        │
                        │ Tailscale Mesh
                        │ (100.64.x.x)
                        │
                        ▼
            ┌───────────────────────┐
            │  Control Plane Node   │
            │  (Behind CGNAT)       │
            │                       │
            │  K3s API: 6443        │
            └───────────────────────┘
```

## Prerequisites

1. **Kubernetes Cluster**: k3s or any Kubernetes cluster (v1.24+)
2. **Tailscale Operator** (optional): For advanced features
3. **GitHub Repository**: Where you want to run workflows
4. **Tailscale Account**: For VPN connectivity
5. **Secrets**:
   - GitHub runner registration token or PAT
   - Tailscale auth key

## Installation

### Step 1: Create Namespace

```bash
kubectl create namespace github-runner
```

### Step 2: Create Secrets

#### Option A: Manual Secret Creation

```bash
# GitHub runner token (get from repo settings or API)
kubectl create secret generic github-runner-token \
  --from-literal=token=YOUR_GITHUB_TOKEN \
  -n github-runner

# Tailscale auth key
kubectl create secret generic tailscale-auth \
  --from-literal=authkey=YOUR_TAILSCALE_KEY \
  -n github-runner
```

#### Option B: Using SOPS (Recommended)

```bash
# Copy example secrets
cp secrets-example.yaml secrets.yaml

# Edit with your values
vim secrets.yaml

# Encrypt with SOPS
sops -e secrets.yaml > secrets.enc.yaml

# Apply encrypted secrets
sops -d secrets.enc.yaml | kubectl apply -f -
```

### Step 3: Configure Values

Create a `values-custom.yaml` file:

```yaml
github:
  repository: "https://github.com/YOUR_ORG/YOUR_REPO"
  tokenSecretName: "github-runner-token"
  tokenSecretKey: "token"

runner:
  name: ""  # Auto-generated from pod name
  labels:
    - self-hosted
    - kubernetes
    - tailscale
    - linux
    - x64
  replicas: 1
  ephemeral: false  # Set to true for one-time runners

tailscale:
  enabled: true
  authKeySecretName: "tailscale-auth"
  authKeySecretKey: "authkey"
  hostname: "github-runner"
  tags:
    - tag:k8s
    - tag:ci
  acceptRoutes: true

kubernetes:
  namespace: github-runner
  rbac:
    create: true
    clusterRole: true  # Cluster-wide permissions

storage:
  enabled: true
  size: 10Gi

clusterAccess:
  enabled: true
  useServiceAccount: true  # Use in-cluster config
```

### Step 4: Install the Chart

```bash
# From the helmfile directory
helm install github-runner ./charts/github-runner \
  -f values-custom.yaml \
  -n github-runner

# Or using helmfile
helmfile -l name=github-runner apply
```

### Step 5: Verify Installation

```bash
# Check pods
kubectl get pods -n github-runner

# Check logs
kubectl logs -n github-runner github-runner-0 -c runner
kubectl logs -n github-runner github-runner-0 -c tailscale

# Check Tailscale connectivity
kubectl exec -n github-runner github-runner-0 -c tailscale -- tailscale status

# Test kubectl access from runner
kubectl exec -n github-runner github-runner-0 -c runner -- kubectl get nodes
```

## Configuration

### GitHub Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `github.repository` | GitHub repository URL | `""` |
| `github.token` | GitHub runner token (use secret instead) | `""` |
| `github.tokenSecretName` | Secret name for GitHub token | `github-runner-token` |
| `github.tokenSecretKey` | Secret key for GitHub token | `token` |

### Runner Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `runner.name` | Runner name (empty for pod name) | `""` |
| `runner.group` | Runner group | `""` |
| `runner.labels` | Runner labels | `[self-hosted, kubernetes, tailscale, linux, x64]` |
| `runner.replicas` | Number of runner replicas | `1` |
| `runner.ephemeral` | Ephemeral mode (one job then exit) | `false` |
| `runner.image.repository` | Runner image repository | `ghcr.io/actions/actions-runner` |
| `runner.image.tag` | Runner image tag | `2.311.0` |

### Tailscale Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tailscale.enabled` | Enable Tailscale sidecar | `true` |
| `tailscale.authKey` | Tailscale auth key (use secret instead) | `""` |
| `tailscale.authKeySecretName` | Secret name for auth key | `tailscale-auth` |
| `tailscale.authKeySecretKey` | Secret key for auth key | `authkey` |
| `tailscale.hostname` | Tailscale hostname prefix | `github-runner` |
| `tailscale.tags` | Tailscale tags for ACL | `[tag:k8s, tag:ci]` |
| `tailscale.acceptRoutes` | Accept routes from Tailscale | `true` |

### Kubernetes Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `kubernetes.namespace` | Deployment namespace | `github-runner` |
| `kubernetes.serviceAccount.create` | Create service account | `true` |
| `kubernetes.rbac.create` | Create RBAC resources | `true` |
| `kubernetes.rbac.clusterRole` | Use ClusterRole (cluster-wide) | `true` |
| `kubernetes.resources.requests.cpu` | CPU request | `500m` |
| `kubernetes.resources.requests.memory` | Memory request | `512Mi` |
| `kubernetes.resources.limits.cpu` | CPU limit | `2000m` |
| `kubernetes.resources.limits.memory` | Memory limit | `2Gi` |

### Storage Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storage.enabled` | Enable persistent storage | `true` |
| `storage.storageClass` | Storage class | `""` (default) |
| `storage.size` | Storage size | `10Gi` |
| `storage.accessMode` | Access mode | `ReadWriteOnce` |

## Usage in Workflows

### Basic Example

```yaml
name: Deploy Application

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: [self-hosted, kubernetes, tailscale]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy with kubectl
        run: |
          kubectl apply -f kubernetes/
          kubectl rollout status deployment/myapp
```

### With Helm

```yaml
name: Helm Deploy

on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: [self-hosted, kubernetes, tailscale]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy with Helm
        run: |
          helm upgrade --install myapp ./charts/myapp \
            --namespace production \
            --create-namespace \
            --wait
```

## Scaling

### Multiple Runners

To run multiple runners:

```yaml
runner:
  replicas: 3
```

Each replica will register as a separate runner with a unique name based on the pod name.

### Ephemeral Runners

For better security and resource usage, use ephemeral runners:

```yaml
runner:
  ephemeral: true
  replicas: 5  # Pool of runners
```

Ephemeral runners are removed after completing one job, ensuring a clean state for each workflow run.

## Security

### Tailscale ACL Configuration

Configure ACLs in Tailscale admin console to restrict runner access:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:ci"],
      "dst": ["tag:k8s-control:6443,10250"]
    }
  ],
  "tagOwners": {
    "tag:ci": ["autogroup:admin"],
    "tag:k8s-control": ["autogroup:admin"]
  }
}
```

### RBAC Permissions

The chart creates a ClusterRole with broad permissions for deployments. For production, consider:

1. **Namespace-scoped**: Set `kubernetes.rbac.clusterRole: false`
2. **Custom Role**: Create your own Role with minimal permissions
3. **Multiple Service Accounts**: Different SAs for different environments

### Secrets Management

Never commit secrets to Git. Use one of:

1. **SOPS**: Encrypt secrets with age or GPG
2. **Sealed Secrets**: Encrypt secrets for Git storage
3. **GitHub Secrets**: Store secrets in GitHub (for tokens)
4. **Ansible Vault**: For infrastructure-level secrets

## Troubleshooting

### Runner Not Registering

```bash
# Check runner container logs
kubectl logs -n github-runner github-runner-0 -c runner

# Common issues:
# - Invalid GitHub token (check secret)
# - Network connectivity (check Tailscale)
# - Repository permissions (token needs admin:repo_hook)
```

### Tailscale Not Connecting

```bash
# Check Tailscale logs
kubectl logs -n github-runner github-runner-0 -c tailscale

# Verify auth key
kubectl get secret tailscale-auth -n github-runner -o yaml

# Test Tailscale connectivity
kubectl exec -n github-runner github-runner-0 -c tailscale -- tailscale status
kubectl exec -n github-runner github-runner-0 -c tailscale -- tailscale ping control-plane
```

### kubectl Access Denied

```bash
# Check service account
kubectl get sa -n github-runner
kubectl describe sa github-runner -n github-runner

# Check RBAC
kubectl get clusterrole github-runner
kubectl get clusterrolebinding github-runner

# Test from pod
kubectl exec -n github-runner github-runner-0 -c runner -- kubectl get nodes
```

### Workflow Jobs Not Starting

```bash
# Check runner status in GitHub UI
# Settings → Actions → Runners

# Verify runner is online and idle
kubectl logs -n github-runner github-runner-0 -c runner | grep "Listening for Jobs"

# Check labels match workflow
# Workflow: runs-on: [self-hosted, kubernetes]
# Runner labels: self-hosted, kubernetes, tailscale
```

## Maintenance

### Updating Runner Version

```bash
# Update values
helm upgrade github-runner ./charts/github-runner \
  --set runner.image.tag=2.312.0 \
  -n github-runner

# Restart pods to apply
kubectl rollout restart statefulset/github-runner -n github-runner
```

### Rotating Secrets

```bash
# Generate new GitHub token
# Update secret
kubectl create secret generic github-runner-token \
  --from-literal=token=NEW_TOKEN \
  -n github-runner \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart runners
kubectl rollout restart statefulset/github-runner -n github-runner
```

### Viewing Logs

```bash
# Runner logs
kubectl logs -n github-runner github-runner-0 -c runner -f

# Tailscale logs
kubectl logs -n github-runner github-runner-0 -c tailscale -f

# All containers
kubectl logs -n github-runner github-runner-0 --all-containers -f
```

## Uninstallation

```bash
# Using Helm
helm uninstall github-runner -n github-runner

# Clean up secrets (optional)
kubectl delete secret github-runner-token tailscale-auth -n github-runner

# Clean up namespace (optional)
kubectl delete namespace github-runner
```

## Advanced Usage

### Using with Tailscale Operator

If you have the Tailscale Kubernetes Operator installed, you can use it instead of the sidecar:

```yaml
tailscale:
  enabled: false  # Disable sidecar

# Add annotation to pod
kubernetes:
  podAnnotations:
    tailscale.com/expose: "false"
    tailscale.com/hostname: "github-runner"
```

### Custom Docker Images

Build a custom runner image with pre-installed tools:

```dockerfile
FROM ghcr.io/actions/actions-runner:2.311.0

USER root

# Install additional tools
RUN apt-get update && apt-get install -y \
    helm \
    kubectl \
    && rm -rf /var/lib/apt/lists/*

USER runner
```

Then use in values:

```yaml
runner:
  image:
    repository: your-registry/custom-runner
    tag: latest
```

### Organization-Level Runners

To register at organization level instead of repository:

```yaml
github:
  repository: "https://github.com/YOUR_ORG"
```

Requires a PAT or GitHub App with `admin:org` scope.

## References

- [GitHub Actions Self-Hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
