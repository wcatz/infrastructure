# Security and Compliance Onboarding Guide

Welcome! This guide will help you get started with the security and compliance tools in this infrastructure repository.

## Quick Start Checklist

### For New Team Members

- [ ] Read [README.md](README.md) for repository overview
- [ ] Review [SECURITY.md](SECURITY.md) for security policies
- [ ] Read [COMPLIANCE.md](COMPLIANCE.md) for audit procedures
- [ ] Review [GITOPS.md](GITOPS.md) for workflow guidelines
- [ ] Read [SECRETS.md](SECRETS.md) for secret management
- [ ] Install pre-commit hooks (see below)
- [ ] Request access to required secrets
- [ ] Join security alerts notifications

### For Repository Administrators

- [ ] Enable branch protection on `main` (see [GITOPS.md](GITOPS.md#branch-protection))
- [ ] Configure required GitHub Secrets:
  - `SOPS_AGE_KEY` - For decrypting SOPS files
  - `KUBECONFIG_PRODUCTION` - For production deployments
  - `KUBECONFIG_STAGING` - For staging deployments
  - `ANSIBLE_VAULT_PASSWORD` - For Ansible vault
- [ ] Enable GitHub Security features:
  - Secret scanning
  - Push protection
  - Dependabot alerts
  - Code scanning
- [ ] Configure PR review requirements
- [ ] Set up notification channels for security alerts

## Automated Security Tools Overview

This repository includes 6 automated security tools that run continuously:

### 1. 🔍 TruffleHog - Secrets Detection

**What it does**: Scans code and git history for exposed secrets

**When it runs**:
- Daily at 2 AM UTC
- On every push to main/develop
- On every pull request

**How to check results**:
- GitHub Actions → TruffleHog Secrets Scan workflow
- Security tab → Code scanning alerts
- Workflow summary in PR

**Config file**: `.trufflehog.yaml`

**Common issues**:
- False positive on example secrets in docs → Add to allowlist
- Found real secret → Rotate immediately (see [SECRETS.md](SECRETS.md))

### 2. 🛡️ Checkov - IaC Security

**What it does**: Scans Infrastructure-as-Code for security issues

**When it runs**:
- On every push to main/develop
- On every PR that changes IaC files
- Manual trigger available

**Scans**:
- Helm charts (`helmfile/charts/`)
- Kubernetes manifests (`helmfile/manifests/`)
- Helmfile values (`helmfile/values/`)
- Ansible playbooks (`ansible/`)

**How to check results**:
- PR comments with summary
- Security tab → Code scanning alerts
- Download artifacts for detailed reports

**Config file**: `.checkov.yaml`

**Common issues**:
- False positive → Add to skip-check in `.checkov.yaml`
- Real issue → Fix configuration or document exception

### 3. 📦 Dependabot - Dependency Updates

**What it does**: Creates PRs for dependency updates

**When it runs**:
- Monday 2 AM UTC: GitHub Actions
- Tuesday 2 AM UTC: Docker images
- Wednesday 2 AM UTC: Python packages

**How to review**:
- Check PR description for changes
- Review automated test results
- Test in staging before merging
- Merge or close if not needed

**Config file**: `.github/dependabot.yml`

**Note**: Helm charts require manual updates (see [COMPLIANCE.md](COMPLIANCE.md))

### 4. ⚙️ kube-bench - CIS Kubernetes Benchmark

**What it does**: Audits K8s cluster against CIS benchmarks

**When it runs**:
- Monthly on 1st at 3 AM UTC
- Manual trigger available

**Scan types**:
- Control plane audit
- Worker node audit
- Full cluster audit

**How to check results**:
- Workflow summary with pass/fail counts
- Download artifacts for detailed reports
- Results retained for 90 days

**Note**: Requires `KUBECONFIG_PRODUCTION` secret configured

### 5. 🦁 kube-hunter - K8s Security Scanner

**What it does**: Hunts for security weaknesses in cluster

**When it runs**:
- Monthly on 15th at 3 AM UTC
- Manual trigger available

**Scan types**:
- Remote scan (external attacker view)
- Pod scan (internal perspective)

**How to check results**:
- Workflow summary with severity breakdown
- Download artifacts for detailed reports
- Results retained for 90 days

**Note**: Requires `KUBECONFIG_PRODUCTION` secret configured

### 6. 🔐 Ansible Security Hardening

**What it does**: Applies OS-level security hardening

**When to run**:
- Initial cluster deployment
- When adding new nodes
- Quarterly re-hardening

**What it configures**:
- SSH hardening (key-only, limited retries)
- UFW firewall
- Kernel security parameters
- fail2ban
- auditd logging
- Automatic updates

**How to run**:
```bash
cd ansible
ansible-playbook -i inventory.ini playbooks/security-hardening.yaml
```

**Playbook**: `ansible/playbooks/security-hardening.yaml`

## Setting Up Your Development Environment

### 1. Install Pre-commit Hooks

Pre-commit hooks catch issues before you push code.

```bash
# Install pre-commit
pip install pre-commit

# Or on macOS
brew install pre-commit

# Install hooks in this repository
cd /path/to/infrastructure
pre-commit install
```

### 2. Configure SOPS for Secret Management

```bash
# Generate age key
age-keygen -o ~/.config/sops/age/keys.txt

# Get your public key
cat ~/.config/sops/age/keys.txt | grep "public key:"

# Share public key with team lead to add to .sops.yaml
```

See [SECRETS.md](SECRETS.md) for complete SOPS setup.

### 3. Configure Ansible Vault

```bash
cd ansible

# Create vault password file
echo "your-secure-password" > .vault_pass
chmod 600 .vault_pass

# Test vault access
ansible-vault view group_vars/all/vault.yml
```

See [SECRETS.md](SECRETS.md) for vault setup.

### 4. Install Required Tools

```bash
# macOS
brew install ansible kubectl helm helmfile sops age cloudflared yamllint

# Linux (Ubuntu/Debian)
# See docs/setup.md for detailed instructions
```

## Common Workflows

### Making Infrastructure Changes

1. **Create feature branch**
   ```bash
   git checkout -b feature/my-change
   ```

2. **Make changes**
   ```bash
   # Edit files
   vim helmfile/values/prometheus-values.yaml
   
   # Commit with conventional commit format
   git commit -m "feat(monitoring): increase Prometheus retention"
   ```

3. **Push and create PR**
   ```bash
   git push origin feature/my-change
   gh pr create --title "Increase Prometheus retention" --body "..."
   ```

4. **Wait for automated checks**
   - YAML validation
   - Helm linting
   - Security scans (Trivy, Checkov, TruffleHog)
   - Helmfile diff preview

5. **Request review**
   - Tag reviewer
   - Address any feedback
   - Ensure all checks pass

6. **Merge PR**
   - Squash and merge (recommended)
   - Delete branch after merge

See [GITOPS.md](GITOPS.md) for complete workflow.

### Encrypting Secrets

```bash
# Create plaintext secret
cat > secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
type: Opaque
stringData:
  password: supersecret123
EOF

# Encrypt with SOPS
sops -e secret.yaml > secret.enc.yaml

# Delete plaintext
rm secret.yaml

# Commit encrypted file
git add secret.enc.yaml
git commit -m "feat(secrets): add new secret"
```

See [SECRETS.md](SECRETS.md) for complete guide.

### Running Security Scans Manually

```bash
# Run TruffleHog locally
docker run --rm -v $(pwd):/src trufflesecurity/trufflehog:latest \
  filesystem /src --config /src/.trufflehog.yaml

# Run Checkov locally
pip install checkov
checkov --directory . --config-file .checkov.yaml

# Trigger GitHub workflows manually
gh workflow run checkov-scan.yaml
gh workflow run kube-bench-audit.yaml
gh workflow run kube-hunter-scan.yaml
```

### Responding to Security Alerts

#### Secret Detected

1. **Verify** it's a real secret (not false positive)
2. **Rotate** immediately (see [SECRETS.md](SECRETS.md))
3. **Remove** from git history if needed
4. **Update** `.gitignore` to prevent recurrence
5. **Document** the incident

#### IaC Security Issue

1. **Review** the Checkov finding
2. **Assess** severity and impact
3. **Fix** configuration or document exception
4. **Re-run** scan to verify fix
5. **Update** `.checkov.yaml` if false positive

#### Dependency Vulnerability

1. **Review** Dependabot PR
2. **Check** changelog for breaking changes
3. **Test** in staging environment
4. **Merge** if tests pass
5. **Deploy** to production

See [COMPLIANCE.md](COMPLIANCE.md#remediation-guidelines) for detailed procedures.

## Scheduled Maintenance

### Daily (Automated)
- TruffleHog secrets scan at 2 AM UTC

### Weekly (Automated)
- Dependabot PRs (Mon/Tue/Wed 2 AM UTC)

### Monthly (Automated)
- kube-bench audit (1st at 3 AM UTC)
- kube-hunter scan (15th at 3 AM UTC)

### Quarterly (Manual)
- [ ] Comprehensive security review
- [ ] Helm chart version updates
- [ ] OS hardening re-application
- [ ] Secret rotation review
- [ ] Documentation updates

### Annual (Manual)
- [ ] Full security assessment
- [ ] Penetration testing
- [ ] Encryption key rotation
- [ ] SSH key rotation
- [ ] Policy updates

See [COMPLIANCE.md](COMPLIANCE.md#audit-schedule) for complete schedule.

## Getting Help

### Documentation

- **[README.md](README.md)** - Repository overview and quick start
- **[SECURITY.md](SECURITY.md)** - Security policies and procedures
- **[COMPLIANCE.md](COMPLIANCE.md)** - Audit procedures and schedules
- **[GITOPS.md](GITOPS.md)** - GitOps workflow and branch protection
- **[SECRETS.md](SECRETS.md)** - Secret management guide
- **[docs/setup.md](docs/setup.md)** - Complete setup guide
- **[docs/operate.md](docs/operate.md)** - Operations guide

### Support Channels

- **Issues**: Create GitHub issue for bugs or questions
- **Security**: Email security@example.com for security concerns
- **Slack**: #infrastructure channel for general questions
- **Team Lead**: Contact your team lead for access or permissions

### Tool Documentation

- [TruffleHog](https://github.com/trufflesecurity/trufflehog)
- [Checkov](https://www.checkov.io/)
- [Dependabot](https://docs.github.com/en/code-security/dependabot)
- [kube-bench](https://github.com/aquasecurity/kube-bench)
- [kube-hunter](https://github.com/aquasecurity/kube-hunter)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

## Frequently Asked Questions

### Q: What secrets need to be configured in GitHub?

**A**: Four secrets are required:
1. `SOPS_AGE_KEY` - Private age key for SOPS decryption
2. `KUBECONFIG_PRODUCTION` - Base64-encoded kubeconfig for production
3. `KUBECONFIG_STAGING` - Base64-encoded kubeconfig for staging
4. `ANSIBLE_VAULT_PASSWORD` - Password for Ansible vault

### Q: How do I run a workflow manually?

**A**: 
```bash
gh workflow run <workflow-name>.yaml

# Or via web UI:
# Actions → Select workflow → Run workflow
```

### Q: What if I accidentally commit a secret?

**A**: 
1. Don't panic!
2. Rotate the secret immediately
3. Remove from git history using `git-filter-repo`
4. See [SECRETS.md](SECRETS.md) for detailed steps

### Q: How do I update Helm chart versions?

**A**: 
1. Update version in `helmfile/config/releases.yaml.gotmpl`
2. Run `helmfile diff` to preview changes
3. Test in staging
4. Create PR with changes
5. Deploy to production after merge

### Q: What's the difference between remote and pod kube-hunter scans?

**A**:
- **Remote**: Simulates external attacker, scans from outside cluster
- **Pod**: Runs inside cluster, finds internal vulnerabilities

Both perspectives are valuable for comprehensive security.

### Q: How often should I run OS hardening?

**A**:
- Initial deployment (required)
- When adding new nodes (required)
- Quarterly (recommended)
- After OS upgrades (recommended)

### Q: Can I skip security scans for urgent fixes?

**A**: 
- Branch protection enforces checks, but admins can override
- Only skip for genuine emergencies
- Document why checks were skipped
- Review findings after deployment

## Next Steps

1. ✅ Complete the onboarding checklist at the top
2. 📖 Read the core documentation (SECURITY.md, COMPLIANCE.md, GITOPS.md)
3. 🔧 Set up your development environment
4. 🧪 Try making a small change to test the workflow
5. 👥 Attend team security training session
6. 📅 Add maintenance tasks to your calendar

---

**Welcome to the team!** If you have any questions, don't hesitate to ask. Security is everyone's responsibility.

**Last Updated**: 2024-12-09  
**Maintainer**: DevOps Team / Security Team
