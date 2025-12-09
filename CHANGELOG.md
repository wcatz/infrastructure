# Changelog

All notable changes to this infrastructure project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- SOPS configuration file (.sops.yaml) for age-based encryption
- Comprehensive SECRETS.md documentation for secret management
- SECURITY.md policy document for cluster health and security
- Example encrypted secret files (Cloudflared, GitHub runner, monitoring)
- Health check script (scripts/health-check.sh) for cluster security validation
- helmfile/secrets/ directory with README and examples
- External Secrets Operator for secure secret management
- Velero for backup and disaster recovery
- DISASTER_RECOVERY.md guide with RTO/RPO expectations
- Grafana dashboards for HAProxy, k3s, and Cloudflared
- Alertmanager configuration with actionable alerts
- NetworkPolicies for sensitive workload isolation
- Enhanced CI workflows with YAML validation and Helm linting
- Security and policy checks in CI workflows
- CONTRIBUTING.md for contribution guidelines
- CHANGELOG.md for tracking changes

### Changed
- Non-production environments (dev/staging) disabled by default for security
- Updated .gitignore to allow encrypted secrets while blocking plaintext
- Enhanced README with links to SECRETS.md and SECURITY.md
- Enhanced HAProxy configuration with externalized backend services
- Improved health checks for HAProxy
- Added environment-specific template support for HAProxy
- Refined architecture diagram in README
- Updated quick-start setup instructions
- Enhanced monitoring and alerting documentation

### Security
- Implemented SOPS with age encryption for all secrets
- Non-production environments disabled to mitigate risk exposure
- Documented secret exposure mitigation strategies
- Implemented NetworkPolicies for workload isolation
- Added security scanning to CI/CD workflows
- Enhanced secret management practices
- Cloudflared credentials secured with SOPS encryption
- GitHub Actions secrets properly configured for SOPS decryption

## [1.0.0] - Previous Release

### Added
- k3s cluster deployment via Ansible
- HAProxy TCP/UDP load balancer for NodePorts
- HAProxy Ingress Controller for HTTP/HTTPS traffic
- Cloudflared tunnel integration for Zero Trust access
- Prometheus monitoring stack
- GitHub Actions workflows for GitOps
- Multi-environment support (dev, staging, prod)
- Comprehensive documentation

### Features
- GitOps automation with Helmfile
- Automatic PR diff previews
- YAML linting in CI
- Secret suppression in workflows
- Environment-specific configurations
- Health checks and failover support

### Documentation
- README.md with architecture diagram
- helmfile/README.md for Helmfile management
- ansible/README.md for Ansible documentation
- CLOUDFLARED_SETUP.md for tunnel setup
- DNS_SETUP.md for DNS configuration
- TESTING.md for testing procedures
- CONTRIBUTING.md for contribution guidelines
- SECRETS.md for secret management
- DISASTER_RECOVERY.md for DR procedures

---

## Release Notes

### Versioning Strategy

This infrastructure uses semantic versioning:
- **Major**: Breaking changes, significant architecture changes
- **Minor**: New features, backwards-compatible changes
- **Patch**: Bug fixes, documentation updates, minor improvements

### Change Categories

- **Added**: New features, capabilities, or documentation
- **Changed**: Changes to existing functionality
- **Deprecated**: Features that will be removed in future releases
- **Removed**: Removed features or functionality
- **Fixed**: Bug fixes
- **Security**: Security improvements and vulnerability fixes

### How to Use This Changelog

- Check **[Unreleased]** for upcoming changes
- Review version sections before upgrading
- Note any **Breaking Changes** in major releases
- Review **Security** sections for important updates
