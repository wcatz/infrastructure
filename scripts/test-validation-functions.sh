#!/bin/bash
# Test script for validation function improvements
# This script tests the new validation functions without requiring a live cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TESTS_PASSED=0
TESTS_FAILED=0

print_test_header() {
    echo ""
    echo "======================================"
    echo "$1"
    echo "======================================"
}

print_test_pass() {
    echo -e "${GREEN}✅ PASS: $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_test_fail() {
    echo -e "${RED}❌ FAIL: $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Test 1: Helmfile template validation in runme.sh
print_test_header "Test 1: Helmfile Template Validation Logic"

print_info "Checking if runme.sh contains template validation..."
if grep -q "helmfile.*template.*validation" runme.sh; then
    print_test_pass "Helmfile template validation code exists in runme.sh"
else
    print_test_fail "Helmfile template validation code not found in runme.sh"
fi

if grep -q "Validating Helmfile template syntax" runme.sh; then
    print_test_pass "Helmfile template validation message exists"
else
    print_test_fail "Helmfile template validation message not found"
fi

if grep -q "Helmfile template validation failed" runme.sh; then
    print_test_pass "Error handling for template validation exists"
else
    print_test_fail "Error handling for template validation not found"
fi

# Test 2: Cloudflared validation function
print_test_header "Test 2: Cloudflared Validation Function"

print_info "Checking if cloudflared validation function exists..."
if grep -q "validate_cloudflared_tunnel" runme.sh; then
    print_test_pass "validate_cloudflared_tunnel function exists"
else
    print_test_fail "validate_cloudflared_tunnel function not found"
fi

if grep -q "Checking cloudflared pod status" runme.sh; then
    print_test_pass "Cloudflared pod status check exists"
else
    print_test_fail "Cloudflared pod status check not found"
fi

if grep -q "Verifying tunnel connection in pod logs" runme.sh; then
    print_test_pass "Tunnel connection verification exists"
else
    print_test_fail "Tunnel connection verification not found"
fi

if grep -q "max_retries.*30" runme.sh; then
    print_test_pass "Retry logic with timeout exists"
else
    print_test_fail "Retry logic with timeout not found"
fi

# Test 3: Kubernetes cluster validation enhancements
print_test_header "Test 3: Kubernetes Cluster Validation"

print_info "Checking enhanced Kubernetes validation in runme.sh..."
if grep -q "Checking cluster component health" runme.sh; then
    print_test_pass "Cluster component health check exists"
else
    print_test_fail "Cluster component health check not found"
fi

if grep -q "Checking CoreDNS" runme.sh; then
    print_test_pass "CoreDNS validation exists"
else
    print_test_fail "CoreDNS validation not found"
fi

if grep -q "Testing DNS resolution" runme.sh; then
    print_test_pass "DNS resolution test exists"
else
    print_test_fail "DNS resolution test not found"
fi

if grep -q "readyz" runme.sh; then
    print_test_pass "Cluster health endpoint check exists"
else
    print_test_fail "Cluster health endpoint check not found"
fi

# Test 4: validate.sh enhancements
print_test_header "Test 4: validate.sh Script Enhancements"

print_info "Checking enhanced validation in validate.sh..."
if grep -q "Validating Helmfile templates" scripts/validate.sh; then
    print_test_pass "Helmfile template validation exists in validate.sh"
else
    print_test_fail "Helmfile template validation not found in validate.sh"
fi

if grep -q "Validating Kubernetes cluster health" scripts/validate.sh; then
    print_test_pass "Kubernetes cluster health validation exists in validate.sh"
else
    print_test_fail "Kubernetes cluster health validation not found in validate.sh"
fi

if grep -q "CoreDNS is healthy" scripts/validate.sh; then
    print_test_pass "CoreDNS health check exists in validate.sh"
else
    print_test_fail "CoreDNS health check not found in validate.sh"
fi

# Test 5: Error handling and fallbacks
print_test_header "Test 5: Error Handling and Fallbacks"

print_info "Checking error handling in runme.sh..."
if grep -q "Falling back to helmfile.yaml" runme.sh; then
    print_test_pass "Helmfile fallback logic exists"
else
    print_test_fail "Helmfile fallback logic not found"
fi

if grep -q "No valid Helmfile configuration found" runme.sh; then
    print_test_pass "Error message for missing Helmfile exists"
else
    print_test_fail "Error message for missing Helmfile not found"
fi

if grep -q "Continue despite validation failure" runme.sh; then
    print_test_pass "User prompt for validation failure exists"
else
    print_test_fail "User prompt for validation failure not found"
fi

# Test 6: Syntax validation
print_test_header "Test 6: Shell Script Syntax Validation"

print_info "Validating runme.sh syntax..."
if bash -n runme.sh; then
    print_test_pass "runme.sh has valid bash syntax"
else
    print_test_fail "runme.sh has syntax errors"
fi

print_info "Validating validate.sh syntax..."
if bash -n scripts/validate.sh; then
    print_test_pass "validate.sh has valid bash syntax"
else
    print_test_fail "validate.sh has syntax errors"
fi

# Summary
print_test_header "Test Summary"

echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✨ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    exit 1
fi
