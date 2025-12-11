#!/bin/bash
# 06-cloudflared-validate.sh - Validate Cloudflared tunnel setup (optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Source the helper library
source "$SCRIPT_DIR/../lib.sh"

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
    read -p "Press Enter after completing Cloudflared setup to validate the connection..."
    
    # Validate cloudflared tunnel if deployed
    if kubectl get namespace cloudflare &> /dev/null; then
        if validate_cloudflared_tunnel "cloudflare"; then
            print_success "Cloudflared tunnel validation passed"
        else
            print_warning "Cloudflared tunnel validation failed"
            print_info "Check the troubleshooting section in docs/setup.md#6-cloudflared-tunnel-setup"
            if ! confirm "Continue despite validation failure?"; then
                exit 1
            fi
        fi
    else
        print_warning "Cloudflared namespace not found - skipping validation"
        print_info "Deploy cloudflared via Helmfile and re-run this script to validate"
    fi
else
    print_info "Skipping Cloudflared configuration"
    print_info "You can configure it later by following docs/setup.md#6-cloudflared-tunnel-setup"
fi

print_success "Cloudflared validation step completed"
