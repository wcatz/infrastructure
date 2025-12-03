# Infrastructure Management

This repository contains infrastructure management tools and GitOps workflows.

## Structure

- **helmfile/**: Helmfile configurations for Kubernetes deployments
  - **helmfile.yaml**: Main Helmfile configuration defining chart releases
  - **values/**: Helm values files for each chart
- **.github/workflows/**: GitHub Actions workflows for GitOps automation
  - **helmfile-diff.yaml**: Automatic diff on pull requests
  - **helmfile-apply.yaml**: Manual deployment workflow

## GitOps Workflows

This repository uses GitHub Actions to implement GitOps practices with Helmfile.

### Helmfile Diff Workflow

The `helmfile-diff` workflow automatically runs on all pull requests that modify the `helmfile/` directory. It provides a detailed diff of changes that would be applied to the Kubernetes cluster.

**How it works:**
1. Create a pull request with changes to Helmfile configurations
2. The workflow automatically triggers and runs `helmfile diff`
3. A comment is posted to the PR showing the proposed changes
4. Review the diff output before merging

### Manual Helmfile Apply Workflow

The `helmfile-apply` workflow allows authorized users to manually deploy changes to the Kubernetes cluster after PR approval and merge.

**How to trigger:**
1. Navigate to the "Actions" tab in GitHub
2. Select "Helmfile Apply" workflow
3. Click "Run workflow"
4. Select the target environment (default, staging, or production)
5. Click "Run workflow" to start the deployment

**Prerequisites:**
- Configure Kubernetes credentials in repository secrets
- Set `KUBECONFIG` secret with base64-encoded kubeconfig content
- Ensure proper RBAC permissions are configured

## Helmfile Configuration

### Adding a New Chart

1. Add the chart repository to `helmfile/helmfile.yaml` under `repositories:`
2. Add a new release definition under `releases:`
3. Create a values file in `helmfile/values/` (e.g., `my-chart-values.yaml`)
4. Reference the values file in the release definition

Example:
```yaml
releases:
  - name: my-app
    namespace: my-namespace
    createNamespace: true
    chart: my-repo/my-chart
    version: 1.0.0
    values:
      - values/my-app-values.yaml
```

### Modifying Chart Values

1. Edit the corresponding values file in `helmfile/values/`
2. Create a pull request with your changes
3. Review the diff output posted by the workflow
4. Merge the PR after approval
5. Manually trigger the `helmfile-apply` workflow to deploy

## Example Charts

This repository includes example configurations for:

- **Prometheus**: Monitoring and alerting stack (namespace: `monitoring`)
- **NGINX Ingress Controller**: Ingress controller for routing (namespace: `ingress-nginx`)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes to the Helmfile configuration
4. Submit a pull request
5. Wait for the automatic diff workflow to complete
6. Address any review feedback
7. After merge, coordinate with maintainers to trigger deployment

## Security

- Never commit sensitive data or secrets to this repository
- Use Kubernetes secrets or external secret management tools
- The workflows use `--suppress-secrets` flag to avoid exposing sensitive data in logs
- Configure repository environments and protection rules for production deployments

## License
This project is licensed under the MIT License.