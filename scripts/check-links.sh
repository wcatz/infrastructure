#!/bin/bash
# check-links.sh - Validate markdown links in documentation
# This script checks for broken internal links in markdown files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BROKEN_LINKS=0
TOTAL_LINKS=0

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo "======================================"
echo "Markdown Link Validation"
echo "======================================"
echo ""

# Find all markdown files
MD_FILES=$(find . -name "*.md" -type f ! -path "./node_modules/*" ! -path "./.git/*")

for file in $MD_FILES; do
    echo "Checking $file..."
    
    # Extract markdown links [text](path)
    # Exclude external URLs (http/https)
    LINKS=$(grep -oE '\[([^\]]+)\]\(([^)]+)\)' "$file" | grep -v "http" || true)
    
    if [ -z "$LINKS" ]; then
        continue
    fi
    
    while IFS= read -r link; do
        TOTAL_LINKS=$((TOTAL_LINKS + 1))
        
        # Extract the path from [text](path)
        PATH_PART=$(echo "$link" | sed -E 's/.*\(([^)]+)\).*/\1/')
        
        # Remove anchor links (#section)
        FILE_PATH=$(echo "$PATH_PART" | sed 's/#.*//')
        
        # Skip empty paths (anchor-only links)
        if [ -z "$FILE_PATH" ]; then
            continue
        fi
        
        # Resolve relative path
        DIR=$(dirname "$file")
        FULL_PATH="$DIR/$FILE_PATH"
        
        # Normalize path
        FULL_PATH=$(realpath -m "$FULL_PATH" 2>/dev/null || echo "$FULL_PATH")
        
        # Check if file exists
        if [ ! -e "$FULL_PATH" ]; then
            print_error "Broken link in $file: $PATH_PART"
            print_error "  Expected file: $FULL_PATH"
            BROKEN_LINKS=$((BROKEN_LINKS + 1))
        fi
    done <<< "$LINKS"
done

echo ""
echo "======================================"
echo "Summary"
echo "======================================"
echo "Total links checked: $TOTAL_LINKS"

if [ $BROKEN_LINKS -eq 0 ]; then
    print_success "All links are valid!"
    exit 0
else
    print_error "Found $BROKEN_LINKS broken link(s)"
    exit 1
fi
