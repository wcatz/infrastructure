# Legacy and Optional Configurations

This document describes legacy components and optional configurations that are available but not enabled by default in the current hybrid cluster architecture.

## Overview

The infrastructure has been refactored to use a **hybrid cluster architecture** with:
- **Cloudflared** for HTTP/HTTPS ingress (instead of traditional ingress controllers)
- **Tailscale** for secure inter-node communication
- **Direct NodePort/HostNetwork** for non-HTTP services
- **No load balancer** (MetalLB, HAProxy, etc.)

However, for backwards compatibility or alternative deployment scenarios, some components can be optionally enabled.

## HAProxy Ingress Controller (Legacy)

### Status
**DISABLED by default** - Not required for hybrid cluster architecture

### Description
HAProxy Ingress Controller was used in previous architectures for HTTP/HTTPS ingress and load balancing. It has been replaced by Cloudflared tunnels which provide:
- Better security (no exposed load balancer)
- Simplified networking (no need for public IP on control plane)
- Built-in DDoS protection via Cloudflare
- Free tier available

### When to Use HAProxy
Consider enabling HAProxy if:
- You need traditional Kubernetes Ingress resources
- You cannot use Cloudflared (e.g., compliance requirements)
- You have a dedicated load balancer IP available
- You prefer traditional load balancing over tunnel-based ingress

### Enabling HAProxy Ingress

1. **Update helmfile/config/enabled.yaml**:
   ```yaml
   enabled:
     haproxyIngress: true  # Enable HAProxy
     cloudflared: false    # Optionally disable Cloudflared
   ```

2. **Create HAProxy values file** at `helmfile/values/haproxy-ingress.yaml`:
   ```yaml
   controller:
     kind: DaemonSet
     hostNetwork: true
     service:
       type: NodePort
       nodePorts:
         http: 30080
         https: 30443
     resources:
       requests:
         cpu: 100m
         memory: 128Mi
       limits:
         cpu: 500m
         memory: 512Mi
   
   defaultBackend:
     enabled: true
     resources:
       requests:
         cpu: 10m
         memory: 20Mi
       limits:
         cpu: 50m
         memory: 50Mi
   ```

3. **Create environment-specific overrides** (optional):
   - `helmfile/environments/dev/haproxy-ingress.yaml`
   - `helmfile/environments/staging/haproxy-ingress.yaml`
   - `helmfile/environments/prod/haproxy-ingress.yaml`

4. **Deploy**:
   ```bash
   cd helmfile
   helmfile apply
   ```

5. **Create Ingress resources**:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: example-ingress
     annotations:
       kubernetes.io/ingress.class: haproxy
   spec:
     rules:
       - host: app.example.com
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: app-service
                   port:
                     number: 80
   ```

### Configuration Notes

- HAProxy runs as a DaemonSet on worker nodes
- Uses hostNetwork for direct port binding
- Requires ports 80 and 443 available on worker nodes
- Consider firewall rules for public access

## MetalLB Load Balancer (Optional)

### Status
**NOT INCLUDED** - Not needed for hybrid architecture

### Description
MetalLB provides load balancer IPs for on-premises clusters. Not required when using:
- Cloudflared for HTTP/S ingress
- NodePort for direct TCP/UDP services
- Cloud provider load balancers (if applicable)

### When to Use MetalLB
Consider using MetalLB if:
- You need LoadBalancer service type support
- You have available IP addresses for load balancing
- You're not using Cloudflared
- You need multiple load-balanced services

### Setup Instructions

1. **Install MetalLB**:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
   ```

2. **Configure IP address pool**:
   ```yaml
   apiVersion: metallb.io/v1beta1
   kind: IPAddressPool
   metadata:
     name: default-pool
     namespace: metallb-system
   spec:
     addresses:
       - 192.168.1.240-192.168.1.250
   
   ---
   apiVersion: metallb.io/v1beta1
   kind: L2Advertisement
   metadata:
     name: default
     namespace: metallb-system
   spec:
     ipAddressPools:
       - default-pool
   ```

3. **Use LoadBalancer services**:
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: app-lb
   spec:
     type: LoadBalancer
     ports:
       - port: 80
         targetPort: 8080
     selector:
       app: myapp
   ```

## Traefik Ingress (Alternative)

### Status
**NOT INCLUDED** - Disabled in k3s installation

### Description
Traefik is the default ingress controller in k3s but is disabled in our installation in favor of Cloudflared or HAProxy.

### Enabling Traefik

If you prefer Traefik over HAProxy or Cloudflared:

1. **Remove k3s flag** that disables Traefik:
   - Edit `ansible/roles/k3s/defaults/main.yaml`
   - Remove `--disable traefik` from k3s_server_options

2. **Configure Traefik** via k3s HelmChartConfig:
   ```yaml
   apiVersion: helm.cattle.io/v1
   kind: HelmChartConfig
   metadata:
     name: traefik
     namespace: kube-system
   spec:
     valuesContent: |-
       service:
         type: NodePort
       ports:
         web:
           nodePort: 30080
         websecure:
           nodePort: 30443
   ```

3. **Use Traefik IngressRoute** CRDs for advanced routing

## NGINX Ingress Controller (Alternative)

### Status
**NOT INCLUDED**

### Description
Popular alternative to HAProxy with extensive community support.

### Installation

```bash
# Add repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
```

## Service Mesh (Advanced - Optional)

### Istio

For advanced traffic management, consider Istio:

```bash
# Install Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-*
export PATH=$PWD/bin:$PATH
istioctl install --set profile=default -y
```

### Linkerd

Lighter-weight alternative to Istio:

```bash
# Install Linkerd CLI
curl -sL https://run.linkerd.io/install | sh

# Install Linkerd to cluster
linkerd install | kubectl apply -f -
```

## Comparison Matrix

| Component | Current | Legacy/Optional | Use Case |
|-----------|---------|-----------------|----------|
| **Ingress** | Cloudflared | HAProxy/Traefik/NGINX | HTTP/HTTPS traffic |
| **Load Balancer** | None (Direct NodePort) | MetalLB | Multiple LoadBalancer services |
| **VPN** | Tailscale | WireGuard/OpenVPN | Cluster networking |
| **Service Mesh** | None | Istio/Linkerd | Advanced traffic mgmt |
| **Storage** | Local PV | Longhorn/Rook | Distributed storage |

## Current Architecture (Default)

```
Internet
  ↓
Cloudflare Edge
  ↓
Cloudflared Tunnel (Worker Node)
  ↓
Kubernetes Service (Direct)
  ↓
Application Pods

Control Plane ←→ Tailscale VPN ←→ Worker Nodes
```

## Legacy Architecture (With HAProxy)

```
Internet
  ↓
HAProxy Load Balancer (Worker Node)
  ↓
HAProxy Ingress Controller
  ↓
Kubernetes Service
  ↓
Application Pods

Control Plane ←→ K3s Network ←→ Worker Nodes
```

## Migration Notes

### From HAProxy to Cloudflared

1. **Set up Cloudflared tunnel**:
   ```bash
   cloudflared tunnel create my-tunnel
   cloudflared tunnel route dns my-tunnel app.example.com
   ```

2. **Deploy Cloudflared** via Helmfile (already configured)

3. **Update DNS** to point to Cloudflare CNAME

4. **Remove Ingress resources** and HAProxy

5. **Test** all application endpoints

### From NodePort to LoadBalancer (with MetalLB)

1. Install MetalLB
2. Configure IP pool
3. Change services from NodePort to LoadBalancer
4. Update firewall rules

## Best Practices

### When Using Legacy Components

1. **Document deviations** from default architecture
2. **Test thoroughly** in dev environment first
3. **Monitor resource usage** - legacy components may use more resources
4. **Keep security updated** - ensure all components are patched
5. **Plan migration** back to default architecture when possible

### Security Considerations

- **HAProxy**: Ensure proper TLS configuration and certificate management
- **MetalLB**: Restrict IP pool to avoid conflicts
- **Service Mesh**: Understand mTLS implications and performance overhead

## Support

For questions about:
- **Current architecture**: See main [README.md](README.md)
- **Setup and deployment**: See [docs/setup.md](docs/setup.md)
- **Operations and testing**: See [docs/operate.md](docs/operate.md)
- **Legacy components**: Open an issue with `legacy` tag

## Updates

This document is maintained to reflect available but non-default configurations. Check commit history for changes.

**Last Updated**: 2024-12-05
