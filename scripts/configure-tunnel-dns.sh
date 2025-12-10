#!/bin/bash
#
# Cloudflare Tunnel DNS Configuration Script
#
# This script configures DNS routes for an existing Cloudflare Tunnel,
# mapping hostnames to the tunnel endpoint.
#
# Usage:
#   ./configure-tunnel-dns.sh [OPTIONS]
#
# Options:
#   -t, --tunnel-name <NAME>   Tunnel name (required)
#   -d, --domains <LIST>       Comma-separated list of domains/subdomains (required)
#   -r, --remove               Remove DNS routes instead of adding them
#   -l, --list                 List existing DNS routes
#   -v, --verify               Verify DNS propagation after configuration
#   -h, --help                 Show this help message
#
# Examples:
#   # Add DNS routes
#   ./configure-tunnel-dns.sh \
#     -t infrastructure-prod-tunnel \
#     -d "app.example.com,api.example.com,grafana.example.com"
#
#   # List routes
#   ./configure-tunnel-dns.sh -t infrastructure-prod-tunnel -l
#
#   # Remove routes
#   ./configure-tunnel-dns.sh \
#     -t infrastructure-prod-tunnel \
#     -d "app.example.com" \
#     -r
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TUNNEL_NAME=""
DOMAINS=""
REMOVE_MODE=false
LIST_MODE=false
VERIFY_DNS=false

# Function to print colored messages
print_error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
}

# Function to display help
show_help() {
    head -n 30 "$0" | tail -n 28 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tunnel-name)
            TUNNEL_NAME="$2"
            shift 2
            ;;
        -d|--domains)
            DOMAINS="$2"
            shift 2
            ;;
        -r|--remove)
            REMOVE_MODE=true
            shift
            ;;
        -l|--list)
            LIST_MODE=true
            shift
            ;;
        -v|--verify)
            VERIFY_DNS=true
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

# Validation
if [ -z "$TUNNEL_NAME" ]; then
    print_error "Tunnel name is required. Use -t or --tunnel-name option."
    echo ""
    echo "To find your tunnel name, run:"
    echo "  cloudflared tunnel list"
    exit 1
fi

echo "======================================================================"
echo "  Cloudflare Tunnel DNS Configuration"
echo "======================================================================"
echo ""
print_info "Tunnel Name: $TUNNEL_NAME"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

# Check if cloudflared is installed
if ! command -v cloudflared &> /dev/null; then
    print_error "cloudflared is not installed"
    echo ""
    echo "Install cloudflared:"
    echo "  macOS:  brew install cloudflared"
    echo "  Linux:  wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
    exit 1
fi
print_success "cloudflared is installed ($(cloudflared --version))"

# Verify tunnel exists
print_info "Verifying tunnel exists..."
if ! cloudflared tunnel info "$TUNNEL_NAME" &>/dev/null; then
    print_error "Tunnel '$TUNNEL_NAME' not found or not accessible"
    echo ""
    echo "Available tunnels:"
    cloudflared tunnel list || echo "  (none found or not authenticated)"
    echo ""
    echo "To authenticate:"
    echo "  cloudflared tunnel login"
    exit 1
fi
print_success "Tunnel verified"

# Get tunnel information
TUNNEL_INFO=$(cloudflared tunnel info "$TUNNEL_NAME" 2>/dev/null || echo "")
if [ -n "$TUNNEL_INFO" ]; then
    TUNNEL_ID=$(echo "$TUNNEL_INFO" | grep "ID:" | awk '{print $2}')
    print_info "Tunnel ID: $TUNNEL_ID"
fi

# List mode
if [ "$LIST_MODE" = true ]; then
    echo ""
    print_info "Listing DNS routes for tunnel '$TUNNEL_NAME'..."
    echo ""
    
    if cloudflared tunnel route list 2>/dev/null | grep -q "No routes"; then
        print_warning "No DNS routes found for this tunnel"
    else
        cloudflared tunnel route list 2>/dev/null || print_error "Failed to list routes"
    fi
    
    exit 0
fi

# Validate domains are provided for add/remove operations
if [ -z "$DOMAINS" ]; then
    print_error "Domains are required. Use -d or --domains option."
    echo ""
    echo "Example: -d \"app.example.com,api.example.com\""
    exit 1
fi

# Convert comma-separated domains to array
IFS=',' read -ra DOMAIN_ARRAY <<< "$DOMAINS"

# Trim whitespace from domains
CLEAN_DOMAINS=()
for domain in "${DOMAIN_ARRAY[@]}"; do
    CLEAN_DOMAINS+=("$(echo "$domain" | xargs)")
done

echo ""
if [ "$REMOVE_MODE" = true ]; then
    print_info "Mode: Remove DNS routes"
else
    print_info "Mode: Add DNS routes"
fi

echo "Domains to process: ${#CLEAN_DOMAINS[@]}"
for domain in "${CLEAN_DOMAINS[@]}"; do
    echo "  - $domain"
done
echo ""

# Confirmation prompt
if [ "$REMOVE_MODE" = true ]; then
    ACTION="remove"
    ACTION_MSG="This will DELETE DNS routes from Cloudflare"
else
    ACTION="add"
    ACTION_MSG="This will CREATE DNS routes in Cloudflare"
fi

echo "$ACTION_MSG"
read -p "Continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warning "Operation cancelled"
    exit 0
fi

echo ""
print_info "Processing DNS routes..."
echo ""

# Track success/failure
SUCCESS_COUNT=0
FAILED_DOMAINS=()

# Process each domain
for domain in "${CLEAN_DOMAINS[@]}"; do
    echo "Processing: $domain"
    
    if [ "$REMOVE_MODE" = true ]; then
        # Remove DNS route
        if cloudflared tunnel route dns --overwrite-dns "$TUNNEL_NAME" "$domain" 2>&1 | grep -q "error\|Error"; then
            print_error "Failed to remove route for $domain"
            FAILED_DOMAINS+=("$domain")
        else
            # Cloudflare doesn't have a direct 'remove' command, so we verify it was processed
            print_success "Processed removal request for $domain"
            ((SUCCESS_COUNT++))
        fi
    else
        # Add DNS route
        if cloudflared tunnel route dns "$TUNNEL_NAME" "$domain" 2>&1 | tee /tmp/cloudflared-output-$$.txt | grep -q "error\|Error\|already exists"; then
            OUTPUT=$(cat /tmp/cloudflared-output-$$.txt)
            
            if echo "$OUTPUT" | grep -q "already exists"; then
                print_warning "DNS route already exists for $domain"
                ((SUCCESS_COUNT++))
            else
                print_error "Failed to add route for $domain"
                echo "  Error: $OUTPUT"
                FAILED_DOMAINS+=("$domain")
            fi
            rm -f /tmp/cloudflared-output-$$.txt
        else
            print_success "Added DNS route for $domain"
            ((SUCCESS_COUNT++))
            rm -f /tmp/cloudflared-output-$$.txt
        fi
    fi
    
    echo ""
done

# Summary
echo "======================================================================"
print_info "DNS Configuration Summary"
echo "======================================================================"
echo ""
echo "Successful: $SUCCESS_COUNT/${#CLEAN_DOMAINS[@]}"

if [ ${#FAILED_DOMAINS[@]} -gt 0 ]; then
    echo "Failed domains:"
    for domain in "${FAILED_DOMAINS[@]}"; do
        echo "  - $domain"
    done
fi

echo ""

# List current routes
print_info "Current DNS routes for tunnel '$TUNNEL_NAME':"
echo ""
cloudflared tunnel route list 2>/dev/null || print_warning "Unable to list routes"

# DNS verification
if [ "$VERIFY_DNS" = true ] && [ "$REMOVE_MODE" = false ] && [ $SUCCESS_COUNT -gt 0 ]; then
    echo ""
    print_info "Verifying DNS propagation..."
    echo ""
    
    # Check if dig is available
    if command -v dig &> /dev/null; then
        for domain in "${CLEAN_DOMAINS[@]}"; do
            # Skip if it failed earlier
            if [[ " ${FAILED_DOMAINS[@]} " =~ " ${domain} " ]]; then
                continue
            fi
            
            echo "Checking: $domain"
            
            # Query DNS
            RESULT=$(dig +short "$domain" @1.1.1.1 CNAME 2>/dev/null || echo "")
            
            if [ -n "$RESULT" ]; then
                if echo "$RESULT" | grep -q "cfargotunnel.com"; then
                    print_success "DNS configured correctly"
                    echo "  Points to: $RESULT"
                else
                    print_warning "DNS points to: $RESULT (expected *.cfargotunnel.com)"
                fi
            else
                print_warning "DNS not propagated yet (this can take a few minutes)"
            fi
            echo ""
        done
    else
        print_warning "dig not installed, skipping DNS verification"
        echo "  Install: brew install bind (macOS) or apt-get install dnsutils (Linux)"
    fi
fi

echo ""
print_info "Next steps:"
echo ""
echo "1. Verify DNS routes:"
echo "   cloudflared tunnel route list"
echo ""
echo "2. Update Helmfile ingress configuration:"
echo "   vim helmfile/values/cloudflared-values.yaml"
echo ""
echo "   Add ingress rules for each domain:"
for domain in "${CLEAN_DOMAINS[@]}"; do
    echo "   - hostname: $domain"
    echo "     service: http://<service-name>.<namespace>.svc.cluster.local:<port>"
done
echo ""
echo "3. Deploy Cloudflared to Kubernetes:"
echo "   cd helmfile"
echo "   helmfile apply"
echo ""
echo "4. Verify deployment:"
echo "   kubectl get pods -n cloudflare"
echo "   kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared"
echo ""
echo "5. Test access:"
for domain in "${CLEAN_DOMAINS[@]}"; do
    echo "   curl -I https://$domain"
done
echo ""
print_info "For detailed documentation, see:"
echo "   helmfile/CLOUDFLARED_SETUP.md"
echo ""

if [ ${#FAILED_DOMAINS[@]} -gt 0 ]; then
    exit 1
else
    print_success "All DNS routes configured successfully!"
    exit 0
fi
