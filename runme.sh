#!/bin/bash
# runme.sh - Thin orchestrator for modular deployment scripts
# This script sources a helper library and executes step scripts in a fixed order

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source the helper library
if [ -f "scripts/runme/lib.sh" ]; then
    source scripts/runme/lib.sh
else
    echo "Error: Helper library scripts/runme/lib.sh not found"
    exit 1
fi

# Show banner
echo "╔═══════════════════════════════════════════════════════════════"
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
echo "╚═══════════════════════════════════════════════════════════════"
echo ""

print_warning "This script will make changes to your infrastructure."
if ! confirm "Do you want to continue?"; then
    echo "Deployment cancelled."
    exit 0
fi

# Define step scripts in execution order
STEP_SCRIPTS=(
    "01-validate-prereqs.sh"
    "02-configure-secrets.sh"
    "03-deploy-tailscale.sh"
    "04-deploy-k3s.sh"
    "05-deploy-infra.sh"
    "06-cloudflared-validate.sh"
    "07-validate-deployment.sh"
)

# Execute each step script if present and executable
STEPS_DIR="scripts/runme/steps"
for step in "${STEP_SCRIPTS[@]}"; do
    STEP_PATH="$STEPS_DIR/$step"
    
    if [ -f "$STEP_PATH" ]; then
        if [ -x "$STEP_PATH" ]; then
            print_info "Executing step: $step"
            if ! "$STEP_PATH"; then
                print_error "Step $step failed"
                exit 1
            fi
        else
            print_warning "Step script $step exists but is not executable, skipping..."
        fi
    else
        print_warning "Step script $step not found, skipping..."
    fi
done

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