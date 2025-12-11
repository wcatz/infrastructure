#!/bin/bash
# 01-validate-prereqs.sh - Validate prerequisites before deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Source the helper library
source "$SCRIPT_DIR/../lib.sh"

print_section "Step 1: Validating Prerequisites"

if [ -f "$REPO_ROOT/scripts/validate-prereqs.sh" ]; then
    print_info "Running prerequisite validation..."
    if "$REPO_ROOT/scripts/validate-prereqs.sh"; then
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

print_success "Prerequisite validation step completed"
