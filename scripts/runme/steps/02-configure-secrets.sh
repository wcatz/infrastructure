#!/bin/bash
# 02-configure-secrets.sh - Configure secrets (Ansible Vault & SOPS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Source the helper library
source "$SCRIPT_DIR/../lib.sh"

print_section "Step 2: Configuring Secrets"

print_info "Setting up Ansible Vault..."

# Check if Ansible vault is configured
if [ ! -f "$REPO_ROOT/ansible/.vault_pass" ]; then
    print_warning "Ansible vault password file not found"
    print_info "Creating .vault_pass file..."
    
    if [ -f "$REPO_ROOT/ansible/.vault_pass.example" ]; then
        cp "$REPO_ROOT/ansible/.vault_pass.example" "$REPO_ROOT/ansible/.vault_pass"
        print_warning "Please edit ansible/.vault_pass with your vault password"
        read -p "Press Enter after updating .vault_pass..."
    else
        print_error "ansible/.vault_pass.example not found"
        exit 1
    fi
fi

# Check if vault.yml exists
if [ ! -f "$REPO_ROOT/ansible/group_vars/all/vault.yml" ]; then
    print_warning "Ansible vault.yml not found"
    
    if [ -f "$REPO_ROOT/ansible/group_vars/all/vault.yml.example" ]; then
        print_info "Creating vault.yml from example..."
        cp "$REPO_ROOT/ansible/group_vars/all/vault.yml.example" "$REPO_ROOT/ansible/group_vars/all/vault.yml"
        print_warning "Please edit ansible/group_vars/all/vault.yml with your secrets:"
        print_info "  - vault_k3s_token: Generate with 'openssl rand -hex 32'"
        print_info "  - vault_tailscale_key: Get from https://login.tailscale.com/admin/settings/keys"
        read -p "Press Enter after updating vault.yml..."
        
        print_info "Encrypting vault.yml..."
        cd "$REPO_ROOT/ansible"
        ansible-vault encrypt group_vars/all/vault.yml
        cd "$REPO_ROOT"
        print_success "vault.yml encrypted"
    else
        print_error "ansible/group_vars/all/vault.yml.example not found"
        exit 1
    fi
fi

# Check if inventory exists
if [ ! -f "$REPO_ROOT/ansible/inventory.ini" ]; then
    print_warning "Ansible inventory not found"
    
    if [ -f "$REPO_ROOT/ansible/inventory.ini.example" ]; then
        print_info "Creating inventory.ini from example..."
        cp "$REPO_ROOT/ansible/inventory.ini.example" "$REPO_ROOT/ansible/inventory.ini"
        print_warning "Please edit ansible/inventory.ini with your server details"
        read -p "Press Enter after updating inventory.ini..."
    else
        print_error "ansible/inventory.ini.example not found"
        exit 1
    fi
fi

# Test Ansible connectivity
print_info "Testing Ansible connectivity..."
cd "$REPO_ROOT/ansible"
if ansible all -i inventory.ini -m ping &> /dev/null; then
    print_success "Ansible connectivity test passed"
else
    print_warning "Ansible connectivity test failed"
    print_info "Please verify your inventory.ini and SSH access"
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi
cd "$REPO_ROOT"

# Configure SOPS
print_info "Checking SOPS configuration..."

if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
    print_warning "SOPS age key not found"
    print_info "Generating age key..."
    mkdir -p "$HOME/.config/sops/age"
    age-keygen -o "$HOME/.config/sops/age/keys.txt"
    print_success "Age key generated at ~/.config/sops/age/keys.txt"
    print_warning "IMPORTANT: Back up this key securely!"
    
    # Extract public key
    PUBLIC_KEY=$(cat "$HOME/.config/sops/age/keys.txt" | grep "public key:" | cut -d ":" -f2 | tr -d ' ')
    
    if [ -z "$PUBLIC_KEY" ]; then
        print_error "Failed to extract public key from age key file"
        print_warning "Please manually update .sops.yaml with your public key"
    else
        print_info "Your public key: $PUBLIC_KEY"
        
        # Update .sops.yaml if it exists
        if [ -f "$REPO_ROOT/.sops.yaml" ]; then
            print_info "Updating .sops.yaml with your public key..."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/YOUR_PUBLIC_KEY_HERE/$PUBLIC_KEY/" "$REPO_ROOT/.sops.yaml"
            else
                sed -i "s/YOUR_PUBLIC_KEY_HERE/$PUBLIC_KEY/" "$REPO_ROOT/.sops.yaml"
            fi
            print_success ".sops.yaml updated"
        fi
    fi
fi

print_success "Secret configuration completed"
