#!/bin/bash
# ralph-with-review.sh - Ralph Moss with full review pipeline
# Usage: ./ralph-with-review.sh [max_iterations] [options]
#
# This is a convenience wrapper that enables:
#   - Automated quality gates (typecheck, lint, tests)
#   - Agent-to-agent code review
#
# Equivalent to: ./ralph.sh --quality-gate --review [other args]
#
# Additional options are passed through to ralph.sh:
#   --strict        Fail on lint warnings
#   --skip-tests    Skip test execution (faster, less thorough)
#   --skip-preflight Skip PRD validation
#   --no-cost       Disable cost tracking
#
# Example:
#   ./ralph-with-review.sh 15 --skip-tests
#   # Runs 15 iterations with quality gate but skips slow tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Ralph Moss - Full Review Pipeline"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  This mode enables:"
echo "    ✓ Quality Gate: typecheck, lint, tests"
echo "    ✓ Agent Review: second Claude reviews changes"
echo ""
echo "  Use ./ralph.sh directly for more control over options."
echo ""

# Pass through all arguments plus the review flags
exec "$SCRIPT_DIR/ralph.sh" --quality-gate --review "$@"
