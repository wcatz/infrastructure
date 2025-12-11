#!/bin/bash
# lib.sh - Shared helper library for runme.sh and step scripts
# This library provides colorized print helpers, confirmations, and utility functions

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print helpers
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

# Function to validate cloudflared tunnel connectivity
validate_cloudflared_tunnel() {
    local namespace="${1:-cloudflare}"
    local max_retries=30
    local retry_interval=10
    
    print_info "Validating Cloudflared tunnel connectivity..."
    
    # Check if cloudflared namespace exists
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        print_warning "Cloudflared namespace '$namespace' not found"
        return 1
    fi
    
    # Check if cloudflared pods are running
    print_info "Checking cloudflared pod status..."
    local pods_ready=false
    for i in $(seq 1 $max_retries); do
        local running_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=cloudflared --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        local total_pods=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=cloudflared --no-headers 2>/dev/null | wc -l)
        
        if [ "$total_pods" -eq 0 ]; then
            print_warning "No cloudflared pods found (attempt $i/$max_retries)"
        elif [ "$running_pods" -eq "$total_pods" ] && [ "$running_pods" -gt 0 ]; then
            print_success "All cloudflared pods are running ($running_pods/$total_pods)"
            pods_ready=true
            break
        else
            print_info "Waiting for cloudflared pods to be ready ($running_pods/$total_pods ready) - attempt $i/$max_retries"
        fi
        
        if [ $i -lt $max_retries ]; then
            sleep $retry_interval
        fi
    done
    
    if [ "$pods_ready" = false ]; then
        print_error "Cloudflared pods did not become ready within timeout"
        kubectl get pods -n "$namespace" -l app.kubernetes.io/name=cloudflared 2>/dev/null || true
        return 1
    fi
    
    # Check for tunnel connection in logs
    print_info "Verifying tunnel connection in pod logs..."
    local pod_name=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=cloudflared --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$pod_name" ]; then
        # Look for connection success indicators in logs
        if kubectl logs -n "$namespace" "$pod_name" --tail=100 2>/dev/null | grep -qi "connection.*registered\|registered tunnel connection\|connected to"; then
            print_success "Cloudflared tunnel connection established successfully"
            return 0
        else
            print_warning "Could not confirm tunnel connection from logs"
            print_info "Recent cloudflared logs:"
            kubectl logs -n "$namespace" "$pod_name" --tail=20 2>/dev/null || true
            return 1
        fi
    else
        print_warning "Could not find cloudflared pod for log validation"
        return 1
    fi
}

# Robust function to get the first non-comment host line for a given group
get_first_host_line() {
    local group="$1"
    # Prints first non-blank, non-comment line after matching [group] and before next [othergroup]
    awk -v grp="$group" '
    $0 ~ /^\[.*\]/ {
      if ($0 == "[" grp "]") { in_group = 1; next }
      else if (in_group) exit
    }
    in_group == 1 {
      if ($0 ~ /^\s*#/ || $0 ~ /^\s*$/) next
      print; exit
    }
    ' ansible/inventory.ini || true
}

# Remote SCP helper function
remote_scp() {
    local user="$1"
    local host="$2"
    local remote_path="$3"
    local local_path="$4"
    
    if [ -z "$user" ] || [ -z "$host" ] || [ -z "$remote_path" ] || [ -z "$local_path" ]; then
        print_error "remote_scp: Missing required parameters"
        print_info "Usage: remote_scp <user> <host> <remote_path> <local_path>"
        return 1
    fi
    
    print_info "Copying from $user@$host:$remote_path to $local_path..."
    if scp "$user@$host:$remote_path" "$local_path"; then
        return 0
    else
        print_error "Failed to copy from remote host"
        return 1
    fi
}
