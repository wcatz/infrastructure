# GitHub Actions OIDC Setup Guide

This document explains how to configure OpenID Connect (OIDC) for GitHub Actions to authenticate with cloud providers without long-lived credentials.

## Overview

OIDC allows GitHub Actions workflows to authenticate with cloud providers using short-lived tokens instead of storing long-lived credentials. This improves security by:

- **No stored credentials**: No access keys or service account keys in GitHub Secrets
- **Short-lived tokens**: Tokens expire automatically
- **Scoped access**: Fine-grained permissions per workflow
- **Audit trail**: All authentication is logged by cloud provider

## Supported Cloud Providers

- AWS (IAM Roles)
- Azure (Workload Identity)
- Google Cloud Platform (Workload Identity Federation)
- HashiCorp Vault

## AWS OIDC Setup

### 1. Create OIDC Identity Provider in AWS

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. Create IAM Role for GitHub Actions

Create a trust policy file `github-actions-trust-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

For environment-specific roles (recommended):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:environment:production"
        }
      }
    }
  ]
}
```

Create the role:

```bash
# Create the role
aws iam create-role \
  --role-name github-actions-production \
  --assume-role-policy-document file://github-actions-trust-policy.json

# Attach necessary policies
aws iam attach-role-policy \
  --role-name github-actions-production \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# Attach custom policy for Velero, EKS access, etc.
aws iam attach-role-policy \
  --role-name github-actions-production \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/GitHubActionsDeploymentPolicy
```

### 3. Update GitHub Actions Workflow

Add OIDC authentication to your workflow:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
      contents: read
    steps:
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT_ID:role/github-actions-production
          role-session-name: github-deploy-${{ github.run_id }}
          aws-region: us-west-2
      
      # Now AWS credentials are available for subsequent steps
      - name: Use AWS CLI
        run: aws sts get-caller-identity
```

## Azure OIDC Setup

### 1. Create Azure AD Application

```bash
# Create application
az ad app create --display-name github-actions-infrastructure

# Get application ID
APP_ID=$(az ad app list --display-name github-actions-infrastructure --query '[0].appId' -o tsv)

# Create service principal
az ad sp create --id $APP_ID

# Get service principal object ID
SP_OBJECT_ID=$(az ad sp list --display-name github-actions-infrastructure --query '[0].id' -o tsv)
```

### 2. Configure Federated Credentials

```bash
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "github-actions-production",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR_ORG/YOUR_REPO:environment:production",
    "description": "GitHub Actions Production Environment",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### 3. Assign Azure Roles

```bash
# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Assign Contributor role (or more specific role)
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/YOUR_RESOURCE_GROUP
```

### 4. Update GitHub Actions Workflow

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Use Azure CLI
        run: az account show
```

Store these as GitHub Secrets (not sensitive, just IDs):
- `AZURE_CLIENT_ID`: Application (client) ID
- `AZURE_TENANT_ID`: Directory (tenant) ID
- `AZURE_SUBSCRIPTION_ID`: Subscription ID

## Google Cloud Platform OIDC Setup

### 1. Create Workload Identity Pool

```bash
# Create pool
gcloud iam workload-identity-pools create github-actions-pool \
  --location=global \
  --display-name="GitHub Actions Pool"

# Create provider
gcloud iam workload-identity-pools providers create-oidc github-actions-provider \
  --location=global \
  --workload-identity-pool=github-actions-pool \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository_owner == 'YOUR_ORG'"
```

### 2. Create Service Account and Grant Permissions

```bash
# Create service account
gcloud iam service-accounts create github-actions \
  --display-name="GitHub Actions Service Account"

# Grant permissions
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:github-actions@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

# Allow Workload Identity to impersonate service account
gcloud iam service-accounts add-iam-policy-binding \
  github-actions@PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/attribute.repository/YOUR_ORG/YOUR_REPO"
```

### 3. Update GitHub Actions Workflow

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider'
          service_account: 'github-actions@PROJECT_ID.iam.gserviceaccount.com'
      
      - name: Use gcloud CLI
        run: gcloud auth list
```

## HashiCorp Vault OIDC Setup

### 1. Configure GitHub OIDC in Vault

```bash
# Enable JWT auth method
vault auth enable jwt

# Configure JWT auth
vault write auth/jwt/config \
  oidc_discovery_url="https://token.actions.githubusercontent.com" \
  bound_issuer="https://token.actions.githubusercontent.com"

# Create role for GitHub Actions
vault write auth/jwt/role/github-actions \
  role_type="jwt" \
  bound_audiences="https://github.com/YOUR_ORG" \
  bound_subject="repo:YOUR_ORG/YOUR_REPO:*" \
  user_claim="actor" \
  policies="github-actions-policy" \
  ttl=1h
```

### 2. Update GitHub Actions Workflow

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Get Vault Token
        uses: hashicorp/vault-action@v2
        with:
          url: https://vault.example.com
          method: jwt
          role: github-actions
          secrets: |
            secret/data/production/database password | DB_PASSWORD
      
      - name: Use secrets
        run: echo "Database password length: ${#DB_PASSWORD}"
```

## Security Best Practices

### 1. Scope OIDC Access

**DO**: Scope to specific repositories and environments
```json
"token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:environment:production"
```

**DON'T**: Allow all repositories
```json
"token.actions.githubusercontent.com:sub": "repo:myorg/*:*"
```

### 2. Use Environment Protection Rules

Configure GitHub environments with:
- Required reviewers for production
- Wait timer before deployment
- Deployment branches restriction

### 3. Implement Least Privilege

Grant only necessary permissions:
- Separate roles for dev/staging/production
- Specific resource access only
- Read-only where possible

### 4. Monitor and Audit

- Enable CloudTrail (AWS) / Activity Log (Azure) / Audit Logs (GCP)
- Set up alerts for unusual authentication patterns
- Regularly review role assignments

### 5. Rotate and Review

- Quarterly review of OIDC configurations
- Remove unused roles and permissions
- Update trust policies as needed

## Troubleshooting

### Common Issues

#### 1. "Error: Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Solution**: Check trust policy conditions match your repository and environment:
```bash
aws iam get-role --role-name github-actions-production --query 'Role.AssumeRolePolicyDocument'
```

#### 2. "Error: Token audience validation failed"

**Solution**: Ensure `aud` claim matches expected value:
- AWS: `sts.amazonaws.com`
- Azure: `api://AzureADTokenExchange`
- GCP: Default is project number

#### 3. "Error: Subject claim validation failed"

**Solution**: Verify the subject format matches GitHub's claim:
- Main branch: `repo:ORG/REPO:ref:refs/heads/main`
- Environment: `repo:ORG/REPO:environment:ENV_NAME`
- Pull request: `repo:ORG/REPO:pull_request`

### Debug OIDC Token

Add this step to your workflow to inspect the token:

```yaml
- name: Debug OIDC Token
  run: |
    OIDC_TOKEN=$(curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
    echo $OIDC_TOKEN | cut -d'.' -f2 | base64 -d | jq
```

## Migration from Long-lived Credentials

### Step 1: Set up OIDC (in parallel)

Configure OIDC while keeping existing credentials working.

### Step 2: Test OIDC in non-production

Deploy to dev/staging using OIDC to verify configuration.

### Step 3: Update production workflows

Switch production to OIDC after successful testing.

### Step 4: Remove old credentials

After verification:
1. Delete access keys / service account keys from GitHub Secrets
2. Delete unused IAM users / service accounts
3. Document the change

## Additional Resources

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS OIDC Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Azure Workload Identity](https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation)
- [GCP Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [HashiCorp Vault JWT Auth](https://www.vaultproject.io/docs/auth/jwt)

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review cloud provider documentation
3. Open an issue in the repository
