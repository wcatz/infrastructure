# GitHub Copilot Instructions for Infrastructure Repository

This document provides guidance for GitHub Copilot when working with this hybrid Kubernetes infrastructure repository.

## Repository Overview

This is a **production-ready hybrid Kubernetes infrastructure** repository that:
- Manages a K3s cluster with control plane behind CGNAT and workers on public VPS
- Uses **Tailscale** for secure mesh networking between nodes
- Uses **Cloudflared** for HTTP/HTTPS ingress (no load balancers)
- Exposes TCP/UDP services via NodePorts on worker nodes
- Manages infrastructure with **Ansible** playbooks
- Deploys services declaratively with **Helmfile**
- Implements defense-in-depth security with multiple compliance tools

## Technology Stack

- **Orchestration**: Kubernetes (k3s), Helm v3, Helmfile
- **Infrastructure as Code**: Ansible 2.10+ (minimum; newer versions recommended for security and features)
- **Networking**: Tailscale VPN mesh, Cloudflared tunnels
- **Secret Management**: SOPS with age encryption, Ansible Vault
- **CI/CD**: GitHub Actions with OIDC authentication
- **Security**: Checkov, TruffleHog, kube-bench, kube-hunter
- **Monitoring**: Prometheus, Grafana
- **Backup**: Velero

## Coding Standards

### YAML Files

- Use **2 spaces** for indentation (never tabs)
- Keep lines under **120 characters** (yamllint configured)
- Follow `.yamllint` configuration rules
- Always include YAML document start (`---`) for Ansible playbooks
- Add comments for complex configurations
- Use consistent naming conventions (kebab-case for files)

**Example:**
```yaml
---
# Good - Clear, properly indented
releases:
  - name: my-app
    namespace: apps
    chart: repo/chart
    version: 1.0.0
    values:
      - values/my-app-values.yaml
```

### Ansible Playbooks

- Use descriptive task names that explain what the task does
- Include tags for selective execution (`setup`, `config`, `security`, etc.)
- Add comments at the top explaining purpose and usage
- Document required variables and secrets
- Handle errors gracefully with `failed_when` or `ignore_errors` when appropriate
- Support check mode (`--check`) for dry runs

**Example:**
```yaml
---
# Deploy k3s cluster with Tailscale networking
# Usage: ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml
# Secrets: Requires vault.yml with k3s_token

- name: Deploy k3s Server
  hosts: k3s_servers
  become: true
  roles:
    - k3s
  tags:
    - k3s
    - setup
```

### Helmfile Configurations

- Version-pin all Helm charts (never use `latest`)
- Use gotmpl templates for conditional logic
- Separate base configuration from environment overrides
- Enable/disable applications via `config/enabled.yaml`
- Document custom values with inline comments
- Use `--suppress-secrets` when running diff or template commands

**File Structure:**
```
helmfile/
├── helmfile.yaml.gotmpl       # Main Helmfile (uses gotmpl)
├── config/
│   ├── enabled.yaml           # Base app enable/disable
│   ├── repositories.yaml.gotmpl
│   └── releases.yaml.gotmpl
├── environments/
│   ├── dev/enabled.yaml       # Dev overrides
│   ├── staging/enabled.yaml
│   └── prod/enabled.yaml
└── values/
    └── app-values.yaml        # Per-app configuration
```

### Helm Values

- Group related settings together logically
- Use clear, descriptive key names
- Add comments for non-obvious settings
- Always include resource limits and requests
- Set appropriate timeouts and retry values
- Follow the pattern of existing values files

## Secret Management (CRITICAL)

### Never Commit Plaintext Secrets

**NEVER commit these to Git:**
- Passwords, API keys, tokens
- Private keys, certificates
- Database credentials
- Cloudflare API tokens
- Tailscale auth keys
- Ansible Vault passwords
- age private keys

### Use Proper Secret Encryption

**For Kubernetes Secrets:**
```bash
# Encrypt with SOPS before committing
cd helmfile/secrets
sops -e plaintext-secret.yaml > my-secret.enc.yaml
git add my-secret.enc.yaml
# NEVER add the plaintext version
```

**For Ansible Secrets:**
```bash
# Use Ansible Vault
cd ansible
ansible-vault encrypt group_vars/all/vault.yml
# Store vault password in .vault_pass (gitignored)
```

### Secret File Patterns

- Encrypted Kubernetes secrets: `helmfile/secrets/*.enc.yaml`
- Ansible vault files: `ansible/group_vars/all/vault.yml`
- Never commit: `.vault_pass`, `keys.txt`, `*-credentials.json`

## Testing and Validation

### Before Committing Changes

1. **Validate YAML syntax:**
   ```bash
   yamllint helmfile/ ansible/
   ```

2. **Test Helmfile templates:**
   ```bash
   cd helmfile
   helmfile template --suppress-secrets
   ```

3. **Preview Helmfile changes:**
   ```bash
   helmfile diff --suppress-secrets
   ```

4. **Validate Ansible playbooks:**
   ```bash
   ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --syntax-check
   ```

5. **Test Ansible in dry-run mode:**
   ```bash
   ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml --check
   ```

### CI/CD Integration

All pull requests automatically run:
- YAML linting (yamllint)
- Helmfile template validation
- Helmfile diff preview
- Security scanning (Checkov, TruffleHog)

Review automated diff output carefully before merging.

## Security Guidelines

### Defense-in-Depth Approach

1. **Encryption at rest**: All secrets encrypted with SOPS/Ansible Vault
2. **Encryption in transit**: Tailscale mesh, Cloudflare tunnels, TLS
3. **Access control**: RBAC, network policies, firewall rules
4. **Monitoring**: Prometheus alerts, audit logs, secret scanning
5. **Compliance**: Regular audits with kube-bench and kube-hunter

### Security Tools in Use

- **TruffleHog**: Daily secrets scanning in code and git history
- **Checkov**: IaC security scanning for Helm, Kubernetes, Ansible
- **Dependabot**: Automated dependency updates and vulnerability alerts
- **kube-bench**: Monthly CIS Kubernetes benchmark audits
- **kube-hunter**: Monthly Kubernetes penetration testing
- **GitHub Secret Scanning**: Automated detection with push protection

### When Making Changes

- Always scan for accidentally committed secrets
- Use `--suppress-secrets` with Helmfile commands
- Review security tool outputs in CI/CD
- Consider the principle of least privilege
- Document security implications in PR descriptions

## Development Workflow

### Branch Naming

- Features: `feature/descriptive-name`
- Bug fixes: `fix/bug-description`
- Security: `security/vulnerability-fix`
- Documentation: `docs/what-changed`

### Commit Messages

Use clear, descriptive commit messages:
- Present tense: "Add feature" not "Added feature"
- Imperative mood: "Fix bug" not "Fixes bug"
- Limit first line to 72 characters
- Reference issues: "Fixes #123" or "Relates to #456"

**Examples:**
- ✅ "Add Grafana dashboard for HAProxy monitoring"
- ✅ "Fix Tailscale certificate rotation issue #234"
- ❌ "Updated files"
- ❌ "WIP changes"

### Pull Request Process

1. Keep PRs focused and manageable
2. Include clear description of changes and rationale
3. Update relevant documentation
4. Ensure all CI checks pass
5. Address review feedback promptly
6. Squash commits if requested

## Documentation Standards

### What to Document

- New features and their usage
- Configuration options and defaults
- Setup and installation steps
- Troubleshooting common issues
- Security considerations
- Examples and use cases

### Documentation Structure

All documentation follows a clear structure:
- **README.md**: Main documentation and quick start
- **docs/setup.md**: Complete setup guide
- **docs/operate.md**: Operations, testing, monitoring, DR
- **docs/ansible.md**: Ansible playbooks and automation
- **docs/helmfile.md**: Helmfile configuration and services
- **SECRETS.md**: Secret management guide
- **SECURITY.md**: Security policy and incident response
- **COMPLIANCE.md**: Audit procedures and compliance
- **CONTRIBUTING.md**: Contribution guidelines

### Documentation Style

- Use clear, concise language
- Include code examples with proper syntax highlighting
- Provide step-by-step instructions
- Link to related documentation
- Keep documentation updated with code changes

## Common Operations

### Deploy Infrastructure

```bash
# Complete deployment
./runme.sh

# Or step-by-step (with vault password for encrypted secrets):
ansible-playbook -i inventory.ini --vault-password-file .vault_pass playbooks/setup-tailscale.yaml
ansible-playbook -i inventory.ini --vault-password-file .vault_pass playbooks/deploy-k3s.yaml
cd helmfile && helmfile apply
```

### Deploy Services

```bash
cd helmfile
helmfile apply                    # Deploy all enabled services
helmfile -e staging apply         # Deploy to staging environment
helmfile diff --suppress-secrets  # Preview changes
```

### Manage Secrets

```bash
# Edit encrypted Kubernetes secret
cd helmfile/secrets
sops my-secret.enc.yaml

# Edit Ansible vault
cd ansible
ansible-vault edit group_vars/all/vault.yml
```

### Troubleshooting

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# View logs
kubectl logs -n namespace pod-name -f

# Check Helmfile status
cd helmfile
helmfile status
```

## Architecture-Specific Considerations

### Hybrid Cluster Design

- **Control plane**: Behind CGNAT, no public IP, uses Tailscale
- **Worker nodes**: Public VPS with direct internet access
- **Inter-node communication**: Always via Tailscale mesh (100.64.0.0/10)
- **Never** assume direct control plane to worker connectivity

### Ingress Patterns

- **HTTP/HTTPS traffic**: Route through Cloudflared tunnels
- **TCP/UDP services**: Expose via NodePort (30000-32767) on workers
- **No load balancers**: Architecture uses Cloudflared + NodePorts (cost optimization)
- **No traditional Ingress controllers**: Traefik is intentionally disabled in k3s configuration (using Cloudflared instead)

### Service Exposure

When adding new services:
- HTTP/HTTPS: Configure Cloudflared tunnel in `helmfile/values/cloudflared-values.yaml`
- TCP/UDP: Use NodePort service type, document external port mapping
- Update DNS configuration in `DNS_SETUP.md` if needed

## File Locations Reference

### Configuration Files

- Ansible inventory: `ansible/inventory.ini` (create from `inventory.ini.example`)
- Ansible vault: `ansible/group_vars/all/vault.yml` (create from `vault.yml.example`, then encrypt)
- Helmfile enabled apps: `helmfile/config/enabled.yaml`
- SOPS configuration: `.sops.yaml`
- Yamllint rules: `.yamllint`

### Secrets (Examples provided, create actual files without -example suffix)

- Kubernetes secrets pattern: `helmfile/secrets/*.enc.yaml`
- Examples: `cloudflared-credentials-example.enc.yaml`, `github-runner-secrets-example.enc.yaml`
- Actual files (not in repo): `cloudflared-credentials.enc.yaml`, `github-runner-secrets.enc.yaml`

### Scripts

- Validation: `scripts/validate-prereqs.sh`
- Health checks: `scripts/health-check.sh`
- Tunnel setup: `scripts/configure-tunnel-dns.sh`

## Best Practices for AI-Assisted Development

### When Suggesting Changes

1. **Understand context first**: Read related files and documentation
2. **Follow existing patterns**: Match the style and structure of existing code
3. **Make minimal changes**: Only modify what's necessary
4. **Preserve security**: Never weaken security configurations
5. **Test before committing**: Validate syntax and run dry-runs
6. **Document changes**: Update relevant docs and add comments

### What to Avoid

- Don't remove or weaken security configurations:
  - Disabling RBAC or network policies
  - Weakening pod security standards or encryption
  - Relaxing firewall rules or access controls
- Don't commit secrets or credentials:
  - Plaintext passwords, API keys, private keys, tokens
  - Unencrypted certificate files or credential JSONs
- Don't make breaking changes without discussion:
  - Changing service ports or removing features
  - Modifying APIs or changing resource names
- Don't ignore linting or validation errors:
  - yamllint, Helmfile template errors, Ansible syntax errors
  - Security scan findings from Checkov or TruffleHog
- Don't skip testing steps:
  - Dry-run validation, diff previews, syntax checks
  - CI/CD automated test results
- Don't use `latest` tags for production deployments:
  - Always pin specific versions for charts and images

### When Uncertain

- Refer to existing examples in the repository
- Check documentation in `docs/` directory
- Look for patterns in `.github/workflows/` for CI/CD
- Review `CONTRIBUTING.md` for contribution guidelines
- Ask for clarification rather than guessing

## Additional Resources

- [Complete Setup Guide](../docs/setup.md)
- [Operations Manual](../docs/operate.md)
- [Security Policy](../SECURITY.md)
- [Secret Management Guide](../SECRETS.md)
- [Compliance Framework](../COMPLIANCE.md)
- [Contributing Guidelines](../CONTRIBUTING.md)

---

**Remember**: This infrastructure is production-ready and security is paramount. Always validate changes, encrypt secrets, and follow the principle of least privilege.
