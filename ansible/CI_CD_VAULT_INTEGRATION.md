# CI/CD Integration for Ansible Vault

This guide explains how to integrate Ansible Vault encrypted secrets into CI/CD pipelines.

## GitHub Actions Integration

### Prerequisites

1. **Encrypt your secrets** using Ansible Vault (see [SECRETS.md](SECRETS.md))
2. **Store vault password** as a GitHub repository secret

### Setup Repository Secrets

1. Go to your repository's Settings → Secrets and variables → Actions
2. Add a new repository secret:
   - **Name**: `ANSIBLE_VAULT_PASSWORD`
   - **Value**: Your vault password (same as in `.vault_pass` file)

### Workflow Example

Here's a complete example workflow for deploying with Ansible:

```yaml
name: Deploy Infrastructure with Ansible

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
          - prod

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install Ansible
        run: |
          python -m pip install --upgrade pip
          pip install ansible
      
      - name: Setup Ansible Vault password
        run: |
          echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > ansible/.vault_pass
          chmod 600 ansible/.vault_pass
      
      - name: Verify vault decryption
        run: |
          cd ansible
          ansible-vault view group_vars/all/vault.yml --vault-password-file=.vault_pass
        # This step verifies the vault can be decrypted but doesn't output secrets
        continue-on-error: false
      
      - name: Setup SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -H ${{ secrets.SERVER_HOST }} >> ~/.ssh/known_hosts
      
      - name: Deploy k3s cluster
        run: |
          cd ansible
          ansible-playbook -i inventory-${{ inputs.environment }}.ini \
            playbooks/deploy-k3s.yaml \
            --vault-password-file=.vault_pass
      
      - name: Deploy Tailscale
        run: |
          cd ansible
          ansible-playbook -i inventory-${{ inputs.environment }}.ini \
            playbooks/setup-tailscale.yaml \
            --vault-password-file=.vault_pass
      
      - name: Cleanup vault password
        if: always()
        run: |
          rm -f ansible/.vault_pass
```

### Security Best Practices for CI/CD

1. **Never log decrypted secrets**: Ensure your workflow doesn't print vault contents
2. **Clean up sensitive files**: Always remove `.vault_pass` in cleanup steps
3. **Use environment-specific inventories**: Keep separate inventories for dev/staging/prod
4. **Restrict workflow permissions**: Use GitHub's OIDC and minimal permissions
5. **Audit secret access**: Regularly review who has access to repository secrets

## GitLab CI Integration

For GitLab CI/CD:

```yaml
variables:
  ANSIBLE_VAULT_PASSWORD_FILE: ".vault_pass"

before_script:
  - apt-get update && apt-get install -y ansible
  - echo "$ANSIBLE_VAULT_PASSWORD" > .vault_pass
  - chmod 600 .vault_pass

deploy:
  stage: deploy
  script:
    - cd ansible
    - ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml
  after_script:
    - rm -f .vault_pass
  only:
    - main
```

Set `ANSIBLE_VAULT_PASSWORD` as a protected and masked variable in GitLab CI/CD settings.

## Jenkins Integration

For Jenkins Pipeline:

```groovy
pipeline {
    agent any
    
    environment {
        VAULT_PASSWORD = credentials('ansible-vault-password')
    }
    
    stages {
        stage('Setup') {
            steps {
                sh 'pip install ansible'
                sh 'echo "$VAULT_PASSWORD" > ansible/.vault_pass'
                sh 'chmod 600 ansible/.vault_pass'
            }
        }
        
        stage('Deploy') {
            steps {
                dir('ansible') {
                    sh 'ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml'
                }
            }
        }
    }
    
    post {
        always {
            sh 'rm -f ansible/.vault_pass'
        }
    }
}
```

Add `ansible-vault-password` as a Secret Text credential in Jenkins.

## Alternative: Environment Variable

Instead of creating a file, you can use an environment variable:

```bash
# Set environment variable
export ANSIBLE_VAULT_PASSWORD="your-vault-password"

# Run playbook
ansible-playbook playbooks/deploy-k3s.yaml \
  --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD")
```

In GitHub Actions:

```yaml
- name: Deploy with vault password from environment
  env:
    ANSIBLE_VAULT_PASSWORD: ${{ secrets.ANSIBLE_VAULT_PASSWORD }}
  run: |
    cd ansible
    ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml \
      --vault-password-file <(echo "$ANSIBLE_VAULT_PASSWORD")
```

## Troubleshooting

### "Decryption failed" error

- Verify the vault password in GitHub Secrets matches your local `.vault_pass`
- Check that the vault file is properly encrypted: `ansible-vault view group_vars/all/vault.yml`

### "vault_k3s_token is undefined" error

- Ensure `group_vars/all/vault.yml` is committed to the repository (encrypted)
- Verify the vault file contains all required variables

### Secrets not being used

- Check ansible.cfg has `vault_password_file = .vault_pass`
- Ensure role defaults reference vault variables: `k3s_token: "{{ vault_k3s_token }}"`

## Future: SOPS Integration

As mentioned in the problem statement, the next phase will implement **SOPS with workflows** for additional secret management capabilities alongside Ansible Vault.
