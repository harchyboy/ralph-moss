# Ralph Moss Smart Merge - AI-assisted merge with conflict resolution
# Usage: .\merge-smart.ps1 [-AutoResolve] [-DryRun] [-Branches @("branch1", "branch2")]
#
# Merges multiple Ralph Moss branches with intelligent conflict resolution:
#   - PRD files (prd.json, progress.txt): Use feature branch version (--theirs)
#   - Code files: AI resolution via Claude with fallback to --theirs
#
# Options:
#   -AutoResolve    Automatically resolve conflicts (default: prompt)
#   -DryRun         Show what would be merged without making changes
#   -Branches       Specific branches to merge (default: all ralph-moss/*)
#   -TargetBranch   Branch to merge into (default: main)
#
# Examples:
#   .\merge-smart.ps1 -DryRun
#   .\merge-smart.ps1 -AutoResolve
#   .\merge-smart.ps1 -Branches @("ralph-moss/fix-sidebar", "ralph-moss/story-030")

param(
    [switch]$AutoResolve,
    [switch]$DryRun,
    [string[]]$Branches = @(),
    [string]$TargetBranch = "main"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot

# ===================================================================
# CONFLICT RESOLUTION STRATEGIES
# ===================================================================

# File patterns and their resolution strategies
$ConflictStrategies = @{
    # PRD/progress files - always use feature branch version
    "prd.json" = "theirs"
    "progress.txt" = "theirs"
    "costs.log" = "theirs"

    # Lock files - always use target branch
    "package-lock.json" = "ours"
    "yarn.lock" = "ours"

    # Code files - attempt AI resolution
    "*.ts" = "ai"
    "*.tsx" = "ai"
    "*.js" = "ai"
    "*.jsx" = "ai"
    "*.css" = "ai"
    "*.scss" = "ai"
    "*.json" = "ai"
    "*.md" = "ai"
}

function Get-ConflictStrategy {
    param([string]$FilePath)

    $FileName = Split-Path $FilePath -Leaf

    # Check exact match first
    if ($ConflictStrategies.ContainsKey($FileName)) {
        return $ConflictStrategies[$FileName]
    }

    # Check pattern match
    foreach ($pattern in $ConflictStrategies.Keys) {
        if ($pattern.StartsWith("*")) {
            $extension = $pattern.Substring(1)
            if ($FileName.EndsWith($extension)) {
                return $ConflictStrategies[$pattern]
            }
        }
    }

    # Default to theirs for unknown files
    return "theirs"
}

function Resolve-ConflictWithAI {
    param(
        [string]$FilePath,
        [string]$ConflictContent
    )

    try {
        # Check if claude CLI is available
        $claudeCheck = Get-Command claude -ErrorAction SilentlyContinue
        if (-not $claudeCheck) {
            Write-Host "      Claude CLI not found, falling back to --theirs" -ForegroundColor Yellow
            return $null
        }

        $prompt = @"
You are resolving a git merge conflict. Here is the conflicted file:

File: $FilePath

$ConflictContent

Please provide the resolved content that intelligently merges both changes.
Keep both sets of changes where possible, or choose the most appropriate version.
Output ONLY the resolved file content with no explanation or markdown formatting.
"@

        Write-Host "      Attempting AI resolution..." -ForegroundColor Gray
        $resolved = echo $prompt | claude --dangerously-skip-permissions -p 2>$null

        if ($LASTEXITCODE -eq 0 -and $resolved) {
            return $resolved
        }

        Write-Host "      AI resolution failed, falling back to --theirs" -ForegroundColor Yellow
        return $null

    } catch {
        Write-Host "      AI resolution error: $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Resolve-MergeConflicts {
    param([switch]$AutoResolve)

    # Get list of conflicted files
    $conflictedFiles = git diff --name-only --diff-filter=U 2>$null

    if (-not $conflictedFiles) {
        Write-Host "   No conflicts to resolve" -ForegroundColor Green
        return $true
    }

    Write-Host "   Resolving $(@($conflictedFiles).Count) conflict(s)..." -ForegroundColor Cyan

    foreach ($file in $conflictedFiles) {
        $strategy = Get-ConflictStrategy $file
        Write-Host "      $file [$strategy]" -ForegroundColor Gray

        switch ($strategy) {
            "theirs" {
                git checkout --theirs $file 2>$null
                git add $file 2>$null
            }
            "ours" {
                git checkout --ours $file 2>$null
                git add $file 2>$null
            }
            "ai" {
                if ($AutoResolve) {
                    # Try AI resolution
                    $content = Get-Content $file -Raw -ErrorAction SilentlyContinue
                    $resolved = Resolve-ConflictWithAI -FilePath $file -ConflictContent $content

                    if ($resolved) {
                        $resolved | Set-Content $file -NoNewline
                        git add $file 2>$null
                    } else {
                        # Fallback to theirs
                        git checkout --theirs $file 2>$null
                        git add $file 2>$null
                    }
                } else {
                    # Manual resolution needed
                    Write-Host "      Requires manual resolution (use -AutoResolve for AI)" -ForegroundColor Yellow
                    return $false
                }
            }
        }
    }

    return $true
}

# ===================================================================
# MAIN SCRIPT
# ===================================================================

Write-Host ""
Write-Host "Ralph Moss Smart Merge"
Write-Host "========================================================"

# Get list of ralph-moss branches if not specified
if ($Branches.Count -eq 0) {
    $remoteBranches = git branch -r --list "origin/ralph-moss/*" 2>$null
    $localBranches = git branch --list "ralph-moss/*" 2>$null

    $allBranches = @()
    if ($remoteBranches) {
        $allBranches += $remoteBranches | ForEach-Object { $_.Trim().Replace("origin/", "") }
    }
    if ($localBranches) {
        $allBranches += $localBranches | ForEach-Object { $_.Trim().TrimStart("* ") }
    }

    $Branches = $allBranches | Select-Object -Unique | Sort-Object
}

if ($Branches.Count -eq 0) {
    Write-Host "   No ralph-moss/* branches found to merge" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Branches are created when Ralph Moss runs with a PRD that has a branchName."
    Write-Host "   Check your PRD files for the branchName field."
    exit 0
}

Write-Host "   Target branch: $TargetBranch"
Write-Host "   Branches to merge: $($Branches.Count)"
foreach ($branch in $Branches) {
    Write-Host "      - $branch"
}
if ($AutoResolve) {
    Write-Host "   Conflict resolution: automatic (AI + fallback)" -ForegroundColor Cyan
} else {
    Write-Host "   Conflict resolution: manual" -ForegroundColor Yellow
}
if ($DryRun) {
    Write-Host "   Mode: DRY RUN" -ForegroundColor Yellow
}
Write-Host "========================================================"
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN - No changes will be made"
    Write-Host ""

    foreach ($branch in $Branches) {
        Write-Host "[WOULD MERGE] $branch" -ForegroundColor Cyan

        # Show what commits would be merged
        $commits = git log --oneline "$TargetBranch..$branch" 2>$null
        if ($commits) {
            Write-Host "   Commits:"
            $commits | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
        } else {
            Write-Host "   No new commits (may need to fetch)" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    Write-Host "========================================================"
    Write-Host "   DRY RUN COMPLETE"
    Write-Host "   Remove -DryRun to perform the actual merge"
    Write-Host "========================================================"
    exit 0
}

# Ensure we're on the target branch
$currentBranch = git branch --show-current 2>$null
if ($currentBranch -ne $TargetBranch) {
    Write-Host "Switching to $TargetBranch..." -ForegroundColor Gray
    git checkout $TargetBranch 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to switch to $TargetBranch"
        exit 1
    }
}

# Pull latest
Write-Host "Pulling latest $TargetBranch..." -ForegroundColor Gray
git pull origin $TargetBranch 2>$null

$MergedCount = 0
$FailedCount = 0
$FailedBranches = @()

foreach ($branch in $Branches) {
    Write-Host ""
    Write-Host "[MERGING] $branch" -ForegroundColor Cyan

    # Attempt merge
    $mergeOutput = git merge $branch --no-edit 2>&1
    $mergeExitCode = $LASTEXITCODE

    if ($mergeExitCode -eq 0) {
        Write-Host "   Merged successfully" -ForegroundColor Green
        $MergedCount++
    } else {
        # Check if there are conflicts
        $hasConflicts = git diff --name-only --diff-filter=U 2>$null

        if ($hasConflicts) {
            Write-Host "   Merge conflicts detected" -ForegroundColor Yellow

            $resolved = Resolve-MergeConflicts -AutoResolve:$AutoResolve

            if ($resolved) {
                # Complete the merge
                git commit -m "Merge branch '$branch' into $TargetBranch (auto-resolved)" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "   Resolved and merged" -ForegroundColor Green
                    $MergedCount++
                } else {
                    Write-Host "   Failed to complete merge commit" -ForegroundColor Red
                    git merge --abort 2>$null
                    $FailedCount++
                    $FailedBranches += $branch
                }
            } else {
                Write-Host "   Could not auto-resolve, aborting merge" -ForegroundColor Red
                git merge --abort 2>$null
                $FailedCount++
                $FailedBranches += $branch
            }
        } else {
            Write-Host "   Merge failed: $mergeOutput" -ForegroundColor Red
            git merge --abort 2>$null
            $FailedCount++
            $FailedBranches += $branch
        }
    }
}

Write-Host ""
Write-Host "========================================================"
Write-Host "   MERGE COMPLETE"
Write-Host "   Merged: $MergedCount"
Write-Host "   Failed: $FailedCount"
if ($FailedBranches.Count -gt 0) {
    Write-Host ""
    Write-Host "   Failed branches:" -ForegroundColor Yellow
    foreach ($branch in $FailedBranches) {
        Write-Host "      - $branch"
    }
    Write-Host ""
    Write-Host "   To manually merge a failed branch:" -ForegroundColor Gray
    Write-Host "      git merge <branch-name>" -ForegroundColor Gray
    Write-Host "      # resolve conflicts" -ForegroundColor Gray
    Write-Host "      git add . && git commit" -ForegroundColor Gray
}
Write-Host "========================================================"

if ($MergedCount -gt 0) {
    Write-Host ""
    Write-Host "Push merged changes to origin? (git push origin $TargetBranch)"
    Write-Host "   Run: git push origin $TargetBranch" -ForegroundColor Cyan
}

exit $FailedCount
