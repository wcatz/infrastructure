#!/bin/bash
# 05-deploy-infra.sh - Deploy infrastructure services via Helmfile

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Source the helper library
source "$SCRIPT_DIR/../lib.sh"

print_section "Step 5: Deploying Infrastructure Services via Helmfile"

print_info "Deploying services with Helmfile..."
cd "$REPO_ROOT/helmfile"

# Detect Helmfile configuration file
# Check for helmfile configuration files in order of precedence:
# 1. helmfile.yaml.gotmpl (Go template format - used in this project)
# 2. helmfile.gotmpl (legacy Go template format)
# 3. helmfile.yaml (standard YAML format)
HF_FILE=""
if [ -f "helmfile.yaml.gotmpl" ]; then
  HF_FILE="helmfile.yaml.gotmpl"
  print_info "Found helmfile.yaml.gotmpl"
elif [ -f "helmfile.gotmpl" ]; then
  HF_FILE="helmfile.gotmpl"
  print_info "Found helmfile.gotmpl"
elif [ -f "helmfile.yaml" ]; then
  HF_FILE="helmfile.yaml"
  print_info "Found helmfile.yaml"
fi

# Verify the selected file exists
if [ -z "$HF_FILE" ] || [ ! -f "$HF_FILE" ]; then
  print_error "Helmfile configuration not found"
  print_error "Expected one of: helmfile.yaml.gotmpl, helmfile.gotmpl, or helmfile.yaml"
  cd "$REPO_ROOT"
  exit 1
fi

print_success "Using Helmfile configuration: $HF_FILE"

# Preview changes using the chosen file
print_info "Previewing Helmfile changes (file: $HF_FILE)..."
if helmfile -f "$HF_FILE" diff --suppress-secrets; then
    print_info "Helmfile diff completed"
else
    print_warning "Helmfile diff failed or no changes detected"
    print_info "This may be expected if this is the first deployment"
fi

# Apply Helmfile
if confirm "Deploy all enabled services?"; then
    if helmfile -f "$HF_FILE" apply; then
        print_success "Infrastructure services deployed successfully"
    else
        print_error "Helmfile deployment failed"
        cd "$REPO_ROOT"
        exit 1
    fi
else
    print_warning "Skipping Helmfile deployment"
fi

cd "$REPO_ROOT"
print_success "Infrastructure deployment step completed"
