#!/bin/bash
# ralph-parallel.sh - Run independent stories in parallel using subagent spawning
# Usage: ./ralph-parallel.sh [max_parallel] [prd_file]
#
# Analyzes story dependencies and runs independent stories concurrently.
# Stories with dependencies wait for their prerequisites to complete.
#
# Prerequisites:
#   - jq for JSON parsing
#   - GNU parallel (optional, falls back to background jobs)

set -e

MAX_PARALLEL=${1:-3}
PRD_FILE=${2:-"./prd.json"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Ensure jq is available
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    exit 1
fi

if [ ! -f "$PRD_FILE" ]; then
    log_error "PRD file not found: $PRD_FILE"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# DEPENDENCY ANALYSIS
# ═══════════════════════════════════════════════════════════════════

analyze_dependencies() {
    log_info "Analyzing story dependencies..."

    # Get all stories
    local stories=$(jq -r '.userStories[] | @base64' "$PRD_FILE")

    echo ""
    echo "Story Dependency Graph:"
    echo "========================"

    for story in $stories; do
        local id=$(echo "$story" | base64 -d | jq -r '.id')
        local title=$(echo "$story" | base64 -d | jq -r '.title')
        local passes=$(echo "$story" | base64 -d | jq -r '.passes')
        local depends=$(echo "$story" | base64 -d | jq -r '.dependsOn // [] | join(", ")')

        local status_icon="⏳"
        if [ "$passes" = "true" ]; then
            status_icon="✅"
        fi

        if [ -n "$depends" ] && [ "$depends" != "" ]; then
            echo "$status_icon $id: $title (depends on: $depends)"
        else
            echo "$status_icon $id: $title (no dependencies - can run immediately)"
        fi
    done
    echo ""
}

# Get stories that can run now (no unmet dependencies)
get_runnable_stories() {
    local runnable=()
    local stories=$(jq -r '.userStories[] | @base64' "$PRD_FILE")

    for story in $stories; do
        local id=$(echo "$story" | base64 -d | jq -r '.id')
        local passes=$(echo "$story" | base64 -d | jq -r '.passes')
        local depends=$(echo "$story" | base64 -d | jq -r '.dependsOn // []')

        # Skip completed stories
        if [ "$passes" = "true" ]; then
            continue
        fi

        # Check if all dependencies are met
        local deps_met=true
        for dep in $(echo "$depends" | jq -r '.[]'); do
            local dep_passes=$(jq -r ".userStories[] | select(.id == \"$dep\") | .passes" "$PRD_FILE")
            if [ "$dep_passes" != "true" ]; then
                deps_met=false
                break
            fi
        done

        if [ "$deps_met" = "true" ]; then
            runnable+=("$id")
        fi
    done

    echo "${runnable[@]}"
}

# ═══════════════════════════════════════════════════════════════════
# PARALLEL EXECUTION
# ═══════════════════════════════════════════════════════════════════

run_story() {
    local story_id=$1
    local log_file="$WORK_DIR/logs/${story_id}.log"

    mkdir -p "$WORK_DIR/logs"

    log_info "Starting $story_id in background..."

    # Create a story-specific prompt that targets just this story
    local story_prompt="Working directory: $WORK_DIR

# Ralph Moss - Single Story Execution

You are executing story $story_id from the PRD. Focus ONLY on this story.

## Instructions
1. Read prd.json and find story $story_id
2. Read progress.txt for context
3. Implement ONLY story $story_id
4. Run quality checks
5. Update prd.json to set passes: true for $story_id
6. Append progress to progress.txt
7. DO NOT commit - the main process will handle commits

$(cat "$SCRIPT_DIR/prompt-claude.md" | grep -A 1000 "## Critical Mindset Rules" | head -100)
"

    # Run Claude for this specific story
    echo "$story_prompt" | claude --dangerously-skip-permissions -p - > "$log_file" 2>&1 &

    echo $!  # Return the PID
}

wait_for_stories() {
    local pids=("$@")
    local failed=0

    for pid in "${pids[@]}"; do
        wait $pid || ((failed++))
    done

    return $failed
}

# ═══════════════════════════════════════════════════════════════════
# MAIN PARALLEL LOOP
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Ralph Moss - Parallel Story Execution"
echo "  Max parallel: $MAX_PARALLEL"
echo "═══════════════════════════════════════════════════════════════"
echo ""

analyze_dependencies

iteration=0
max_iterations=50  # Safety limit

while true; do
    ((iteration++))

    if [ $iteration -gt $max_iterations ]; then
        log_error "Reached max iterations ($max_iterations). Aborting."
        exit 1
    fi

    # Get stories that can run now
    runnable=($(get_runnable_stories))

    if [ ${#runnable[@]} -eq 0 ]; then
        # Check if all done or stuck
        remaining=$(jq '[.userStories[] | select(.passes==false)] | length' "$PRD_FILE")
        if [ "$remaining" -eq 0 ]; then
            log_success "All stories complete!"
            break
        else
            log_error "No runnable stories but $remaining remain. Possible circular dependency."
            exit 1
        fi
    fi

    log_info "Iteration $iteration: ${#runnable[@]} stories ready to run"

    # Limit to max parallel
    to_run=("${runnable[@]:0:$MAX_PARALLEL}")

    echo "Running: ${to_run[*]}"

    # Start stories in parallel
    pids=()
    for story_id in "${to_run[@]}"; do
        pid=$(run_story "$story_id")
        pids+=($pid)
    done

    # Wait for this batch
    log_info "Waiting for batch to complete..."
    wait_for_stories "${pids[@]}" || log_warn "Some stories in batch failed"

    # Check results
    for story_id in "${to_run[@]}"; do
        passes=$(jq -r ".userStories[] | select(.id == \"$story_id\") | .passes" "$PRD_FILE")
        if [ "$passes" = "true" ]; then
            log_success "$story_id completed"
        else
            log_warn "$story_id did not complete (will retry next iteration)"
        fi
    done

    echo ""
done

# ═══════════════════════════════════════════════════════════════════
# FINAL COMMIT
# ═══════════════════════════════════════════════════════════════════

log_info "All stories complete. Creating final commit..."

git add -A
git commit -m "feat: Complete all stories from PRD (parallel execution)" || true
git push || log_warn "Push failed - may need manual push"

log_success "Ralph Moss parallel execution complete!"
echo ""
echo "Logs available in: $WORK_DIR/logs/"
