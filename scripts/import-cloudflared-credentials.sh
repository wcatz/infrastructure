#!/bin/bash
#
# Cloudflare Tunnel Credentials Import Script
# 
# This script helps import existing Cloudflare Tunnel credentials into 
# Kubernetes for use with the infrastructure cluster.
#
# Usage:
#   ./import-cloudflared-credentials.sh [OPTIONS]
#
# Options:
#   -t, --tunnel-id <ID>       Tunnel ID (required)
#   -n, --tunnel-name <NAME>   Tunnel name (optional, for verification)
#   -c, --creds-file <PATH>    Path to credentials file (default: ~/.cloudflared/<TUNNEL-ID>.json)
#   -e, --environment <ENV>    Target environment: dev, staging, prod (default: production)
#   -s, --skip-validation      Skip tunnel validation
#   -h, --help                 Show this help message
#
# Example:
#   ./import-cloudflared-credentials.sh \
#     -t 12345678-1234-1234-1234-123456789abc \
#     -n infrastructure-prod-tunnel \
#     -e prod
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
TUNNEL_ID=""
TUNNEL_NAME=""
CREDENTIALS_FILE=""
ENVIRONMENT="production"
SKIP_VALIDATION=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
    sed -n '/^# Cloudflare Tunnel Credentials Import Script/,/^$/p' "$0" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tunnel-id)
            TUNNEL_ID="$2"
            shift 2
            ;;
        -n|--tunnel-name)
            TUNNEL_NAME="$2"
            shift 2
            ;;
        -c|--creds-file)
            CREDENTIALS_FILE="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--skip-validation)
            SKIP_VALIDATION=true
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
if [ -z "$TUNNEL_ID" ]; then
    print_error "Tunnel ID is required. Use -t or --tunnel-id option."
    echo ""
    echo "To find your tunnel ID, run:"
    echo "  cloudflared tunnel list"
    exit 1
fi

# Set default credentials file if not provided
if [ -z "$CREDENTIALS_FILE" ]; then
    CREDENTIALS_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
fi

# Validate environment
case $ENVIRONMENT in
    dev|staging|prod|production)
        ;;
    *)
        print_error "Invalid environment: $ENVIRONMENT"
        echo "Valid options: dev, staging, prod, production"
        exit 1
        ;;
esac

# Normalize environment name
if [ "$ENVIRONMENT" = "production" ]; then
    ENV_DIR="prod"
else
    ENV_DIR="$ENVIRONMENT"
fi

echo "======================================================================"
echo "  Cloudflare Tunnel Credentials Import"
echo "======================================================================"
echo ""
print_info "Configuration:"
echo "  Tunnel ID:        $TUNNEL_ID"
echo "  Tunnel Name:      ${TUNNEL_NAME:-<will be read from credentials>}"
echo "  Credentials File: $CREDENTIALS_FILE"
echo "  Environment:      $ENVIRONMENT ($ENV_DIR)"
echo "  Repository Root:  $REPO_ROOT"
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
print_success "cloudflared is installed"

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed"
    echo ""
    echo "Install kubectl:"
    echo "  macOS:  brew install kubectl"
    echo "  Linux:  See https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
print_success "kubectl is installed"

# Check if sops is installed
if ! command -v sops &> /dev/null; then
    print_error "sops is not installed"
    echo ""
    echo "Install sops:"
    echo "  macOS:  brew install sops"
    echo "  Linux:  See https://github.com/mozilla/sops/releases"
    exit 1
fi
print_success "sops is installed"

# Check if jq is installed (optional but recommended)
if ! command -v jq &> /dev/null; then
    print_warning "jq is not installed (optional, for JSON validation)"
    echo "  Install: brew install jq (macOS) or apt-get install jq (Linux)"
fi

# Check if credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
    print_error "Credentials file not found: $CREDENTIALS_FILE"
    echo ""
    echo "Expected location: ~/.cloudflared/${TUNNEL_ID}.json"
    echo ""
    echo "To get credentials:"
    echo "  1. Login: cloudflared tunnel login"
    echo "  2. Create tunnel: cloudflared tunnel create <name>"
    echo "  3. Credentials will be saved to ~/.cloudflared/<TUNNEL-ID>.json"
    echo ""
    echo "Or specify a custom path with -c option"
    exit 1
fi
print_success "Credentials file found"

# Validate JSON structure
print_info "Validating credentials file..."
if command -v jq &> /dev/null; then
    if ! jq empty "$CREDENTIALS_FILE" 2>/dev/null; then
        print_error "Credentials file is not valid JSON"
        exit 1
    fi
    
    # Extract tunnel name from credentials
    CREDS_TUNNEL_NAME=$(jq -r '.TunnelName // empty' "$CREDENTIALS_FILE")
    CREDS_TUNNEL_ID=$(jq -r '.TunnelID // empty' "$CREDENTIALS_FILE")
    CREDS_ACCOUNT_TAG=$(jq -r '.AccountTag // empty' "$CREDENTIALS_FILE")
    
    if [ -z "$CREDS_TUNNEL_ID" ]; then
        print_error "TunnelID not found in credentials file"
        exit 1
    fi
    
    if [ "$CREDS_TUNNEL_ID" != "$TUNNEL_ID" ]; then
        print_error "Tunnel ID mismatch!"
        echo "  Expected: $TUNNEL_ID"
        echo "  Found:    $CREDS_TUNNEL_ID"
        exit 1
    fi
    
    print_success "Credentials file is valid JSON"
    echo "  Tunnel Name: $CREDS_TUNNEL_NAME"
    echo "  Tunnel ID:   $CREDS_TUNNEL_ID"
    echo "  Account:     ${CREDS_ACCOUNT_TAG:0:8}..."
    
    # Use credentials tunnel name if not provided
    if [ -z "$TUNNEL_NAME" ] && [ -n "$CREDS_TUNNEL_NAME" ]; then
        TUNNEL_NAME="$CREDS_TUNNEL_NAME"
    fi
else
    print_warning "Skipping JSON validation (jq not installed)"
fi

# Validate tunnel exists (optional)
if [ "$SKIP_VALIDATION" = false ]; then
    print_info "Validating tunnel exists in Cloudflare..."
    
    if cloudflared tunnel info "$TUNNEL_ID" &>/dev/null || \
       cloudflared tunnel info "$TUNNEL_NAME" &>/dev/null; then
        print_success "Tunnel exists and is accessible"
    else
        print_error "Failed to validate tunnel in Cloudflare"
        echo ""
        echo "This could mean:"
        echo "  1. Tunnel doesn't exist or was deleted"
        echo "  2. Not authenticated with Cloudflare (run: cloudflared tunnel login)"
        echo "  3. Network connectivity issues"
        echo ""
        echo "Use -s or --skip-validation to skip this check"
        exit 1
    fi
fi

# Create working directory
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

print_info "Working directory: $WORK_DIR"

# Create Kubernetes secret YAML
print_info "Creating Kubernetes secret manifest..."

cat > "$WORK_DIR/cloudflared-credentials.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflared-credentials
  namespace: cloudflare
type: Opaque
stringData:
  credentials.json: |
$(cat "$CREDENTIALS_FILE" | sed 's/^/    /')
EOF

print_success "Secret manifest created"

# Encrypt with SOPS
print_info "Encrypting credentials with SOPS..."

# Check if SOPS age key is configured
if [ -z "$SOPS_AGE_KEY_FILE" ] && [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
    print_error "SOPS age key not found"
    echo ""
    echo "Set SOPS_AGE_KEY_FILE or create key at ~/.config/sops/age/keys.txt"
    echo ""
    echo "To create an age key:"
    echo "  mkdir -p ~/.config/sops/age"
    echo "  age-keygen -o ~/.config/sops/age/keys.txt"
    echo ""
    echo "Then update .sops.yaml with your public key"
    exit 1
fi

export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if ! sops -e "$WORK_DIR/cloudflared-credentials.yaml" > "$WORK_DIR/cloudflared-credentials.enc.yaml"; then
    print_error "Failed to encrypt credentials with SOPS"
    echo ""
    echo "Ensure .sops.yaml is configured with your age public key"
    exit 1
fi

print_success "Credentials encrypted successfully"

# Determine output path
OUTPUT_DIR="$REPO_ROOT/helmfile/secrets"
if [ "$ENV_DIR" != "prod" ]; then
    OUTPUT_DIR="$REPO_ROOT/helmfile/environments/$ENV_DIR"
fi

OUTPUT_FILE="$OUTPUT_DIR/cloudflared-credentials.enc.yaml"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Copy encrypted file to repository
cp "$WORK_DIR/cloudflared-credentials.enc.yaml" "$OUTPUT_FILE"
print_success "Encrypted credentials saved to: $OUTPUT_FILE"

# Securely delete plaintext files
print_info "Securely deleting plaintext files..."
shred -u "$WORK_DIR/cloudflared-credentials.yaml" 2>/dev/null || rm -f "$WORK_DIR/cloudflared-credentials.yaml"

# Optionally delete original credentials
echo ""
read -p "Delete original credentials file? (y/N): " DELETE_ORIGINAL
if [[ "$DELETE_ORIGINAL" =~ ^[Yy]$ ]]; then
    if command -v shred &> /dev/null; then
        shred -u "$CREDENTIALS_FILE"
        print_success "Original credentials securely deleted"
    else
        rm -f "$CREDENTIALS_FILE"
        print_warning "Original credentials deleted (shred not available, used rm)"
    fi
else
    print_warning "Original credentials file retained: $CREDENTIALS_FILE"
    print_warning "Consider deleting it manually after verification"
fi

echo ""
echo "======================================================================"
print_success "Credentials import completed successfully!"
echo "======================================================================"
echo ""
print_info "Next steps:"
echo ""
echo "1. Review the encrypted credentials:"
echo "   cat $OUTPUT_FILE"
echo ""
echo "2. Commit the encrypted credentials to Git:"
echo "   git add $OUTPUT_FILE"
echo "   git commit -m \"Add Cloudflare Tunnel credentials for $ENVIRONMENT\""
echo ""
echo "3. Deploy the secret to Kubernetes:"
echo "   kubectl create namespace cloudflare --dry-run=client -o yaml | kubectl apply -f -"
echo "   sops -d $OUTPUT_FILE | kubectl apply -f -"
echo ""
echo "4. Update helmfile values with tunnel configuration:"
echo "   vim $REPO_ROOT/helmfile/values/cloudflared-values.yaml"
echo ""
echo "   Set:"
echo "     cloudflare:"
echo "       tunnelName: \"$TUNNEL_NAME\""
echo "       tunnelId: \"$TUNNEL_ID\""
echo ""
echo "5. Configure ingress rules for your services in cloudflared-values.yaml"
echo ""
echo "6. Deploy with Helmfile:"
echo "   cd $REPO_ROOT/helmfile"
echo "   helmfile diff  # Preview changes"
echo "   helmfile apply # Deploy"
echo ""
echo "7. Verify deployment:"
echo "   kubectl get pods -n cloudflare"
echo "   kubectl logs -n cloudflare -l app.kubernetes.io/name=cloudflared"
echo ""
print_info "For detailed documentation, see:"
echo "   $REPO_ROOT/helmfile/CLOUDFLARED_SETUP.md"
echo ""
