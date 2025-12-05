#!/bin/bash
# Prerequisite validation script for infrastructure setup
# Checks required tools, credentials, and connectivity

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

ERRORS=0
WARNINGS=0
CHECKS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
    CHECKS=$((CHECKS + 1))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ERRORS=$((ERRORS + 1))
    CHECKS=$((CHECKS + 1))
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    WARNINGS=$((WARNINGS + 1))
    CHECKS=$((CHECKS + 1))
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

# Function to check if command exists and get version
check_command() {
    local cmd=$1
    local required=$2
    local version_flag=${3:-"--version"}
    
    if command -v "$cmd" &> /dev/null; then
        local version_output
        version_output=$("$cmd" $version_flag 2>&1 | head -1 || echo "version unknown")
        print_success "$cmd is installed ($version_output)"
    else
        if [ "$required" = "true" ]; then
            print_error "$cmd is not installed (required)"
        else
            print_warning "$cmd is not installed (optional)"
        fi
    fi
}

# Banner
echo "======================================"
echo "Infrastructure Prerequisites Validator"
echo "======================================"
echo ""
print_info "This script validates your environment for infrastructure deployment"
echo ""

# ======================================
# 1. Required Local Tools
# ======================================
print_section "1. Checking Required Local Tools"

print_info "Core tools..."
check_command "git" "true"
check_command "python3" "true"
check_command "pip3" "false" "--version"

print_info "Ansible tools..."
check_command "ansible" "true"
check_command "ansible-playbook" "true"
check_command "ansible-vault" "true"

print_info "Kubernetes tools..."
check_command "kubectl" "true" "version --client"
check_command "helm" "true" "version"
check_command "helmfile" "true"

print_info "Secret management tools..."
check_command "age" "true"
check_command "age-keygen" "true"
check_command "sops" "true"

print_info "Network/connectivity tools..."
check_command "cloudflared" "false"
check_command "tailscale" "false"
check_command "curl" "true"
check_command "ping" "true" "-V"

# Check for Helm diff plugin
echo ""
print_info "Checking Helm plugins..."
if command -v helm &> /dev/null; then
    if helm plugin list 2>/dev/null | grep -q "diff"; then
        print_success "Helm diff plugin is installed"
    else
        print_warning "Helm diff plugin is not installed (recommended: helm plugin install https://github.com/databus23/helm-diff)"
    fi
fi

# Check for Python dependencies
echo ""
print_info "Checking Python dependencies..."
if command -v python3 &> /dev/null; then
    if python3 -c "import jmespath" 2>/dev/null; then
        print_success "Python jmespath module is installed"
    else
        print_warning "Python jmespath module is not installed (required for Ansible: pip3 install jmespath)"
    fi
    
    if python3 -c "import yaml" 2>/dev/null; then
        print_success "Python yaml module is installed"
    else
        print_warning "Python yaml module is not installed (recommended: pip3 install pyyaml)"
    fi
fi

# ======================================
# 2. Credentials Availability
# ======================================
print_section "2. Checking Credentials Availability"

print_info "Checking Ansible Vault configuration..."
if [ -f "ansible/.vault_pass" ]; then
    print_success "Ansible vault password file exists (ansible/.vault_pass)"
else
    print_warning "Ansible vault password file not found (ansible/.vault_pass)"
    print_info "  Create from example: cp ansible/.vault_pass.example ansible/.vault_pass"
fi

if [ -f "ansible/group_vars/all/vault.yml" ]; then
    print_success "Ansible vault file exists (ansible/group_vars/all/vault.yml)"
    
    # Check if it's encrypted
    if head -1 "ansible/group_vars/all/vault.yml" | grep -q "\$ANSIBLE_VAULT"; then
        print_success "Ansible vault file is encrypted"
    else
        print_warning "Ansible vault file exists but is not encrypted"
        print_info "  Encrypt with: ansible-vault encrypt ansible/group_vars/all/vault.yml"
    fi
else
    print_warning "Ansible vault file not found (ansible/group_vars/all/vault.yml)"
    print_info "  Create from example: cp ansible/group_vars/all/vault.yml.example ansible/group_vars/all/vault.yml"
fi

if [ -f "ansible/inventory.ini" ]; then
    print_success "Ansible inventory file exists (ansible/inventory.ini)"
else
    print_warning "Ansible inventory file not found (ansible/inventory.ini)"
    print_info "  Create from example: cp ansible/inventory.ini.example ansible/inventory.ini"
fi

echo ""
print_info "Checking SOPS age key configuration..."
if [ -f "$HOME/.config/sops/age/keys.txt" ]; then
    print_success "SOPS age keys file exists (~/.config/sops/age/keys.txt)"
    
    # Verify it contains a private key
    if grep -q "AGE-SECRET-KEY" "$HOME/.config/sops/age/keys.txt"; then
        print_success "SOPS age private key found"
        
        # Extract and display public key
        if grep -q "# public key:" "$HOME/.config/sops/age/keys.txt"; then
            public_key=$(grep "# public key:" "$HOME/.config/sops/age/keys.txt" | awk '{print $NF}')
            print_info "  Public key: $public_key"
        fi
    else
        print_error "SOPS age keys file exists but no private key found"
    fi
else
    print_warning "SOPS age keys file not found (~/.config/sops/age/keys.txt)"
    print_info "  Generate with: mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt"
fi

if [ -f ".sops.yaml" ]; then
    print_success "SOPS configuration file exists (.sops.yaml)"
else
    print_warning "SOPS configuration file not found (.sops.yaml)"
    print_info "  Create with your age public key (see SECRETS.md)"
fi

echo ""
print_info "Checking Cloudflare credentials..."
if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
    print_success "CLOUDFLARE_API_TOKEN environment variable is set"
elif [ -n "$CF_API_TOKEN" ]; then
    print_success "CF_API_TOKEN environment variable is set"
else
    print_warning "Cloudflare API token not found in environment"
    print_info "  Set CLOUDFLARE_API_TOKEN or CF_API_TOKEN environment variable"
    print_info "  Or configure cloudflared with: cloudflared tunnel login"
fi

# Check for cloudflared credentials
if [ -d "$HOME/.cloudflared" ] && [ -n "$(ls -A $HOME/.cloudflared/*.json 2>/dev/null)" ]; then
    tunnel_count=$(ls -1 "$HOME/.cloudflared"/*.json 2>/dev/null | wc -l)
    print_success "Cloudflared tunnel credentials found ($tunnel_count tunnel(s))"
else
    print_warning "Cloudflared tunnel credentials not found in ~/.cloudflared/"
    print_info "  Create tunnel with: cloudflared tunnel create <name>"
fi

echo ""
print_info "Checking Tailscale authentication..."
if command -v tailscale &> /dev/null; then
    if tailscale status &> /dev/null; then
        print_success "Tailscale is authenticated and running"
        # Show current status
        if tailscale status --json &> /dev/null; then
            ts_status=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    hostname = data['Self']['HostName']
    ip = data['Self']['TailscaleIPs'][0]
    print(f'{hostname} ({ip})')
except:
    print('unknown')
" 2>/dev/null)
            print_info "  Status: $ts_status"
        fi
    else
        print_warning "Tailscale is installed but not authenticated"
        print_info "  Authenticate with: tailscale up"
    fi
else
    print_warning "Tailscale is not installed (optional but recommended)"
fi

# ======================================
# 3. Connectivity Checks
# ======================================
print_section "3. Checking Connectivity"

print_info "Checking internet connectivity..."
if curl -s --connect-timeout 3 --max-time 5 https://www.google.com > /dev/null 2>&1; then
    print_success "Internet connectivity: OK"
else
    print_warning "Internet connectivity check failed (may be network restriction)"
    print_info "  If behind firewall, this is expected. Skipping further connectivity checks."
    SKIP_NETWORK_CHECKS=true
fi

if [ "$SKIP_NETWORK_CHECKS" != "true" ]; then
    echo ""
    print_info "Checking Cloudflare connectivity..."
    if curl -s --connect-timeout 3 --max-time 5 https://api.cloudflare.com/client/v4/user/tokens/verify > /dev/null 2>&1; then
        print_success "Cloudflare API is reachable"
    else
        print_warning "Cloudflare API connectivity check failed"
    fi

    echo ""
    print_info "Checking container registry connectivity..."
    # Check common registries
    if curl -s --connect-timeout 3 --max-time 5 https://registry.hub.docker.com > /dev/null 2>&1; then
        print_success "Docker Hub is reachable"
    else
        print_warning "Docker Hub connectivity check failed"
    fi

    if curl -s --connect-timeout 3 --max-time 5 https://ghcr.io > /dev/null 2>&1; then
        print_success "GitHub Container Registry is reachable"
    else
        print_warning "GitHub Container Registry connectivity check failed"
    fi

    if curl -s --connect-timeout 3 --max-time 5 https://quay.io > /dev/null 2>&1; then
        print_success "Quay.io is reachable"
    else
        print_warning "Quay.io connectivity check failed"
    fi
fi

echo ""
print_info "Checking Kubernetes cluster connectivity..."
if command -v kubectl &> /dev/null; then
    # Check if kubeconfig exists
    if [ -f "$HOME/.kube/config" ] || [ -n "$KUBECONFIG" ]; then
        if kubectl cluster-info &> /dev/null; then
            print_success "Kubernetes cluster is reachable"
            
            # Get cluster info
            cluster_endpoint=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "unknown")
            print_info "  Cluster: $cluster_endpoint"
            
            # Check if we can list nodes
            if kubectl get nodes &> /dev/null; then
                node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
                print_success "Can access cluster nodes ($node_count node(s))"
            else
                print_warning "Cannot list cluster nodes (permission issue?)"
            fi
        else
            print_warning "Kubernetes cluster is not reachable"
            print_info "  Configure kubeconfig or ensure cluster is running"
        fi
    else
        print_warning "Kubernetes config not found (~/.kube/config or \$KUBECONFIG)"
        print_info "  Configure kubectl to connect to your cluster"
    fi
else
    print_warning "kubectl not available, skipping Kubernetes connectivity check"
fi

echo ""
print_info "Checking Tailscale connectivity..."
if command -v tailscale &> /dev/null; then
    if tailscale status &> /dev/null; then
        # Check if we can ping ourselves (basic test)
        self_ip=$(tailscale ip -4 2>/dev/null | head -1)
        if [ -n "$self_ip" ]; then
            print_success "Tailscale network is active (IP: $self_ip)"
            
            # List active peers
            if tailscale status --json &> /dev/null; then
                peer_count=$(tailscale status --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    online_peers = [p for p in data.get('Peer', {}).values() if p.get('Online', False)]
    print(len(online_peers))
except:
    print('0')
" 2>/dev/null)
                if [ "$peer_count" -gt 0 ]; then
                    print_info "  Connected peers: $peer_count"
                fi
            fi
        else
            print_warning "Tailscale is running but no IP assigned"
        fi
    else
        print_warning "Tailscale is not running or not authenticated"
    fi
else
    print_info "Tailscale not installed, skipping connectivity check"
fi

# ======================================
# Summary
# ======================================
print_section "Validation Summary"

echo "Total checks performed: $CHECKS"
echo ""

if [ $ERRORS -gt 0 ]; then
    print_error "Validation completed with $ERRORS error(s)"
    echo ""
    print_info "Please resolve the errors above before proceeding with deployment."
    print_info "See the following documentation for setup instructions:"
    print_info "  - README.md - General setup and prerequisites"
    print_info "  - DEPLOYMENT_AUDIT.md - Tool installation steps"
    print_info "  - SECRETS.md - Credential and secret management"
    print_info "  - TAILSCALE_SETUP.md - Tailscale configuration"
    print_info "  - helmfile/CLOUDFLARED_SETUP.md - Cloudflare tunnel setup"
    echo ""
    exit 1
else
    print_success "✨ All critical checks passed!"
    
    if [ $WARNINGS -gt 0 ]; then
        echo ""
        print_warning "Note: $WARNINGS warning(s) found"
        print_info "Warnings indicate optional components or recommended configurations."
        print_info "You can proceed, but consider addressing warnings for full functionality."
    fi
    
    echo ""
    print_info "Next steps:"
    print_info "  1. Review TAILSCALE_SETUP.md to configure Tailscale networking"
    print_info "  2. Review HYBRID_CLUSTER_SETUP.md to deploy the k3s cluster"
    print_info "  3. Review helmfile/CLOUDFLARED_SETUP.md to setup Cloudflare tunnels"
    print_info "  4. Run 'cd ansible && ansible-playbook -i inventory.ini playbooks/deploy-k3s.yaml'"
    echo ""
    exit 0
fi
