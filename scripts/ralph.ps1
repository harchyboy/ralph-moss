# Ralph Moss - Autonomous AI agent loop with fresh context per iteration
# Usage: .\ralph.ps1 [-PrdPath "prds/my-feature"] [-MaxStories 3] [-MaxIterations 10]
#
# Examples:
#   .\ralph.ps1 -PrdPath "prds/fix-property-enrich-500" -MaxStories 2
#   .\ralph.ps1 -PrdPath "prds/comprehensive-requirement-details"
#
# Or run from a prds/ subdirectory:
#   cd scripts\ralph-moss\prds\my-feature
#   ..\..\ralph.ps1
#
# Each PRD lives in its own directory and is never deleted.
# Multiple PRDs can run concurrently with ralph-all.ps1

param(
    [string]$PrdPath = "",
    [int]$MaxStories = 0,
    [int]$MaxIterations = 15,
    [int]$SleepSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
# MAIN LOOP - Fresh Claude session per iteration (no context rot)
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
Write-Host "   Max iterations: $MaxIterations"
if ($MaxStories -gt 0) {
    Write-Host "   Max stories: $MaxStories"
}
Write-Host ""

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

    # Save prompt to temp file and pipe to Claude (avoids command line length limits)
    $PromptTmp = Join-Path $WorkDir "prompt.tmp"
    $Prompt | Set-Content -Path $PromptTmp -Encoding UTF8

    # Run Claude with the prompt
    # Uses stdin piping which works on most systems
    Push-Location $WorkDir
    $Output = ""
    $exitCode = 0
    try {
        Write-Host "  Running Claude..." -ForegroundColor Gray

        # Run Claude and capture output - let it run interactively with -p flag
        # The prompt is piped via stdin
        $result = Get-Content -Path $PromptTmp -Raw | & claude --dangerously-skip-permissions -p 2>&1
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
            Write-Host "  Note: Claude exited with code 1 but produced output" -ForegroundColor Gray
        }

        # Debug: If Claude failed immediately with no output, show more info
        if ($exitCode -ne 0 -and $Output.Length -lt 50) {
            Write-Host ""
            Write-Host "  [DEBUG] Claude exit code: $exitCode" -ForegroundColor Yellow
            Write-Host "  [DEBUG] Output length: $($Output.Length) chars" -ForegroundColor Yellow
            if ($Output.Length -gt 0) {
                Write-Host "  [DEBUG] Output: $Output" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "  Troubleshooting tips:" -ForegroundColor Cyan
            Write-Host "  1. Run 'claude' interactively to verify authentication" -ForegroundColor Cyan
            Write-Host "  2. Check if there are any API errors in the output above" -ForegroundColor Cyan
            Write-Host "  3. Try running: claude -p 'Hello'" -ForegroundColor Cyan
            Write-Host ""
        }

    } catch {
        $errorMsg = $_.Exception.Message
        Write-Warning "Claude error: $errorMsg"
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
        exit 0
    }

    if ($exitCode -ne 0) {
        # Only warn if not due to the expected "no messages" completion scenario
        Write-Host "  Claude exited with code $exitCode (continuing to next iteration)" -ForegroundColor Yellow
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
            exit 0
        }

        # Check if we've hit MaxStories limit
        if ($MaxStories -gt 0 -and $StoriesCompletedThisRun -ge $MaxStories) {
            Write-Host ""
            Write-Host "===========================================================" -ForegroundColor Green
            Write-Host "  [OK] Completed $StoriesCompletedThisRun stories (max reached)" -ForegroundColor Green
            Write-Host "  Remaining: $remainingAfter stories" -ForegroundColor Yellow
            Write-Host "===========================================================" -ForegroundColor Green
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
