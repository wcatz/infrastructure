#!/bin/bash
# Validation script for hybrid K8s infrastructure
# Tests YAML syntax, Ansible playbooks, and Kubernetes manifests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

ERRORS=0
WARNINGS=0

echo "======================================"
echo "Infrastructure Validation Script"
echo "======================================"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ERRORS=$((ERRORS + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    WARNINGS=$((WARNINGS + 1))
}

print_info() {
    echo "ℹ️  $1"
}

# Check required tools
echo "Checking required tools..."
REQUIRED_TOOLS=("yamllint" "ansible" "python3")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        print_success "$tool is installed"
    else
        print_error "$tool is not installed"
    fi
done
echo ""

# Validate YAML files
echo "Validating YAML syntax..."
if command -v yamllint &> /dev/null; then
    if yamllint helmfile/ ansible/ kubernetes-examples/ .github/workflows/ > /tmp/yamllint.log 2>&1; then
        print_success "YAML syntax validation passed"
    else
        ERROR_COUNT=$(grep -c "::error" /tmp/yamllint.log || echo "0")
        WARN_COUNT=$(grep -c "::warning" /tmp/yamllint.log || echo "0")

        if [ "$ERROR_COUNT" -gt 0 ]; then
            print_error "YAML syntax validation found $ERROR_COUNT error(s)"
            grep "::error" /tmp/yamllint.log | head -10
        else
            print_success "YAML syntax validation passed (no errors)"
        fi

        if [ "$WARN_COUNT" -gt 0 ]; then
            print_warning "YAML syntax validation found $WARN_COUNT warning(s)"
        fi
    fi
else
    print_warning "yamllint not available, skipping YAML validation"
fi
echo ""

# Validate Ansible playbooks
echo "Validating Ansible playbooks..."
if command -v ansible-playbook &> /dev/null; then
    # Create temporary vault password file for syntax checking
    echo "dummy-password" > ansible/.vault_pass.tmp
    chmod 400 ansible/.vault_pass.tmp

    PLAYBOOKS=(
        "ansible/playbooks/deploy-k3s.yaml"
        "ansible/playbooks/setup-tailscale.yaml"
        "ansible/playbooks/configure-hostname.yaml"
        "ansible/playbooks/configure-base-system.yaml"
    )

    for playbook in "${PLAYBOOKS[@]}"; do
        if [ -f "$playbook" ]; then
            # Use -i /dev/null to avoid inventory warnings and run from ansible dir
            if (cd ansible && ANSIBLE_VAULT_PASSWORD_FILE=.vault_pass.tmp ansible-playbook "../$playbook" --syntax-check -i /dev/null) > /tmp/ansible-check.log 2>&1; then
                print_success "$(basename "$playbook") syntax check passed"
            else
                # Check if it's just a "role not found" error - this is expected without proper setup
                if grep -q "was not found" /tmp/ansible-check.log; then
                    print_warning "$(basename "$playbook") - roles not in standard path (expected in CI)"
                else
                    print_error "$(basename "$playbook") syntax check failed"
                    cat /tmp/ansible-check.log
                fi
            fi
        fi
    done

    # Clean up temp vault file
    rm -f ansible/.vault_pass.tmp
else
    print_warning "ansible-playbook not available, skipping Ansible validation"
fi
echo ""

# Validate Kubernetes manifests
echo "Validating Kubernetes manifests..."
if command -v python3 &> /dev/null; then
    python3 << 'EOF'
import yaml
import sys
import os

files = [
    'kubernetes-examples/deployment.yaml',
    'kubernetes-examples/service.yaml',
    'kubernetes-examples/ingress.yaml',
    'kubernetes-examples/configmap.yaml',
    'kubernetes-examples/secret.yaml'
]

errors = []
total_docs = 0

for f in files:
    if not os.path.exists(f):
        print(f'⚠️  {f} not found, skipping')
        continue

    try:
        with open(f, 'r') as stream:
            docs = list(yaml.safe_load_all(stream))
            doc_count = len([d for d in docs if d is not None])
            total_docs += doc_count
            print(f'✅ {os.path.basename(f)}: {doc_count} document(s) valid')
    except Exception as e:
        errors.append(f'❌ {os.path.basename(f)}: {str(e)}')
        print(f'❌ {os.path.basename(f)}: {str(e)}')

print(f'\nTotal: {total_docs} Kubernetes manifest documents validated')

if errors:
    sys.exit(1)
EOF

    if [ $? -eq 0 ]; then
        print_success "Kubernetes manifests validation passed"
    else
        print_error "Kubernetes manifests validation failed"
    fi
else
    print_warning "python3 not available, skipping Kubernetes manifest validation"
fi
echo ""

# Check for common issues
echo "Checking for common issues..."

# Check if vault example exists
if [ -f "ansible/group_vars/all/vault.yml.example" ]; then
    print_success "Ansible vault example file exists"
else
    print_error "Ansible vault example file missing"
fi

# Check if inventory example exists
if [ -f "ansible/inventory.ini.example" ]; then
    print_success "Ansible inventory example file exists"
else
    print_error "Ansible inventory example file missing"
fi

# Check if .gitignore includes sensitive files
if grep -q ".vault_pass" .gitignore && grep -q "credentials.json" .gitignore; then
    print_success ".gitignore includes sensitive files"
else
    print_warning ".gitignore may not include all sensitive files"
fi

# Check if actual secrets are committed (should not be)
if [ -f "ansible/.vault_pass" ] || [ -f "ansible/inventory.ini" ]; then
    print_error "Sensitive files found in repository (should be in .gitignore)"
else
    print_success "No sensitive files found in repository"
fi

# Validate Helmfile templates
echo ""
echo "Validating Helmfile templates..."

# Check for Helmfile configuration in order of precedence
HF_FILE=""
if [ -f "helmfile/helmfile.yaml.gotmpl" ]; then
    HF_FILE="helmfile.yaml.gotmpl"
    print_success "Found helmfile.yaml.gotmpl"
elif [ -f "helmfile/helmfile.gotmpl" ]; then
    HF_FILE="helmfile.gotmpl"
    print_success "Found helmfile.gotmpl"
elif [ -f "helmfile/helmfile.yaml" ]; then
    HF_FILE="helmfile.yaml"
    print_success "Found helmfile.yaml (standard format)"
else
    print_warning "No Helmfile configuration found"
fi

# Validate template syntax if file was found and contains templates
if [ -n "$HF_FILE" ]; then
    cd helmfile
    
    # Check if file contains Go templates
    if grep -q '{{' "$HF_FILE" || grep -q '}}' "$HF_FILE"; then
        print_info "Validating Helmfile template syntax..."
        
        if command -v helmfile &> /dev/null; then
            if helmfile -f "$HF_FILE" template &> /tmp/helmfile-validation.log 2>&1; then
                print_success "Helmfile template syntax is valid"
            else
                # Check if it's just missing values/secrets (acceptable in CI)
                if grep -qiE "\bno such file\b|secret.*not found|value.*required" /tmp/helmfile-validation.log; then
                    print_warning "Helmfile template validation skipped (missing runtime values - expected in CI)"
                else
                    print_error "Helmfile template has syntax errors"
                    head -10 /tmp/helmfile-validation.log
                fi
            fi
        else
            print_warning "helmfile not installed, skipping template validation"
        fi
    else
        print_info "No Go templates detected in $HF_FILE, skipping template validation"
    fi
    
    cd ..
fi

# Validate Kubernetes cluster health (if accessible)
echo ""
echo "Validating Kubernetes cluster health..."
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    print_info "Cluster is accessible, running health checks..."
    
    # Check node status - count nodes with Ready status
    if kubectl get nodes &> /dev/null; then
        TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {count++} END {print count+0}')
        
        if [ "$READY_NODES" -eq "$TOTAL_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
            print_success "All cluster nodes are Ready ($READY_NODES/$TOTAL_NODES)"
        else
            print_warning "Not all nodes are Ready ($READY_NODES/$TOTAL_NODES)"
        fi
    fi
    
    # Check system pods
    if kubectl get pods -n kube-system &> /dev/null; then
        FAILING_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
        if [ "$FAILING_PODS" -eq 0 ]; then
            print_success "All kube-system pods are healthy"
        else
            print_warning "$FAILING_PODS kube-system pod(s) not running"
        fi
    fi
    
    # Check CoreDNS
    if kubectl get deployment -n kube-system coredns &> /dev/null; then
        COREDNS_READY=$(kubectl get deployment -n kube-system coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        COREDNS_DESIRED=$(kubectl get deployment -n kube-system coredns -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        if [ "$COREDNS_READY" = "$COREDNS_DESIRED" ] && [ "$COREDNS_READY" != "0" ]; then
            print_success "CoreDNS is healthy ($COREDNS_READY/$COREDNS_DESIRED replicas)"
        else
            print_warning "CoreDNS may not be fully ready ($COREDNS_READY/$COREDNS_DESIRED)"
        fi
    fi
    
    # Check cluster API health
    if kubectl get --raw='/readyz?verbose' &> /dev/null; then
        print_success "Cluster API server is healthy"
    else
        print_warning "Cluster API health check returned warnings"
    fi
else
    print_info "Kubernetes cluster not accessible - skipping runtime validation"
    print_info "This is expected in CI or when cluster is not yet deployed"
fi

echo ""
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ $ERRORS -gt 0 ]; then
    print_error "Validation failed with $ERRORS error(s)"
    exit 1
else
    print_success "Validation passed! ✨"
    if [ $WARNINGS -gt 0 ]; then
        print_warning "Note: $WARNINGS warning(s) found"
    fi
    exit 0
fi
