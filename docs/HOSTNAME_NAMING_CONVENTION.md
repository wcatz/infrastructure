# Hostname Naming Convention

## Standard Format

All infrastructure hostnames should follow this naming convention:

```
[function]-[environment]-[sequence]
```

### Components

1. **function**: The role or purpose of the server
   - `dns` - DNS server
   - `k3s` - Kubernetes control plane or worker
   - `app` - Application server
   - `db` - Database server
   - `mon` - Monitoring server
   - `proxy` - Reverse proxy/load balancer
   - `runner` - CI/CD runner

2. **environment**: The deployment environment
   - `prod` - Production
   - `staging` - Staging/pre-production
   - `dev` - Development
   - `test` - Testing

3. **sequence**: Sequential number (zero-padded to 2 digits)
   - `01`, `02`, `03`, etc.

## Examples

- `dns-prod-01` - First production DNS server
- `k3s-prod-01` - First production K3s control plane
- `k3s-prod-02` - Second production K3s worker node
- `app-staging-01` - First staging application server
- `runner-dev-01` - First development CI/CD runner

## Implementation

### Ansible Inventory

Set hostnames in your inventory file:

```ini
[k3s_servers]
k3s-prod-01 ansible_host=100.64.1.10 hostname=k3s-prod-01

[k3s_agents]
k3s-prod-02 ansible_host=100.64.1.20 hostname=k3s-prod-02
k3s-prod-03 ansible_host=100.64.1.21 hostname=k3s-prod-03
```

### Ansible Playbook

Use the `hostname` role to configure hostnames:

```yaml
- name: Configure Hostname
  hosts: all
  become: true
  roles:
    - hostname
```

The role will automatically use the `hostname` variable from your inventory.

### Kubernetes Node Names

When deploying K3s, nodes will automatically register with their configured hostname:

```bash
kubectl get nodes
# NAME           STATUS   ROLE                  AGE
# k3s-prod-01    Ready    control-plane,master  10d
# k3s-prod-02    Ready    <none>                10d
# k3s-prod-03    Ready    <none>                10d
```

## DNS Configuration

### A Records

Configure DNS A records to match hostnames:

```
k3s-prod-01.example.com    A    203.0.113.10
k3s-prod-02.example.com    A    203.0.113.20
k3s-prod-03.example.com    A    203.0.113.21
```

### Avoid IP-based URLs

❌ **Don't use:** `https://152.53.88.122/`

✅ **Use instead:** `https://k3s-prod-01.example.com/`

## Benefits

1. **Consistency**: Standardized naming across all infrastructure
2. **Readability**: Clear indication of server purpose and environment
3. **Scalability**: Easy to add new servers with sequential numbers
4. **Automation**: Programmatic hostname generation and validation
5. **DNS-friendly**: Resolvable hostnames instead of IP addresses
6. **Security**: Easier to manage certificates with stable DNS names

## Migration from IP-based References

If you currently have hardcoded IP addresses in your configuration:

1. Add DNS A records for each server
2. Update configuration files to use hostnames
3. Update Kubernetes manifests to use DNS names
4. Update monitoring and logging configurations
5. Verify connectivity using DNS names before removing IP references

Example migration:

```yaml
# Before
apiserver_url: "https://152.53.88.122:6443"

# After
apiserver_url: "https://k3s-prod-01.example.com:6443"
```

## Validation

To verify hostnames are correctly configured:

```bash
# Check system hostname
hostname

# Check /etc/hostname
cat /etc/hostname

# Check /etc/hosts
cat /etc/hosts

# Verify DNS resolution
dig k3s-prod-01.example.com +short
```
