# GitOps Workflow and Best Practices

This document outlines the GitOps workflow, branch protection requirements, and PR review process for the infrastructure repository.

## Table of Contents

- [Overview](#overview)
- [Branch Protection](#branch-protection)
- [Pull Request Workflow](#pull-request-workflow)
- [Automated Checks](#automated-checks)
- [Pre-commit Hooks](#pre-commit-hooks)
- [Deployment Process](#deployment-process)
- [Best Practices](#best-practices)

## Overview

This repository follows GitOps principles where:

1. **Git is the single source of truth** for infrastructure and application configuration
2. **All changes go through Pull Requests** with mandatory reviews
3. **Automated testing validates changes** before merge
4. **Deployments are triggered from main branch** after merge
5. **Rollback is achieved through git revert** and redeployment

### GitOps Principles

```
┌──────────────────────────────────────────────────────────────────┐
│                         GitOps Flow                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Developer      Pull Request       Automated         Deployment  │
│  ┌──────┐      ┌──────────┐       ┌────────┐       ┌─────────┐ │
│  │ Push │  →   │ Review & │   →   │ Tests  │   →   │ Merge & │ │
│  │ Code │      │ Approve  │       │ Checks │       │ Deploy  │ │
│  └──────┘      └──────────┘       └────────┘       └─────────┘ │
│                                                                   │
│     ↑                                                      ↓      │
│     │                                                      │      │
│     └──────────────── Git Revert ─────────────────────────┘      │
│                       (if issues)                                 │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

## Branch Protection

### Required Settings for `main` Branch

Enable the following branch protection rules on the `main` branch:

#### 1. Require Pull Request Reviews

- **Require approvals**: At least 1 approval required
- **Dismiss stale reviews**: Yes (when new commits are pushed)
- **Require review from code owners**: Yes (if CODEOWNERS file exists)
- **Restrict who can dismiss reviews**: Repository administrators only

#### 2. Require Status Checks

Required status checks before merging:

- ✅ `validate-yaml` - YAML syntax validation
- ✅ `helm-lint` - Helm chart linting
- ✅ `security-scan` - Trivy security scanning
- ✅ `checkov` - IaC security scanning (Checkov)
- ✅ `helmfile-diff` - Preview Kubernetes changes

**Status check settings**:
- Require branches to be up to date: Yes
- Do not allow bypassing: Yes

#### 3. Require Signed Commits

- **Require signed commits**: Recommended (optional)
- Ensures commit authenticity via GPG/SSH signatures

#### 4. Additional Protection Rules

- **Require linear history**: Yes (no merge commits, use squash or rebase)
- **Include administrators**: Yes (admins follow same rules)
- **Restrict pushes**: Yes (only through pull requests)
- **Allow force pushes**: No
- **Allow deletions**: No

### Configuring Branch Protection

#### Via GitHub Web UI

1. Navigate to: **Settings** → **Branches** → **Branch protection rules**
2. Click **Add rule**
3. Set **Branch name pattern**: `main`
4. Enable all protections listed above
5. Click **Create** or **Save changes**

#### Via GitHub CLI

```bash
# Install GitHub CLI if not already installed
# brew install gh  # macOS
# See: https://cli.github.com/manual/installation

# Authenticate
gh auth login

# Enable branch protection
gh api repos/wcatz/infrastructure/branches/main/protection \
  --method PUT \
  --field required_pull_request_reviews[required_approving_review_count]=1 \
  --field required_pull_request_reviews[dismiss_stale_reviews]=true \
  --field required_status_checks[strict]=true \
  --field required_status_checks[contexts][]=validate-yaml \
  --field required_status_checks[contexts][]=helm-lint \
  --field required_status_checks[contexts][]=security-scan \
  --field required_status_checks[contexts][]=checkov \
  --field enforce_admins=true \
  --field required_linear_history=true \
  --field allow_force_pushes=false \
  --field allow_deletions=false
```

## Pull Request Workflow

### 1. Create Feature Branch

```bash
# Update main branch
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/add-new-service

# Or for bugfixes
git checkout -b fix/correct-network-policy
```

### 2. Make Changes

```bash
# Make your changes
vim helmfile/values/prometheus-values.yaml

# Stage changes
git add helmfile/values/prometheus-values.yaml

# Commit with descriptive message
git commit -m "feat(monitoring): increase Prometheus retention to 30 days"
```

**Commit message format**:
```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `chore`: Maintenance tasks
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `ci`: CI/CD changes

### 3. Push Branch and Create PR

```bash
# Push branch
git push origin feature/add-new-service

# Create PR via GitHub CLI
gh pr create \
  --title "Add new monitoring service" \
  --body "Adds Prometheus retention configuration to improve metrics history" \
  --label "enhancement" \
  --label "monitoring"

# Or create PR via web UI
# Navigate to: https://github.com/wcatz/infrastructure/pulls
# Click "New pull request"
```

### 4. PR Description Template

Use this template for PR descriptions:

```markdown
## Description
Brief description of what this PR does.

## Changes Made
- Change 1
- Change 2
- Change 3

## Testing
- [ ] Tested in local environment
- [ ] Tested in staging environment
- [ ] All automated checks passed

## Deployment Notes
Any special considerations for deployment (e.g., manual steps, downtime)

## Checklist
- [ ] Code follows repository conventions
- [ ] Documentation updated (if applicable)
- [ ] Secrets properly encrypted (if applicable)
- [ ] Helmfile diff reviewed
- [ ] Breaking changes documented

## Related Issues
Closes #123
```

### 5. Automated Review Process

Once PR is created, automated workflows run:

1. **YAML Validation** - Ensures syntax correctness
2. **Helm Linting** - Validates Helm chart structure
3. **Security Scanning** - Trivy scans for vulnerabilities
4. **Checkov Scan** - IaC security analysis
5. **TruffleHog Scan** - Secrets detection
6. **Helmfile Diff** - Preview Kubernetes changes

**PR will show**:
- ✅ All checks passed - ready for review
- ❌ Checks failed - review errors and fix

### 6. Code Review

**Reviewer responsibilities**:

- [ ] Review code changes for correctness
- [ ] Verify Helmfile diff output is expected
- [ ] Check security scan results
- [ ] Ensure secrets are encrypted
- [ ] Validate documentation updates
- [ ] Test changes if complex
- [ ] Request changes if needed
- [ ] Approve when satisfied

**Review checklist**:

```markdown
## Review Checklist

### Code Quality
- [ ] Changes are clear and well-structured
- [ ] Follows repository conventions
- [ ] No unnecessary changes

### Security
- [ ] No secrets in plaintext
- [ ] Security scans passed
- [ ] Network policies updated (if needed)
- [ ] RBAC configured correctly

### Functionality
- [ ] Helmfile diff is reasonable
- [ ] Resource limits are appropriate
- [ ] Service configuration is correct

### Documentation
- [ ] README updated (if needed)
- [ ] Comments explain complex logic
- [ ] Breaking changes documented

### Testing
- [ ] Automated tests pass
- [ ] Manual testing performed (if needed)
```

### 7. Merge PR

After approval and all checks pass:

1. **Squash and merge** (recommended) - Creates single clean commit
2. **Rebase and merge** - Maintains individual commits (if needed)
3. **Merge commit** - Not recommended (violates linear history)

```bash
# Via GitHub CLI
gh pr merge --squash --delete-branch

# Or via web UI
# Click "Squash and merge" button
# Confirm merge
```

### 8. Deployment

After merge to `main`:

1. Automated deployment workflows trigger (if configured)
2. Or manually deploy:

```bash
cd helmfile
helmfile -e prod diff  # Preview changes
helmfile -e prod apply # Deploy to production
```

## Automated Checks

### Helmfile Diff Preview

On every PR, the `helmfile-diff` workflow runs and comments with preview:

**Example output**:

```diff
## Helmfile Diff Output

### Default Environment

```diff
prometheus, prometheus, Deployment (apps) has changed:
  # Source: prometheus/templates/server-deployment.yaml
  spec:
    template:
      spec:
        containers:
        - name: prometheus-server
-         image: "quay.io/prometheus/prometheus:v2.45.0"
+         image: "quay.io/prometheus/prometheus:v2.46.0"
```

### Next Steps

1. **Review the diff** to ensure changes are as expected
2. **Merge the PR** after approval
3. **Deploy changes** using the helmfile-apply workflow
```

This helps reviewers understand the impact of changes before merging.

### Security Scanning

Multiple security tools scan every PR:

1. **Trivy**: Container and configuration scanning
2. **Checkov**: IaC security policies
3. **TruffleHog**: Secrets detection

Results appear in:
- PR status checks
- PR comments
- GitHub Security tab

## Pre-commit Hooks

Pre-commit hooks help catch issues before pushing code.

### Installation

```bash
# Install pre-commit
pip install pre-commit

# Or on macOS
brew install pre-commit

# Install hooks in repository
cd /path/to/infrastructure
pre-commit install
```

### Configuration

Create `.pre-commit-config.yaml`:

```yaml
repos:
  # YAML linting
  - repo: https://github.com/adrienverge/yamllint
    rev: v1.32.0
    hooks:
      - id: yamllint
        args: [-c, .yamllint]
        
  # Trailing whitespace and file endings
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: check-merge-conflict
        
  # Secrets detection
  - repo: https://github.com/trufflesecurity/trufflehog
    rev: v3.63.0
    hooks:
      - id: trufflehog
        args:
          - --config=.trufflehog.yaml
          
  # Ansible linting
  - repo: https://github.com/ansible/ansible-lint
    rev: v6.18.0
    hooks:
      - id: ansible-lint
        files: ^ansible/
```

### Usage

```bash
# Hooks run automatically on git commit
git commit -m "feat: add new service"

# Run manually on all files
pre-commit run --all-files

# Skip hooks (not recommended)
git commit --no-verify -m "emergency fix"
```

## Deployment Process

### Staging Deployment

```bash
# 1. Ensure branch is up to date
git checkout main
git pull origin main

# 2. Review changes
cd helmfile
helmfile -e staging diff

# 3. Deploy to staging
helmfile -e staging apply

# 4. Verify deployment
kubectl get pods -A
kubectl get deployments -A

# 5. Test functionality
# Run smoke tests, verify monitoring
```

### Production Deployment

**Manual deployment**:

```bash
# 1. Deploy to staging first
helmfile -e staging apply

# 2. Test staging thoroughly
# Run full test suite, manual verification

# 3. Create production deployment PR or trigger workflow
gh workflow run deploy-production.yaml

# 4. Review Helmfile diff in workflow
# 5. Approve deployment (if required)
# 6. Monitor deployment progress
# 7. Run post-deployment verification
```

**Automated deployment** (if configured):

Triggered automatically after merge to `main`:

1. Workflow runs pre-deployment validation
2. Creates Velero backup
3. Runs helmfile diff
4. Applies changes to cluster
5. Waits for deployments to be ready
6. Runs smoke tests
7. Reports success/failure

### Rollback Process

If deployment causes issues:

**Option 1: Git Revert**

```bash
# Find the problematic commit
git log --oneline -10

# Revert the commit
git revert <commit-sha>

# Push revert
git push origin main

# Redeploy
cd helmfile
helmfile -e prod apply
```

**Option 2: Velero Restore**

```bash
# List recent backups
kubectl get backups -n velero

# Restore from backup
velero restore create --from-backup pre-deploy-20241209-120000

# Monitor restore
velero restore describe <restore-name>
```

**Option 3: Helmfile Rollback**

```bash
# Checkout previous version
git checkout <previous-commit>

# Deploy previous version
cd helmfile
helmfile -e prod apply

# Return to main
git checkout main
```

## Best Practices

### 1. Small, Focused PRs

- ✅ Make small, incremental changes
- ✅ One logical change per PR
- ✅ Easy to review and understand
- ❌ Avoid large, multi-purpose PRs

### 2. Descriptive Commit Messages

```bash
# Good
git commit -m "feat(monitoring): add Prometheus retention configuration

Increases retention from 15d to 30d to support longer-term analysis.
Updates resource requests to handle increased storage."

# Bad
git commit -m "fix stuff"
git commit -m "update config"
```

### 3. Test Before Pushing

```bash
# Lint locally
cd helmfile && yamllint .
cd ansible && yamllint .

# Validate Helmfile
cd helmfile && helmfile template > /dev/null

# Check for secrets
grep -r "password\|secret\|token" . --exclude-dir=.git

# Run pre-commit hooks
pre-commit run --all-files
```

### 4. Keep Branches Up to Date

```bash
# Regularly sync with main
git checkout feature/my-feature
git fetch origin
git rebase origin/main

# Or merge main into branch
git merge origin/main
```

### 5. Meaningful PR Titles and Descriptions

- Use conventional commit format
- Explain what and why
- Link to related issues
- Include testing notes
- Document breaking changes

### 6. Encrypt Secrets Properly

```bash
# Always encrypt before committing
sops -e secret.yaml > secret.enc.yaml

# Verify encryption
grep -q "sops:" secret.enc.yaml && echo "Encrypted" || echo "NOT ENCRYPTED!"

# Never commit plaintext
rm secret.yaml
```

### 7. Review Helmfile Diff Carefully

- Understand all changes before approving
- Question unexpected differences
- Verify image tags and versions
- Check resource changes
- Validate configuration updates

### 8. Document Complex Changes

```yaml
# Bad
replicas: 5

# Good
# Increased from 3 to 5 to handle peak traffic
# Based on load testing results from 2024-12-01
replicas: 5
```

### 9. Use Labels Effectively

GitHub labels for PRs:

- `enhancement`: New features
- `bug`: Bug fixes
- `documentation`: Doc updates
- `security`: Security-related changes
- `dependencies`: Dependency updates
- `breaking-change`: Breaking changes
- `needs-review`: Awaiting review
- `work-in-progress`: Not ready for review

### 10. Follow Security Guidelines

- Never commit plaintext secrets
- Always use SOPS encryption
- Review security scan results
- Address vulnerabilities promptly
- Follow least privilege principle
- Keep dependencies updated

## Related Documentation

- **[COMPLIANCE.md](COMPLIANCE.md)**: Audit schedules and compliance procedures
- **[SECURITY.md](SECURITY.md)**: Security policies and incident response
- **[SECRETS.md](SECRETS.md)**: Secret management best practices
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Contribution guidelines
- **[README.md](README.md)**: Repository overview

## Resources

- [GitHub Branch Protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [Pre-commit Framework](https://pre-commit.com/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitOps Principles](https://www.gitops.tech/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)

---

**Last Updated**: 2024-12-09  
**Owner**: DevOps Team / Platform Team
