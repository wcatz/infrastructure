# GitOps Workflows Guide

Complete guide for setting up and using GitOps workflows with GitHub Actions for automated deployments.

## Table of Contents

- [Overview](#overview)
- [GitHub Actions Setup](#github-actions-setup)
- [SOPS Integration](#sops-integration)
- [Automated Deployments](#automated-deployments)
- [Multi-Environment Workflows](#multi-environment-workflows)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

GitOps is a way to do Kubernetes cluster management and application delivery using Git as the single source of truth.

### Benefits

- **Version Control**: All changes tracked in Git
- **Audit Trail**: Complete history of who changed what and when
- **Rollback**: Easy rollback to previous versions
- **Automation**: Automated validation and deployment
- **Consistency**: Same process for all environments
- **Collaboration**: Pull request reviews before changes

### Workflow Architecture

```
Developer → Git Push → GitHub → Workflow Trigger → Validation → Deployment → Kubernetes
                          ↓
                    Pull Request Review
                          ↓
                    Automated Diff Preview
                          ↓
                    Merge to Main
                          ↓
                    Manual Deployment Trigger
```

## GitHub Actions Setup

### Prerequisites

1. **Kubernetes Cluster**: Running k3s cluster
2. **Kubeconfig**: Admin access to cluster
3. **GitHub Repository**: This infrastructure repository
4. **SOPS Keys**: For secret decryption (optional)

### Step 1: Configure Repository Secrets

Navigate to repository Settings → Secrets and Variables → Actions:

#### Required Secrets

**KUBECONFIG**:
```bash
# Get kubeconfig from k3s server
scp ubuntu@k3s-server:/etc/rancher/k3s/k3s.yaml /tmp/kubeconfig

# Update server address
sed -i 's/127.0.0.1/YOUR_SERVER_IP/g' /tmp/kubeconfig

# Base64 encode
cat /tmp/kubeconfig | base64 -w 0

# Add to GitHub Secrets as KUBECONFIG
# Clean up
rm /tmp/kubeconfig
```

**SOPS_AGE_KEY** (if using SOPS):
```bash
# Get your age private key
cat ~/.config/sops/age/keys.txt

# Copy the entire content including:
# # created: <timestamp>
# # public key: <public-key>
# <PRIVATE-KEY>

# Add to GitHub Secrets as SOPS_AGE_KEY
```

### Step 2: Configure Environments

Create environment-specific protection rules:

#### Development Environment
- Settings → Environments → New environment → "dev"
- No required reviewers
- Allow all branches

#### Staging Environment
- Settings → Environments → New environment → "staging"
- Required reviewers: 1
- Deployment branches: main only

#### Production Environment
- Settings → Environments → New environment → "production"
- Required reviewers: 2+
- Deployment branches: main only
- Wait timer: 5 minutes

### Step 3: Enable Workflows

The repository includes two pre-configured workflows:

1. **helmfile-diff.yaml**: Automated validation on PRs
2. **helmfile-apply.yaml**: Manual deployment workflow

No configuration needed - they're ready to use!

## SOPS Integration

### Workflow with SOPS Decryption

Create `.github/workflows/deploy-with-sops.yaml`:

```yaml
name: Deploy with SOPS

on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        type: choice
        options:
          - dev
          - staging
          - production

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Install tools
        run: |
          # Install Helm
          curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
          
          # Install helm-diff
          helm plugin install https://github.com/databus23/helm-diff
          
          # Install Helmfile
          wget -O helmfile https://github.com/helmfile/helmfile/releases/download/v0.159.0/helmfile_0.159.0_linux_amd64
          chmod +x helmfile
          sudo mv helmfile /usr/local/bin/
          
          # Install SOPS
          wget -O sops https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
          chmod +x sops
          sudo mv sops /usr/local/bin/
          
          # Install kubectl
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
      
      - name: Setup SOPS key
        env:
          SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}
        run: |
          mkdir -p ~/.config/sops/age
          echo "$SOPS_AGE_KEY" > ~/.config/sops/age/keys.txt
          chmod 600 ~/.config/sops/age/keys.txt
      
      - name: Configure kubectl
        env:
          KUBECONFIG_CONTENT: ${{ secrets.KUBECONFIG }}
        run: |
          mkdir -p ~/.kube
          echo "$KUBECONFIG_CONTENT" | base64 -d > ~/.kube/config
          chmod 600 ~/.kube/config
      
      - name: Decrypt and deploy secrets
        working-directory: helmfile
        run: |
          # Decrypt all secrets
          if [ -d "../secrets/${{ inputs.environment }}" ]; then
            for file in ../secrets/${{ inputs.environment }}/*.yaml; do
              echo "Deploying secret: $file"
              sops -d "$file" | kubectl apply -f -
            done
          fi
      
      - name: Deploy Helmfile
        working-directory: helmfile
        run: |
          helmfile -e ${{ inputs.environment }} apply --suppress-secrets
      
      - name: Verify deployment
        run: |
          kubectl get pods -A
          kubectl get svc -A
```

### SOPS with AWS KMS

For AWS KMS-encrypted secrets:

```yaml
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: us-west-2
      
      - name: Decrypt and deploy secrets
        run: |
          for file in secrets/${{ inputs.environment }}/*.enc.yaml; do
            sops -d "$file" | kubectl apply -f -
          done
```

## Automated Deployments

### Pull Request Validation

The `helmfile-diff` workflow automatically runs on every PR:

```yaml
name: Helmfile Diff

on:
  pull_request:
    paths:
      - 'helmfile/**'
      - 'ansible/**'

jobs:
  diff:
    runs-on: ubuntu-latest
    steps:
      # ... (see .github/workflows/helmfile-diff.yaml)
```

**What it does**:
1. Validates YAML syntax
2. Renders Helmfile templates
3. Generates diff preview
4. Posts comment to PR with changes
5. Fails if errors detected

### Manual Deployment

Trigger deployment via GitHub Actions UI:

1. Go to Actions tab
2. Select "Helmfile Apply" workflow
3. Click "Run workflow"
4. Select environment (dev/staging/production)
5. Click "Run workflow" button
6. Monitor execution

### Automated Deployment on Merge

Create `.github/workflows/auto-deploy-dev.yaml`:

```yaml
name: Auto Deploy to Dev

on:
  push:
    branches:
      - main
    paths:
      - 'helmfile/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: dev
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      # ... (same setup steps as manual deployment)
      
      - name: Deploy to dev
        working-directory: helmfile
        run: |
          helmfile -e dev apply --suppress-secrets
```

## Multi-Environment Workflows

### Progressive Deployment

Deploy to dev → staging → production with approvals:

```yaml
name: Progressive Deployment

on:
  workflow_dispatch:

jobs:
  deploy-dev:
    runs-on: ubuntu-latest
    environment: dev
    steps:
      # ... deploy to dev
  
  deploy-staging:
    needs: deploy-dev
    runs-on: ubuntu-latest
    environment: staging
    steps:
      # ... deploy to staging
  
  deploy-production:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production
    steps:
      # ... deploy to production
```

### Environment-Specific Secrets

```yaml
      - name: Deploy with environment secrets
        env:
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}  # Different per environment
          API_KEY: ${{ secrets.API_KEY }}
        run: |
          kubectl create secret generic app-secrets \
            --from-literal=db-password="$DB_PASSWORD" \
            --from-literal=api-key="$API_KEY" \
            -n production \
            --dry-run=client -o yaml | kubectl apply -f -
```

## Security Best Practices

### Secret Handling

```yaml
# Always use --suppress-secrets flag
helmfile apply --suppress-secrets

# Never echo secrets
# BAD:
echo "$SECRET_VALUE"

# GOOD:
if [ -z "$SECRET_VALUE" ]; then
  echo "Secret not set"
  exit 1
fi
```

### OIDC Authentication

Use GitHub's OIDC for AWS/Azure/GCP authentication instead of static credentials:

**AWS Example**:

```yaml
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GitHubActionsRole
          aws-region: us-west-2
          role-session-name: GitHubActions-${{ github.run_id }}
```

**Trust Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:wcatz/infrastructure:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

### Kubeconfig Security

```yaml
      - name: Setup kubeconfig
        env:
          KUBECONFIG_CONTENT: ${{ secrets.KUBECONFIG }}
        run: |
          mkdir -p ~/.kube
          echo "$KUBECONFIG_CONTENT" | base64 -d > ~/.kube/config
          chmod 600 ~/.kube/config
      
      # Always clean up at end
      - name: Cleanup
        if: always()
        run: |
          rm -f ~/.kube/config
          rm -f ~/.config/sops/age/keys.txt
```

### Artifact Attestation

Sign and verify deployments:

```yaml
      - name: Generate deployment manifest
        run: |
          helmfile template > deployment-manifest.yaml
      
      - name: Attest deployment
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: 'deployment-manifest.yaml'
```

## Troubleshooting

### Workflow Fails on Helmfile Diff

```bash
# Check YAML syntax locally
cd helmfile
yamllint .

# Test Helmfile rendering
helmfile template --suppress-secrets > /dev/null

# Check specific release
helmfile -l name=haproxy-ingress template
```

### Cannot Connect to Cluster

```bash
# Verify kubeconfig secret
# 1. Decode secret locally
echo "$KUBECONFIG_SECRET" | base64 -d > /tmp/config

# 2. Test connection
KUBECONFIG=/tmp/config kubectl get nodes

# 3. Check server address
grep server: /tmp/config

# 4. Verify network access from GitHub Actions
# GitHub Actions runs from various IPs, may need to whitelist
```

### SOPS Decryption Fails

```bash
# Verify age key format
cat ~/.config/sops/age/keys.txt
# Should contain:
# # created: ...
# # public key: age1...
# AGE-SECRET-KEY-1...

# Test decryption locally
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
sops -d secrets/dev/test.yaml

# Verify .sops.yaml configuration
cat .sops.yaml
```

### Deployment Timeout

```yaml
      - name: Deploy with timeout
        timeout-minutes: 30  # Increase for large deployments
        run: |
          helmfile apply --timeout 600  # 10 minutes per release
```

### Debugging Workflows

Enable debug logging:

```yaml
      - name: Enable debug
        run: |
          set -x  # Enable bash debug mode
          
      - name: Debug kubectl
        if: failure()
        run: |
          kubectl get pods -A
          kubectl get events -A --sort-by='.lastTimestamp'
```

## Advanced Patterns

### Blue-Green Deployments

```yaml
      - name: Deploy to green environment
        run: |
          helmfile -e production-green apply
      
      - name: Run smoke tests
        run: |
          # Test green environment
          curl https://green.example.com/health
      
      - name: Switch traffic
        run: |
          kubectl patch ingress app-ingress -p '{"spec":{"rules":[{"host":"app.example.com","http":{"paths":[{"backend":{"service":{"name":"app-green"}}}]}}]}}'
      
      - name: Decommission blue
        run: |
          helmfile -e production-blue destroy
```

### Rollback Workflow

```yaml
name: Rollback

on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        type: choice
        options: [dev, staging, production]
      commit_sha:
        description: 'Commit SHA to rollback to'
        required: true

jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout at specific commit
        uses: actions/checkout@v3
        with:
          ref: ${{ inputs.commit_sha }}
      
      - name: Deploy previous version
        run: |
          helmfile -e ${{ inputs.environment }} apply --suppress-secrets
```

## Best Practices

1. **Always use --suppress-secrets**: Prevent secret exposure in logs
2. **Require approvals for production**: Use environment protection rules
3. **Test in lower environments first**: dev → staging → production
4. **Use OIDC over static credentials**: More secure authentication
5. **Enable branch protection**: Require reviews before merge
6. **Run validation on every PR**: Catch issues early
7. **Use environment-specific secrets**: Never share production secrets
8. **Clean up temporary files**: Remove kubeconfig and keys after use
9. **Monitor workflow runs**: Set up alerts for failures
10. **Document deployment process**: Keep runbooks updated

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [GitOps Principles](https://www.gitops.tech/)
- [Kubernetes GitOps](https://kubernetes.io/blog/2021/05/21/gitops-with-kubernetes/)
- [ArgoCD](https://argo-cd.readthedocs.io/) - Alternative GitOps tool
- [FluxCD](https://fluxcd.io/) - Alternative GitOps tool
