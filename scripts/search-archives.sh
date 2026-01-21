#!/bin/bash
# search-archives.sh - Search archived PRDs for relevant learnings
# Usage: ./search-archives.sh "keyword1 keyword2" [archive_dir]
#
# This script helps Ralph Moss find learnings from similar past PRDs
# by searching archive descriptions, progress files, and folder names.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="${2:-$SCRIPT_DIR/archive}"
SEARCH_TERMS="$1"

if [ -z "$SEARCH_TERMS" ]; then
  echo "Usage: ./search-archives.sh \"keyword1 keyword2\" [archive_dir]"
  echo ""
  echo "Examples:"
  echo "  ./search-archives.sh \"contact search modal\""
  echo "  ./search-archives.sh \"unit loading skeleton\""
  echo "  ./search-archives.sh \"pipeline dashboard widget\""
  exit 1
fi

if [ ! -d "$ARCHIVE_DIR" ]; then
  echo "No archive directory found at: $ARCHIVE_DIR"
  echo "No historical learnings available."
  exit 0
fi

echo "==========================================="
echo "  ARCHIVE SEARCH: Relevant Past Learnings"
echo "==========================================="
echo ""
echo "Search terms: $SEARCH_TERMS"
echo "Archive location: $ARCHIVE_DIR"
echo ""

# Convert search terms to lowercase for case-insensitive matching
SEARCH_LOWER=$(echo "$SEARCH_TERMS" | tr '[:upper:]' '[:lower:]')

# Track if we found anything
FOUND_MATCHES=false

# Search each archive folder
for archive_folder in "$ARCHIVE_DIR"/*/; do
  if [ ! -d "$archive_folder" ]; then
    continue
  fi

  folder_name=$(basename "$archive_folder")
  prd_file="$archive_folder/prd.json"
  progress_file="$archive_folder/progress.txt"

  # Check if this archive matches our search terms
  MATCH=false
  MATCH_REASON=""

  # 1. Check folder name
  folder_lower=$(echo "$folder_name" | tr '[:upper:]' '[:lower:]' | tr '-' ' ')
  for term in $SEARCH_LOWER; do
    if echo "$folder_lower" | grep -q "$term"; then
      MATCH=true
      MATCH_REASON="folder name"
      break
    fi
  done

  # 2. Check PRD description
  if [ -f "$prd_file" ] && [ "$MATCH" = false ]; then
    prd_desc=$(jq -r '.description // ""' "$prd_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    for term in $SEARCH_LOWER; do
      if echo "$prd_desc" | grep -q "$term"; then
        MATCH=true
        MATCH_REASON="PRD description"
        break
      fi
    done
  fi

  # 3. Check progress.txt content
  if [ -f "$progress_file" ] && [ "$MATCH" = false ]; then
    progress_content=$(cat "$progress_file" | tr '[:upper:]' '[:lower:]')
    for term in $SEARCH_LOWER; do
      if echo "$progress_content" | grep -q "$term"; then
        MATCH=true
        MATCH_REASON="progress file content"
        break
      fi
    done
  fi

  # If we found a match, extract and display learnings
  if [ "$MATCH" = true ]; then
    FOUND_MATCHES=true
    echo "-------------------------------------------"
    echo "MATCH FOUND: $folder_name"
    echo "Matched via: $MATCH_REASON"
    echo "-------------------------------------------"

    # Show PRD description
    if [ -f "$prd_file" ]; then
      desc=$(jq -r '.description // "No description"' "$prd_file" 2>/dev/null)
      echo ""
      echo "PRD Description: $desc"
    fi

    # Extract Codebase Patterns section from progress.txt
    if [ -f "$progress_file" ]; then
      echo ""
      echo "=== LEARNINGS FROM THIS PRD ==="

      # Extract the Codebase Patterns section
      patterns=$(awk '/^## Codebase Patterns/,/^---/' "$progress_file" | grep -v '^---' | grep -v '^\(Patterns discovered\|This section will\)')
      if [ -n "$patterns" ] && [ "$patterns" != "## Codebase Patterns" ]; then
        echo ""
        echo "CODEBASE PATTERNS:"
        echo "$patterns"
      fi

      # Extract "Learnings for future iterations" sections
      learnings=$(grep -A 20 "Learnings for future iterations" "$progress_file" 2>/dev/null | grep "^-" | head -20)
      if [ -n "$learnings" ]; then
        echo ""
        echo "KEY LEARNINGS:"
        echo "$learnings"
      fi

      # Extract any CRITICAL notes
      critical=$(grep -i "critical" "$progress_file" 2>/dev/null | head -5)
      if [ -n "$critical" ]; then
        echo ""
        echo "CRITICAL NOTES:"
        echo "$critical"
      fi
    fi

    echo ""
  fi
done

if [ "$FOUND_MATCHES" = false ]; then
  echo "No matching archives found for: $SEARCH_TERMS"
  echo ""
  echo "Available archives:"
  ls -1 "$ARCHIVE_DIR" 2>/dev/null | head -10
  echo ""
  echo "Try broader search terms or check archive folder names above."
fi

echo ""
echo "==========================================="
echo "  END OF ARCHIVE SEARCH"
echo "==========================================="
