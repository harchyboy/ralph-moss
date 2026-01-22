# Ralph Moss Concurrent - Run multiple PRDs in parallel
# Usage: .\ralph-all.ps1 [-MaxIterations 10] [-UseWorktrees] [-AutoPR] [-DraftPR]
#
# Spawns a Ralph Moss instance for each PRD in prds/ directory
# Each runs independently with fresh context per micro-task
#
# Worktree Options:
#   -UseWorktrees      Run each PRD in isolated git worktree (prevents conflicts)
#   -CleanupWorktrees  Remove worktrees after completion (default: keep for PR review)
#
# Auto PR Options:
#   -AutoPR            Create GitHub PR when each PRD completes
#   -DraftPR           Create PRs as drafts (requires -AutoPR)
#
# Examples:
#   .\ralph-all.ps1 -MaxIterations 15
#   .\ralph-all.ps1 -UseWorktrees -MaxIterations 15
#   .\ralph-all.ps1 -UseWorktrees -AutoPR -MaxIterations 15
#   .\ralph-all.ps1 -UseWorktrees -AutoPR -DraftPR -MaxIterations 15

param(
    [int]$MaxIterations = 10,
    [switch]$UseWorktrees,
    [switch]$CleanupWorktrees,
    [switch]$AutoPR,
    [switch]$DraftPR
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$PrdsDir = Join-Path $ScriptDir "prds"
$LogDir = Join-Path $ScriptDir "logs"
$WorktreeRoot = Join-Path $ScriptDir ".worktrees"

# Get repo root directory
$RepoRoot = git rev-parse --show-toplevel 2>$null
if (-not $RepoRoot) {
    $RepoRoot = (Get-Item $ScriptDir).Parent.Parent.FullName
}

# ===================================================================
# WORKTREE FUNCTIONS
# ===================================================================

function New-RalphWorktree {
    param(
        [string]$PrdName,
        [string]$BranchName,
        [string]$WorktreeRoot
    )

    $WorktreePath = Join-Path $WorktreeRoot $PrdName

    # Remove existing worktree if present
    if (Test-Path $WorktreePath) {
        Write-Host "   Removing existing worktree: $PrdName" -ForegroundColor Gray
        git worktree remove $WorktreePath --force 2>$null
    }

    # Check if branch exists on remote
    $remoteBranch = git branch -r --list "origin/$BranchName" 2>$null

    if ($remoteBranch) {
        # Branch exists remotely, check it out
        Write-Host "   Creating worktree from existing branch: $BranchName" -ForegroundColor Gray
        git worktree add $WorktreePath $BranchName 2>$null
    } else {
        # Create new branch from main
        Write-Host "   Creating worktree with new branch: $BranchName" -ForegroundColor Gray
        git worktree add -B $BranchName $WorktreePath main 2>$null
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to create worktree for $PrdName"
        return $null
    }

    return $WorktreePath
}

function Remove-RalphWorktree {
    param(
        [string]$PrdName,
        [string]$WorktreeRoot
    )

    $WorktreePath = Join-Path $WorktreeRoot $PrdName

    if (Test-Path $WorktreePath) {
        Write-Host "   Cleaning up worktree: $PrdName" -ForegroundColor Gray
        git worktree remove $WorktreePath --force 2>$null
    }
}

function Copy-PrdToWorktree {
    param(
        [string]$SourcePrdPath,
        [string]$WorktreePath,
        [string]$PrdName
    )

    # Calculate relative path from repo root to prds directory
    $RelativeScriptPath = $ScriptDir.Replace($RepoRoot, "").TrimStart("\", "/")

    # Create the target PRD directory in the worktree
    $TargetPrdDir = Join-Path $WorktreePath $RelativeScriptPath "prds" $PrdName
    New-Item -ItemType Directory -Path $TargetPrdDir -Force | Out-Null

    # Copy PRD files
    Copy-Item -Path (Join-Path $SourcePrdPath "*") -Destination $TargetPrdDir -Recurse -Force

    return $TargetPrdDir
}

# Ensure prds directory exists
if (-not (Test-Path $PrdsDir)) {
    Write-Host "No prds/ directory found. Create PRDs with:"
    Write-Host ""
    Write-Host "  mkdir $PrdsDir\my-feature"
    Write-Host "  cd $PrdsDir\my-feature"
    Write-Host '  claude "/prd [describe your feature]"'
    Write-Host ""
    exit 1
}

# Create logs directory
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

# Find all PRDs with incomplete tasks
$ActivePrds = @()
Get-ChildItem -Path $PrdsDir -Directory | ForEach-Object {
    $PrdFile = Join-Path $_.FullName "prd.json"
    if (Test-Path $PrdFile) {
        try {
            $prd = Get-Content $PrdFile -Raw | ConvertFrom-Json
            $Incomplete = ($prd.userStories | Where-Object { $_.passes -eq $false }).Count
            if ($Incomplete -gt 0) {
                $ActivePrds += @{
                    Path = $_.FullName
                    Name = $_.Name
                    Prd = $prd
                    Incomplete = $Incomplete
                }
            }
        } catch {
            Write-Warning "Could not parse $PrdFile"
        }
    }
}

if ($ActivePrds.Count -eq 0) {
    Write-Host "No active PRDs found (all complete or none exist)"
    Write-Host ""
    Write-Host "Create a new PRD:"
    Write-Host "  mkdir $PrdsDir\my-feature; cd `$_"
    Write-Host '  claude "/prd [describe your feature]"'
    exit 0
}

Write-Host ""
Write-Host "Ralph Moss Concurrent"
Write-Host "========================================================"
Write-Host "   Active PRDs: $($ActivePrds.Count)"
Write-Host "   Max iterations per PRD: $MaxIterations"
Write-Host "   Logs: $LogDir\"
if ($UseWorktrees) {
    Write-Host "   Worktrees: enabled (isolated parallel execution)" -ForegroundColor Cyan
    Write-Host "   Worktree root: $WorktreeRoot"
    if ($CleanupWorktrees) {
        Write-Host "   Cleanup: will remove worktrees after completion" -ForegroundColor Yellow
    } else {
        Write-Host "   Cleanup: worktrees will be kept for PR review" -ForegroundColor Gray
    }
}
if ($AutoPR) {
    $draftDisplay = if ($DraftPR) { " (draft)" } else { "" }
    Write-Host "   Auto PR: enabled$draftDisplay" -ForegroundColor Cyan
}
Write-Host "========================================================"
Write-Host ""

# Create worktree root if using worktrees
if ($UseWorktrees) {
    New-Item -ItemType Directory -Path $WorktreeRoot -Force | Out-Null
    Write-Host "Setting up worktrees..."
}

# Track jobs
$Jobs = @()

# Spawn Ralph for each active PRD
foreach ($prdInfo in $ActivePrds) {
    $PrdName = $prdInfo.Name
    $PrdPath = $prdInfo.Path
    $Project = if ($prdInfo.Prd.project) { $prdInfo.Prd.project } else { "Unknown" }
    $BranchName = if ($prdInfo.Prd.branchName) { $prdInfo.Prd.branchName } else { "ralph-moss/$PrdName" }
    $Total = $prdInfo.Prd.userStories.Count
    $Done = ($prdInfo.Prd.userStories | Where-Object { $_.passes -eq $true }).Count

    $LogFile = Join-Path $LogDir "$Timestamp-$PrdName.log"

    Write-Host "[PRD] $PrdName ($Project) - $Done/$Total done"
    Write-Host "   Log: $LogFile"

    # Determine execution path
    $ExecutionPath = $PrdPath
    $WorktreePath = $null

    if ($UseWorktrees) {
        # Create worktree for isolated execution
        $WorktreePath = New-RalphWorktree -PrdName $PrdName -BranchName $BranchName -WorktreeRoot $WorktreeRoot
        if ($WorktreePath) {
            # Copy PRD files to worktree
            $ExecutionPath = Copy-PrdToWorktree -SourcePrdPath $PrdPath -WorktreePath $WorktreePath -PrdName $PrdName
            Write-Host "   Worktree: $WorktreePath" -ForegroundColor Gray
        } else {
            Write-Warning "   Failed to create worktree, falling back to shared execution"
        }
    }

    # Build ralph arguments
    $RalphArgs = @("-MaxIterations", $MaxIterations)
    if ($AutoPR) {
        $RalphArgs += "-AutoPR"
        if ($DraftPR) {
            $RalphArgs += "-Draft"
        }
    }

    # Run Ralph in background as a job
    $RalphScript = Join-Path $ScriptDir "ralph.ps1"

    if ($UseWorktrees -and $WorktreePath) {
        # For worktrees, we need to run ralph.ps1 from within the worktree
        $WorktreeRalphScript = Join-Path $WorktreePath ($RalphScript.Replace($RepoRoot, "").TrimStart("\", "/"))
        $Job = Start-Job -ScriptBlock {
            param($Path, $Script, $RalphArgs)
            Set-Location $Path
            & $Script @RalphArgs
        } -ArgumentList $ExecutionPath, $WorktreeRalphScript, $RalphArgs
    } else {
        # Standard execution
        $Job = Start-Job -ScriptBlock {
            param($Path, $Script, $RalphArgs)
            Set-Location $Path
            & $Script @RalphArgs
        } -ArgumentList $ExecutionPath, $RalphScript, $RalphArgs
    }

    $Jobs += @{
        Job = $Job
        Name = $PrdName
        LogFile = $LogFile
        WorktreePath = $WorktreePath
    }
}

Write-Host ""
Write-Host "========================================================"
Write-Host "   All $($ActivePrds.Count) Ralph Moss instances spawned"
Write-Host "   Monitor with: Get-Content $LogDir\$Timestamp-*.log -Wait"
Write-Host "========================================================"
Write-Host ""

# Handle Ctrl+C
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Host ""
    Write-Host "Stopping all Ralph Moss instances..."
    Get-Job | Stop-Job -PassThru | Remove-Job
}

# Wait for all to complete and stream output to log files
Write-Host "Waiting for all Ralph Moss instances to complete..."
Write-Host "(Press Ctrl+C to stop all)"
Write-Host ""

$Failed = 0
$Completed = @()
foreach ($jobInfo in $Jobs) {
    $Job = $jobInfo.Job
    $PrdName = $jobInfo.Name
    $LogFile = $jobInfo.LogFile
    $WorktreePath = $jobInfo.WorktreePath

    # Wait for job and capture output
    $Job | Wait-Job | Out-Null
    $Output = Receive-Job -Job $Job

    # Write output to log file
    $Output | Out-File -FilePath $LogFile -Encoding utf8

    if ($Job.State -eq 'Completed') {
        # Check if the output indicates success
        if ($Output -match "All tasks complete") {
            Write-Host "[OK] $PrdName completed" -ForegroundColor Green
            $Completed += $jobInfo
        } else {
            Write-Host "[WARN] $PrdName finished (check log for status)" -ForegroundColor Yellow
            $Failed++
        }
    } else {
        Write-Host "[FAIL] $PrdName failed" -ForegroundColor Red
        $Failed++
    }

    Remove-Job -Job $Job
}

# Worktree cleanup
if ($UseWorktrees) {
    Write-Host ""
    if ($CleanupWorktrees) {
        Write-Host "Cleaning up worktrees..."
        foreach ($jobInfo in $Jobs) {
            if ($jobInfo.WorktreePath) {
                Remove-RalphWorktree -PrdName $jobInfo.Name -WorktreeRoot $WorktreeRoot
            }
        }
        # Clean up the worktree root if empty
        if ((Test-Path $WorktreeRoot) -and (Get-ChildItem $WorktreeRoot | Measure-Object).Count -eq 0) {
            Remove-Item $WorktreeRoot -Force 2>$null
        }
        Write-Host "Worktrees removed." -ForegroundColor Gray
    } else {
        Write-Host "Worktrees preserved for PR review:" -ForegroundColor Cyan
        foreach ($jobInfo in $Completed) {
            if ($jobInfo.WorktreePath) {
                Write-Host "   $($jobInfo.Name): $($jobInfo.WorktreePath)"
            }
        }
        Write-Host ""
        Write-Host "To clean up worktrees later, run:" -ForegroundColor Gray
        Write-Host "   git worktree list" -ForegroundColor Gray
        Write-Host "   git worktree remove <path>" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "========================================================"
if ($Failed -eq 0) {
    Write-Host "  [OK] All PRDs completed successfully!" -ForegroundColor Green
} else {
    Write-Host "  [WARN] $Failed PRD(s) may need attention" -ForegroundColor Yellow
    Write-Host "  Check logs: $LogDir\$Timestamp-*.log"
}
Write-Host "========================================================"

exit $Failed
