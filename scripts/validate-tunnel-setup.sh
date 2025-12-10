#!/bin/bash
#
# Cloudflare Tunnel Validation Script
#
# This script validates the Cloudflare Tunnel setup in Kubernetes,
# checking credentials, pod status, connectivity, and DNS configuration.
#
# Usage:
#   ./validate-tunnel-setup.sh [OPTIONS]
#
# Options:
#   -n, --namespace <NAME>     Kubernetes namespace (default: cloudflare)
#   -t, --tunnel-name <NAME>   Expected tunnel name (optional)
#   -d, --domains <LIST>       Comma-separated domains to test (optional)
#   -s, --skip-dns             Skip DNS verification
#   -h, --help                 Show this help message
#
# Examples:
#   # Basic validation
#   ./validate-tunnel-setup.sh
#
#   # Validate with specific tunnel and domains
#   ./validate-tunnel-setup.sh \
#     -t infrastructure-prod-tunnel \
#     -d "app.example.com,api.example.com"
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="cloudflare"
TUNNEL_NAME=""
DOMAINS=""
SKIP_DNS=false

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Function to print colored messages
print_error() {
    echo -e "${RED}❌ FAIL: $1${NC}"
    ((CHECKS_FAILED++))
}

print_success() {
    echo -e "${GREEN}✅ PASS: $1${NC}"
    ((CHECKS_PASSED++))
}

print_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARN: $1${NC}"
    ((CHECKS_WARNING++))
}

# Function to display help
show_help() {
    sed -n '/^# Cloudflare Tunnel Validation Script/,/^$/p' "$0" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -t|--tunnel-name)
            TUNNEL_NAME="$2"
            shift 2
            ;;
        -d|--domains)
            DOMAINS="$2"
            shift 2
            ;;
        -s|--skip-dns)
            SKIP_DNS=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            ;;
    esac
done

echo "======================================================================"
echo "  Cloudflare Tunnel Setup Validation"
echo "======================================================================"
echo ""
print_info "Configuration:"
echo "  Namespace:    $NAMESPACE"
echo "  Tunnel Name:  ${TUNNEL_NAME:-<not specified>}"
echo "  Domains:      ${DOMAINS:-<not specified>}"
echo ""

# Prerequisites check
print_info "Checking prerequisites..."
echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    exit 1
fi
print_success "kubectl is installed"

# Check cluster access
if ! kubectl cluster-info &>/dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    echo "  Verify kubeconfig and cluster connectivity"
    exit 1
fi
print_success "Kubernetes cluster is accessible"

# Optional: Check cloudflared
if command -v cloudflared &> /dev/null; then
    print_success "cloudflared CLI is installed"
else
    print_warning "cloudflared CLI not installed (optional)"
fi

# Optional: Check curl
if command -v curl &> /dev/null; then
    print_success "curl is installed"
else
    print_warning "curl not installed (needed for HTTP tests)"
fi

echo ""
echo "======================================================================"
print_info "Validating Kubernetes Resources"
echo "======================================================================"
echo ""

# Check namespace
print_info "Checking namespace..."
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    print_success "Namespace '$NAMESPACE' exists"
else
    print_error "Namespace '$NAMESPACE' does not exist"
    echo "  Create with: kubectl create namespace $NAMESPACE"
    exit 1
fi

# Check secret
print_info "Checking credentials secret..."
if kubectl get secret cloudflared-credentials -n "$NAMESPACE" &>/dev/null; then
    print_success "Secret 'cloudflared-credentials' exists"
    
    # Fetch secret data once
    CREDS_DATA=$(kubectl get secret cloudflared-credentials -n "$NAMESPACE" -o jsonpath='{.data.credentials\.json}' 2>/dev/null)
    
    # Verify secret has the required key
    if [ -n "$CREDS_DATA" ]; then
        CREDS_JSON=$(echo "$CREDS_DATA" | base64 -d 2>/dev/null)
        
        if [ -n "$CREDS_JSON" ]; then
            print_success "Secret contains 'credentials.json' key"
            
            # Try to parse as JSON
            if command -v jq &> /dev/null; then
                if echo "$CREDS_JSON" | jq empty 2>/dev/null; then
                    print_success "Credentials JSON is valid"
                    
                    # Extract tunnel info
                    SECRET_TUNNEL_NAME=$(echo "$CREDS_JSON" | jq -r '.TunnelName // empty')
                    SECRET_TUNNEL_ID=$(echo "$CREDS_JSON" | jq -r '.TunnelID // empty')
                    
                    echo "  Tunnel Name: $SECRET_TUNNEL_NAME"
                    echo "  Tunnel ID:   $SECRET_TUNNEL_ID"
                    
                    # Verify tunnel name matches if provided
                    if [ -n "$TUNNEL_NAME" ] && [ "$SECRET_TUNNEL_NAME" != "$TUNNEL_NAME" ]; then
                        print_warning "Tunnel name mismatch"
                        echo "  Expected: $TUNNEL_NAME"
                        echo "  Found:    $SECRET_TUNNEL_NAME"
                    fi
                else
                    print_error "Credentials JSON is invalid"
                fi
            fi
        else
            print_error "Failed to decode credentials data"
        fi
    else
        print_error "Secret missing 'credentials.json' key"
    fi
else
    print_error "Secret 'cloudflared-credentials' not found"
    echo "  Create with: sops -d helmfile/secrets/cloudflared-credentials.enc.yaml | kubectl apply -f -"
fi

# Check deployment/pods
print_info "Checking cloudflared deployment..."
if kubectl get deployment cloudflared -n "$NAMESPACE" &>/dev/null; then
    print_success "Deployment 'cloudflared' exists"
    
    # Check replica status
    DESIRED=$(kubectl get deployment cloudflared -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment cloudflared -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    AVAILABLE=$(kubectl get deployment cloudflared -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')
    
    echo "  Desired:   $DESIRED"
    echo "  Ready:     ${READY:-0}"
    echo "  Available: ${AVAILABLE:-0}"
    
    if [ "${READY:-0}" -eq "$DESIRED" ] && [ "${AVAILABLE:-0}" -eq "$DESIRED" ]; then
        print_success "All replicas are ready and available"
    else
        print_warning "Not all replicas are ready"
    fi
else
    print_error "Deployment 'cloudflared' not found"
    echo "  Deploy with: helmfile apply"
fi

# Check pods
print_info "Checking cloudflared pods..."
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=cloudflared --no-headers 2>/dev/null | wc -l)

if [ "$POD_COUNT" -gt 0 ]; then
    print_success "Found $POD_COUNT cloudflared pod(s)"
    
    # Check each pod status
    RUNNING_PODS=0
    while IFS= read -r line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        POD_STATUS=$(echo "$line" | awk '{print $3}')
        POD_READY=$(echo "$line" | awk '{print $2}')
        
        if [ "$POD_STATUS" = "Running" ] && [[ "$POD_READY" == "1/1" ]]; then
            ((RUNNING_PODS++))
            echo "  ✓ $POD_NAME: $POD_STATUS ($POD_READY)"
        else
            echo "  ✗ $POD_NAME: $POD_STATUS ($POD_READY)"
        fi
    done < <(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=cloudflared --no-headers)
    
    if [ "$RUNNING_PODS" -eq "$POD_COUNT" ]; then
        print_success "All pods are running and ready"
    else
        print_warning "Some pods are not running/ready"
    fi
    
    # Check recent pod logs for errors
    print_info "Checking pod logs for errors..."
    FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=cloudflared -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$FIRST_POD" ]; then
        ERROR_COUNT=$(kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=100 2>/dev/null | grep -i "error\|failed\|fatal" | wc -l)
        
        if [ "$ERROR_COUNT" -eq 0 ]; then
            print_success "No errors found in recent logs"
        else
            print_warning "Found $ERROR_COUNT error message(s) in logs"
            echo "  Review logs with: kubectl logs -n $NAMESPACE $FIRST_POD"
        fi
        
        # Check for successful connection message
        if kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=100 2>/dev/null | grep -q "Registered tunnel connection\|Connection.*established"; then
            print_success "Tunnel connection established"
        else
            print_warning "No tunnel connection confirmation in logs"
        fi
    fi
else
    print_error "No cloudflared pods found"
fi

# Check service account
print_info "Checking service account..."
if kubectl get serviceaccount cloudflared -n "$NAMESPACE" &>/dev/null; then
    print_success "ServiceAccount 'cloudflared' exists"
else
    print_warning "ServiceAccount 'cloudflared' not found (may not be required)"
fi

echo ""
echo "======================================================================"
print_info "Validating Network Connectivity"
echo "======================================================================"
echo ""

# Check if pods can reach Cloudflare
if [ "$POD_COUNT" -gt 0 ]; then
    print_info "Testing Cloudflare connectivity from pod..."
    FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=cloudflared -o jsonpath='{.items[0].metadata.name}')
    
    if [ -n "$FIRST_POD" ]; then
        # Try to get tunnel info from inside pod
        if kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- cloudflared version &>/dev/null; then
            CLOUDFLARED_VERSION=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- cloudflared version 2>/dev/null)
            print_success "Pod can execute cloudflared (version: $CLOUDFLARED_VERSION)"
        else
            print_warning "Cannot execute cloudflared in pod"
        fi
    fi
fi

# DNS validation
if [ "$SKIP_DNS" = false ] && [ -n "$DOMAINS" ]; then
    echo ""
    echo "======================================================================"
    print_info "Validating DNS Configuration"
    echo "======================================================================"
    echo ""
    
    IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"
    
    for domain in "${DOMAIN_ARRAY[@]}"; do
        domain=$(echo "$domain" | xargs)  # Trim whitespace
        
        print_info "Checking DNS for: $domain"
        
        if command -v dig &> /dev/null; then
            CNAME=$(dig +short "$domain" @1.1.1.1 CNAME 2>/dev/null || echo "")
            
            if [ -n "$CNAME" ]; then
                if echo "$CNAME" | grep -q "cfargotunnel.com"; then
                    print_success "DNS points to Cloudflare Tunnel"
                    echo "  Target: $CNAME"
                else
                    print_warning "DNS configured but not pointing to tunnel"
                    echo "  Target: $CNAME"
                fi
            else
                print_warning "No CNAME record found (may be A record or not configured)"
            fi
        elif command -v nslookup &> /dev/null; then
            if nslookup "$domain" 1.1.1.1 &>/dev/null; then
                print_success "Domain resolves"
            else
                print_warning "Domain does not resolve"
            fi
        else
            print_warning "Neither dig nor nslookup available for DNS check"
        fi
        
        # HTTP test if curl is available
        if command -v curl &> /dev/null; then
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "https://$domain" 2>/dev/null || echo "000")
            
            if [ "$HTTP_CODE" != "000" ]; then
                print_success "HTTP request successful (status: $HTTP_CODE)"
            else
                print_warning "Cannot reach $domain via HTTP"
            fi
        fi
        
        echo ""
    done
fi

# Summary
echo "======================================================================"
echo "  Validation Summary"
echo "======================================================================"
echo ""
echo "  Passed:   $CHECKS_PASSED"
echo "  Failed:   $CHECKS_FAILED"
echo "  Warnings: $CHECKS_WARNING"
echo ""

if [ $CHECKS_FAILED -eq 0 ]; then
    print_success "All critical checks passed!"
    
    if [ $CHECKS_WARNING -gt 0 ]; then
        print_warning "Some warnings detected - review output above"
    fi
    
    echo ""
    print_info "Next steps:"
    echo "  • Monitor pod logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=cloudflared -f"
    echo "  • Check tunnel status: cloudflared tunnel info <tunnel-name>"
    echo "  • View metrics: kubectl port-forward -n $NAMESPACE deployment/cloudflared 2000:2000"
    echo ""
    
    exit 0
else
    print_error "Validation failed with $CHECKS_FAILED error(s)"
    
    echo ""
    print_info "Troubleshooting tips:"
    echo "  • Check pod logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=cloudflared"
    echo "  • Describe pods: kubectl describe pods -n $NAMESPACE"
    echo "  • Verify credentials: kubectl get secret cloudflared-credentials -n $NAMESPACE -o yaml"
    echo "  • Review documentation: helmfile/CLOUDFLARED_SETUP.md"
    echo ""
    
    exit 1
fi
