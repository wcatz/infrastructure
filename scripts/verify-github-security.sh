#!/bin/bash
set -e

echo "=== GitHub Security Features Verification ==="
echo ""

# Repository can be set via environment variable or defaults to wcatz/infrastructure
REPO="${GITHUB_REPOSITORY:-wcatz/infrastructure}"

echo "Checking repository: $REPO"
echo ""

# Requires gh CLI with authentication
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) not installed"
    echo "   Install: https://cli.github.com/"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "❌ Not authenticated with GitHub CLI"
    echo "   Run: gh auth login"
    exit 1
fi

echo "✅ GitHub CLI authenticated"
echo ""

# Fetch security settings
SECURITY_JSON=$(gh api "repos/$REPO" --jq '.security_and_analysis')

# Secret Scanning
SECRET_SCANNING=$(echo "$SECURITY_JSON" | jq -r '.secret_scanning.status // "disabled"')
if [ "$SECRET_SCANNING" == "enabled" ]; then
    echo "✅ Secret Scanning: ENABLED"
else
    echo "❌ Secret Scanning: DISABLED"
    echo "   Enable at: https://github.com/$REPO/settings/security_analysis"
fi

# Push Protection
PUSH_PROTECTION=$(echo "$SECURITY_JSON" | jq -r '.secret_scanning_push_protection.status // "disabled"')
if [ "$PUSH_PROTECTION" == "enabled" ]; then
    echo "✅ Push Protection: ENABLED"
else
    echo "❌ Push Protection: DISABLED"
    echo "   Enable at: https://github.com/$REPO/settings/security_analysis"
fi

# Dependabot Alerts
DEPENDABOT=$(echo "$SECURITY_JSON" | jq -r '.dependabot_security_updates.status // "disabled"')
if [ "$DEPENDABOT" == "enabled" ]; then
    echo "✅ Dependabot Security Updates: ENABLED"
else
    echo "⚠️  Dependabot Security Updates: DISABLED (recommended)"
    echo "   Enable at: https://github.com/$REPO/settings/security_analysis"
fi

echo ""
echo "=== Security Alerts Summary ==="

# Check for active secret scanning alerts
SECRET_ALERTS=$(gh api "repos/$REPO/secret-scanning/alerts?state=open" --jq 'length')
if [ "$SECRET_ALERTS" -eq 0 ]; then
    echo "✅ No open secret scanning alerts"
else
    echo "⚠️  $SECRET_ALERTS open secret scanning alert(s)"
    echo "   Review at: https://github.com/$REPO/security/secret-scanning"
fi

# Check for Dependabot alerts
VULN_ALERTS=$(gh api "repos/$REPO/dependabot/alerts?state=open" --jq 'length' 2>/dev/null || echo "0")
if [ "$VULN_ALERTS" -eq 0 ]; then
    echo "✅ No open Dependabot alerts"
else
    echo "⚠️  $VULN_ALERTS open Dependabot alert(s)"
    echo "   Review at: https://github.com/$REPO/security/dependabot"
fi

# Check for Code Scanning alerts
CODE_ALERTS=$(gh api "repos/$REPO/code-scanning/alerts?state=open" --jq 'length' 2>/dev/null || echo "N/A")
if [ "$CODE_ALERTS" == "N/A" ]; then
    echo "⚠️  Code Scanning: Not configured (recommended)"
    echo "   Setup at: https://github.com/$REPO/security/code-scanning"
elif [ "$CODE_ALERTS" -eq 0 ]; then
    echo "✅ No open code scanning alerts"
else
    echo "⚠️  $CODE_ALERTS open code scanning alert(s)"
    echo "   Review at: https://github.com/$REPO/security/code-scanning"
fi

echo ""
echo "=== Verification Complete ==="
