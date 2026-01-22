# Ralph Moss - Autonomous AI agent loop with fresh context per iteration
# Usage: .\ralph.ps1 [-PrdPath "prds/my-feature"] [-MaxStories 3] [-MaxIterations 10] [-DryRun] [-Engine <name>]
#
# Supported Engines: claude (default), cursor, codex, opencode, qwen, copilot, droid
#
# Examples:
#   .\ralph.ps1 -PrdPath "prds/fix-property-enrich-500" -MaxStories 2
#   .\ralph.ps1 -PrdPath "prds/comprehensive-requirement-details"
#   .\ralph.ps1 -DryRun                                              # Preview what would be executed
#   .\ralph.ps1 -Engine cursor                                       # Use Cursor AI instead of Claude
#   .\ralph.ps1 -Engine codex -MaxIterations 10                      # Use Codex with 10 iterations
#
# Or run from a prds/ subdirectory:
#   cd scripts\ralph-moss\prds\my-feature
#   ..\..\ralph.ps1
#   ..\..\ralph.ps1 -DryRun                                          # Dry run from subdirectory
#   ..\..\ralph.ps1 -Engine copilot                                  # Use GitHub Copilot
#
# Quality Gate Options:
#   -QualityGate     Run typecheck/lint/test after each iteration
#   -Strict          Fail quality gate on lint warnings
#   -SkipTests       Skip unit tests (faster iteration)
#   -SkipLint        Skip ESLint
#
# Auto PR Options:
#   -AutoPR          Create GitHub PR when all stories complete
#   -Draft           Create PR as draft (requires -AutoPR)
#
# Each PRD lives in its own directory and is never deleted.
# Multiple PRDs can run concurrently with ralph-all.ps1

param(
    [string]$PrdPath = "",
    [int]$MaxStories = 0,
    [int]$MaxIterations = 15,
    [int]$SleepSeconds = 2,
    [switch]$DryRun,
    [ValidateSet("claude", "cursor", "codex", "opencode", "qwen", "copilot", "droid")]
    [string]$Engine = "claude",
    [switch]$QualityGate,
    [switch]$Strict,
    [switch]$SkipTests,
    [switch]$SkipLint,
    [switch]$AutoPR,
    [switch]$Draft
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Engine configuration - command and flags for each supported engine
$EngineConfig = @{
    "claude" = @{
        Command = "claude"
        Flags = @("--dangerously-skip-permissions", "-p")
        Name = "Claude Code"
    }
    "cursor" = @{
        Command = "cursor"
        Flags = @("--yes")
        Name = "Cursor"
    }
    "codex" = @{
        Command = "codex"
        Flags = @("--full-auto")
        Name = "Codex"
    }
    "opencode" = @{
        Command = "opencode"
        Flags = @()
        Name = "OpenCode"
    }
    "qwen" = @{
        Command = "qwen"
        Flags = @("--yes")
        Name = "Qwen-Code"
    }
    "copilot" = @{
        Command = "gh"
        Flags = @("copilot", "--yes")
        Name = "GitHub Copilot"
    }
    "droid" = @{
        Command = "droid"
        Flags = @("--auto")
        Name = "Factory Droid"
    }
}

$CurrentEngine = $EngineConfig[$Engine]

# Determine working directory
if ($PrdPath) {
    # Use provided path (relative to script directory)
    $FullPrdPath = Join-Path $PSScriptRoot $PrdPath
    if (Test-Path (Join-Path $FullPrdPath "prd.json")) {
        $WorkDir = $FullPrdPath
    } elseif (Test-Path $PrdPath) {
        # Absolute path provided
        $WorkDir = $PrdPath
    } else {
        Write-Error "PRD not found at: $FullPrdPath"
        exit 1
    }
} elseif (Test-Path "./prd.json") {
    $WorkDir = (Get-Location).Path
} elseif (Test-Path "$PSScriptRoot/prd.json") {
    $WorkDir = $PSScriptRoot
} else {
    Write-Error "No prd.json found. Use -PrdPath to specify location, e.g.: -PrdPath 'prds/my-feature'"
    exit 1
}

$ScriptDir = $PSScriptRoot
$PrdFile = Join-Path $WorkDir "prd.json"
$ProgressFile = Join-Path $WorkDir "progress.txt"
$PromptFile = Join-Path $ScriptDir "prompt-claude.md"

# Get repo root directory
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) {
    $RepoRoot = (Get-Item $ScriptDir).Parent.Parent.FullName
}

# Function to sync PRD learning files back to main
# This ensures prd.json (with passes/notes) and progress.txt persist
function Sync-PrdToMain {
    param([string]$WorkDir, [string]$RepoRoot)

    try {
        # Get relative path from repo root
        $RelativePath = $WorkDir.Replace($RepoRoot, "").TrimStart("\", "/")

        # Get current branch
        $CurrentBranch = git branch --show-current 2>$null
        if (-not $CurrentBranch -or $CurrentBranch -eq "main") {
            Write-Host "  [Sync] Already on main or no branch - skipping sync" -ForegroundColor Gray
            return
        }

        Write-Host ""
        Write-Host "  [Sync] Preserving PRD learning files to main..." -ForegroundColor Cyan

        # Commit any uncommitted PRD changes on current branch first
        $prdStatus = git status --porcelain "$RelativePath/prd.json" "$RelativePath/progress.txt" 2>$null
        if ($prdStatus) {
            git add "$RelativePath/prd.json" "$RelativePath/progress.txt" 2>$null
            git commit -m "chore: Update PRD progress for $CurrentBranch" 2>$null
        }

        # Stash any other changes
        $hasStash = $false
        $stashOutput = git stash push -m "ralph-moss-sync-temp" 2>&1
        if ($stashOutput -notmatch "No local changes") {
            $hasStash = $true
        }

        # Checkout main and pull latest
        git checkout main 2>$null
        git pull origin main 2>$null

        # Copy PRD files from feature branch
        git checkout $CurrentBranch -- "$RelativePath/prd.json" 2>$null
        if (Test-Path "$WorkDir/progress.txt") {
            git checkout $CurrentBranch -- "$RelativePath/progress.txt" 2>$null
        }

        # Commit and push to main
        $hasChanges = git status --porcelain "$RelativePath" 2>$null
        if ($hasChanges) {
            git add "$RelativePath/prd.json" "$RelativePath/progress.txt" 2>$null
            git commit -m "chore: Sync completed PRD from $CurrentBranch" 2>$null
            git push origin main 2>$null
            Write-Host "  [Sync] PRD files synced to main" -ForegroundColor Green
        } else {
            Write-Host "  [Sync] PRD files already up to date on main" -ForegroundColor Gray
        }

        # Return to feature branch
        git checkout $CurrentBranch 2>$null

        # Restore stash if we had one
        if ($hasStash) {
            git stash pop 2>$null
        }

    } catch {
        Write-Warning "  [Sync] Could not sync to main: $($_.Exception.Message)"
        # Try to get back to original branch
        git checkout $CurrentBranch 2>$null
    }
}

# Function to create a Pull Request when all stories are complete
function New-RalphPullRequest {
    param(
        [string]$WorkDir,
        [string]$PrdFile,
        [switch]$Draft
    )

    try {
        # Check if gh CLI is available
        $ghCheck = Get-Command gh -ErrorAction SilentlyContinue
        if (-not $ghCheck) {
            Write-Warning "  [PR] GitHub CLI (gh) not found. Install it to enable auto PR creation."
            return $null
        }

        # Check if authenticated
        $authStatus = gh auth status 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  [PR] GitHub CLI not authenticated. Run 'gh auth login' first."
            return $null
        }

        # Load PRD for metadata
        $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json

        # Get current branch
        $CurrentBranch = git branch --show-current 2>$null
        if (-not $CurrentBranch -or $CurrentBranch -eq "main") {
            Write-Warning "  [PR] Cannot create PR from main branch"
            return $null
        }

        Write-Host ""
        Write-Host "  [PR] Creating Pull Request..." -ForegroundColor Cyan

        # Push branch to origin first
        Write-Host "  [PR] Pushing branch to origin..." -ForegroundColor Gray
        git push -u origin $CurrentBranch 2>$null

        # Check if PR already exists
        $existingPR = gh pr view $CurrentBranch --json url 2>$null | ConvertFrom-Json
        if ($existingPR -and $existingPR.url) {
            Write-Host "  [PR] PR already exists: $($existingPR.url)" -ForegroundColor Green

            # Update prd.json with PR URL
            $prd | Add-Member -NotePropertyName "prUrl" -NotePropertyValue $existingPR.url -Force
            $prd | ConvertTo-Json -Depth 10 | Set-Content $PrdFile

            return $existingPR.url
        }

        # Build PR title from PRD
        $prTitle = if ($prd.project) { $prd.project } else { $CurrentBranch }
        if ($prd.description) {
            $prTitle = "$prTitle - $($prd.description.Substring(0, [Math]::Min(50, $prd.description.Length)))"
            if ($prd.description.Length -gt 50) { $prTitle += "..." }
        }

        # Build PR body with completed stories
        $storyList = ""
        foreach ($story in $prd.userStories) {
            $status = if ($story.passes) { "[x]" } else { "[ ]" }
            $storyList += "- $status $($story.id): $($story.title)`n"
        }

        $prBody = @"
## Summary
Automated PR from Ralph Moss for: **$($prd.project)**

$($prd.description)

## Completed Stories
$storyList

## Test Plan
- [ ] Verify changes on preview deployment
- [ ] Review code changes
- [ ] Run test suite

---
*Generated by Ralph Moss Autonomous Agent*
"@

        # Create PR
        $prArgs = @("pr", "create", "--title", $prTitle, "--body", $prBody, "--base", "main")
        if ($Draft) {
            $prArgs += "--draft"
        }

        $prOutput = & gh @prArgs 2>&1
        $prExitCode = $LASTEXITCODE

        if ($prExitCode -eq 0 -and $prOutput -match "https://") {
            $prUrl = ($prOutput | Select-String -Pattern "https://[^\s]+").Matches[0].Value
            Write-Host "  [PR] Created: $prUrl" -ForegroundColor Green

            # Update prd.json with PR URL
            $prd | Add-Member -NotePropertyName "prUrl" -NotePropertyValue $prUrl -Force
            $prd | ConvertTo-Json -Depth 10 | Set-Content $PrdFile

            return $prUrl
        } else {
            Write-Warning "  [PR] Failed to create PR: $prOutput"
            return $null
        }

    } catch {
        Write-Warning "  [PR] Error creating PR: $($_.Exception.Message)"
        return $null
    }
}

# Initialize progress file if missing
if (-not (Test-Path $ProgressFile)) {
    try {
        $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $BranchName = if ($prd.branchName) { $prd.branchName } else { "unknown" }
    } catch {
        $BranchName = "unknown"
    }
    @"
# Ralph Moss Progress Log
Started: $(Get-Date)
Feature: $BranchName

## Codebase Patterns
(Patterns discovered during implementation)

---
"@ | Set-Content $ProgressFile
}

# ===================================================================
# MAIN LOOP - Fresh AI session per iteration (no context rot)
# ===================================================================
try {
    $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json
    $Project = if ($prd.project) { $prd.project } else { "Project" }
} catch {
    $Project = "Project"
}

Write-Host ""
Write-Host "[Ralph Moss] Starting..." -ForegroundColor Cyan
Write-Host "   Project: $Project"
Write-Host "   PRD: $PrdFile"
Write-Host "   Engine: $($CurrentEngine.Name)" -ForegroundColor Magenta
Write-Host "   Max iterations: $MaxIterations"
if ($MaxStories -gt 0) {
    Write-Host "   Max stories: $MaxStories"
}
if ($DryRun) {
    Write-Host "   Mode: DRY RUN (no changes will be made)" -ForegroundColor Yellow
}
if ($QualityGate) {
    $strictDisplay = if ($Strict) { " (strict)" } else { "" }
    $skipDisplay = @()
    if ($SkipTests) { $skipDisplay += "tests" }
    if ($SkipLint) { $skipDisplay += "lint" }
    $skipStr = if ($skipDisplay.Count -gt 0) { " [skip: $($skipDisplay -join ', ')]" } else { "" }
    Write-Host "   Quality gate: enabled$strictDisplay$skipStr" -ForegroundColor Green
}
if ($AutoPR) {
    $draftDisplay = if ($Draft) { " (draft)" } else { "" }
    Write-Host "   Auto PR: enabled$draftDisplay" -ForegroundColor Cyan
}
Write-Host ""

# ===================================================================
# DRY RUN MODE - Show what would be executed without running AI
# ===================================================================
if ($DryRun) {
    Write-Host "===========================================================" -ForegroundColor Magenta
    Write-Host "  DRY RUN - Showing what would be executed" -ForegroundColor Magenta
    Write-Host "===========================================================" -ForegroundColor Magenta
    Write-Host ""

    # Load and display PRD details
    try {
        $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json

        Write-Host "[PRD Information]" -ForegroundColor Cyan
        Write-Host "   Branch: $($prd.branchName)" -ForegroundColor White
        Write-Host "   Description: $($prd.description)" -ForegroundColor White
        Write-Host ""

        # Display all user stories with status
        Write-Host "[User Stories]" -ForegroundColor Cyan
        $storyNum = 0
        foreach ($story in $prd.userStories) {
            $storyNum++
            $status = if ($story.passes) { "[DONE]" } else { "[TODO]" }
            $statusColor = if ($story.passes) { "Green" } else { "Yellow" }
            Write-Host "   $status $($story.id): $($story.title)" -ForegroundColor $statusColor

            # Show acceptance criteria for pending stories
            if (-not $story.passes -and $story.acceptanceCriteria) {
                foreach ($criterion in $story.acceptanceCriteria) {
                    Write-Host "      - $criterion" -ForegroundColor Gray
                }
            }
        }
        Write-Host ""

        # Show next story to be executed
        $nextStory = $prd.userStories | Where-Object { -not $_.passes } | Select-Object -First 1
        if ($nextStory) {
            Write-Host "[Next Iteration Would Execute]" -ForegroundColor Cyan
            Write-Host "   Story: $($nextStory.id) - $($nextStory.title)" -ForegroundColor White
            Write-Host "   Description: $($nextStory.description)" -ForegroundColor Gray
            if ($nextStory.PSObject.Properties['technicalDetails'] -and $nextStory.technicalDetails.PSObject.Properties['filesAffected']) {
                Write-Host "   Files affected:" -ForegroundColor Gray
                foreach ($file in $nextStory.technicalDetails.filesAffected) {
                    Write-Host "      - $file" -ForegroundColor Gray
                }
            }
            Write-Host ""

            # Show command that would be run
            Write-Host "[Command That Would Run]" -ForegroundColor Cyan
            $flagsStr = if ($CurrentEngine.Flags.Count -gt 0) { " " + ($CurrentEngine.Flags -join " ") } else { "" }
            Write-Host "   $($CurrentEngine.Command)$flagsStr < prompt.tmp" -ForegroundColor White
            Write-Host "   Engine: $($CurrentEngine.Name)" -ForegroundColor Magenta
            Write-Host ""

            # Show prompt file info
            Write-Host "[Prompt File]" -ForegroundColor Cyan
            Write-Host "   Location: $PromptFile" -ForegroundColor White
            $promptLines = (Get-Content $PromptFile | Measure-Object -Line).Lines
            Write-Host "   Lines: $promptLines" -ForegroundColor White
            Write-Host ""
        } else {
            Write-Host "[Status]" -ForegroundColor Cyan
            Write-Host "   All stories are already complete!" -ForegroundColor Green
            Write-Host ""
        }

        # Summary
        $total = @($prd.userStories).Count
        $done = @($prd.userStories | Where-Object { $_.passes -eq $true }).Count
        $remaining = $total - $done
        Write-Host "[Summary]" -ForegroundColor Cyan
        Write-Host "   Total stories: $total" -ForegroundColor White
        Write-Host "   Completed: $done" -ForegroundColor Green
        Write-Host "   Remaining: $remaining" -ForegroundColor Yellow
        if ($remaining -gt 0) {
            $estimatedIterations = [Math]::Min($remaining, $MaxIterations)
            Write-Host "   Estimated iterations needed: $estimatedIterations" -ForegroundColor White
        }
        Write-Host ""

    } catch {
        Write-Warning "Could not parse PRD file: $($_.Exception.Message)"
    }

    Write-Host "===========================================================" -ForegroundColor Magenta
    Write-Host "  DRY RUN COMPLETE - No changes were made" -ForegroundColor Magenta
    Write-Host "  Remove -DryRun flag to execute for real" -ForegroundColor Magenta
    Write-Host "===========================================================" -ForegroundColor Magenta
    exit 0
}

# Track how many stories we've completed this run
$StoriesCompletedThisRun = 0

for ($i = 1; $i -le $MaxIterations; $i++) {
    # Show progress
    $NextStory = $null
    try {
        $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $Total = @($prd.userStories).Count
        $Done = @($prd.userStories | Where-Object { $_.passes -eq $true }).Count
        $NextStory = $prd.userStories | Where-Object { -not $_.passes } | Select-Object -First 1
        $Next = if ($NextStory) { "$($NextStory.id): $($NextStory.title)" } else { "None - ALL COMPLETE" }
    } catch {
        $Total = "?"
        $Done = "?"
        $Next = "Unknown"
    }

    # Check if already complete before starting iteration
    if ($null -eq $NextStory) {
        Write-Host ""
        Write-Host "===========================================================" -ForegroundColor Green
        Write-Host "  [OK] All tasks already complete!" -ForegroundColor Green
        Write-Host "===========================================================" -ForegroundColor Green
        if ($AutoPR) {
            New-RalphPullRequest -WorkDir $WorkDir -PrdFile $PrdFile -Draft:$Draft
        }
        Sync-PrdToMain -WorkDir $WorkDir -RepoRoot $RepoRoot
        exit 0
    }

    Write-Host "===========================================================" -ForegroundColor Yellow
    Write-Host "  Iteration $i of $MaxIterations  |  Progress: $Done/$Total" -ForegroundColor Yellow
    Write-Host "  Next: $Next" -ForegroundColor Yellow
    Write-Host "===========================================================" -ForegroundColor Yellow
    Write-Host ""

    # Read prompt and inject working directory context
    $PromptContent = Get-Content $PromptFile -Raw
    $Prompt = @"
Working directory: $WorkDir

$PromptContent
"@

    # Save prompt to temp file and pipe to AI engine (avoids command line length limits)
    $PromptTmp = Join-Path $WorkDir "prompt.tmp"
    $Prompt | Set-Content -Path $PromptTmp -Encoding UTF8

    # Run AI engine with the prompt
    # Uses stdin piping which works on most systems
    Push-Location $WorkDir
    $Output = ""
    $exitCode = 0
    try {
        Write-Host "  Running $($CurrentEngine.Name)..." -ForegroundColor Gray

        # Run engine and capture output - the prompt is piped via stdin
        $engineCmd = $CurrentEngine.Command
        $engineFlags = $CurrentEngine.Flags
        $result = Get-Content -Path $PromptTmp -Raw | & $engineCmd @engineFlags 2>&1
        $exitCode = $LASTEXITCODE

        # Process and display output
        $Output = ""
        if ($result) {
            foreach ($line in $result) {
                $lineStr = if ($line -is [System.Management.Automation.ErrorRecord]) {
                    $line.ToString()
                } else {
                    $line.ToString()
                }
                # Filter out benign errors
                if ($lineStr -notmatch "No messages returned" -and
                    $lineStr -notmatch "promise which was not handled" -and
                    $lineStr -notmatch "rejecting a promise" -and
                    $lineStr -notmatch "ExperimentalWarning") {
                    Write-Host $lineStr
                    $Output += $lineStr + "`n"
                }
            }
        }

        # If exit code is 1 but we got meaningful output, it might have worked
        if ($exitCode -eq 1 -and $Output.Length -gt 100) {
            Write-Host "  Note: $($CurrentEngine.Name) exited with code 1 but produced output" -ForegroundColor Gray
        }

        # Debug: If engine failed immediately with no output, show more info
        if ($exitCode -ne 0 -and $Output.Length -lt 50) {
            Write-Host ""
            Write-Host "  [DEBUG] $($CurrentEngine.Name) exit code: $exitCode" -ForegroundColor Yellow
            Write-Host "  [DEBUG] Output length: $($Output.Length) chars" -ForegroundColor Yellow
            if ($Output.Length -gt 0) {
                Write-Host "  [DEBUG] Output: $Output" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "  Troubleshooting tips:" -ForegroundColor Cyan
            Write-Host "  1. Run '$($CurrentEngine.Command)' interactively to verify it's installed" -ForegroundColor Cyan
            Write-Host "  2. Check if there are any API errors in the output above" -ForegroundColor Cyan
            Write-Host "  3. Try running: $($CurrentEngine.Command) --help" -ForegroundColor Cyan
            Write-Host ""
        }

    } catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "$($CurrentEngine.Name) error: $errorMsg"
        $exitCode = 1
    } finally {
        Pop-Location
    }

    # Cleanup temp file
    Remove-Item $PromptTmp -Force -ErrorAction SilentlyContinue

    Write-Host ""

    # Check for completion signal in output (like bash script does)
    if ($Output -match "<promise>COMPLETE</promise>") {
        Write-Host ""
        Write-Host "===========================================================" -ForegroundColor Green
        Write-Host "  [OK] All tasks complete after $i iterations!" -ForegroundColor Green
        Write-Host "===========================================================" -ForegroundColor Green
        if ($AutoPR) {
            New-RalphPullRequest -WorkDir $WorkDir -PrdFile $PrdFile -Draft:$Draft
        }
        Sync-PrdToMain -WorkDir $WorkDir -RepoRoot $RepoRoot
        exit 0
    }

    if ($exitCode -ne 0) {
        # Only warn if not due to the expected "no messages" completion scenario
        Write-Host "  $($CurrentEngine.Name) exited with code $exitCode (continuing to next iteration)" -ForegroundColor Yellow
    }

    # Run quality gate after each iteration
    if ($QualityGate) {
        $QualityGateScript = Join-Path $ScriptDir "quality-gate.ps1"
        if (Test-Path $QualityGateScript) {
            Write-Host ""
            Write-Host "Running quality gate..." -ForegroundColor Cyan

            $gateArgs = @()
            if ($Strict) { $gateArgs += "-Strict" }
            if ($SkipTests) { $gateArgs += "-SkipTests" }
            if ($SkipLint) { $gateArgs += "-SkipLint" }

            & $QualityGateScript @gateArgs
            $gateExitCode = $LASTEXITCODE

            if ($gateExitCode -ne 0) {
                Write-Host ""
                Write-Host "  Quality gate FAILED (exit code $gateExitCode)" -ForegroundColor Yellow
                Write-Host "  Next iteration will attempt to fix the issues." -ForegroundColor Yellow
                # Don't exit - let next iteration fix
            } else {
                Write-Host "  Quality gate passed" -ForegroundColor Green
            }
        } else {
            Write-Warning "Quality gate script not found at: $QualityGateScript"
        }
    }

    # Check PRD for completion (since we can't capture output with streaming)
    try {
        $prdAfter = Get-Content $PrdFile -Raw | ConvertFrom-Json
        $remainingAfter = @($prdAfter.userStories | Where-Object { -not $_.passes }).Count
        $doneAfter = @($prdAfter.userStories | Where-Object { $_.passes -eq $true }).Count

        # Check if a story was completed this iteration
        if ($doneAfter -gt $Done) {
            $StoriesCompletedThisRun += ($doneAfter - $Done)
            Write-Host "  Story completed! ($StoriesCompletedThisRun completed this run)" -ForegroundColor Green
        }

        # Check if all done
        if ($remainingAfter -eq 0) {
            Write-Host ""
            Write-Host "===========================================================" -ForegroundColor Green
            Write-Host "  [OK] All tasks complete after $i iterations!" -ForegroundColor Green
            Write-Host "===========================================================" -ForegroundColor Green
            if ($AutoPR) {
                New-RalphPullRequest -WorkDir $WorkDir -PrdFile $PrdFile -Draft:$Draft
            }
            Sync-PrdToMain -WorkDir $WorkDir -RepoRoot $RepoRoot
            exit 0
        }

        # Check if we've hit MaxStories limit
        if ($MaxStories -gt 0 -and $StoriesCompletedThisRun -ge $MaxStories) {
            Write-Host ""
            Write-Host "===========================================================" -ForegroundColor Green
            Write-Host "  [OK] Completed $StoriesCompletedThisRun stories (max reached)" -ForegroundColor Green
            Write-Host "  Remaining: $remainingAfter stories" -ForegroundColor Yellow
            Write-Host "===========================================================" -ForegroundColor Green
            # Only create PR if all stories are actually done
            if ($AutoPR -and $remainingAfter -eq 0) {
                New-RalphPullRequest -WorkDir $WorkDir -PrdFile $PrdFile -Draft:$Draft
            }
            Sync-PrdToMain -WorkDir $WorkDir -RepoRoot $RepoRoot
            exit 0
        }
    } catch {
        Write-Warning "Could not read PRD file to check completion"
    }

    Write-Host "Iteration $i complete. Sleeping ${SleepSeconds}s..." -ForegroundColor Cyan
    Write-Host ""
    Start-Sleep -Seconds $SleepSeconds
}

Write-Host ""
Write-Host "===========================================================" -ForegroundColor Yellow
Write-Host "  [WARN] Reached max iterations ($MaxIterations)" -ForegroundColor Yellow
Write-Host "  Check $ProgressFile for status" -ForegroundColor Yellow
Write-Host "===========================================================" -ForegroundColor Yellow
exit 1
