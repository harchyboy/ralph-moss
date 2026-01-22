#!/bin/bash
# Ralph Moss Smart Merge - AI-assisted merge with conflict resolution
# Usage: ./merge-smart.sh [options]
#
# Merges multiple Ralph Moss branches with intelligent conflict resolution:
#   - PRD files (prd.json, progress.txt): Use feature branch version (--theirs)
#   - Code files: AI resolution via Claude with fallback to --theirs
#
# Options:
#   --auto-resolve    Automatically resolve conflicts (default: prompt)
#   --dry-run         Show what would be merged without making changes
#   --branches        Specific branches to merge (comma-separated)
#   --target          Branch to merge into (default: main)
#
# Examples:
#   ./merge-smart.sh --dry-run
#   ./merge-smart.sh --auto-resolve
#   ./merge-smart.sh --branches "ralph-moss/fix-sidebar,ralph-moss/story-030"

set -e

# Parse arguments
AUTO_RESOLVE=false
DRY_RUN=false
BRANCHES=""
TARGET_BRANCH="main"

for arg in "$@"; do
    case $arg in
        --auto-resolve)
            AUTO_RESOLVE=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        --branches=*)
            BRANCHES="${arg#*=}"
            ;;
        --target=*)
            TARGET_BRANCH="${arg#*=}"
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===================================================================
# CONFLICT RESOLUTION
# ===================================================================

get_conflict_strategy() {
    local file="$1"
    local filename=$(basename "$file")

    # PRD/progress files - always use feature branch version
    case "$filename" in
        prd.json|progress.txt|costs.log)
            echo "theirs"
            return
            ;;
        package-lock.json|yarn.lock)
            echo "ours"
            return
            ;;
    esac

    # Code files - attempt AI resolution
    case "$file" in
        *.ts|*.tsx|*.js|*.jsx|*.css|*.scss|*.json|*.md)
            echo "ai"
            return
            ;;
    esac

    # Default to theirs for unknown files
    echo "theirs"
}

resolve_with_ai() {
    local file="$1"

    # Check if claude CLI is available
    if ! command -v claude &> /dev/null; then
        echo "      Claude CLI not found, falling back to --theirs"
        return 1
    fi

    local content=$(cat "$file")
    local prompt="You are resolving a git merge conflict. Here is the conflicted file:

File: $file

$content

Please provide the resolved content that intelligently merges both changes.
Keep both sets of changes where possible, or choose the most appropriate version.
Output ONLY the resolved file content with no explanation or markdown formatting."

    echo "      Attempting AI resolution..."
    local resolved=$(echo "$prompt" | claude --dangerously-skip-permissions -p 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$resolved" ]; then
        echo "$resolved" > "$file"
        return 0
    fi

    echo "      AI resolution failed, falling back to --theirs"
    return 1
}

resolve_conflicts() {
    local auto_resolve="$1"

    # Get list of conflicted files
    local conflicted=$(git diff --name-only --diff-filter=U 2>/dev/null)

    if [ -z "$conflicted" ]; then
        echo "   No conflicts to resolve"
        return 0
    fi

    local count=$(echo "$conflicted" | wc -l)
    echo "   Resolving $count conflict(s)..."

    for file in $conflicted; do
        local strategy=$(get_conflict_strategy "$file")
        echo "      $file [$strategy]"

        case "$strategy" in
            theirs)
                git checkout --theirs "$file" 2>/dev/null
                git add "$file" 2>/dev/null
                ;;
            ours)
                git checkout --ours "$file" 2>/dev/null
                git add "$file" 2>/dev/null
                ;;
            ai)
                if [ "$auto_resolve" = true ]; then
                    if ! resolve_with_ai "$file"; then
                        # Fallback to theirs
                        git checkout --theirs "$file" 2>/dev/null
                    fi
                    git add "$file" 2>/dev/null
                else
                    echo "      Requires manual resolution (use --auto-resolve for AI)"
                    return 1
                fi
                ;;
        esac
    done

    return 0
}

# ===================================================================
# MAIN SCRIPT
# ===================================================================

echo ""
echo "Ralph Moss Smart Merge"
echo "========================================================"

# Get list of ralph-moss branches if not specified
if [ -z "$BRANCHES" ]; then
    remote_branches=$(git branch -r --list "origin/ralph-moss/*" 2>/dev/null | tr -d ' ')
    local_branches=$(git branch --list "ralph-moss/*" 2>/dev/null | tr -d '* ')

    all_branches=""
    if [ -n "$remote_branches" ]; then
        all_branches="$remote_branches"
    fi
    if [ -n "$local_branches" ]; then
        if [ -n "$all_branches" ]; then
            all_branches="$all_branches"$'\n'"$local_branches"
        else
            all_branches="$local_branches"
        fi
    fi

    # Remove origin/ prefix and deduplicate
    BRANCHES=$(echo "$all_branches" | sed 's|origin/||g' | sort -u | tr '\n' ',' | sed 's/,$//')
fi

if [ -z "$BRANCHES" ]; then
    echo "   No ralph-moss/* branches found to merge"
    echo ""
    echo "   Branches are created when Ralph Moss runs with a PRD that has a branchName."
    echo "   Check your PRD files for the branchName field."
    exit 0
fi

# Convert comma-separated to array
IFS=',' read -ra BRANCH_ARRAY <<< "$BRANCHES"

echo "   Target branch: $TARGET_BRANCH"
echo "   Branches to merge: ${#BRANCH_ARRAY[@]}"
for branch in "${BRANCH_ARRAY[@]}"; do
    echo "      - $branch"
done
if [ "$AUTO_RESOLVE" = true ]; then
    echo "   Conflict resolution: automatic (AI + fallback)"
else
    echo "   Conflict resolution: manual"
fi
if [ "$DRY_RUN" = true ]; then
    echo "   Mode: DRY RUN"
fi
echo "========================================================"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "DRY RUN - No changes will be made"
    echo ""

    for branch in "${BRANCH_ARRAY[@]}"; do
        echo "[WOULD MERGE] $branch"

        # Show what commits would be merged
        commits=$(git log --oneline "$TARGET_BRANCH..$branch" 2>/dev/null || echo "")
        if [ -n "$commits" ]; then
            echo "   Commits:"
            echo "$commits" | while read line; do
                echo "      $line"
            done
        else
            echo "   No new commits (may need to fetch)"
        fi
        echo ""
    done

    echo "========================================================"
    echo "   DRY RUN COMPLETE"
    echo "   Remove --dry-run to perform the actual merge"
    echo "========================================================"
    exit 0
fi

# Ensure we're on the target branch
current_branch=$(git branch --show-current 2>/dev/null)
if [ "$current_branch" != "$TARGET_BRANCH" ]; then
    echo "Switching to $TARGET_BRANCH..."
    git checkout "$TARGET_BRANCH" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to switch to $TARGET_BRANCH"
        exit 1
    fi
fi

# Pull latest
echo "Pulling latest $TARGET_BRANCH..."
git pull origin "$TARGET_BRANCH" 2>/dev/null || true

MERGED_COUNT=0
FAILED_COUNT=0
FAILED_BRANCHES=()

for branch in "${BRANCH_ARRAY[@]}"; do
    echo ""
    echo "[MERGING] $branch"

    # Attempt merge
    merge_output=$(git merge "$branch" --no-edit 2>&1)
    merge_exit=$?

    if [ $merge_exit -eq 0 ]; then
        echo "   Merged successfully"
        MERGED_COUNT=$((MERGED_COUNT + 1))
    else
        # Check if there are conflicts
        has_conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)

        if [ -n "$has_conflicts" ]; then
            echo "   Merge conflicts detected"

            if resolve_conflicts "$AUTO_RESOLVE"; then
                # Complete the merge
                git commit -m "Merge branch '$branch' into $TARGET_BRANCH (auto-resolved)" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "   Resolved and merged"
                    MERGED_COUNT=$((MERGED_COUNT + 1))
                else
                    echo "   Failed to complete merge commit"
                    git merge --abort 2>/dev/null
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    FAILED_BRANCHES+=("$branch")
                fi
            else
                echo "   Could not auto-resolve, aborting merge"
                git merge --abort 2>/dev/null
                FAILED_COUNT=$((FAILED_COUNT + 1))
                FAILED_BRANCHES+=("$branch")
            fi
        else
            echo "   Merge failed: $merge_output"
            git merge --abort 2>/dev/null
            FAILED_COUNT=$((FAILED_COUNT + 1))
            FAILED_BRANCHES+=("$branch")
        fi
    fi
done

echo ""
echo "========================================================"
echo "   MERGE COMPLETE"
echo "   Merged: $MERGED_COUNT"
echo "   Failed: $FAILED_COUNT"
if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    echo ""
    echo "   Failed branches:"
    for branch in "${FAILED_BRANCHES[@]}"; do
        echo "      - $branch"
    done
    echo ""
    echo "   To manually merge a failed branch:"
    echo "      git merge <branch-name>"
    echo "      # resolve conflicts"
    echo "      git add . && git commit"
fi
echo "========================================================"

if [ $MERGED_COUNT -gt 0 ]; then
    echo ""
    echo "Push merged changes to origin? (git push origin $TARGET_BRANCH)"
    echo "   Run: git push origin $TARGET_BRANCH"
fi

exit $FAILED_COUNT
