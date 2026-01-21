# Ralph Moss Concurrent - Run multiple PRDs in parallel
# Usage: .\ralph-all.ps1 [-MaxIterations 10]
#
# Spawns a Ralph Moss instance for each PRD in prds/ directory
# Each runs independently with fresh context per micro-task

param(
    [int]$MaxIterations = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$PrdsDir = Join-Path $ScriptDir "prds"
$LogDir = Join-Path $ScriptDir "logs"

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
Write-Host "🚀 Ralph Moss Concurrent"
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host "   Active PRDs: $($ActivePrds.Count)"
Write-Host "   Max iterations per PRD: $MaxIterations"
Write-Host "   Logs: $LogDir\"
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host ""

# Track jobs
$Jobs = @()

# Spawn Ralph for each active PRD
foreach ($prdInfo in $ActivePrds) {
    $PrdName = $prdInfo.Name
    $PrdPath = $prdInfo.Path
    $Project = if ($prdInfo.Prd.project) { $prdInfo.Prd.project } else { "Unknown" }
    $Total = $prdInfo.Prd.userStories.Count
    $Done = ($prdInfo.Prd.userStories | Where-Object { $_.passes -eq $true }).Count

    $LogFile = Join-Path $LogDir "$Timestamp-$PrdName.log"

    Write-Host "📦 $PrdName ($Project) - $Done/$Total done"
    Write-Host "   Log: $LogFile"

    # Run Ralph in background as a job
    $RalphScript = Join-Path $ScriptDir "ralph.ps1"
    $Job = Start-Job -ScriptBlock {
        param($Path, $Script, $MaxIter)
        Set-Location $Path
        & $Script -MaxIterations $MaxIter
    } -ArgumentList $PrdPath, $RalphScript, $MaxIterations

    $Jobs += @{
        Job = $Job
        Name = $PrdName
        LogFile = $LogFile
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════"
Write-Host "   All $($ActivePrds.Count) Ralph Moss instances spawned"
Write-Host "   Monitor with: Get-Content $LogDir\$Timestamp-*.log -Wait"
Write-Host "═══════════════════════════════════════════════════════════"
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
foreach ($jobInfo in $Jobs) {
    $Job = $jobInfo.Job
    $PrdName = $jobInfo.Name
    $LogFile = $jobInfo.LogFile

    # Wait for job and capture output
    $Job | Wait-Job | Out-Null
    $Output = Receive-Job -Job $Job

    # Write output to log file
    $Output | Out-File -FilePath $LogFile -Encoding utf8

    if ($Job.State -eq 'Completed') {
        # Check if the output indicates success
        if ($Output -match "All tasks complete") {
            Write-Host "✅ $PrdName completed"
        } else {
            Write-Host "⚠️  $PrdName finished (check log for status)"
            $Failed++
        }
    } else {
        Write-Host "❌ $PrdName failed"
        $Failed++
    }

    Remove-Job -Job $Job
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════"
if ($Failed -eq 0) {
    Write-Host "  ✅ All PRDs completed successfully!"
} else {
    Write-Host "  ⚠️  $Failed PRD(s) may need attention"
    Write-Host "  Check logs: $LogDir\$Timestamp-*.log"
}
Write-Host "═══════════════════════════════════════════════════════════"

exit $Failed
