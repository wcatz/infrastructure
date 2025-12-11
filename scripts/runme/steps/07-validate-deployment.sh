#!/bin/bash
# 07-validate-deployment.sh - Validate the complete deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../../.."

# Source the helper library
source "$SCRIPT_DIR/../lib.sh"

print_section "Step 7: Validating Deployment"

print_info "Running deployment validation..."

# Check nodes
print_info "Checking cluster nodes..."
if kubectl get nodes &> /dev/null; then
    kubectl get nodes
    
    # Verify all nodes are Ready - count nodes with Ready status
    TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {count++} END {print count+0}')
    
    if [ "$READY_NODES" -eq "$TOTAL_NODES" ] && [ "$TOTAL_NODES" -gt 0 ]; then
        print_success "All nodes are Ready ($READY_NODES/$TOTAL_NODES)"
    else
        print_warning "Not all nodes are Ready ($READY_NODES/$TOTAL_NODES)"
        kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print}' || true
    fi
else
    print_error "Cannot query nodes - cluster may not be accessible"
    print_info "Ensure kubeconfig is properly configured and cluster is running"
    exit 1
fi

# Check cluster component health
print_info "Checking cluster component health..."
if kubectl get --raw='/readyz?verbose' &> /dev/null; then
    print_success "Cluster API server is healthy"
else
    print_warning "Cluster health check failed"
fi

# Verify CoreDNS is running
print_info "Checking CoreDNS..."
if kubectl get deployment -n kube-system coredns &> /dev/null; then
    COREDNS_READY=$(kubectl get deployment -n kube-system coredns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    COREDNS_DESIRED=$(kubectl get deployment -n kube-system coredns -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "$COREDNS_READY" = "$COREDNS_DESIRED" ] && [ "$COREDNS_READY" != "0" ]; then
        print_success "CoreDNS is running ($COREDNS_READY/$COREDNS_DESIRED replicas ready)"
    else
        print_warning "CoreDNS may not be fully ready ($COREDNS_READY/$COREDNS_DESIRED replicas)"
    fi
else
    print_warning "CoreDNS deployment not found"
fi

# Check system pods
print_info "Checking system pods..."
if kubectl get pods -n kube-system &> /dev/null; then
    PENDING_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
    if [ "$PENDING_PODS" -eq 0 ]; then
        print_success "All system pods are running"
    else
        print_warning "$PENDING_PODS system pods not running"
        kubectl get pods -n kube-system | grep -v Running || true
    fi
else
    print_warning "Cannot query system pods"
fi

# Test DNS functionality
print_info "Testing DNS resolution..."
DNS_TEST_POD="dns-test-$(date +%s)"
DNS_TEST_LOG="/tmp/dns-test.log"
if kubectl run "$DNS_TEST_POD" --image=busybox:1.28 --rm -i --restart=Never --command -- nslookup kubernetes.default &> "$DNS_TEST_LOG" 2>&1; then
    print_success "DNS resolution is working"
else
    # Check if it's just because the pod already exists or other temporary issue
    if grep -q "kubernetes.default.svc.cluster.local" "$DNS_TEST_LOG"; then
        print_success "DNS resolution is working"
    else
        print_warning "DNS resolution test failed"
        print_info "DNS test output:"
        head -n 10 "$DNS_TEST_LOG"
    fi
fi
rm -f "$DNS_TEST_LOG"

# Check monitoring pods (if enabled)
if kubectl get namespace monitoring &> /dev/null; then
    print_info "Checking monitoring stack..."
    if kubectl get pods -n monitoring &> /dev/null; then
        PENDING_PODS=$(kubectl get pods -n monitoring --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
        if [ "$PENDING_PODS" -eq 0 ]; then
            print_success "Monitoring stack is running"
        else
            print_warning "$PENDING_PODS monitoring pods not running"
        fi
    fi
fi

# Run validation script if available
if [ -f "$REPO_ROOT/scripts/validate.sh" ]; then
    print_info "Running validation script..."
    if "$REPO_ROOT/scripts/validate.sh"; then
        print_success "Validation completed successfully"
    else
        print_warning "Validation completed with warnings"
    fi
fi

print_success "Deployment validation completed"
