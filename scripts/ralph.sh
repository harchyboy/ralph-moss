#!/bin/bash
# Ralph Moss - Autonomous AI agent loop with fresh context per iteration
# Usage: ./ralph.sh [max_iterations] [sleep_seconds] [options]
#
# Run from a prds/ subdirectory:
#   cd scripts/ralph-moss/prds/my-feature
#   ../../ralph.sh
#
# Options:
#   --skip-preflight    Skip PRD validation
#   --no-cost           Disable cost tracking
#   --max-cost <n>      Stop if total cost exceeds $n (e.g., --max-cost 5.00)
#   --max-plan          Use Max plan mode (track iterations/duration, not costs)
#   --quality-gate      Run lint/typecheck/test after each iteration
#   --review            Enable agent-to-agent code review
#   --strict            Strict mode for quality gate (fail on warnings)
#   --skip-tests        Skip tests in quality gate (faster iteration)
#
# Features:
#   - Preflight validation (file path staleness detection)
#   - Cost tracking per iteration with budget limits
#   - Quality gates (automated checks after implementation)
#   - Agent-to-agent review (second Claude reviews first's work)
#   - Battle-tested prompt patterns
#   - Archive search integration
#
# Each PRD lives in its own directory and is never deleted.
# Multiple PRDs can run concurrently with ralph-all.sh

set -e

# Parse arguments
MAX_ITERATIONS=10
SLEEP_SECONDS=2
SKIP_PREFLIGHT=false
TRACK_COSTS=true
QUALITY_GATE=false
AGENT_REVIEW=false
STRICT_MODE=false
SKIP_TESTS=false
MAX_COST=""  # Empty means no limit
MAX_PLAN=false  # Anthropic Max plan mode (flat subscription, no per-token costs)

# Parse arguments with value handling
ARGS=("$@")
for ((idx=0; idx<${#ARGS[@]}; idx++)); do
    arg="${ARGS[idx]}"
    case $arg in
        --skip-preflight)
            SKIP_PREFLIGHT=true
            ;;
        --no-cost)
            TRACK_COSTS=false
            ;;
        --max-cost)
            # Next argument is the cost value
            ((idx++))
            MAX_COST="${ARGS[idx]}"
            ;;
        --max-cost=*)
            # Handle --max-cost=5.00 format
            MAX_COST="${arg#*=}"
            ;;
        --max-plan)
            MAX_PLAN=true
            ;;
        --quality-gate)
            QUALITY_GATE=true
            ;;
        --review)
            AGENT_REVIEW=true
            ;;
        --strict)
            STRICT_MODE=true
            ;;
        --skip-tests)
            SKIP_TESTS=true
            ;;
        [0-9]*)
            if [ $MAX_ITERATIONS -eq 10 ]; then
                MAX_ITERATIONS=$arg
            else
                SLEEP_SECONDS=$arg
            fi
            ;;
    esac
done

# Determine working directory (support running from prds/ subdirectories)
if [ -f "./prd.json" ]; then
    WORK_DIR="$(pwd)"
elif [ -f "$(dirname "$0")/prd.json" ]; then
    WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
else
    echo "Error: No prd.json found in current directory or script directory"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRD_FILE="$WORK_DIR/prd.json"
PROGRESS_FILE="$WORK_DIR/progress.txt"
PROMPT_FILE="$SCRIPT_DIR/prompt-claude.md"
COSTS_FILE="$WORK_DIR/costs.log"
PREFLIGHT_SCRIPT="$SCRIPT_DIR/preflight.sh"
COST_TRACKER="$SCRIPT_DIR/track-cost.sh"
QUALITY_GATE_SCRIPT="$SCRIPT_DIR/quality-gate.sh"
REVIEW_AGENT_SCRIPT="$SCRIPT_DIR/review-agent.sh"

# Ensure jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Initialize progress file if missing
if [ ! -f "$PROGRESS_FILE" ]; then
    BRANCH_NAME=$(jq -r '.branchName // "unknown"' "$PRD_FILE" 2>/dev/null || echo "unknown")
    cat > "$PROGRESS_FILE" << EOF
# Ralph Moss Progress Log
Started: $(date)
Feature: $BRANCH_NAME

## Codebase Patterns
(Patterns discovered during implementation)

---
EOF
fi

# ═══════════════════════════════════════════════════════════════════
# PREFLIGHT CHECK - Validate PRD before execution
# ═══════════════════════════════════════════════════════════════════
if [ "$SKIP_PREFLIGHT" = false ] && [ -f "$PREFLIGHT_SCRIPT" ]; then
    echo ""
    echo "Running preflight checks..."
    chmod +x "$PREFLIGHT_SCRIPT"

    if ! "$PREFLIGHT_SCRIPT" "$PRD_FILE"; then
        preflight_exit=$?
        if [ $preflight_exit -eq 1 ]; then
            echo ""
            echo "❌ Preflight FAILED. Fix errors before running Ralph Moss."
            echo "   Use --skip-preflight to bypass (not recommended)"
            exit 1
        else
            echo ""
            echo "⚠️  Preflight passed with warnings. Proceeding..."
            sleep 2
        fi
    fi
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════
# MAIN LOOP - Fresh Claude session per iteration (no context rot)
# ═══════════════════════════════════════════════════════════════════
PROJECT=$(jq -r '.project // "Project"' "$PRD_FILE")
echo ""
echo "🤖 Starting Ralph Moss (Ultimate Edition)"
echo "   Project: $PROJECT"
echo "   PRD: $PRD_FILE"
echo "   Max iterations: $MAX_ITERATIONS"
if [ "$MAX_PLAN" = true ]; then
    echo "   Plan: Anthropic Max (tracking iterations & duration only)"
elif [ "$TRACK_COSTS" = true ]; then
    echo "   Cost tracking: enabled (API estimates)"
    if [ -n "$MAX_COST" ]; then
        echo "   Cost budget: \$$MAX_COST"
    fi
else
    echo "   Cost tracking: disabled"
fi
echo "   Quality gate: $QUALITY_GATE $([ "$STRICT_MODE" = true ] && echo "(strict)" || echo "")"
echo "   Agent review: $AGENT_REVIEW"
echo ""

# Initialize cost tracking
if [ "$TRACK_COSTS" = true ]; then
    export COSTS_FILE
    echo "# Ralph Moss Cost Log - $(date)" > "$COSTS_FILE.header"
    echo "# PRD: $PRD_FILE" >> "$COSTS_FILE.header"
    echo "" >> "$COSTS_FILE.header"
    touch "$COSTS_FILE"
fi

# Track totals
TOTAL_INPUT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_COST=0
TOTAL_DURATION=0

for ((i=1; i<=$MAX_ITERATIONS; i++)); do
    # Show progress
    TOTAL=$(jq '[.userStories | length] | add' "$PRD_FILE")
    DONE=$(jq '[.userStories[] | select(.passes==true)] | length' "$PRD_FILE")
    NEXT=$(jq -r '.userStories[] | select(.passes==false) | .id + ": " + .title' "$PRD_FILE" | head -1)

    echo "═══════════════════════════════════════════════════════════"
    echo "  Iteration $i of $MAX_ITERATIONS  │  Progress: $DONE/$TOTAL"
    echo "  Next: $NEXT"
    echo "═══════════════════════════════════════════════════════════"

    # Read prompt and inject working directory context
    PROMPT="Working directory: $WORK_DIR

$(cat "$PROMPT_FILE")"

    # Fresh Claude session (the key to avoiding context rot)
    # Use --output-format to get structured output for cost tracking if available
    ITERATION_START=$(date +%s)
    OUTPUT=$(claude --dangerously-skip-permissions -p "$PROMPT" 2>&1 | tee /dev/stderr) || true
    ITERATION_END=$(date +%s)
    ITERATION_DURATION=$((ITERATION_END - ITERATION_START))

    # Always track duration
    TOTAL_DURATION=$((TOTAL_DURATION + ITERATION_DURATION))

    # Track iteration metrics
    if [ "$MAX_PLAN" = true ]; then
        # Max plan mode: track iterations and duration only (no cost estimates)
        OUTPUT_CHARS=${#OUTPUT}

        # Log this iteration (duration-based)
        echo "$(date -Iseconds)|$i|max-plan|${OUTPUT_CHARS}chars|${ITERATION_DURATION}s" >> "$COSTS_FILE"

        echo ""
        echo "  ⏱️  Iteration $i: ${ITERATION_DURATION}s (${OUTPUT_CHARS} chars output)"
        echo "  📊 Total time: ${TOTAL_DURATION}s across $i iteration(s)"

    elif [ "$TRACK_COSTS" = true ]; then
        # API mode: track estimated costs
        # Try to parse token counts from output
        # Claude may output: "Tokens: input=X output=Y" or similar
        INPUT_TOKENS=$(echo "$OUTPUT" | grep -oE 'input[_=: ]*([0-9,]+)' -i | grep -oE '[0-9]+' | tail -1 || echo "0")
        OUTPUT_TOKENS=$(echo "$OUTPUT" | grep -oE 'output[_=: ]*([0-9,]+)' -i | grep -oE '[0-9]+' | tail -1 || echo "0")

        # Default estimate if not found (rough estimate based on output length)
        COST_IS_ESTIMATE=false
        if [ -z "$INPUT_TOKENS" ] || [ "$INPUT_TOKENS" = "0" ]; then
            # Estimate: ~4 chars per token, prompt is ~10K chars
            INPUT_TOKENS=3000
            COST_IS_ESTIMATE=true
        fi
        if [ -z "$OUTPUT_TOKENS" ] || [ "$OUTPUT_TOKENS" = "0" ]; then
            OUTPUT_TOKENS=$(( ${#OUTPUT} / 4 ))
            COST_IS_ESTIMATE=true
        fi

        # Calculate cost (using Sonnet pricing: $3/M input, $15/M output)
        ITER_COST=$(echo "scale=6; ($INPUT_TOKENS * 3 + $OUTPUT_TOKENS * 15) / 1000000" | bc)

        # Update totals
        TOTAL_INPUT_TOKENS=$((TOTAL_INPUT_TOKENS + INPUT_TOKENS))
        TOTAL_OUTPUT_TOKENS=$((TOTAL_OUTPUT_TOKENS + OUTPUT_TOKENS))
        TOTAL_COST=$(echo "$TOTAL_COST + $ITER_COST" | bc)

        # Log this iteration
        echo "$(date -Iseconds)|$i|$INPUT_TOKENS|$OUTPUT_TOKENS|sonnet|$ITER_COST|${ITERATION_DURATION}s" >> "$COSTS_FILE"

        echo ""
        if [ "$COST_IS_ESTIMATE" = true ]; then
            echo "  💰 Iteration $i cost: ~\$$(printf '%.4f' $ITER_COST) (estimated) [${ITERATION_DURATION}s]"
            echo "  📊 Running total: ~\$$(printf '%.4f' $TOTAL_COST) (estimates - actual may vary)"
        else
            echo "  💰 Iteration $i cost: \$$(printf '%.4f' $ITER_COST) (${INPUT_TOKENS} in / ${OUTPUT_TOKENS} out) [${ITERATION_DURATION}s]"
            echo "  📊 Running total: \$$(printf '%.4f' $TOTAL_COST)"
        fi

        # Check cost budget limit
        if [ -n "$MAX_COST" ]; then
            BUDGET_EXCEEDED=$(echo "$TOTAL_COST > $MAX_COST" | bc -l)
            if [ "$BUDGET_EXCEEDED" -eq 1 ]; then
                echo ""
                echo "═══════════════════════════════════════════════════════════"
                echo "  🛑 COST BUDGET EXCEEDED"
                echo "═══════════════════════════════════════════════════════════"
                echo ""
                echo "  Budget: \$$MAX_COST"
                echo "  Spent:  \$$(printf '%.4f' $TOTAL_COST)"
                echo ""
                echo "  Ralph Moss stopped to prevent overspending."
                echo "  To continue, either:"
                echo "    1. Increase budget: --max-cost <higher_value>"
                echo "    2. Remove limit: (omit --max-cost flag)"
                echo ""
                echo "  Progress saved in: $PROGRESS_FILE"
                echo "  Cost log: $COSTS_FILE"
                echo "═══════════════════════════════════════════════════════════"
                exit 2
            fi

            # Warn if approaching budget (>80%)
            BUDGET_RATIO=$(echo "scale=2; $TOTAL_COST / $MAX_COST" | bc -l)
            BUDGET_PCT=$(echo "scale=0; $BUDGET_RATIO * 100 / 1" | bc)
            if [ "$BUDGET_PCT" -ge 80 ]; then
                echo "  ⚠️  Warning: ${BUDGET_PCT}% of budget used (\$$MAX_COST limit)"
            fi
        fi
    fi

    # ═══════════════════════════════════════════════════════════════
    # QUALITY GATE - Run automated checks after implementation
    # ═══════════════════════════════════════════════════════════════
    if [ "$QUALITY_GATE" = true ] && [ -f "$QUALITY_GATE_SCRIPT" ]; then
        echo ""
        echo "Running quality gate..."
        chmod +x "$QUALITY_GATE_SCRIPT"

        GATE_ARGS=""
        [ "$STRICT_MODE" = true ] && GATE_ARGS="$GATE_ARGS --strict"
        [ "$SKIP_TESTS" = true ] && GATE_ARGS="$GATE_ARGS --skip-tests"

        if ! "$QUALITY_GATE_SCRIPT" $GATE_ARGS; then
            gate_exit=$?
            echo ""
            echo "⚠️  Quality gate FAILED (exit code $gate_exit)"
            echo "   The implementation agent's code did not pass quality checks."
            echo "   Next iteration will attempt to fix the issues."
            echo ""
            # Don't exit - let the next iteration fix the issues
            # The agent should see the failures and address them
        else
            echo "✅ Quality gate passed"
        fi
    fi

    # ═══════════════════════════════════════════════════════════════
    # AGENT REVIEW - Have a second agent critique the work
    # ═══════════════════════════════════════════════════════════════
    if [ "$AGENT_REVIEW" = true ] && [ -f "$REVIEW_AGENT_SCRIPT" ]; then
        # Only run review if quality gate passed (or wasn't enabled)
        if [ "$QUALITY_GATE" = false ] || [ -z "$gate_exit" ] || [ "$gate_exit" -eq 0 ]; then
            echo ""
            echo "Running agent-to-agent review..."
            chmod +x "$REVIEW_AGENT_SCRIPT"

            export WORK_DIR
            if ! "$REVIEW_AGENT_SCRIPT"; then
                review_exit=$?
                echo ""
                echo "⚠️  Review agent found issues (exit code $review_exit)"
                echo "   Next iteration should address the review feedback."
                echo "   Review saved to: $WORK_DIR/last-review.md"
                echo ""
                # Don't exit - let the next iteration address feedback
            else
                echo "✅ Review passed"
            fi
        else
            echo ""
            echo "⏭️  Skipping review (quality gate failed)"
        fi
    fi

    # Check for completion
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "  ✅ All tasks complete after $i iterations!"
        if [ "$MAX_PLAN" = true ]; then
            echo "  ⏱️  Total time: ${TOTAL_DURATION}s"
        elif [ "$TRACK_COSTS" = true ]; then
            echo "  💰 Total cost: ~\$$(printf '%.4f' $TOTAL_COST) (estimated)"
            echo "  📊 Total tokens: ~${TOTAL_INPUT_TOKENS} input / ~${TOTAL_OUTPUT_TOKENS} output"
            echo "  ⏱️  Total time: ${TOTAL_DURATION}s"
        fi
        echo "═══════════════════════════════════════════════════════════"
        exit 0
    fi

    echo ""
    echo "Iteration $i complete. Sleeping ${SLEEP_SECONDS}s..."
    sleep $SLEEP_SECONDS
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ⚠️  Reached max iterations ($MAX_ITERATIONS)"
echo "  Check $PROGRESS_FILE for status"
if [ "$MAX_PLAN" = true ]; then
    echo ""
    echo "  ⏱️  Total time: ${TOTAL_DURATION}s"
    echo "  📁 Log: $COSTS_FILE"
elif [ "$TRACK_COSTS" = true ]; then
    echo ""
    echo "  💰 Total cost: ~\$$(printf '%.4f' $TOTAL_COST) (estimated)"
    echo "  📊 Total tokens: ~${TOTAL_INPUT_TOKENS} input / ~${TOTAL_OUTPUT_TOKENS} output"
    echo "  ⏱️  Total time: ${TOTAL_DURATION}s"
    echo "  📁 Cost log: $COSTS_FILE"
fi
echo "═══════════════════════════════════════════════════════════"
exit 1
