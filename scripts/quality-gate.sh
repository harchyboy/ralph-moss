#!/bin/bash
# quality-gate.sh - Automated Quality Gate for Ralph Moss
# Usage: ./quality-gate.sh [--strict] [--skip-tests]
#
# Runs automated quality checks in order:
#   1. TypeScript type checking (fast, catches type errors)
#   2. ESLint (catches code quality issues)
#   3. Unit tests (validates behavior)
#
# Exit codes:
#   0 - All checks pass
#   1 - Type check failed
#   2 - Lint failed
#   3 - Tests failed
#
# The --strict flag makes lint warnings fail the gate
# The --skip-tests flag skips running tests (for faster iteration)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
STRICT_MODE=false
SKIP_TESTS=false
SKIP_LINT=false
VERBOSE=false

for arg in "$@"; do
    case $arg in
        --strict)
            STRICT_MODE=true
            ;;
        --skip-tests)
            SKIP_TESTS=true
            ;;
        --skip-lint)
            SKIP_LINT=true
            ;;
        --verbose|-v)
            VERBOSE=true
            ;;
    esac
done

log_info() { echo -e "${BLUE}[GATE]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Track timing
start_time=$(date +%s)

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  RALPH MOSS QUALITY GATE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Mode: $([ "$STRICT_MODE" = true ] && echo "STRICT" || echo "Standard")"
echo "  Tests: $([ "$SKIP_TESTS" = true ] && echo "Skipped" || echo "Enabled")"
echo "  Lint: $([ "$SKIP_LINT" = true ] && echo "Skipped" || echo "Enabled")"
echo ""

cd "$REPO_ROOT"

# ═══════════════════════════════════════════════════════════════════
# GATE 1: TypeScript Type Check (Required - fast feedback)
# ═══════════════════════════════════════════════════════════════════
log_step "Gate 1: TypeScript Type Check"
gate1_start=$(date +%s)

if npm run typecheck 2>&1; then
    gate1_end=$(date +%s)
    log_pass "Type check passed ($((gate1_end - gate1_start))s)"
else
    log_fail "Type check FAILED"
    echo ""
    echo "Fix type errors before proceeding. Common issues:"
    echo "  - Missing imports"
    echo "  - Type mismatches"
    echo "  - Missing type annotations"
    echo ""
    exit 1
fi
echo ""

# ═══════════════════════════════════════════════════════════════════
# GATE 2: ESLint (Required - catches code quality issues)
# ═══════════════════════════════════════════════════════════════════
if [ "$SKIP_LINT" = false ]; then
    log_step "Gate 2: ESLint"
    gate2_start=$(date +%s)

    lint_output=$(npm run lint 2>&1) || lint_exit=$?
    gate2_end=$(date +%s)

    # Check for errors vs warnings
    error_count=$(echo "$lint_output" | grep -c "error" || echo "0")
    warning_count=$(echo "$lint_output" | grep -c "warning" || echo "0")

    if [ "$VERBOSE" = true ]; then
        echo "$lint_output"
    fi

    if [ "${lint_exit:-0}" -ne 0 ] || [ "$error_count" -gt 0 ]; then
        log_fail "Lint FAILED ($error_count errors, $warning_count warnings) ($((gate2_end - gate2_start))s)"
        if [ "$VERBOSE" = false ]; then
            echo "$lint_output" | grep -E "(error|warning)" | head -20
        fi
        echo ""
        exit 2
    elif [ "$warning_count" -gt 0 ] && [ "$STRICT_MODE" = true ]; then
        log_fail "Lint warnings in STRICT mode ($warning_count warnings) ($((gate2_end - gate2_start))s)"
        echo ""
        exit 2
    elif [ "$warning_count" -gt 0 ]; then
        log_warn "Lint passed with $warning_count warnings ($((gate2_end - gate2_start))s)"
    else
        log_pass "Lint passed ($((gate2_end - gate2_start))s)"
    fi
    echo ""
else
    log_info "Gate 2: ESLint - SKIPPED"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════
# GATE 3: Unit Tests (Optional but recommended)
# ═══════════════════════════════════════════════════════════════════
if [ "$SKIP_TESTS" = false ]; then
    log_step "Gate 3: Unit Tests"
    gate3_start=$(date +%s)

    # Run tests with a timeout (tests shouldn't hang forever)
    if timeout 300 npm run test -- --run 2>&1; then
        gate3_end=$(date +%s)
        log_pass "Tests passed ($((gate3_end - gate3_start))s)"
    else
        gate3_end=$(date +%s)
        log_fail "Tests FAILED ($((gate3_end - gate3_start))s)"
        echo ""
        echo "Fix failing tests before proceeding."
        echo "Run 'npm run test' to see full output."
        echo ""
        exit 3
    fi
    echo ""
else
    log_info "Gate 3: Unit Tests - SKIPPED"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════
end_time=$(date +%s)
total_time=$((end_time - start_time))

echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}ALL QUALITY GATES PASSED${NC}"
echo "  Total time: ${total_time}s"
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit 0
