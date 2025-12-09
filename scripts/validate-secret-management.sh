#!/bin/bash
# Secret Management Implementation Validation
#
# This script validates the SOPS secret management implementation
# Usage: ./validate-secret-management.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "Secret Management Implementation Validation"
echo "=============================================="
echo ""

ERRORS=0
WARNINGS=0

# Function to check file exists
check_file() {
    local file=$1
    local desc=$2
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅ $desc exists: $file${NC}"
    else
        echo -e "${RED}❌ $desc missing: $file${NC}"
        ERRORS=$((ERRORS + 1))
    fi
}

# Function to check directory exists
check_dir() {
    local dir=$1
    local desc=$2
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✅ $desc exists: $dir${NC}"
    else
        echo -e "${RED}❌ $desc missing: $dir${NC}"
        ERRORS=$((ERRORS + 1))
    fi
}

# Function to check file content contains pattern
check_content() {
    local file=$1
    local pattern=$2
    local desc=$3
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo -e "${GREEN}✅ $desc: $file contains '$pattern'${NC}"
    else
        echo -e "${YELLOW}⚠️  $desc: $file doesn't contain '$pattern'${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
}

echo "=== 1. Core Files ==="
check_file ".sops.yaml" "SOPS configuration"
check_file "SECRETS.md" "Secret management documentation"
check_file "SECURITY.md" "Security policy documentation"
check_file "SOPS_SETUP.md" "SOPS setup guide"
check_file ".gitignore" "Gitignore configuration"
echo ""

echo "=== 2. Helmfile Structure ==="
check_dir "helmfile/secrets" "Secrets directory"
check_file "helmfile/secrets/README.md" "Secrets directory README"
check_file "helmfile/secrets/cloudflared-credentials-example.enc.yaml" "Cloudflared example"
check_file "helmfile/secrets/github-runner-secrets-example.enc.yaml" "GitHub runner example"
check_file "helmfile/secrets/monitoring-secrets-example.enc.yaml" "Monitoring secrets example"
echo ""

echo "=== 3. Environment Configuration ==="
check_file "helmfile/environments/dev/enabled.yaml" "Dev environment config"
check_file "helmfile/environments/staging/enabled.yaml" "Staging environment config"
check_file "helmfile/environments/prod/enabled.yaml" "Production environment config"
echo ""

echo "=== 4. Non-Production Environments Disabled ==="
# Check dev environment is disabled
if grep -q "prometheus: false" helmfile/environments/dev/enabled.yaml && \
   grep -q "cloudflared: false" helmfile/environments/dev/enabled.yaml; then
    echo -e "${GREEN}✅ Dev environment services are disabled${NC}"
else
    echo -e "${RED}❌ Dev environment services not fully disabled${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check staging environment is disabled
if grep -q "prometheus: false" helmfile/environments/staging/enabled.yaml && \
   grep -q "cloudflared: false" helmfile/environments/staging/enabled.yaml; then
    echo -e "${GREEN}✅ Staging environment services are disabled${NC}"
else
    echo -e "${RED}❌ Staging environment services not fully disabled${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check production environment is enabled
if grep -q "prometheus: true" helmfile/environments/prod/enabled.yaml && \
   grep -q "cloudflared: true" helmfile/environments/prod/enabled.yaml; then
    echo -e "${GREEN}✅ Production environment services are enabled${NC}"
else
    echo -e "${YELLOW}⚠️  Production environment services not fully enabled${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

echo "=== 5. SOPS Configuration ==="
check_content ".sops.yaml" "creation_rules" "SOPS has creation rules"
check_content ".sops.yaml" "age:" "SOPS uses age encryption"
check_content ".sops.yaml" "encrypted_regex" "SOPS has encrypted_regex"
echo ""

echo "=== 6. GitIgnore Configuration ==="
check_content ".gitignore" "!.sops.yaml" "GitIgnore allows .sops.yaml"
check_content ".gitignore" "!*.enc.yaml" "GitIgnore allows encrypted secrets"
check_content ".gitignore" "*credentials*.yaml" "GitIgnore blocks plaintext credentials"
check_content ".gitignore" "*-secrets.yaml" "GitIgnore blocks plaintext secrets"
echo ""

echo "=== 7. Documentation Content ==="
check_content "SECRETS.md" "SOPS with age" "SECRETS.md covers SOPS"
check_content "SECRETS.md" "Cloudflared" "SECRETS.md covers Cloudflared"
check_content "SECRETS.md" "Secret Rotation" "SECRETS.md covers rotation"
check_content "SECURITY.md" "Secret Exposure Mitigation" "SECURITY.md covers exposure"
check_content "SECURITY.md" "Non-production environments DISABLED" "SECURITY.md documents environment policy"
echo ""

echo "=== 8. Scripts ==="
check_file "scripts/health-check.sh" "Health check script"
if [ -f "scripts/health-check.sh" ]; then
    if [ -x "scripts/health-check.sh" ]; then
        echo -e "${GREEN}✅ Health check script is executable${NC}"
    else
        echo -e "${YELLOW}⚠️  Health check script is not executable${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
    
    # Check script syntax - use relative path since script validates from repo root
    if [ -f "scripts/health-check.sh" ] && bash -n "scripts/health-check.sh" 2>/dev/null; then
        echo -e "${GREEN}✅ Health check script has valid syntax${NC}"
    else
        echo -e "${RED}❌ Health check script has syntax errors or not found${NC}"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

echo "=== 9. YAML Validation ==="
if command -v yamllint &> /dev/null; then
    echo "Running yamllint..."
    
    # Check .sops.yaml
    if yamllint .sops.yaml > /dev/null 2>&1; then
        echo -e "${GREEN}✅ .sops.yaml is valid YAML${NC}"
    else
        echo -e "${RED}❌ .sops.yaml has YAML errors${NC}"
        ERRORS=$((ERRORS + 1))
    fi
    
    # Check environment configs
    if yamllint helmfile/environments/*/enabled.yaml > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Environment configs are valid YAML${NC}"
    else
        echo -e "${RED}❌ Environment configs have YAML errors${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}⚠️  yamllint not installed, skipping YAML validation${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

echo "=== 10. README and CHANGELOG Updates ==="
check_content "README.md" "SECRETS.md" "README references SECRETS.md"
check_content "README.md" "SECURITY.md" "README references SECURITY.md"
check_content "CHANGELOG.md" "SOPS" "CHANGELOG documents SOPS implementation"
check_content "CHANGELOG.md" "Non-production environments" "CHANGELOG documents environment changes"
echo ""

echo "=== 11. Security Checklist ==="
echo "Verifying security requirements..."

# Check for SOPS encryption setup
if [ -f ".sops.yaml" ]; then
    echo -e "${GREEN}✅ SOPS encryption configured${NC}"
else
    echo -e "${RED}❌ SOPS encryption not configured${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check example secrets are encrypted format
if grep -q "sops:" helmfile/secrets/cloudflared-credentials-example.enc.yaml 2>/dev/null && \
   grep -q "mac:" helmfile/secrets/cloudflared-credentials-example.enc.yaml 2>/dev/null; then
    echo -e "${GREEN}✅ Example secrets use SOPS encrypted format${NC}"
else
    echo -e "${YELLOW}⚠️  Example secrets don't show SOPS format${NC}"
    WARNINGS=$((WARNINGS + 1))
fi

# Check non-prod environments disabled
if grep -q "false" helmfile/environments/dev/enabled.yaml && \
   grep -q "false" helmfile/environments/staging/enabled.yaml; then
    echo -e "${GREEN}✅ Non-production environments disabled${NC}"
else
    echo -e "${RED}❌ Non-production environments not disabled${NC}"
    ERRORS=$((ERRORS + 1))
fi

# Check documentation exists
if [ -f "SECRETS.md" ] && [ -f "SECURITY.md" ]; then
    echo -e "${GREEN}✅ Security documentation complete${NC}"
else
    echo -e "${RED}❌ Security documentation incomplete${NC}"
    ERRORS=$((ERRORS + 1))
fi
echo ""

echo "=============================================="
echo "Validation Summary"
echo "=============================================="
echo ""
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All validations passed!${NC}"
    echo ""
    echo "Next Steps:"
    echo "1. Generate your age key: age-keygen -o ~/.config/sops/age/keys.txt"
    echo "2. Update .sops.yaml with your public key"
    echo "3. Add SOPS_AGE_KEY to GitHub Secrets"
    echo "4. Create and encrypt actual secrets (see SECRETS.md)"
    echo "5. Run health check: ./scripts/health-check.sh"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Validation failed with $ERRORS error(s)${NC}"
    echo ""
    echo "Please fix the errors above and re-run validation."
    exit 1
fi
