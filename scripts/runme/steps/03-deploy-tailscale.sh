#!/bin/bash
# 03-deploy-tailscale.sh - Deploy Tailscale VPN on all nodes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Source the helper library
source "$SCRIPT_DIR/../lib.sh"

print_section "Step 3: Deploying Tailscale VPN"

print_info "Deploying Tailscale on all nodes..."
cd "$REPO_ROOT/ansible"

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

cd "$REPO_ROOT"
print_success "Tailscale deployment step completed"
