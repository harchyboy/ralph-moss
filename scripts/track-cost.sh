#!/bin/bash
# track-cost.sh - Track and aggregate costs for Ralph Moss iterations
# Usage:
#   ./track-cost.sh log <iteration> <input_tokens> <output_tokens> [model]
#   ./track-cost.sh summary
#   ./track-cost.sh reset
#
# Cost file: costs.log in current directory

COSTS_FILE="${COSTS_FILE:-./costs.log}"
COMMAND="${1:-summary}"

# Claude pricing (as of 2025 - update as needed)
# Prices per 1M tokens
declare -A INPUT_PRICES=(
    ["claude-3-opus"]="15.00"
    ["claude-3-sonnet"]="3.00"
    ["claude-3-haiku"]="0.25"
    ["claude-3.5-sonnet"]="3.00"
    ["claude-3.5-haiku"]="0.80"
    ["claude-4-opus"]="15.00"
    ["claude-4-sonnet"]="3.00"
    ["default"]="3.00"
)

declare -A OUTPUT_PRICES=(
    ["claude-3-opus"]="75.00"
    ["claude-3-sonnet"]="15.00"
    ["claude-3-haiku"]="1.25"
    ["claude-3.5-sonnet"]="15.00"
    ["claude-3.5-haiku"]="4.00"
    ["claude-4-opus"]="75.00"
    ["claude-4-sonnet"]="15.00"
    ["default"]="15.00"
)

calculate_cost() {
    local input_tokens=$1
    local output_tokens=$2
    local model=${3:-default}

    local input_price=${INPUT_PRICES[$model]:-${INPUT_PRICES[default]}}
    local output_price=${OUTPUT_PRICES[$model]:-${OUTPUT_PRICES[default]}}

    # Calculate cost: (tokens / 1,000,000) * price
    local input_cost=$(echo "scale=6; $input_tokens * $input_price / 1000000" | bc)
    local output_cost=$(echo "scale=6; $output_tokens * $output_price / 1000000" | bc)
    local total_cost=$(echo "scale=6; $input_cost + $output_cost" | bc)

    echo "$total_cost"
}

log_iteration() {
    local iteration=$1
    local input_tokens=$2
    local output_tokens=$3
    local model=${4:-default}

    local cost=$(calculate_cost "$input_tokens" "$output_tokens" "$model")
    local timestamp=$(date -Iseconds)

    # Append to log
    echo "$timestamp|$iteration|$input_tokens|$output_tokens|$model|$cost" >> "$COSTS_FILE"

    echo "Logged: Iteration $iteration - Input: $input_tokens, Output: $output_tokens, Cost: \$$cost"
}

show_summary() {
    if [ ! -f "$COSTS_FILE" ]; then
        echo "No cost data found. Run some iterations first."
        return
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  RALPH MOSS COST SUMMARY"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Parse log and calculate totals
    local total_input=0
    local total_output=0
    local total_cost=0
    local iteration_count=0

    while IFS='|' read -r timestamp iteration input output model cost; do
        [ -z "$iteration" ] && continue
        total_input=$((total_input + input))
        total_output=$((total_output + output))
        total_cost=$(echo "$total_cost + $cost" | bc)
        ((iteration_count++))
    done < "$COSTS_FILE"

    echo "Iterations:    $iteration_count"
    echo "Input tokens:  $total_input ($(echo "scale=2; $total_input / 1000" | bc)K)"
    echo "Output tokens: $total_output ($(echo "scale=2; $total_output / 1000" | bc)K)"
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    printf "TOTAL COST:    \$%.4f\n" "$total_cost"
    echo "───────────────────────────────────────────────────────────────"
    echo ""

    if [ $iteration_count -gt 0 ]; then
        local avg_cost=$(echo "scale=4; $total_cost / $iteration_count" | bc)
        printf "Average per iteration: \$%.4f\n" "$avg_cost"
    fi

    echo ""
    echo "Per-iteration breakdown:"
    echo "─────────────────────────────────────────────────────────────"
    printf "%-12s %-12s %-12s %-12s %-10s\n" "Iteration" "Input" "Output" "Cost" "Time"
    echo "─────────────────────────────────────────────────────────────"

    while IFS='|' read -r timestamp iteration input output model cost; do
        [ -z "$iteration" ] && continue
        local time_short=$(echo "$timestamp" | cut -d'T' -f2 | cut -d'+' -f1 | cut -d'-' -f1)
        printf "%-12s %-12s %-12s \$%-11.4f %-10s\n" "$iteration" "$input" "$output" "$cost" "$time_short"
    done < "$COSTS_FILE"

    echo ""
}

reset_costs() {
    if [ -f "$COSTS_FILE" ]; then
        # Archive the old file
        local archive_name="costs.$(date +%Y%m%d-%H%M%S).log"
        mv "$COSTS_FILE" "$archive_name"
        echo "Previous costs archived to: $archive_name"
    fi
    touch "$COSTS_FILE"
    echo "Cost tracking reset."
}

# Parse output for token counts
# Claude CLI outputs something like:
# "Input tokens: 12345, Output tokens: 6789" or similar
parse_claude_output() {
    local output="$1"

    # Try to find token counts in various formats
    local input_tokens=$(echo "$output" | grep -oE 'input[_\s]?tokens?:?\s*([0-9,]+)' -i | grep -oE '[0-9,]+' | tr -d ',' | tail -1)
    local output_tokens=$(echo "$output" | grep -oE 'output[_\s]?tokens?:?\s*([0-9,]+)' -i | grep -oE '[0-9,]+' | tr -d ',' | tail -1)

    # Default if not found
    input_tokens=${input_tokens:-0}
    output_tokens=${output_tokens:-0}

    echo "$input_tokens $output_tokens"
}

export_csv() {
    if [ ! -f "$COSTS_FILE" ]; then
        echo "No cost data to export."
        return
    fi

    local csv_file="costs-export-$(date +%Y%m%d).csv"
    echo "timestamp,iteration,input_tokens,output_tokens,model,cost" > "$csv_file"
    cat "$COSTS_FILE" | tr '|' ',' >> "$csv_file"
    echo "Exported to: $csv_file"
}

# Main command handler
case "$COMMAND" in
    log)
        log_iteration "$2" "$3" "$4" "$5"
        ;;
    summary)
        show_summary
        ;;
    reset)
        reset_costs
        ;;
    export)
        export_csv
        ;;
    parse)
        # Parse claude output from stdin or argument
        if [ -n "$2" ]; then
            parse_claude_output "$2"
        else
            parse_claude_output "$(cat)"
        fi
        ;;
    *)
        echo "Usage: ./track-cost.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  log <iter> <input> <output> [model]  - Log iteration cost"
        echo "  summary                               - Show cost summary"
        echo "  reset                                 - Reset cost tracking"
        echo "  export                                - Export to CSV"
        echo "  parse                                 - Parse claude output for tokens"
        echo ""
        echo "Environment:"
        echo "  COSTS_FILE - Path to costs log (default: ./costs.log)"
        ;;
esac
