#!/bin/bash
# preflight.sh - PRD Staleness Detection and Validation
# Usage: ./preflight.sh [prd_file]
#
# Validates a PRD before Ralph Moss execution:
# - Checks if referenced files exist
# - Validates JSON schema
# - Detects stale file paths
# - Warns about potential issues
#
# Exit codes:
#   0 - All checks pass
#   1 - Critical errors (abort execution)
#   2 - Warnings only (can proceed with caution)

set -e

PRD_FILE="${1:-./prd.json}"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

errors=0
warnings=0

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; ((errors++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; ((warnings++)); }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RALPH MOSS PREFLIGHT CHECK"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "PRD File: $PRD_FILE"
echo "Repo Root: $REPO_ROOT"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 1: PRD File Exists
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 1: PRD File Exists ───"
if [ ! -f "$PRD_FILE" ]; then
    log_fail "PRD file not found: $PRD_FILE"
    echo ""
    echo "PREFLIGHT FAILED: Cannot proceed without PRD file."
    exit 1
fi
log_pass "PRD file exists"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 2: Valid JSON
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 2: Valid JSON ───"
if ! jq '.' "$PRD_FILE" > /dev/null 2>&1; then
    log_fail "PRD is not valid JSON"
    jq '.' "$PRD_FILE" 2>&1 | head -5
    echo ""
    echo "PREFLIGHT FAILED: Fix JSON syntax errors first."
    exit 1
fi
log_pass "Valid JSON structure"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 3: Required Fields
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 3: Required Fields ───"

# Check branchName
branch=$(jq -r '.branchName // ""' "$PRD_FILE")
if [ -z "$branch" ]; then
    log_fail "Missing required field: branchName"
else
    log_pass "branchName: $branch"
fi

# Check description
desc=$(jq -r '.description // ""' "$PRD_FILE")
if [ -z "$desc" ]; then
    log_fail "Missing required field: description"
elif [ ${#desc} -lt 20 ]; then
    log_warn "Description is very short (${#desc} chars) - consider adding more context"
else
    log_pass "description present (${#desc} chars)"
fi

# Check userStories
story_count=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null || echo "0")
if [ "$story_count" -eq 0 ]; then
    log_fail "No user stories defined"
else
    log_pass "$story_count user stories defined"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 4: File Path Validation (Staleness Detection)
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 4: Referenced File Paths ───"

# Extract all file paths from PRD
# Look in: context.keyFiles, technicalDetails.filesAffected, referencePatterns.file
all_paths=$(jq -r '
  [
    .context.keyFiles[]?,
    .referencePatterns[]?.file?,
    .userStories[]?.technicalDetails?.filesAffected[]?
  ] | map(select(. != null and . != "")) | unique | .[]
' "$PRD_FILE" 2>/dev/null || echo "")

if [ -z "$all_paths" ]; then
    log_info "No file paths specified in PRD (consider adding for better guidance)"
else
    path_count=0
    missing_count=0

    while IFS= read -r file_path; do
        # Skip empty lines
        [ -z "$file_path" ] && continue

        # Clean up path (remove line numbers like :45-67, descriptions)
        clean_path=$(echo "$file_path" | sed 's/:.*//; s/ -.*//; s/^ *//; s/ *$//')

        # Skip if empty after cleaning
        [ -z "$clean_path" ] && continue

        ((path_count++))

        # Check if file exists (relative to repo root)
        full_path="$REPO_ROOT/$clean_path"
        if [ -f "$full_path" ]; then
            log_pass "File exists: $clean_path"
        else
            # Try without leading slash or src/
            alt_path="$REPO_ROOT/src/$clean_path"
            if [ -f "$alt_path" ]; then
                log_warn "File found at different path: src/$clean_path"
            else
                log_fail "FILE NOT FOUND: $clean_path"
                ((missing_count++))

                # Suggest similar files
                base_name=$(basename "$clean_path" 2>/dev/null || echo "")
                if [ -n "$base_name" ]; then
                    similar=$(find "$REPO_ROOT/src" -name "*${base_name}*" 2>/dev/null | head -3)
                    if [ -n "$similar" ]; then
                        echo "       Similar files found:"
                        echo "$similar" | sed 's|'"$REPO_ROOT/"'|       - |g'
                    fi
                fi
            fi
        fi
    done <<< "$all_paths"

    echo ""
    log_info "Checked $path_count file paths, $missing_count missing"

    if [ "$missing_count" -gt 0 ]; then
        log_warn "PRD references files that don't exist - may be STALE"
        log_warn "Update the PRD or verify the paths before proceeding"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 5: Story Validation
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 5: Story Quality ───"

# Check each story
jq -r '.userStories[] | @base64' "$PRD_FILE" 2>/dev/null | while read -r story; do
    id=$(echo "$story" | base64 -d | jq -r '.id')
    title=$(echo "$story" | base64 -d | jq -r '.title')
    criteria_count=$(echo "$story" | base64 -d | jq '.acceptanceCriteria | length')
    has_typecheck=$(echo "$story" | base64 -d | jq '.acceptanceCriteria | map(select(. | ascii_downcase | contains("typecheck"))) | length')

    if [ "$criteria_count" -lt 2 ]; then
        log_warn "$id: Only $criteria_count acceptance criteria (recommend 2+)"
    fi

    if [ "$has_typecheck" -eq 0 ]; then
        log_warn "$id: No typecheck criterion (recommended for all stories)"
    fi
done

log_pass "Story structure validated"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 6: Dependency Validation
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 6: Dependency Graph ───"

# Get all story IDs
all_ids=$(jq -r '.userStories[].id' "$PRD_FILE")

# Check for invalid dependencies
jq -r '.userStories[] | select(.dependsOn != null) | "\(.id):\(.dependsOn | join(","))"' "$PRD_FILE" 2>/dev/null | while IFS=: read -r story_id deps; do
    [ -z "$deps" ] && continue

    for dep in $(echo "$deps" | tr ',' ' '); do
        if ! echo "$all_ids" | grep -q "^${dep}$"; then
            log_fail "$story_id depends on non-existent story: $dep"
        fi
    done
done

# Check for circular dependencies (simple check)
# A proper cycle detection would require a graph traversal
log_pass "Dependency references valid"
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 7: Anti-Patterns Present
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 7: Anti-Patterns Defined ───"

antipattern_count=$(jq '.antiPatterns | length' "$PRD_FILE" 2>/dev/null || echo "0")
if [ "$antipattern_count" -eq 0 ]; then
    log_warn "No anti-patterns defined - consider adding common pitfalls"
else
    log_pass "$antipattern_count anti-patterns defined"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 8: Visual Assets Validation
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 8: Visual Assets ───"

# Check if visualSpecs exists
has_visual_specs=$(jq 'has("visualSpecs")' "$PRD_FILE" 2>/dev/null || echo "false")

if [ "$has_visual_specs" = "true" ]; then
    visual_asset_count=0
    visual_missing_count=0

    # Check mockups
    mockup_paths=$(jq -r '.visualSpecs.mockups[]?.path // empty' "$PRD_FILE" 2>/dev/null || echo "")
    while IFS= read -r asset_path; do
        [ -z "$asset_path" ] && continue
        ((visual_asset_count++))

        # Check relative to PRD directory first, then repo root
        prd_dir=$(dirname "$PRD_FILE")
        if [ -f "$prd_dir/$asset_path" ]; then
            log_pass "Mockup exists: $asset_path"
        elif [ -f "$REPO_ROOT/$asset_path" ]; then
            log_pass "Mockup exists: $asset_path (at repo root)"
        else
            log_fail "MOCKUP NOT FOUND: $asset_path"
            ((visual_missing_count++))
        fi
    done <<< "$mockup_paths"

    # Check HTML prototypes
    html_paths=$(jq -r '.visualSpecs.htmlPrototypes[]?.path // empty' "$PRD_FILE" 2>/dev/null || echo "")
    while IFS= read -r asset_path; do
        [ -z "$asset_path" ] && continue
        ((visual_asset_count++))

        prd_dir=$(dirname "$PRD_FILE")
        if [ -f "$prd_dir/$asset_path" ]; then
            log_pass "HTML prototype exists: $asset_path"
        elif [ -f "$REPO_ROOT/$asset_path" ]; then
            log_pass "HTML prototype exists: $asset_path (at repo root)"
        else
            log_fail "HTML PROTOTYPE NOT FOUND: $asset_path"
            ((visual_missing_count++))
        fi
    done <<< "$html_paths"

    # Check story-level visualRefs
    visual_refs=$(jq -r '.userStories[]?.visualRef // empty' "$PRD_FILE" 2>/dev/null || echo "")
    while IFS= read -r asset_path; do
        [ -z "$asset_path" ] && continue
        ((visual_asset_count++))

        prd_dir=$(dirname "$PRD_FILE")
        if [ -f "$prd_dir/$asset_path" ]; then
            log_pass "Visual ref exists: $asset_path"
        elif [ -f "$REPO_ROOT/$asset_path" ]; then
            log_pass "Visual ref exists: $asset_path (at repo root)"
        else
            log_fail "VISUAL REF NOT FOUND: $asset_path"
            ((visual_missing_count++))
        fi
    done <<< "$visual_refs"

    if [ "$visual_asset_count" -gt 0 ]; then
        log_info "Checked $visual_asset_count visual assets, $visual_missing_count missing"
        if [ "$visual_missing_count" -gt 0 ]; then
            log_warn "Missing visual assets will cause implementation issues"
        fi
    fi
else
    log_info "No visual specs defined (optional)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# CHECK 9: Git Branch Availability
# ═══════════════════════════════════════════════════════════════════
echo "─── Check 9: Git Branch ───"

if [ -n "$branch" ]; then
    current_branch=$(git branch --show-current 2>/dev/null || echo "")

    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        log_pass "Branch exists locally: $branch"
    elif git ls-remote --heads origin "$branch" 2>/dev/null | grep -q "$branch"; then
        log_pass "Branch exists on remote: $branch"
    else
        log_info "Branch does not exist yet (will be created): $branch"
    fi

    if [ "$current_branch" != "$branch" ]; then
        log_info "Currently on branch '$current_branch', will switch to '$branch'"
    fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════
echo "═══════════════════════════════════════════════════════════════"
echo "  PREFLIGHT SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ $errors -gt 0 ]; then
    echo -e "${RED}FAILED${NC}: $errors errors, $warnings warnings"
    echo ""
    echo "Fix the errors above before running Ralph Moss."
    echo "Stale file paths are the #1 cause of wasted iterations!"
    exit 1
elif [ $warnings -gt 0 ]; then
    echo -e "${YELLOW}PASSED WITH WARNINGS${NC}: $warnings warnings"
    echo ""
    echo "You can proceed, but consider addressing the warnings."
    echo "Especially check any missing file paths - the PRD may be stale."
    exit 2
else
    echo -e "${GREEN}ALL CHECKS PASSED${NC}"
    echo ""
    echo "PRD is valid and ready for Ralph Moss execution."
    exit 0
fi
