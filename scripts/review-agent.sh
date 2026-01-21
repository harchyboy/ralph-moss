#!/bin/bash
# review-agent.sh - Agent-to-Agent Code Review for Ralph Moss
# Usage: ./review-agent.sh [story_id] [--block-on-high]
#
# Spawns a separate Claude instance to review the implementation.
# This provides a "second pair of eyes" that catches issues automated
# checks miss.
#
# Exit codes:
#   0 - Review passed (APPROVE or COMMENT with no critical issues)
#   1 - Review requested changes (CRITICAL or HIGH severity issues)
#   2 - Review failed to run

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$(pwd)}"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Arguments
STORY_ID="${1:-}"
BLOCK_ON_HIGH=false
VERBOSE=false

for arg in "$@"; do
    case $arg in
        --block-on-high)
            BLOCK_ON_HIGH=true
            ;;
        --verbose|-v)
            VERBOSE=true
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[REVIEW]${NC} $1"; }
log_pass() { echo -e "${GREEN}[REVIEW]${NC} $1"; }
log_fail() { echo -e "${RED}[REVIEW]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[REVIEW]${NC} $1"; }

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${MAGENTA}RALPH MOSS AGENT-TO-AGENT REVIEW${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check for required files
PRD_FILE="$WORK_DIR/prd.json"
REVIEW_PROMPT="$SCRIPT_DIR/review-prompt.md"
REVIEW_OUTPUT="$WORK_DIR/last-review.md"

if [ ! -f "$PRD_FILE" ]; then
    log_fail "PRD file not found: $PRD_FILE"
    exit 2
fi

if [ ! -f "$REVIEW_PROMPT" ]; then
    log_fail "Review prompt not found: $REVIEW_PROMPT"
    exit 2
fi

# Get the story being reviewed
if [ -z "$STORY_ID" ]; then
    # Get the most recently completed story
    STORY_ID=$(jq -r '.userStories[] | select(.passes==true) | .id' "$PRD_FILE" | tail -1)
fi

if [ -z "$STORY_ID" ]; then
    log_warn "No completed story found to review"
    exit 0
fi

STORY_TITLE=$(jq -r ".userStories[] | select(.id==\"$STORY_ID\") | .title" "$PRD_FILE")
log_info "Reviewing story: $STORY_ID - $STORY_TITLE"

# Get the git diff for this story
# We look at the most recent commit or uncommitted changes
log_info "Gathering changes for review..."

BRANCH_NAME=$(jq -r '.branchName // "HEAD"' "$PRD_FILE")
BASE_BRANCH=$(git merge-base main "$BRANCH_NAME" 2>/dev/null || echo "main")

# Get the diff - either uncommitted changes or last commit
if [ -n "$(git status --porcelain)" ]; then
    log_info "Reviewing uncommitted changes"
    GIT_DIFF=$(git diff HEAD)
else
    log_info "Reviewing last commit"
    GIT_DIFF=$(git diff HEAD~1..HEAD 2>/dev/null || git diff $BASE_BRANCH..HEAD)
fi

if [ -z "$GIT_DIFF" ]; then
    log_warn "No changes to review"
    exit 0
fi

# Show diff stats
DIFF_STATS=$(echo "$GIT_DIFF" | diffstat 2>/dev/null || echo "$GIT_DIFF" | wc -l | xargs -I {} echo "{} lines changed")
log_info "Changes: $DIFF_STATS"

# Build the review context
log_info "Spawning review agent..."

REVIEW_CONTEXT="# Code Review Request

## Story Being Reviewed
**ID:** $STORY_ID
**Title:** $STORY_TITLE

## PRD Context
\`\`\`json
$(cat "$PRD_FILE")
\`\`\`

## Acceptance Criteria for This Story
\`\`\`json
$(jq ".userStories[] | select(.id==\"$STORY_ID\") | .acceptanceCriteria" "$PRD_FILE")
\`\`\`

## Git Diff to Review
\`\`\`diff
$GIT_DIFF
\`\`\`

## Quality Gate Results
All automated checks (typecheck, lint, tests) have PASSED.
Your job is to find issues that automated tools cannot catch.

---

$(cat "$REVIEW_PROMPT")
"

# Run the review agent
REVIEW_START=$(date +%s)
REVIEW_RESULT=$(echo "$REVIEW_CONTEXT" | claude --dangerously-skip-permissions -p - 2>&1) || true
REVIEW_END=$(date +%s)
REVIEW_DURATION=$((REVIEW_END - REVIEW_START))

# Save the full review output
echo "$REVIEW_RESULT" > "$REVIEW_OUTPUT"
log_info "Full review saved to: $REVIEW_OUTPUT"

# Parse the verdict
VERDICT=$(echo "$REVIEW_RESULT" | grep -oP '(?<=<verdict>)[^<]+' | head -1 || echo "UNKNOWN")
CONFIDENCE=$(echo "$REVIEW_RESULT" | grep -oP '(?<=<confidence>)[^<]+' | head -1 || echo "UNKNOWN")

# Count issues by severity
CRITICAL_COUNT=$(echo "$REVIEW_RESULT" | grep -c 'severity="CRITICAL"' || echo "0")
HIGH_COUNT=$(echo "$REVIEW_RESULT" | grep -c 'severity="HIGH"' || echo "0")
MEDIUM_COUNT=$(echo "$REVIEW_RESULT" | grep -c 'severity="MEDIUM"' || echo "0")
LOW_COUNT=$(echo "$REVIEW_RESULT" | grep -c 'severity="LOW"' || echo "0")

echo ""
echo "───────────────────────────────────────────────────────────────"
echo "  REVIEW RESULTS (${REVIEW_DURATION}s)"
echo "───────────────────────────────────────────────────────────────"
echo ""
echo "  Verdict:    $VERDICT"
echo "  Confidence: $CONFIDENCE"
echo ""
echo "  Issues Found:"
echo "    Critical: $CRITICAL_COUNT"
echo "    High:     $HIGH_COUNT"
echo "    Medium:   $MEDIUM_COUNT"
echo "    Low:      $LOW_COUNT"
echo ""

# Extract and display summary
SUMMARY=$(echo "$REVIEW_RESULT" | grep -oP '(?<=<summary>)[\s\S]*?(?=</summary>)' | head -1 || echo "No summary provided")
echo "  Summary:"
echo "$SUMMARY" | sed 's/^/    /'
echo ""

# Extract and display issues
if [ "$CRITICAL_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 0 ] || [ "$MEDIUM_COUNT" -gt 0 ]; then
    echo "  Issues to Address:"
    echo "$REVIEW_RESULT" | grep -oP '<issue[^>]*>[\s\S]*?</issue>' | while read -r issue; do
        severity=$(echo "$issue" | grep -oP 'severity="[^"]*"' | cut -d'"' -f2)
        title=$(echo "$issue" | grep -oP '(?<=<title>)[^<]+')
        file=$(echo "$issue" | grep -oP '(?<=<file>)[^<]+')
        echo "    [$severity] $title"
        [ -n "$file" ] && echo "      File: $file"
    done
    echo ""
fi

# Determine exit code
echo "───────────────────────────────────────────────────────────────"

if [ "$CRITICAL_COUNT" -gt 0 ]; then
    log_fail "Review BLOCKED - $CRITICAL_COUNT CRITICAL issue(s) found"
    echo ""
    echo "  The review agent found critical issues that must be fixed."
    echo "  See $REVIEW_OUTPUT for full details."
    echo ""
    exit 1
elif [ "$HIGH_COUNT" -gt 0 ] && [ "$BLOCK_ON_HIGH" = true ]; then
    log_fail "Review BLOCKED - $HIGH_COUNT HIGH severity issue(s) found (--block-on-high enabled)"
    echo ""
    exit 1
elif [ "$VERDICT" = "REQUEST_CHANGES" ]; then
    log_warn "Review suggests changes but not blocking"
    echo ""
    echo "  The review agent found issues worth addressing."
    echo "  Consider fixing before merging to main."
    echo ""
    exit 0
else
    log_pass "Review PASSED ($VERDICT)"
    echo ""
    exit 0
fi
