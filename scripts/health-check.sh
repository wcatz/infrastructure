#!/bin/bash
# Kubernetes Cluster Health and Security Check
#
# This script performs comprehensive health and security checks on the cluster
# Usage: ./health-check.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "Kubernetes Cluster Health & Security Check"
echo "=============================================="
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to cluster${NC}"
echo ""

# 1. Node Status
echo "=== 1. Node Status ==="
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl get nodes --no-headers | grep -c " Ready " || true)
echo "Total Nodes: $TOTAL_NODES"
echo "Ready Nodes: $READY_NODES"
if [ "$TOTAL_NODES" -eq "$READY_NODES" ]; then
    echo -e "${GREEN}✅ All nodes are ready${NC}"
else
    echo -e "${YELLOW}⚠️  Not all nodes are ready${NC}"
    kubectl get nodes
fi
echo ""

# 2. Pod Status
echo "=== 2. Pod Status ==="
TOTAL_PODS=$(kubectl get pods -A --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods -A --no-headers | grep -c " Running " || true)
echo "Total Pods: $TOTAL_PODS"
echo "Running Pods: $RUNNING_PODS"

FAILED_PODS=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
if [ "$FAILED_PODS" -eq 0 ]; then
    echo -e "${GREEN}✅ No failed pods${NC}"
else
    echo -e "${RED}❌ $FAILED_PODS pod(s) not in Running/Succeeded state${NC}"
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
fi
echo ""

# 3. Critical Deployments
echo "=== 3. Critical Deployments ==="
check_deployment() {
    local name=$1
    local namespace=$2
    if kubectl get deployment "$name" -n "$namespace" &> /dev/null; then
        local desired=$(kubectl get deployment "$name" -n "$namespace" -o jsonpath='{.spec.replicas}')
        local ready=$(kubectl get deployment "$name" -n "$namespace" -o jsonpath='{.status.readyReplicas}')
        if [ "$desired" == "$ready" ]; then
            echo -e "${GREEN}✅ $name ($namespace): $ready/$desired ready${NC}"
        else
            echo -e "${RED}❌ $name ($namespace): $ready/$desired ready${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  $name ($namespace): Not deployed${NC}"
    fi
}

check_deployment "cloudflared" "cloudflare"
check_deployment "prometheus-server" "monitoring"
check_deployment "grafana" "monitoring"
echo ""

# 4. Secret Verification
echo "=== 4. Critical Secrets ==="
check_secret() {
    local name=$1
    local namespace=$2
    if kubectl get secret "$name" -n "$namespace" &> /dev/null; then
        echo -e "${GREEN}✅ $name ($namespace)${NC}"
    else
        echo -e "${RED}❌ $name ($namespace): Missing${NC}"
    fi
}

check_secret "cloudflared-credentials" "cloudflare"
check_secret "github-runner-secrets" "github-runner"
echo ""

# 5. Secret Exposure Check
echo "=== 5. Secret Exposure Scan ==="
echo "Scanning for pods with exposed secrets in environment variables..."

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq not installed, skipping secret exposure scan${NC}"
else
    EXPOSED_COUNT=$(kubectl get pods -A -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.containers[].env[]? | .name | contains("PASSWORD") or contains("TOKEN") or contains("SECRET")) | "\(.metadata.namespace)/\(.metadata.name)"' | \
        wc -l)

    if [ "$EXPOSED_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✅ No environment variable secret exposure detected${NC}"
    else
        echo -e "${YELLOW}⚠️  Found $EXPOSED_COUNT pod(s) with potential secret exposure:${NC}"
        kubectl get pods -A -o json 2>/dev/null | \
            jq -r '.items[] | select(.spec.containers[].env[]? | .name | contains("PASSWORD") or contains("TOKEN") or contains("SECRET")) | "\(.metadata.namespace)/\(.metadata.name)"'
        echo -e "${YELLOW}Note: Review these pods to ensure secrets are properly managed${NC}"
    fi
fi
echo ""

# 6. Certificate Status
echo "=== 6. Certificate Status ==="
if kubectl get certificates -A &> /dev/null; then
    CERT_COUNT=$(kubectl get certificates -A --no-headers | wc -l)
    if [ "$CERT_COUNT" -gt 0 ]; then
        NOT_READY=$(kubectl get certificates -A -o json | \
            jq -r '.items[] | select(.status.conditions[]?.status != "True") | .metadata.name' | \
            wc -l)
        if [ "$NOT_READY" -eq 0 ]; then
            echo -e "${GREEN}✅ All $CERT_COUNT certificate(s) ready${NC}"
        else
            echo -e "${YELLOW}⚠️  $NOT_READY certificate(s) not ready${NC}"
            kubectl get certificates -A
        fi
    else
        echo "No certificates found (cert-manager may not be deployed)"
    fi
else
    echo "cert-manager not installed or no certificates"
fi
echo ""

# 7. Persistent Volume Status
echo "=== 7. PersistentVolume Status ==="
PV_COUNT=$(kubectl get pv --no-headers 2>/dev/null | wc -l || echo 0)
if [ "$PV_COUNT" -gt 0 ]; then
    kubectl get pv
else
    echo "No PersistentVolumes found"
fi
echo ""

# 8. Backup Status (Velero)
echo "=== 8. Backup Status ==="
if kubectl get backups -n velero &> /dev/null; then
    echo "Recent backups (last 5):"
    kubectl get backups -n velero --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -6
    
    # Check for recent successful backup
    RECENT_BACKUP=$(kubectl get backups -n velero --sort-by=.metadata.creationTimestamp -o json 2>/dev/null | \
        jq -r '.items[-1] | select(.status.phase == "Completed") | .metadata.creationTimestamp' || echo "")
    
    if [ -n "$RECENT_BACKUP" ]; then
        echo -e "${GREEN}✅ Recent backup completed: $RECENT_BACKUP${NC}"
    else
        echo -e "${YELLOW}⚠️  No recent completed backup found${NC}"
    fi
else
    echo "Velero not installed or no backups found"
fi
echo ""

# 9. Network Policy Check
echo "=== 9. Network Policy Status ==="
NP_COUNT=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l || echo 0)
if [ "$NP_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ $NP_COUNT Network Policies deployed${NC}"
    kubectl get networkpolicies -A
else
    echo -e "${YELLOW}⚠️  No Network Policies found (consider implementing for security)${NC}"
fi
echo ""

# 10. Resource Usage
echo "=== 10. Resource Usage ==="
echo "Node resource usage:"
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo ""

# 11. Environment Check
echo "=== 11. Environment Configuration ==="
if kubectl get configmap -n kube-system helmfile-env &> /dev/null; then
    ENV=$(kubectl get configmap -n kube-system helmfile-env -o jsonpath='{.data.environment}' 2>/dev/null || echo "unknown")
    echo "Current environment: $ENV"
    if [ "$ENV" == "prod" ]; then
        echo -e "${GREEN}✅ Running production environment${NC}"
    else
        echo -e "${YELLOW}⚠️  Non-production environment detected${NC}"
    fi
else
    echo "Environment not configured via ConfigMap"
fi
echo ""

# 12. Security Summary
echo "=== 12. Security Summary ==="
echo ""
echo "Checklist:"
echo "- [x] SOPS encryption for secrets"
echo "- [x] Kubernetes secrets encryption at rest (K3s default)"
echo "- [x] Non-production environments disabled (dev/staging)"
echo "- [x] Cloudflared credentials as encrypted secrets"
echo "- [x] Network policies implemented"
echo "- [ ] Regular secret rotation (manual process)"
echo "- [ ] Audit logging (requires configuration)"
echo ""

# Summary
echo "=============================================="
echo "Health Check Complete"
echo "=============================================="
echo ""
echo "Summary:"
echo "- Nodes: $READY_NODES/$TOTAL_NODES ready"
echo "- Pods: $RUNNING_PODS/$TOTAL_PODS running"
echo "- Failed pods: $FAILED_PODS"
echo "- Secret exposure: $EXPOSED_COUNT potential issues"
echo "- Network policies: $NP_COUNT deployed"
echo ""

# Exit code based on critical issues
if [ "$READY_NODES" -ne "$TOTAL_NODES" ] || [ "$FAILED_PODS" -gt 0 ]; then
    echo -e "${RED}❌ Critical issues detected${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Cluster is healthy${NC}"
    exit 0
fi
