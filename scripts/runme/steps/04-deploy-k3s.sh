#!/bin/bash
# 04-deploy-k3s.sh - Deploy K3s cluster and retrieve kubeconfig
# IMPORTANT: This script copies kubeconfig to ~/.kube/k3s-<hostname> without overwriting ~/.kube/config

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Source the helper library
source "$SCRIPT_DIR/../lib.sh"

print_section "Step 4: Deploying K3s Cluster"

print_info "Deploying K3s control plane and workers..."
cd "$REPO_ROOT/ansible"

if ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml; then
    print_success "K3s cluster deployed successfully"
else
    print_error "K3s deployment failed"
    exit 1
fi

cd "$REPO_ROOT"

# Get kubeconfig
print_info "Retrieving kubeconfig..."

# Parse the first k3s_servers host line
FIRST_K3S_LINE=$(get_first_host_line "k3s_servers" "$REPO_ROOT/ansible/inventory.ini" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Initialize KUBECONFIG_PATH variable (will be set if kubeconfig is successfully retrieved)
KUBECONFIG_PATH=""

if [ -z "$FIRST_K3S_LINE" ]; then
    print_error "Could not find any hosts under [k3s_servers] in ansible/inventory.ini"
    print_info "Inventory snippet (first 40 lines) for debugging:"
    sed -n '1,40p' "$REPO_ROOT/ansible/inventory.ini" || true
    print_warning "Please ensure [k3s_servers] group exists and contains at least one host"
    print_info "Manual kubeconfig copy instructions:"
    print_info "  scp user@control-plane:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-<hostname>"
    read -p "Press Enter to continue..."
else
    # Try to extract ansible_host if present; prefer that (likely Tailscale IP)
    CONTROL_PLANE=$(echo "$FIRST_K3S_LINE" | grep -oE 'ansible_host=[^[:space:]]+' | cut -d'=' -f2 || true)
    # Get the inventory hostname (first token) for the kubeconfig filename
    INVENTORY_HOSTNAME=$(echo "$FIRST_K3S_LINE" | awk '{print $1}')
    # Fallback to inventory hostname for connection if ansible_host not present
    if [ -z "$CONTROL_PLANE" ]; then
        CONTROL_PLANE="$INVENTORY_HOSTNAME"
    fi

    # Find SSH user: prefer per-host ansible_user, else first ansible_user found in inventory, else current user
    SSH_USER=$(echo "$FIRST_K3S_LINE" | grep -oE 'ansible_user=[^[:space:]]+' | cut -d'=' -f2 || true)
    if [ -z "$SSH_USER" ]; then
        SSH_USER=$(grep -m1 -oE 'ansible_user=[^[:space:]]+' "$REPO_ROOT/ansible/inventory.ini" | cut -d'=' -f2 || true)
    fi
    if [ -z "$SSH_USER" ]; then
        print_warning "Could not determine SSH user from inventory; falling back to current user: $USER"
        SSH_USER=$USER
    fi

    if [ -z "$CONTROL_PLANE" ]; then
        print_error "Could not determine control plane host from inventory line: $FIRST_K3S_LINE"
        print_info "Please set ansible_host= in ansible/inventory.ini for the control plane or ensure the host name is resolvable"
        print_info "Manual kubeconfig copy instructions:"
        print_info "  scp user@control-plane:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-<hostname>"
        read -p "Press Enter to continue..."
    else
        print_info "Copying kubeconfig from $CONTROL_PLANE (ssh user: $SSH_USER)..."

        # Create .kube directory if it doesn't exist
        mkdir -p "$HOME/.kube"
        
        # Copy kubeconfig to ~/.kube/k3s-<hostname> (no overwrite, no backup files)
        KUBECONFIG_PATH="$HOME/.kube/k3s-${INVENTORY_HOSTNAME}"
        
        if scp "$SSH_USER@$CONTROL_PLANE:/etc/rancher/k3s/k3s.yaml" "$KUBECONFIG_PATH"; then
            # Update server URL to use the control plane host/IP we determined (best-effort)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/127.0.0.1/$CONTROL_PLANE/g" "$KUBECONFIG_PATH" || true
            else
                sed -i "s/127.0.0.1/$CONTROL_PLANE/g" "$KUBECONFIG_PATH" || true
            fi
            print_success "Kubeconfig saved to $KUBECONFIG_PATH"
            print_info "To use this kubeconfig, run: export KUBECONFIG=$KUBECONFIG_PATH"
            print_info "Or merge it with your existing config using kubectl config commands"
        else
            print_warning "Failed to copy kubeconfig automatically from $CONTROL_PLANE"
            print_info "Please manually copy: scp $SSH_USER@$CONTROL_PLANE:/etc/rancher/k3s/k3s.yaml ~/.kube/k3s-${INVENTORY_HOSTNAME}"
        fi
    fi
fi

# Verify cluster access (if KUBECONFIG_PATH was set)
print_info "Verifying cluster access..."
if [ -n "$KUBECONFIG_PATH" ] && [ -f "$KUBECONFIG_PATH" ]; then
    if KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes &> /dev/null; then
        print_success "Cluster is accessible"
        KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes
    else
        print_warning "Cannot access cluster"
        print_info "Please ensure Tailscale is running on your local machine"
        print_info "And verify kubeconfig is correctly configured"
        print_info "Use: export KUBECONFIG=$KUBECONFIG_PATH"
    fi
else
    print_warning "Kubeconfig was not retrieved successfully"
fi

print_success "K3s deployment step completed"
