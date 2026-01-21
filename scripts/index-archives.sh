#!/bin/bash
# index-archives.sh - Build a semantic index of all archived PRDs
# Usage: ./index-archives.sh [archive_dir]
#
# Creates archive-index.json with:
# - Extracted keywords and concepts from each PRD
# - Key learnings and patterns
# - Related terms for semantic matching
# - File paths mentioned
#
# Run this after archiving PRDs to update the search index.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="${1:-$SCRIPT_DIR/archive}"
INDEX_FILE="$SCRIPT_DIR/archive-index.json"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INDEX]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }

if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "No archive directory found at: $ARCHIVE_DIR"
    echo "Nothing to index."
    exit 0
fi

log_info "Building semantic index from archives..."
log_info "Archive directory: $ARCHIVE_DIR"

# Start JSON array
echo '[' > "$INDEX_FILE.tmp"

first_entry=true

for archive_folder in "$ARCHIVE_DIR"/*/; do
    if [ ! -d "$archive_folder" ]; then
        continue
    fi

    folder_name=$(basename "$archive_folder")
    prd_file="$archive_folder/prd.json"
    progress_file="$archive_folder/progress.txt"

    log_info "Indexing: $folder_name"

    # Extract data from PRD
    description=""
    stories=""
    antipatterns=""
    key_files=""
    branch_name=""

    if [ -f "$prd_file" ]; then
        description=$(jq -r '.description // ""' "$prd_file" 2>/dev/null || echo "")
        branch_name=$(jq -r '.branchName // ""' "$prd_file" 2>/dev/null || echo "")
        stories=$(jq -r '[.userStories[]? | .title] | join("; ")' "$prd_file" 2>/dev/null || echo "")
        antipatterns=$(jq -r '[.antiPatterns[]?] | join("; ")' "$prd_file" 2>/dev/null || echo "")
        key_files=$(jq -r '[.context.keyFiles[]?] | join("; ")' "$prd_file" 2>/dev/null || echo "")
    fi

    # Extract learnings from progress.txt
    learnings=""
    patterns=""
    critical_notes=""

    if [ -f "$progress_file" ]; then
        # Extract Codebase Patterns section
        patterns=$(awk '/^## Codebase Patterns/,/^---/' "$progress_file" 2>/dev/null | grep -v '^---' | grep -v '^##' | tr '\n' ' ' || echo "")

        # Extract learnings
        learnings=$(grep -A 10 "Learnings for future" "$progress_file" 2>/dev/null | grep "^-" | tr '\n' ' ' || echo "")

        # Extract critical notes
        critical_notes=$(grep -i "critical\|important\|warning\|gotcha\|don't\|never\|always" "$progress_file" 2>/dev/null | head -10 | tr '\n' ' ' || echo "")
    fi

    # Build keyword list (simple tokenization)
    all_text="$description $stories $antipatterns $learnings $patterns"
    # Extract meaningful words (3+ chars, remove common words)
    keywords=$(echo "$all_text" | tr '[:upper:]' '[:lower:]' | \
        grep -oE '\b[a-z]{3,}\b' | \
        grep -vE '^(the|and|for|that|this|with|from|have|been|will|are|was|were|not|but|can|all|has|had|its|you|use|when|how|what|which|would|could|should|into|more|some|them|then|than|these|those|being|been|each|also|other|such|only|just|any|both|before|after|through|during|about|between|under|again|once|here|there|where|why|most|very|much|many|even|still|while|because|since)$' | \
        sort | uniq -c | sort -rn | head -30 | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')

    # Generate related terms (simple synonym/concept expansion)
    related_terms=""
    if echo "$all_text" | grep -qi "filter"; then
        related_terms="$related_terms,dropdown,select,search,query"
    fi
    if echo "$all_text" | grep -qi "modal"; then
        related_terms="$related_terms,dialog,popup,overlay,slideout"
    fi
    if echo "$all_text" | grep -qi "contact"; then
        related_terms="$related_terms,broker,tenant,landlord,person,user"
    fi
    if echo "$all_text" | grep -qi "property"; then
        related_terms="$related_terms,unit,building,space,listing"
    fi
    if echo "$all_text" | grep -qi "api"; then
        related_terms="$related_terms,endpoint,fetch,request,response,backend"
    fi
    if echo "$all_text" | grep -qi "component"; then
        related_terms="$related_terms,react,ui,widget,element"
    fi
    if echo "$all_text" | grep -qi "bug\|fix"; then
        related_terms="$related_terms,error,issue,problem,broken"
    fi
    if echo "$all_text" | grep -qi "test"; then
        related_terms="$related_terms,spec,verify,check,validation"
    fi

    # Escape strings for JSON
    escape_json() {
        echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr '\n' ' ' | sed 's/  */ /g'
    }

    desc_escaped=$(escape_json "$description")
    stories_escaped=$(escape_json "$stories")
    patterns_escaped=$(escape_json "$patterns")
    learnings_escaped=$(escape_json "$learnings")
    critical_escaped=$(escape_json "$critical_notes")
    antipatterns_escaped=$(escape_json "$antipatterns")

    # Add comma for all but first entry
    if [ "$first_entry" = "true" ]; then
        first_entry=false
    else
        echo ',' >> "$INDEX_FILE.tmp"
    fi

    # Write index entry
    cat >> "$INDEX_FILE.tmp" << EOF
  {
    "folder": "$folder_name",
    "path": "$archive_folder",
    "branch": "$branch_name",
    "description": "$desc_escaped",
    "stories": "$stories_escaped",
    "keywords": "$keywords",
    "relatedTerms": "$related_terms",
    "patterns": "$patterns_escaped",
    "learnings": "$learnings_escaped",
    "criticalNotes": "$critical_escaped",
    "antiPatterns": "$antipatterns_escaped",
    "keyFiles": "$key_files",
    "indexedAt": "$(date -Iseconds)"
  }
EOF

done

echo ']' >> "$INDEX_FILE.tmp"

# Validate and finalize
if jq '.' "$INDEX_FILE.tmp" > /dev/null 2>&1; then
    mv "$INDEX_FILE.tmp" "$INDEX_FILE"
    count=$(jq 'length' "$INDEX_FILE")
    log_success "Index created: $INDEX_FILE"
    log_success "Indexed $count archives"
else
    log_info "Warning: Generated index has JSON errors. Attempting to fix..."
    # Try to create a minimal valid index
    echo '[]' > "$INDEX_FILE"
    log_info "Created empty index. Check archive contents."
fi

echo ""
echo "Index ready for semantic-search.sh"
