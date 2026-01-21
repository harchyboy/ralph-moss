#!/bin/bash
# install.sh - Install Ralph Moss into your project
#
# Usage:
#   ./install.sh [target-directory]
#
# This script copies Ralph Moss scripts and skills to your project.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-.}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_done() { echo -e "${GREEN}[DONE]${NC} $1"; }

echo ""
echo "=================================================="
echo "  Ralph Moss Installer"
echo "=================================================="
echo ""

# Resolve target directory
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
log_info "Installing to: $TARGET_DIR"
echo ""

# Create directories
log_info "Creating directories..."
mkdir -p "$TARGET_DIR/scripts/ralph-moss/prds"
mkdir -p "$TARGET_DIR/.claude/skills"

# Copy scripts
log_info "Copying scripts..."
cp "$SCRIPT_DIR/scripts/"*.sh "$TARGET_DIR/scripts/ralph-moss/" 2>/dev/null || true
cp "$SCRIPT_DIR/scripts/"*.ps1 "$TARGET_DIR/scripts/ralph-moss/" 2>/dev/null || true
cp "$SCRIPT_DIR/scripts/"*.md "$TARGET_DIR/scripts/ralph-moss/"
cp "$SCRIPT_DIR/scripts/"*.json "$TARGET_DIR/scripts/ralph-moss/"
cp "$SCRIPT_DIR/scripts/"*.txt "$TARGET_DIR/scripts/ralph-moss/" 2>/dev/null || true

# Make scripts executable
chmod +x "$TARGET_DIR/scripts/ralph-moss/"*.sh 2>/dev/null || true

# Copy skills
log_info "Copying skills..."
cp -r "$SCRIPT_DIR/skills/"* "$TARGET_DIR/.claude/skills/"

# Copy examples
log_info "Copying examples..."
mkdir -p "$TARGET_DIR/scripts/ralph-moss/examples"
cp "$SCRIPT_DIR/examples/"* "$TARGET_DIR/scripts/ralph-moss/examples/" 2>/dev/null || true

echo ""
log_done "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Create a PRD with '/prd' skill in Claude Code"
echo "  2. Run Ralph Moss:"
echo "     cd scripts/ralph-moss/prds/[feature-name]"
echo "     ../../ralph.sh"
echo ""
echo "Documentation: $TARGET_DIR/scripts/ralph-moss/"
echo ""
