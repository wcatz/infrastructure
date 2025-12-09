# Compliance and Audit Guide

This document outlines the compliance framework, audit procedures, and maintenance schedules for the hybrid Kubernetes infrastructure.

## Table of Contents

- [Overview](#overview)
- [Automated Security Tools](#automated-security-tools)
- [Audit Schedule](#audit-schedule)
- [Tool Ownership](#tool-ownership)
- [Compliance Procedures](#compliance-procedures)
- [Remediation Guidelines](#remediation-guidelines)
- [Reporting and Documentation](#reporting-and-documentation)

## Overview

This infrastructure implements a comprehensive security and compliance framework using automated tools and regular audits to maintain production readiness and security posture.

### Compliance Goals

1. **Prevent Secret Exposure**: Automated scanning for secrets in code and git history
2. **Infrastructure Security**: Continuous scanning of IaC configurations
3. **Dependency Management**: Automated updates and vulnerability tracking
4. **Kubernetes Hardening**: Regular CIS benchmark audits and security scans
5. **Host OS Security**: Automated security hardening of cluster nodes
6. **GitOps Best Practices**: Enforced code review and automated testing

### Compliance Framework

```
┌─────────────────────────────────────────────────────────────────┐
│                     Continuous Compliance                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Secrets Detection    IaC Security      Dependency Mgmt        │
│  ┌──────────────┐    ┌──────────────┐  ┌──────────────┐       │
│  │ TruffleHog   │    │   Checkov    │  │  Dependabot  │       │
│  │ Daily Scans  │    │   PR Checks  │  │   Weekly     │       │
│  └──────────────┘    └──────────────┘  └──────────────┘       │
│                                                                 │
│  K8s Hardening       Host Security      GitOps Integration     │
│  ┌──────────────┐    ┌──────────────┐  ┌──────────────┐       │
│  │  kube-bench  │    │   Ansible    │  │ Branch       │       │
│  │  kube-hunter │    │  Hardening   │  │ Protection   │       │
│  │   Monthly    │    │   On Deploy  │  │   Enforced   │       │
│  └──────────────┘    └──────────────┘  └──────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Automated Security Tools

### 1. TruffleHog - Secrets Detection

**Purpose**: Scan for secrets in repository code and git history

<!-- TruffleHog workflow not yet implemented; reference removed -->

**Schedule**:
- ✅ **Push to main/develop**: Immediate scan
- ✅ **Pull requests**: Scan on PR creation/update
- ✅ **Daily**: Scheduled scan at 2 AM UTC
- ✅ **On-demand**: Manual trigger available

**Configuration**: `.trufflehog.yaml`

**What it scans**:
- Git commit history
- All branches
- API keys, tokens, passwords
- Cloud provider credentials
- SSH keys and certificates

**Output**:
- SARIF format uploaded to GitHub Security tab
- Workflow summary with findings
- Verified secrets highlighted

**Remediation**:
- Immediately rotate exposed secrets
- Remove from git history using `git-filter-repo` or BFG
- Update `.gitignore` to prevent future exposures
- See [SECRETS.md](SECRETS.md) for rotation procedures

### 2. Checkov - IaC Security Scanning

**Purpose**: Scan Infrastructure-as-Code for security misconfigurations

**Workflow**: `.github/workflows/checkov-scan.yaml`

**Schedule**:
- ✅ **Push to main/develop**: Immediate scan
- ✅ **Pull requests**: Scan when IaC files change
- ✅ **On-demand**: Manual trigger available

**Configuration**: `.checkov.yaml`

**What it scans**:
- Helm charts (`helmfile/charts/`)
- Kubernetes manifests (`helmfile/manifests/`)
- Helmfile values (`helmfile/values/`)
- Ansible playbooks (`ansible/`)

**Security checks**:
- Pod security policies
- Network policies
- RBAC configurations
- Secret management
- Resource limits
- Privilege escalation risks
- Image security

**Output**:
- JSON reports with detailed findings
- SARIF format uploaded to GitHub Security tab
- PR comments with scan summary
- Downloadable artifacts (retained 30 days)

**Remediation**:
- Review failed checks in Security tab
- Address CRITICAL and HIGH severity issues immediately
- Document false positives in `.checkov.yaml`
- Update configurations per recommendations

### 3. Dependabot - Dependency Management

**Purpose**: Automated dependency updates and vulnerability alerts

**Configuration**: `.github/dependabot.yml`

**What it monitors**:
- **GitHub Actions**: Weekly updates (Monday 2 AM UTC)
- **Docker Images**: Weekly updates (Tuesday 2 AM UTC)
- **Python/pip**: Weekly updates (Wednesday 2 AM UTC)

**Process**:
1. Dependabot creates PR for updates
2. Automated tests run on PR
3. Review and merge approved updates
4. Security updates are prioritized

**Best Practices**:
- Review PRs weekly
- Test updates in staging before production
- Pin major versions, allow minor/patch updates
- Keep Helm chart versions pinned in `helmfile/config/releases.yaml.gotmpl`

**Manual Helm Chart Updates**:
Dependabot doesn't support Helm natively. Update manually:

```bash
# Check for updates
helm repo update
helm search repo prometheus-community/prometheus --versions | head -5

# Update version in releases.yaml.gotmpl
vim helmfile/config/releases.yaml.gotmpl

# Test changes
cd helmfile && helmfile diff

# Apply updates
helmfile apply
```

### 4. kube-bench - CIS Kubernetes Benchmark

**Purpose**: Audit Kubernetes cluster against CIS benchmarks

**Workflow**: `.github/workflows/kube-bench-audit.yaml`

**Schedule**:
- ✅ **Monthly**: 1st of month at 3 AM UTC
- ✅ **On-demand**: Manual trigger with node type selection

**What it checks**:
- Control plane configuration
- Worker node configuration
- Kubernetes API server settings
- etcd security
- Controller manager settings
- Scheduler configuration
- Network policies

**Scan Types**:
- **Control Plane**: Runs on master nodes
- **Worker**: Runs on worker nodes
- **Both**: Comprehensive cluster audit

**Output**:
- JSON reports with pass/fail/warn counts
- Detailed remediation steps
- Artifacts retained for 90 days

**Remediation**:
- Review all FAIL checks
- Prioritize control plane security
- Apply recommended configurations
- Re-run audit to verify fixes
- Document accepted risks

### 5. kube-hunter - Kubernetes Security Scanner

**Purpose**: Hunt for security weaknesses in Kubernetes clusters

**Workflow**: `.github/workflows/kube-hunter-scan.yaml`

**Schedule**:
- ✅ **Monthly**: 15th of month at 3 AM UTC
- ✅ **On-demand**: Manual trigger with scan type selection

**Scan Types**:
- **Remote**: External attack simulation
- **Pod**: Internal cluster perspective
- **Both**: Comprehensive security assessment

**What it detects**:
- Open Kubernetes API
- Exposed dashboards
- Weak RBAC configurations
- Privilege escalation paths
- Vulnerable services
- Network segmentation issues

**Output**:
- JSON reports by severity (High/Medium/Low)
- Combined security report
- Artifacts retained for 90 days

**Remediation**:
- Address High severity issues immediately
- Review Medium severity within 7 days
- Implement network policies
- Strengthen RBAC
- Verify API server security

### 6. Ansible Security Hardening

**Purpose**: Apply OS-level security hardening to cluster nodes

**Playbook**: `ansible/playbooks/security-hardening.yaml`

**When Applied**:
- ✅ **Initial deployment**: Part of cluster setup
- ✅ **New nodes**: When adding nodes to cluster
- ✅ **Quarterly**: Scheduled hardening updates

**Hardening Applied**:
- SSH hardening (key-only auth, limited retries)
- UFW firewall configuration
- Kernel security parameters (sysctl)
- fail2ban for brute-force protection
- Automatic security updates
- Audit logging (auditd)
- Disabled unused filesystems and protocols

**Running Hardening**:

```bash
cd ansible

# Harden all nodes
ansible-playbook -i inventory.ini playbooks/security-hardening.yaml

# Harden specific group
ansible-playbook -i inventory.ini playbooks/security-hardening.yaml --limit control_plane

# Verify hardening
ansible all -i inventory.ini -m shell -a "ufw status"
ansible all -i inventory.ini -m shell -a "systemctl status fail2ban"
```

## Audit Schedule

### Daily Audits (Automated)

| Time (UTC) | Tool | Scope |
|------------|------|-------|
| 02:00 | TruffleHog | Full repository scan |

### Weekly Audits (Automated)

| Day | Time (UTC) | Tool | Scope |
|-----|------------|------|-------|
| Monday | 02:00 | Dependabot | GitHub Actions |
| Tuesday | 02:00 | Dependabot | Docker Images |
| Wednesday | 02:00 | Dependabot | Python Packages |

### Monthly Audits (Automated)

| Date | Time (UTC) | Tool | Scope |
|------|------------|------|-------|
| 1st | 03:00 | kube-bench | CIS Kubernetes audit |
| 15th | 03:00 | kube-hunter | Security scanning |

### Quarterly Audits (Manual)

| Task | Frequency | Owner |
|------|-----------|-------|
| Comprehensive security review | Quarterly | Security Team |
| Helm chart version updates | Quarterly | DevOps Team |
| OS hardening re-application | Quarterly | Infrastructure Team |
| Secret rotation review | Quarterly | Security Team |
| Compliance documentation update | Quarterly | All Teams |

### Annual Audits (Manual)

| Task | Frequency | Owner |
|------|-----------|-------|
| Full security assessment | Annually | Security Team |
| Penetration testing | Annually | External Auditor |
| Disaster recovery testing | Annually | Infrastructure Team |
| Encryption key rotation | Annually | Security Team |

## Tool Ownership

### TruffleHog - Secrets Detection
- **Primary Owner**: Security Team
- **Backup Owner**: DevOps Team
- **Responsibilities**:
  - Monitor daily scan results
  - Investigate detected secrets
  - Coordinate secret rotation
  - Update exclusion rules
  - Maintain `.trufflehog.yaml`

### Checkov - IaC Security
- **Primary Owner**: DevOps Team
- **Backup Owner**: Platform Team
- **Responsibilities**:
  - Review scan results on PRs
  - Approve/reject security findings
  - Update policies in `.checkov.yaml`
  - Remediate critical issues
  - Document false positives

### Dependabot - Dependencies
- **Primary Owner**: DevOps Team
- **Backup Owner**: Development Team
- **Responsibilities**:
  - Review and merge dependency PRs
  - Test updates in staging
  - Coordinate production rollouts
  - Monitor security advisories
  - Update `.github/dependabot.yml`

### kube-bench - CIS Audits
- **Primary Owner**: Platform Team
- **Backup Owner**: Security Team
- **Responsibilities**:
  - Review monthly audit results
  - Implement CIS recommendations
  - Document accepted risks
  - Track remediation progress
  - Update cluster configurations

### kube-hunter - Security Scanning
- **Primary Owner**: Security Team
- **Backup Owner**: Platform Team
- **Responsibilities**:
  - Analyze monthly scan results
  - Prioritize vulnerability remediation
  - Coordinate with DevOps for fixes
  - Track security improvements
  - Report to management

### Ansible Hardening - OS Security
- **Primary Owner**: Infrastructure Team
- **Backup Owner**: Platform Team
- **Responsibilities**:
  - Apply hardening to new nodes
  - Quarterly re-hardening
  - Update hardening playbook
  - Monitor auditd logs
  - Document hardening exceptions

## Compliance Procedures

### 1. Secret Exposure Response

**If TruffleHog detects a secret:**

1. **Immediate (< 1 hour)**:
   - Verify the secret is valid
   - Rotate the exposed secret
   - Revoke old secret/token
   - Update applications with new secret

2. **Short-term (< 24 hours)**:
   - Review access logs for unauthorized usage
   - Remove secret from git history
   - Update `.gitignore` if needed
   - Document incident

3. **Long-term**:
   - Post-incident review
   - Update training materials
   - Implement additional controls
   - Schedule follow-up audit

**See [SECRETS.md](SECRETS.md) for detailed rotation procedures**

### 2. IaC Security Issue Response

**If Checkov identifies a security issue:**

1. **Critical/High Severity**:
   - Block PR merge
   - Require immediate remediation
   - Security team review
   - Document exception if false positive

2. **Medium Severity**:
   - Create tracking issue
   - Remediate within 7 days
   - Update in next release

3. **Low Severity**:
   - Create backlog item
   - Remediate when convenient
   - Document in `.checkov.yaml` if accepted risk

### 3. Dependency Vulnerability Response

**If Dependabot alerts on a vulnerability:**

1. **Critical Vulnerabilities**:
   - Emergency patch within 24 hours
   - Test in staging
   - Deploy to production immediately
   - Notify stakeholders

2. **High Vulnerabilities**:
   - Patch within 7 days
   - Test thoroughly
   - Schedule maintenance window
   - Update changelog

3. **Medium/Low Vulnerabilities**:
   - Include in regular update cycle
   - Test with other updates
   - Deploy in next release

### 4. Kubernetes Security Findings

**If kube-bench or kube-hunter identifies issues:**

1. **Review Findings**:
   - Categorize by severity
   - Identify affected components
   - Assess risk and impact

2. **Prioritize Remediation**:
   - High: Fix within 7 days
   - Medium: Fix within 30 days
   - Low: Fix when convenient

3. **Implement Fixes**:
   - Update Kubernetes configs
   - Apply via Helmfile/Ansible
   - Test in staging first
   - Deploy to production

4. **Verify**:
   - Re-run security scans
   - Confirm issues resolved
   - Document changes

### 5. OS Hardening Verification

**After applying security hardening:**

1. **Verify Services**:
   ```bash
   # Check SSH configuration
   ansible all -i inventory.ini -m shell -a "sshd -T | grep -E 'permitrootlogin|passwordauthentication'"
   
   # Check firewall
   ansible all -i inventory.ini -m shell -a "ufw status verbose"
   
   # Check fail2ban
   ansible all -i inventory.ini -m shell -a "fail2ban-client status sshd"
   
   # Check kernel parameters
   ansible all -i inventory.ini -m shell -a "sysctl net.ipv4.conf.all.rp_filter"
   ```

2. **Test Connectivity**:
   - Verify SSH access via Tailscale
   - Confirm kubectl access
   - Test application endpoints

3. **Monitor Logs**:
   - Check `/var/log/auth.log` for issues
   - Review auditd logs
   - Monitor fail2ban bans

## Remediation Guidelines

### General Remediation Process

1. **Assess**:
   - Understand the vulnerability/issue
   - Determine impact and risk
   - Identify affected systems

2. **Plan**:
   - Review remediation options
   - Estimate effort and downtime
   - Schedule maintenance window
   - Notify stakeholders

3. **Implement**:
   - Apply fixes in staging first
   - Test thoroughly
   - Document changes
   - Deploy to production

4. **Verify**:
   - Re-run security scans
   - Confirm issue resolved
   - Monitor for regressions
   - Update documentation

5. **Review**:
   - Post-implementation review
   - Document lessons learned
   - Update procedures
   - Share knowledge

### Common Remediation Scenarios

#### Exposed Secret
```bash
# 1. Rotate secret
# See SECRETS.md for specific procedures

# 2. Remove from git history
git filter-repo --path secrets.yaml --invert-paths

# 3. Update .gitignore
echo "secrets.yaml" >> .gitignore

# 4. Re-encrypt properly
sops -e secrets.yaml > secrets.enc.yaml
git add secrets.enc.yaml
```

#### Helm Chart Vulnerability
```bash
# 1. Update chart version
vim helmfile/config/releases.yaml.gotmpl

# 2. Review changes
cd helmfile && helmfile diff

# 3. Test in staging
helmfile -e staging apply

# 4. Deploy to production
helmfile -e prod apply
```

#### Kubernetes Misconfiguration
```bash
# 1. Update manifest
vim helmfile/manifests/network-policies.yaml

# 2. Validate
kubectl --dry-run=client apply -f helmfile/manifests/network-policies.yaml

# 3. Apply changes
kubectl apply -f helmfile/manifests/network-policies.yaml

# 4. Verify
kubectl describe networkpolicy -A
```

#### OS Security Issue
```bash
# 1. Update hardening playbook
vim ansible/playbooks/security-hardening.yaml

# 2. Test on single node
ansible-playbook -i inventory.ini playbooks/security-hardening.yaml --limit node1

# 3. Apply to all nodes
ansible-playbook -i inventory.ini playbooks/security-hardening.yaml

# 4. Verify
ansible all -i inventory.ini -m shell -a "systemctl status fail2ban"
```

## Reporting and Documentation

### Security Scan Results

All automated scans provide results in multiple formats:

1. **GitHub Security Tab**:
   - Navigate to repository **Security** tab
   - View alerts by tool (TruffleHog, Checkov, etc.)
   - Filter by severity, status, branch

2. **Workflow Summaries**:
   - Available in Actions run summary
   - Includes pass/fail counts
   - Links to detailed findings

3. **Downloadable Artifacts**:
   - JSON reports for all scans
   - SARIF format for security tools
   - Retained per tool configuration

### Compliance Reports

#### Monthly Security Summary

Generate monthly report:

```bash
# TruffleHog findings (last 30 days)
gh api /repos/wcatz/infrastructure/code-scanning/alerts \
  --jq '.[] | select(.created_at > (now - 2592000 | strftime("%Y-%m-%dT%H:%M:%SZ")))' \
  > monthly-trufflehog.json

# Checkov findings
gh run list --workflow=checkov-scan.yaml --limit 30 \
  > monthly-checkov-runs.txt

# Dependabot alerts
gh api /repos/wcatz/infrastructure/dependabot/alerts \
  --jq '.[] | select(.state == "open")' \
  > monthly-dependabot.json
```

#### Quarterly Compliance Review

Quarterly checklist:

- [ ] Review all security scan results
- [ ] Update `.checkov.yaml` with new policies
- [ ] Rotate quarterly secrets (see [SECRETS.md](SECRETS.md))
- [ ] Update Helm chart versions
- [ ] Re-apply OS hardening
- [ ] Test disaster recovery
- [ ] Update this document
- [ ] Team training on new tools/procedures

#### Annual Security Assessment

Annual checklist:

- [ ] Comprehensive penetration test
- [ ] Full infrastructure audit
- [ ] Review and update security policies
- [ ] Rotate annual secrets (age keys, SSH keys)
- [ ] Compliance framework review
- [ ] Tool effectiveness review
- [ ] Budget and resource planning
- [ ] Executive summary report

### Documentation Maintenance

Keep these documents current:

- **[SECURITY.md](SECURITY.md)**: Security policies and procedures
- **[SECRETS.md](SECRETS.md)**: Secret management and rotation
- **[COMPLIANCE.md](COMPLIANCE.md)**: This document
- **[README.md](README.md)**: Update with security features
- **Workflow files**: Keep comments and documentation updated

### Stakeholder Communication

**Who to notify:**

| Event | Notify | Timeline |
|-------|--------|----------|
| Critical vulnerability | All teams | Immediately |
| Security incident | Management + Security | < 1 hour |
| Compliance findings | Team leads | Weekly summary |
| Tool updates | DevOps team | As needed |
| Policy changes | All teams | 2 weeks notice |

**Communication channels:**

- **Urgent**: Direct message, phone call
- **Important**: Email, Slack
- **Routine**: Weekly standup, monthly reports
- **Documentation**: Git commits, PR comments

## Appendix

### Related Documentation

- **[SECURITY.md](SECURITY.md)**: Overall security policy
- **[SECRETS.md](SECRETS.md)**: Secret management guide
- **[README.md](README.md)**: Repository overview
- **[docs/setup.md](docs/setup.md)**: Setup and configuration
- **[docs/operate.md](docs/operate.md)**: Operations guide

### External Resources

- [TruffleHog Documentation](https://github.com/trufflesecurity/trufflehog)
- [Checkov Documentation](https://www.checkov.io/)
- [Dependabot Documentation](https://docs.github.com/en/code-security/dependabot)
- [kube-bench Documentation](https://github.com/aquasecurity/kube-bench)
- [kube-hunter Documentation](https://github.com/aquasecurity/kube-hunter)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)

---

**Document Version**: 1.0  
**Last Updated**: 2024-12-09  
**Next Review**: 2025-03-09 (Quarterly)  
**Owner**: Security Team / DevOps Team
