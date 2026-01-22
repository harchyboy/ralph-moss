#!/bin/bash
# Ralph Moss Concurrent - Run multiple PRDs in parallel
# Usage: ./ralph-all.sh [max_iterations] [options]
#
# Spawns a Ralph Moss instance for each PRD in prds/ directory
# Each runs independently with fresh context per micro-task
#
# Options:
#   --worktrees         Run each PRD in isolated git worktree (prevents conflicts)
#   --cleanup           Remove worktrees after completion (default: keep for PR review)
#   --auto-pr           Create GitHub PR when each PRD completes
#   --draft             Create PRs as drafts (requires --auto-pr)
#
# Examples:
#   ./ralph-all.sh 15
#   ./ralph-all.sh --worktrees 15
#   ./ralph-all.sh --worktrees --auto-pr 15
#   ./ralph-all.sh --worktrees --auto-pr --draft 15

set -e

# Parse arguments
MAX_ITERATIONS=10
USE_WORKTREES=false
CLEANUP_WORKTREES=false
AUTO_PR=false
DRAFT_PR=false

for arg in "$@"; do
    case $arg in
        --worktrees)
            USE_WORKTREES=true
            ;;
        --cleanup)
            CLEANUP_WORKTREES=true
            ;;
        --auto-pr)
            AUTO_PR=true
            ;;
        --draft)
            DRAFT_PR=true
            ;;
        [0-9]*)
            MAX_ITERATIONS=$arg
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRDS_DIR="$SCRIPT_DIR/prds"
LOG_DIR="$SCRIPT_DIR/logs"
WORKTREE_ROOT="$SCRIPT_DIR/.worktrees"

# Get repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || dirname "$(dirname "$SCRIPT_DIR")")

# ===================================================================
# WORKTREE FUNCTIONS
# ===================================================================

create_worktree() {
    local prd_name="$1"
    local branch_name="$2"
    local worktree_path="$WORKTREE_ROOT/$prd_name"

    # Remove existing worktree if present
    if [ -d "$worktree_path" ]; then
        echo "   Removing existing worktree: $prd_name"
        git worktree remove "$worktree_path" --force 2>/dev/null || true
    fi

    # Check if branch exists on remote
    if git branch -r --list "origin/$branch_name" | grep -q .; then
        echo "   Creating worktree from existing branch: $branch_name"
        git worktree add "$worktree_path" "$branch_name" 2>/dev/null
    else
        echo "   Creating worktree with new branch: $branch_name"
        git worktree add -B "$branch_name" "$worktree_path" main 2>/dev/null
    fi

    if [ $? -ne 0 ]; then
        echo "   Failed to create worktree for $prd_name"
        return 1
    fi

    echo "$worktree_path"
}

remove_worktree() {
    local prd_name="$1"
    local worktree_path="$WORKTREE_ROOT/$prd_name"

    if [ -d "$worktree_path" ]; then
        echo "   Cleaning up worktree: $prd_name"
        git worktree remove "$worktree_path" --force 2>/dev/null || true
    fi
}

copy_prd_to_worktree() {
    local source_prd="$1"
    local worktree_path="$2"
    local prd_name="$3"

    # Calculate relative path
    local relative_script_path="${SCRIPT_DIR#$REPO_ROOT/}"

    # Create target directory
    local target_dir="$worktree_path/$relative_script_path/prds/$prd_name"
    mkdir -p "$target_dir"

    # Copy PRD files
    cp -r "$source_prd"/* "$target_dir/"

    echo "$target_dir"
}

# Ensure prds directory exists
if [ ! -d "$PRDS_DIR" ]; then
    echo "No prds/ directory found. Create PRDs with:"
    echo ""
    echo "  mkdir -p $PRDS_DIR/my-feature"
    echo "  cd $PRDS_DIR/my-feature"
    echo "  claude \"/prd [describe your feature]\""
    echo ""
    exit 1
fi

# Create logs directory
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Find all PRDs with incomplete tasks
ACTIVE_PRDS=()
for dir in "$PRDS_DIR"/*/; do
    if [ -f "$dir/prd.json" ]; then
        # Check if any tasks are incomplete
        INCOMPLETE=$(jq '[.userStories[] | select(.passes==false)] | length' "$dir/prd.json" 2>/dev/null || echo "0")
        if [ "$INCOMPLETE" -gt 0 ]; then
            ACTIVE_PRDS+=("$dir")
        fi
    fi
done

if [ ${#ACTIVE_PRDS[@]} -eq 0 ]; then
    echo "No active PRDs found (all complete or none exist)"
    echo ""
    echo "Create a new PRD:"
    echo "  mkdir -p $PRDS_DIR/my-feature && cd \$_"
    echo "  claude \"/prd [describe your feature]\""
    exit 0
fi

echo ""
echo "Ralph Moss Concurrent"
echo "========================================================"
echo "   Active PRDs: ${#ACTIVE_PRDS[@]}"
echo "   Max iterations per PRD: $MAX_ITERATIONS"
echo "   Logs: $LOG_DIR/"
if [ "$USE_WORKTREES" = true ]; then
    echo "   Worktrees: enabled (isolated parallel execution)"
    echo "   Worktree root: $WORKTREE_ROOT"
    if [ "$CLEANUP_WORKTREES" = true ]; then
        echo "   Cleanup: will remove worktrees after completion"
    else
        echo "   Cleanup: worktrees will be kept for PR review"
    fi
fi
if [ "$AUTO_PR" = true ]; then
    draft_display=""
    [ "$DRAFT_PR" = true ] && draft_display=" (draft)"
    echo "   Auto PR: enabled$draft_display"
fi
echo "========================================================"
echo ""

# Create worktree root if using worktrees
if [ "$USE_WORKTREES" = true ]; then
    mkdir -p "$WORKTREE_ROOT"
    echo "Setting up worktrees..."
fi

# Track PIDs for cleanup
PIDS=()
WORKTREE_PATHS=()
PRD_NAMES=()

# Spawn Ralph for each active PRD
for prd_dir in "${ACTIVE_PRDS[@]}"; do
    PRD_NAME=$(basename "$prd_dir")
    PROJECT=$(jq -r '.project // "Unknown"' "$prd_dir/prd.json")
    BRANCH_NAME=$(jq -r '.branchName // "ralph-moss/'$PRD_NAME'"' "$prd_dir/prd.json")
    TOTAL=$(jq '[.userStories | length] | add' "$prd_dir/prd.json")
    DONE=$(jq '[.userStories[] | select(.passes==true)] | length' "$prd_dir/prd.json")

    LOG_FILE="$LOG_DIR/$TIMESTAMP-$PRD_NAME.log"

    echo "[PRD] $PRD_NAME ($PROJECT) - $DONE/$TOTAL done"
    echo "   Log: $LOG_FILE"

    # Determine execution path
    EXECUTION_PATH="$prd_dir"
    WORKTREE_PATH=""

    if [ "$USE_WORKTREES" = true ]; then
        # Create worktree for isolated execution
        WORKTREE_PATH=$(create_worktree "$PRD_NAME" "$BRANCH_NAME")
        if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
            # Copy PRD files to worktree
            EXECUTION_PATH=$(copy_prd_to_worktree "$prd_dir" "$WORKTREE_PATH" "$PRD_NAME")
            echo "   Worktree: $WORKTREE_PATH"
        else
            echo "   Warning: Failed to create worktree, falling back to shared execution"
            WORKTREE_PATH=""
        fi
    fi

    # Build ralph arguments
    RALPH_ARGS="$MAX_ITERATIONS"
    if [ "$AUTO_PR" = true ]; then
        RALPH_ARGS="$RALPH_ARGS --auto-pr"
        if [ "$DRAFT_PR" = true ]; then
            RALPH_ARGS="$RALPH_ARGS --draft"
        fi
    fi

    # Run Ralph in background for this PRD
    if [ "$USE_WORKTREES" = true ] && [ -n "$WORKTREE_PATH" ]; then
        # For worktrees, run ralph.sh from within the worktree
        WORKTREE_RALPH="$WORKTREE_PATH/${SCRIPT_DIR#$REPO_ROOT/}/ralph.sh"
        (
            cd "$EXECUTION_PATH"
            "$WORKTREE_RALPH" $RALPH_ARGS 2>&1
        ) > "$LOG_FILE" 2>&1 &
    else
        # Standard execution
        (
            cd "$EXECUTION_PATH"
            "$SCRIPT_DIR/ralph.sh" $RALPH_ARGS 2>&1
        ) > "$LOG_FILE" 2>&1 &
    fi

    PIDS+=($!)
    WORKTREE_PATHS+=("$WORKTREE_PATH")
    PRD_NAMES+=("$PRD_NAME")
done

echo ""
echo "========================================================"
echo "   All ${#ACTIVE_PRDS[@]} Ralph Moss instances spawned"
echo "   Monitor with: tail -f $LOG_DIR/$TIMESTAMP-*.log"
echo "========================================================"
echo ""

# Cleanup on Ctrl+C
cleanup() {
    echo ""
    echo "Stopping all Ralph Moss instances..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    exit 1
}
trap cleanup INT TERM

# Wait for all to complete
echo "Waiting for all Ralph Moss instances to complete..."
echo "(Press Ctrl+C to stop all)"
echo ""

FAILED=0
COMPLETED_INDICES=()
for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    prd_name="${PRD_NAMES[$i]}"

    if wait "$pid"; then
        echo "[OK] $prd_name completed"
        COMPLETED_INDICES+=($i)
    else
        echo "[WARN] $prd_name finished (check log for status)"
        FAILED=$((FAILED + 1))
    fi
done

# Worktree cleanup
if [ "$USE_WORKTREES" = true ]; then
    echo ""
    if [ "$CLEANUP_WORKTREES" = true ]; then
        echo "Cleaning up worktrees..."
        for i in "${!PRD_NAMES[@]}"; do
            if [ -n "${WORKTREE_PATHS[$i]}" ]; then
                remove_worktree "${PRD_NAMES[$i]}"
            fi
        done
        # Clean up worktree root if empty
        if [ -d "$WORKTREE_ROOT" ] && [ -z "$(ls -A "$WORKTREE_ROOT")" ]; then
            rmdir "$WORKTREE_ROOT" 2>/dev/null || true
        fi
        echo "Worktrees removed."
    else
        echo "Worktrees preserved for PR review:"
        for i in "${COMPLETED_INDICES[@]}"; do
            if [ -n "${WORKTREE_PATHS[$i]}" ]; then
                echo "   ${PRD_NAMES[$i]}: ${WORKTREE_PATHS[$i]}"
            fi
        done
        echo ""
        echo "To clean up worktrees later, run:"
        echo "   git worktree list"
        echo "   git worktree remove <path>"
    fi
fi

echo ""
echo "========================================================"
if [ $FAILED -eq 0 ]; then
    echo "  [OK] All PRDs completed successfully!"
else
    echo "  [WARN] $FAILED PRD(s) may need attention"
    echo "  Check logs: $LOG_DIR/$TIMESTAMP-*.log"
fi
echo "========================================================"

exit $FAILED
