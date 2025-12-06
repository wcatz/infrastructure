# Contributing to Infrastructure

Thank you for your interest in contributing to this infrastructure project! This document provides guidelines and best practices for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Workflow](#development-workflow)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow
- Prioritize security and reliability

## How to Contribute

### Reporting Issues

When reporting issues, please include:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Environment details (k8s version, OS, etc.)
- Relevant logs or error messages

### Suggesting Enhancements

For feature requests or enhancements:
- Describe the use case and benefits
- Propose a solution or approach
- Consider backward compatibility
- Think about security implications

## Development Workflow

### 1. Fork and Clone

```bash
# Fork the repository on GitHub
# Clone your fork
git clone https://github.com/YOUR_USERNAME/infrastructure.git
cd infrastructure
```

### 2. Create a Branch

```bash
# Create a feature branch
git checkout -b feature/your-feature-name

# Or for bug fixes
git checkout -b fix/bug-description
```

### 3. Make Changes

Follow the coding standards and test your changes thoroughly.

### 4. Commit Changes

```bash
# Use clear, descriptive commit messages
git add .
git commit -m "Add feature: description of changes"
```

Commit message format:
- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit first line to 72 characters
- Reference issues and PRs when applicable

### 5. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a pull request on GitHub.

## Pull Request Process

### Before Submitting

1. **Test Your Changes**
   ```bash
   # Validate YAML files
   yamllint helmfile/ ansible/
   
   # Test Helmfile templates
   cd helmfile
   helmfile template --suppress-secrets
   
   # Run diff to preview changes
   helmfile diff --suppress-secrets
   ```

2. **Update Documentation**
   - Update relevant README files
   - Add comments for complex configurations
   - Update CHANGELOG.md with your changes

3. **Check for Secrets**
   - Never commit secrets, API keys, or credentials
   - Use Kubernetes secrets or external secret managers
   - Review files for sensitive data before committing

### PR Guidelines

1. **Title**: Use a clear, descriptive title
   - Good: "Add Grafana dashboards for HAProxy monitoring"
   - Bad: "Update files"

2. **Description**: Include:
   - What changes were made and why
   - How to test the changes
   - Any breaking changes or migrations needed
   - Screenshots for UI changes (if applicable)

3. **Size**: Keep PRs focused and manageable
   - Prefer smaller, incremental changes
   - Split large changes into multiple PRs

4. **Reviews**: Address review feedback promptly
   - Respond to all comments
   - Make requested changes or explain why not
   - Re-request review after updates

### Automated Checks

All PRs automatically run:
- YAML linting
- Helmfile diff preview
- Template validation

Review the automated diff output carefully before merging.

## Coding Standards

### YAML Files

- Use 2 spaces for indentation
- Keep lines under 120 characters
- Use consistent naming conventions
- Add comments for complex configurations
- Follow the repository's `.yamllint` configuration

Example:
```yaml
# Good
releases:
  - name: my-app
    namespace: apps
    chart: repo/chart
    version: 1.0.0
    values:
      - values/my-app-values.yaml

# Bad
releases:
- name: my-app
  namespace: apps
  chart: repo/chart
  version: 1.0.0
  values:
  - values/my-app-values.yaml
```

### Ansible Playbooks

- Use descriptive task names
- Add tags for selective execution
- Include check mode support
- Handle errors gracefully
- Document variables in defaults/main.yaml

Example:
```yaml
- name: Install required packages
  apt:
    name: "{{ item }}"
    state: present
    update_cache: yes
  loop: "{{ required_packages }}"
  tags:
    - packages
    - setup
```

### Helmfile Configurations

- Use gotmpl templates for conditional logic
- Separate base values from environment overrides
- Enable/disable apps via config/enabled.yaml
- Version-pin all charts
- Document custom values

### Helm Values

- Group related settings together
- Use clear key names
- Add comments for non-obvious settings
- Include resource limits and requests
- Set appropriate timeouts

## Testing Guidelines

### Pre-deployment Testing

1. **YAML Validation**
   ```bash
   yamllint helmfile/ ansible/
   ```

2. **Template Rendering**
   ```bash
   cd helmfile
   helmfile template --suppress-secrets
   ```

3. **Diff Preview**
   ```bash
   cd helmfile
   helmfile diff --suppress-secrets
   ```

### Ansible Testing

1. **Syntax Check**
   ```bash
   ansible-playbook playbooks/deploy-k3s.yaml --syntax-check
   ```

2. **Dry Run**
   ```bash
   ansible-playbook playbooks/deploy-k3s.yaml --check
   ```

### Post-deployment Verification

1. **Check Pod Status**
   ```bash
   kubectl get pods -A
   ```

2. **Verify Services**
   ```bash
   kubectl get svc -A
   ```

3. **Check Logs**
   ```bash
   kubectl logs -n namespace pod-name
   ```

4. **Test Endpoints**
   ```bash
   curl http://service-endpoint
   ```

See [docs/operate.md](docs/operate.md#testing-and-validation) for comprehensive testing procedures.

## Documentation

### What to Document

- New features and their usage
- Configuration options and defaults
- Setup and installation steps
- Troubleshooting common issues
- Security considerations
- Examples and use cases

### Documentation Standards

- Use clear, concise language
- Include code examples
- Provide step-by-step instructions
- Link to related documentation
- Keep documentation up-to-date with code changes

### Documentation Structure

All documentation is organized in the `docs/` directory:

- **[docs/setup.md](docs/setup.md)** - Complete setup guide (Tailscale, K3s, secrets, Cloudflared, GitHub runners)
- **[docs/operate.md](docs/operate.md)** - Operations, testing, monitoring, disaster recovery, backups
- **[docs/ansible.md](docs/ansible.md)** - Ansible playbooks, roles, and automation
- **[docs/helmfile.md](docs/helmfile.md)** - Helmfile configuration and service management

### Files to Update

When making changes, consider updating:

- **README.md**: Main documentation and quick start guide
- **docs/setup.md**: Setup and configuration steps
- **docs/operate.md**: Operational procedures and testing
- **docs/ansible.md**: Ansible-specific documentation
- **docs/helmfile.md**: Helmfile-specific documentation
- **CHANGELOG.md**: Record of all notable changes
- Component-specific docs (only if major changes)

### Adding New Documentation

1. Determine the appropriate location:
   - **Setup-related**: Add to `docs/setup.md`
   - **Operations-related**: Add to `docs/operate.md`
   - **Ansible-related**: Add to `docs/ansible.md`
   - **Helmfile-related**: Add to `docs/helmfile.md`

2. Follow the existing structure and format
3. Add navigation links at the bottom of the document
4. Update table of contents if adding major sections
5. Reference the new content from README.md if appropriate

## Security Best Practices

### Secret Management

- **Never commit secrets to Git**
  - Secrets include: passwords, API keys, certificates, tokens
  - Use `.gitignore` to exclude credential files
  - Use Kubernetes secrets for sensitive data
  - Consider External Secrets Operator for production

- **Creating Kubernetes Secrets**
  ```bash
  # From file
  kubectl create secret generic app-secret \
    --from-file=config.json \
    -n namespace
  
  # From literal
  kubectl create secret generic db-creds \
    --from-literal=username=admin \
    --from-literal=password=secure \
    -n namespace
  ```

### Configuration Security

- Use NetworkPolicies to restrict traffic
- Enable RBAC for access control
- Set resource limits to prevent DoS
- Use read-only root filesystems when possible
- Scan for vulnerabilities regularly

### Workflow Security

- Review GitHub Actions workflows for secret exposure
- Use `--suppress-secrets` with Helmfile
- Limit workflow permissions to minimum required
- Rotate credentials regularly

## Environment-Specific Changes

### Development Environment

- Lower resource limits acceptable
- Can use relaxed security policies
- Faster iteration cycles
- Test new features here first

### Staging Environment

- Production-like configuration
- Similar resource allocation
- Full security policies
- Test migrations and upgrades

### Production Environment

- Requires careful review
- Change management process
- Backup before changes
- Monitor after deployment
- Rollback plan required

## Getting Help

- **Documentation**: Check the README files first
- **Issues**: Search existing issues on GitHub
- **Discussions**: Use GitHub Discussions for questions
- **Security**: Report security issues privately

## Recognition

Contributors will be recognized in:
- Git commit history
- Pull request acknowledgments
- CHANGELOG.md entries (for significant contributions)

Thank you for contributing to making this infrastructure better!
