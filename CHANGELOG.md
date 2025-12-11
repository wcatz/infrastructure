# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive audit report (AUDIT_REPORT.md) with detailed findings and recommendations
- LICENSE file (MIT License)
- This CHANGELOG to track version history
- TruffleHog secrets scanning workflow with daily automated scans
- Complete compliance framework with automated security tools
- Secret expiration checking workflow
- Self-hosted GitHub Actions runner support
- Comprehensive documentation covering all aspects of the infrastructure

### Changed
- Removed External Secrets Operator in favor of SOPS and Ansible Vault for better security
- Disabled dev/staging environments by default for security (production-only policy)
- Updated all documentation to reflect current implementation

### Fixed
- Documentation links and references
- COMPLIANCE.md comments about TruffleHog implementation status

### Security
- Implemented multi-layered secret management with SOPS (age) and Ansible Vault
- Added automated security scanning with Checkov (IaC), kube-bench (CIS), and kube-hunter
- Configured GitHub secret scanning and push protection
- Established comprehensive secret rotation schedules and procedures
- Implemented OS-level security hardening with Ansible
- Added network policies and RBAC controls

## [1.0.0] - 2024-12-11

### Added
- Initial release of hybrid Kubernetes infrastructure
- K3s cluster deployment and management with Ansible
- Tailscale mesh networking for secure node communication
- Cloudflare tunnel ingress for HTTP/HTTPS traffic (no exposed ports)
- NodePort support for TCP/UDP services on worker nodes
- Prometheus and Grafana monitoring stack
- Velero for backup and disaster recovery
- cert-manager for TLS certificate management
- Comprehensive documentation:
  - README.md with architecture overview
  - SECURITY.md with security policies
  - COMPLIANCE.md with audit framework
  - SECRETS.md with complete secret management guide (1700+ lines)
  - Setup, operation, and troubleshooting guides
- Helmfile-based declarative service management
- Environment-specific configurations (dev/staging/prod)
- GitHub Actions workflows:
  - Checkov IaC security scanning
  - TruffleHog secrets detection
  - kube-bench CIS Kubernetes audits
  - kube-hunter security scanning
  - Automated deployments (production and staging)
  - Helmfile diff and apply workflows
- Example Kubernetes manifests and configurations
- Validation and health check scripts
- Cloudflare tunnel setup and management tools

### Infrastructure Components
- Control plane: K3s server behind CGNAT/firewall (no public IP required)
- Worker nodes: Public VPS with direct internet access
- Tailscale: Secure L3 mesh network (100.64.0.0/10)
- Cloudflared: HTTP/HTTPS ingress without load balancer
- NodePort: Direct TCP/UDP service access (ports 30000-32767)

### Security Features
- Secrets encrypted at rest with SOPS (age encryption)
- Kubernetes etcd encryption enabled (K3s default)
- Ansible Vault for infrastructure secrets
- GitHub Actions OIDC authentication
- SSH key-based authentication only
- Firewall rules and network segmentation
- RBAC and least privilege access control
- Comprehensive audit logging

### Documentation
- Complete setup guide (docs/setup.md)
- Operations manual (docs/operate.md)
- Ansible guide (docs/ansible.md)
- Helmfile guide (docs/helmfile.md)
- Cloudflare tunnel setup guide
- DNS configuration guide
- GitOps workflow documentation
- Contributing guidelines
- Onboarding guide for new team members

---

## Versioning Policy

This project follows [Semantic Versioning](https://semver.org/):
- **MAJOR** version: Incompatible infrastructure changes
- **MINOR** version: New features, backwards-compatible
- **PATCH** version: Bug fixes, backwards-compatible

## Release Process

1. Update CHANGELOG.md with all changes
2. Update version in documentation
3. Tag release: `git tag -a v1.0.0 -m "Release version 1.0.0"`
4. Push tags: `git push --tags`
5. Create GitHub release with notes

## Migration Guides

For major version upgrades that require infrastructure changes, see:
- Migration guides in `docs/migrations/`
- Upgrade procedures in `docs/operate.md#upgrades`

---

**Maintenance**: This CHANGELOG is updated with each merge to main branch.  
**Contact**: For questions about releases, see [CONTRIBUTING.md](CONTRIBUTING.md)
