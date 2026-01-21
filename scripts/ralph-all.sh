#!/bin/bash
# Ralph Moss Concurrent - Run multiple PRDs in parallel
# Usage: ./ralph-all.sh [max_iterations_per_prd]
#
# Spawns a Ralph Moss instance for each PRD in prds/ directory
# Each runs independently with fresh context per micro-task

set -e

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRDS_DIR="$SCRIPT_DIR/prds"
LOG_DIR="$SCRIPT_DIR/logs"

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
echo "🚀 Ralph Moss Concurrent"
echo "═══════════════════════════════════════════════════════════"
echo "   Active PRDs: ${#ACTIVE_PRDS[@]}"
echo "   Max iterations per PRD: $MAX_ITERATIONS"
echo "   Logs: $LOG_DIR/"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Track PIDs for cleanup
PIDS=()

# Spawn Ralph for each active PRD
for prd_dir in "${ACTIVE_PRDS[@]}"; do
    PRD_NAME=$(basename "$prd_dir")
    PROJECT=$(jq -r '.project // "Unknown"' "$prd_dir/prd.json")
    TOTAL=$(jq '[.userStories | length] | add' "$prd_dir/prd.json")
    DONE=$(jq '[.userStories[] | select(.passes==true)] | length' "$prd_dir/prd.json")

    LOG_FILE="$LOG_DIR/$TIMESTAMP-$PRD_NAME.log"

    echo "📦 $PRD_NAME ($PROJECT) - $DONE/$TOTAL done"
    echo "   Log: $LOG_FILE"

    # Run Ralph in background for this PRD
    (
        cd "$prd_dir"
        "$SCRIPT_DIR/ralph.sh" "$MAX_ITERATIONS" 2>&1
    ) > "$LOG_FILE" 2>&1 &

    PIDS+=($!)
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "   All ${#ACTIVE_PRDS[@]} Ralph Moss instances spawned"
echo "   Monitor with: tail -f $LOG_DIR/$TIMESTAMP-*.log"
echo "═══════════════════════════════════════════════════════════"
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
for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    prd_name=$(basename "${ACTIVE_PRDS[$i]}")

    if wait "$pid"; then
        echo "✅ $prd_name completed"
    else
        echo "⚠️  $prd_name finished (check log for status)"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════"
if [ $FAILED -eq 0 ]; then
    echo "  ✅ All PRDs completed successfully!"
else
    echo "  ⚠️  $FAILED PRD(s) may need attention"
    echo "  Check logs: $LOG_DIR/$TIMESTAMP-*.log"
fi
echo "═══════════════════════════════════════════════════════════"

exit $FAILED
