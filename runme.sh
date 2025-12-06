#!/bin/bash
# runme.sh - Unified deployment script for hybrid Kubernetes infrastructure
# This script automates the complete setup from prerequisites validation to full deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_section() {
    echo ""
    echo "======================================"
    echo "$1"
    echo "======================================"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to prompt for confirmation
confirm() {
    local prompt="$1"
    local response
    read -p "$prompt (y/n): " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Show banner
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Hybrid Kubernetes Infrastructure - Unified Deployment Script  ║"
echo "║                                                                ║"
echo "║  This script will:                                             ║"
echo "║  1. Validate prerequisites                                     ║"
echo "║  2. Configure secrets (Ansible Vault & SOPS)                   ║"
echo "║  3. Deploy Tailscale VPN on all nodes                          ║"
echo "║  4. Deploy K3s control plane and workers                       ║"
echo "║  5. Deploy infrastructure services via Helmfile                ║"
echo "║  6. Configure Cloudflared tunnels                              ║"
echo "║  7. Validate deployment                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

print_warning "This script will make changes to your infrastructure."
if ! confirm "Do you want to continue?"; then
    echo "Deployment cancelled."
    exit 0
fi

# Step 1: Validate Prerequisites
print_section "Step 1: Validating Prerequisites"

if [ -f "./scripts/validate-prereqs.sh" ]; then
    print_info "Running prerequisite validation..."
    if ./scripts/validate-prereqs.sh; then
        print_success "Prerequisites validated successfully"
    else
        print_error "Prerequisite validation failed"
        print_info "Please install missing tools and try again"
        print_info "See docs/setup.md for installation instructions"
        exit 1
    fi
else
    print_warning "Prerequisite validation script not found, skipping..."
fi

# Step 2: Configure Secrets
print_section "Step 2: Configuring Secrets"

print_info "Setting up Ansible Vault..."

# Check if Ansible vault is configured
if [ ! -f "ansible/.vault_pass" ]; then
    print_warning "Ansible vault password file not found"
    print_info "Creating .vault_pass file..."
    
    if [ -f "ansible/.vault_pass.example" ]; then
        cp ansible/.vault_pass.example ansible/.vault_pass
        print_warning "Please edit ansible/.vault_pass with your vault password"
        read -p "Press Enter after updating .vault_pass..."
    else
        print_error "ansible/.vault_pass.example not found"
        exit 1
    fi
fi

# Check if vault.yml exists
if [ ! -f "ansible/group_vars/all/vault.yml" ]; then
    print_warning "Ansible vault.yml not found"
    
    if [ -f "ansible/group_vars/all/vault.yml.example" ]; then
        print_info "Creating vault.yml from example..."
        cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml
        print_warning "Please edit ansible/group_vars/all/vault.yml with your secrets:"
        print_info "  - vault_k3s_token: Generate with 'openssl rand -hex 32'"
        print_info "  - vault_tailscale_key: Get from https://login.tailscale.com/admin/settings/keys"
        read -p "Press Enter after updating vault.yml..."
        
        print_info "Encrypting vault.yml..."
        cd ansible
        ansible-vault encrypt group_vars/all/vault.yml
        cd ..
        print_success "vault.yml encrypted"
    else
        print_error "ansible/group_vars/all/vault.yml.example not found"
        exit 1
    fi
fi

# Check if inventory exists
if [ ! -f "ansible/inventory.ini" ]; then
    print_warning "Ansible inventory not found"
    
    if [ -f "ansible/inventory.ini.example" ]; then
        print_info "Creating inventory.ini from example..."
        cp ansible/inventory.ini.example ansible/inventory.ini
        print_warning "Please edit ansible/inventory.ini with your server details"
        read -p "Press Enter after updating inventory.ini..."
    else
        print_error "ansible/inventory.ini.example not found"
        exit 1
    fi
fi

# Test Ansible connectivity
print_info "Testing Ansible connectivity..."
cd ansible
if ansible all -i inventory.ini -m ping &> /dev/null; then
    print_success "Ansible connectivity test passed"
else
    print_warning "Ansible connectivity test failed"
    print_info "Please verify your inventory.ini and SSH access"
    if ! confirm "Continue anyway?"; then
        exit 1
    fi
fi
cd ..

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
        if [ -f ".sops.yaml" ]; then
            print_info "Updating .sops.yaml with your public key..."
            sed -i.bak "s/YOUR_PUBLIC_KEY_HERE/$PUBLIC_KEY/" .sops.yaml
            print_success ".sops.yaml updated"
        fi
    fi
fi

print_success "Secret configuration completed"

# Step 3: Deploy Tailscale
print_section "Step 3: Deploying Tailscale VPN"

print_info "Deploying Tailscale on all nodes..."
cd ansible

if ansible-playbook -i inventory.ini playbooks/setup-tailscale.yaml; then
    print_success "Tailscale deployed successfully"
    
    print_warning "IMPORTANT: Update inventory.ini with Tailscale IPs"
    print_info "SSH to each node and run 'tailscale ip -4' to get the Tailscale IP"
    print_info "Then update the ansible_host in inventory.ini to use Tailscale IPs for control plane"
    read -p "Press Enter after updating inventory.ini with Tailscale IPs..."
else
    print_error "Tailscale deployment failed"
    exit 1
fi

cd ..

# Step 4: Deploy K3s Cluster
print_section "Step 4: Deploying K3s Cluster"

print_info "Deploying K3s control plane and workers..."
cd ansible

if ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml; then
    print_success "K3s cluster deployed successfully"
else
    print_error "K3s deployment failed"
    exit 1
fi

cd ..

# Get kubeconfig
print_info "Retrieving kubeconfig..."

# Get control plane host from inventory
CONTROL_PLANE=$(grep -A 1 "\[k3s_servers\]" ansible/inventory.ini | grep -v "\[k3s_servers\]" | grep -v "^#" | head -1 | awk '{print $2}' | cut -d'=' -f2)

if [ -z "$CONTROL_PLANE" ]; then
    print_error "Could not determine control plane host from inventory"
    print_warning "Please manually copy kubeconfig:"
    print_info "  scp user@control-plane:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
    print_info "  sed -i 's/127.0.0.1/<TAILSCALE-IP>/' ~/.kube/config"
    read -p "Press Enter to continue..."
else
    print_info "Copying kubeconfig from $CONTROL_PLANE..."
    
    # Get SSH user from inventory with fallback to current user
    SSH_USER=$(grep "ansible_user" ansible/inventory.ini | head -1 | cut -d'=' -f2 | tr -d ' ' 2>/dev/null || echo "")
    
    if [ -z "$SSH_USER" ]; then
        print_warning "Could not determine SSH user from inventory, using current user"
        SSH_USER=$USER
    fi
    
    # Backup existing kubeconfig
    if [ -f "$HOME/.kube/config" ]; then
        print_info "Backing up existing kubeconfig..."
        cp "$HOME/.kube/config" "$HOME/.kube/config.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Copy kubeconfig
    mkdir -p "$HOME/.kube"
    if scp "$SSH_USER@$CONTROL_PLANE:/etc/rancher/k3s/k3s.yaml" "$HOME/.kube/config"; then
        # Update server URL to use Tailscale IP
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/127.0.0.1/$CONTROL_PLANE/" "$HOME/.kube/config"
        else
            sed -i "s/127.0.0.1/$CONTROL_PLANE/" "$HOME/.kube/config"
        fi
        print_success "Kubeconfig configured successfully"
    else
        print_warning "Failed to copy kubeconfig automatically"
        print_info "Please manually copy: scp $SSH_USER@$CONTROL_PLANE:/etc/rancher/k3s/k3s.yaml ~/.kube/config"
    fi
fi

# Verify cluster access
print_info "Verifying cluster access..."
if kubectl get nodes &> /dev/null; then
    print_success "Cluster is accessible"
    kubectl get nodes
else
    print_warning "Cannot access cluster"
    print_info "Please ensure Tailscale is running on your local machine"
    print_info "And verify kubeconfig is correctly configured"
fi

# Step 5: Deploy Infrastructure Services
print_section "Step 5: Deploying Infrastructure Services via Helmfile"

print_info "Deploying services with Helmfile..."
cd helmfile

# Preview changes
print_info "Previewing Helmfile changes..."
if helmfile diff --suppress-secrets; then
    print_info "Helmfile diff completed"
else
    print_warning "Helmfile diff failed, continuing..."
fi

# Apply Helmfile
if confirm "Deploy all enabled services?"; then
    if helmfile apply; then
        print_success "Infrastructure services deployed successfully"
    else
        print_error "Helmfile deployment failed"
        cd ..
        exit 1
    fi
else
    print_warning "Skipping Helmfile deployment"
fi

cd ..

# Step 6: Configure Cloudflared (Optional)
print_section "Step 6: Cloudflared Tunnel Configuration (Optional)"

if confirm "Do you want to configure Cloudflared tunnels now?"; then
    print_info "Cloudflared tunnel setup requires manual configuration"
    print_info "Please follow these steps:"
    print_info "  1. Run: cloudflared tunnel login"
    print_info "  2. Run: cloudflared tunnel create infrastructure-tunnel"
    print_info "  3. Create Kubernetes secret with tunnel credentials"
    print_info "  4. Configure DNS routes"
    print_info "  5. Enable Cloudflared in helmfile/config/enabled.yaml"
    print_info "  6. Run: cd helmfile && helmfile apply"
    print_info ""
    print_info "See docs/setup.md#6-cloudflared-tunnel-setup for detailed instructions"
    read -p "Press Enter to continue..."
else
    print_info "Skipping Cloudflared configuration"
    print_info "You can configure it later by following docs/setup.md#6-cloudflared-tunnel-setup"
fi

# Step 7: Validate Deployment
print_section "Step 7: Validating Deployment"

print_info "Running deployment validation..."

# Check nodes
print_info "Checking cluster nodes..."
if kubectl get nodes &> /dev/null; then
    kubectl get nodes
    print_success "Nodes are online"
else
    print_warning "Cannot query nodes"
fi

# Check system pods
print_info "Checking system pods..."
if kubectl get pods -n kube-system &> /dev/null; then
    PENDING_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
    if [ "$PENDING_PODS" -eq 0 ]; then
        print_success "All system pods are running"
    else
        print_warning "$PENDING_PODS system pods not running"
        kubectl get pods -n kube-system | grep -v Running || true
    fi
else
    print_warning "Cannot query system pods"
fi

# Check monitoring pods (if enabled)
if kubectl get namespace monitoring &> /dev/null; then
    print_info "Checking monitoring stack..."
    if kubectl get pods -n monitoring &> /dev/null; then
        PENDING_PODS=$(kubectl get pods -n monitoring --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
        if [ "$PENDING_PODS" -eq 0 ]; then
            print_success "Monitoring stack is running"
        else
            print_warning "$PENDING_PODS monitoring pods not running"
        fi
    fi
fi

# Run validation script if available
if [ -f "./scripts/validate.sh" ]; then
    print_info "Running validation script..."
    if ./scripts/validate.sh; then
        print_success "Validation completed successfully"
    else
        print_warning "Validation completed with warnings"
    fi
fi

# Summary
print_section "Deployment Summary"

print_success "Hybrid Kubernetes infrastructure deployment completed!"
echo ""
print_info "Next steps:"
echo "  1. Configure Cloudflared tunnels (if not done): see docs/setup.md#6-cloudflared-tunnel-setup"
echo "  2. Deploy your applications: see docs/operate.md#kubernetes-workload-examples"
echo "  3. Set up monitoring dashboards in Grafana"
echo "  4. Configure backup schedules with Velero"
echo "  5. Review security and firewall rules"
echo ""
print_info "Documentation:"
echo "  - Setup Guide:      docs/setup.md"
echo "  - Operations Guide: docs/operate.md"
echo "  - Ansible Guide:    docs/ansible.md"
echo "  - Helmfile Guide:   docs/helmfile.md"
echo ""
print_info "Useful commands:"
echo "  - Check nodes:      kubectl get nodes"
echo "  - Check pods:       kubectl get pods -A"
echo "  - Port-forward:     kubectl port-forward -n monitoring svc/grafana 3000:80"
echo "  - View logs:        kubectl logs -n <namespace> <pod-name>"
echo ""
print_success "Happy deploying! 🚀"
