<#
.SYNOPSIS
    Automated cleanup for stale node_modules directories on Windows.

.DESCRIPTION
    Sweepy finds and removes old, unused node_modules folders that are consuming disk space.
    It supports scanning, reporting, previewing, and interactive cleanup.

.PARAMETER Command
    The operation to perform: scan, clean, install-task, uninstall-task.

.PARAMETER Path
    (Scan) Comma-separated paths to search. Defaults to standard dev locations.

.PARAMETER Days
    (Scan) Number of days since last access/modification to consider stale. Default 14.

.PARAMETER OutFile
    (Scan) Custom output path for the report file.

.PARAMETER Legacy
    (Scan) Use node_modules folder LastAccessTime instead of package-lock.json LastWriteTime.

.PARAMETER Exclude
    (Scan) Patterns to exclude from search.

.PARAMETER Report
    (Clean) The report file to read paths from. Defaults to the latest report.

.PARAMETER Force
    (Clean) Skip the "Type DELETE" confirmation prompt.

.PARAMETER Interactive
    (Clean) Use a grid view (GUI) to select folders to delete.

.EXAMPLE
    .\sweepy.ps1 scan
    Scans default locations for stale node_modules.

.EXAMPLE
    .\sweepy.ps1 scan -Path C:\dev -Days 30
    Scans C:\dev for projects untouched for 30 days.

.EXAMPLE
    .\sweepy.ps1 clean -Report .\report.txt -WhatIf
    Previews what would be deleted from the report.

.EXAMPLE
    .\sweepy.ps1 clean
    Interactively cleans up based on the latest report.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('scan', 'clean', 'install-task', 'uninstall-task')]
    [string]$Command,

    # Scan Parameters
    [Parameter(ValueFromPipeline=$true)]
    [string[]]$Path,

    [int]$Days = 14,

    [Alias('Out')]
    [string]$OutFile,

    [switch]$Legacy,

    [string[]]$Exclude,

    # Clean Parameters
    [string]$Report,

    [switch]$Force,

    [switch]$Interactive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Configuration & Constants ---
$AppName = "Sweepy"
$HomeDir = "$HOME\.sweepy"
$ReportsDir = "$HomeDir\reports"
$LogsDir = "$HomeDir\logs"

# --- Helper Functions ---

function Write-Log {
    param([string]$Message, [string]$Level="INFO", [string]$Color="White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $Message -ForegroundColor $Color
    # We might want to file log here too if configured
}

function Test-SystemRequirements {
    Write-Host "🔍 $AppName - System Requirements Check" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

    # OS Check
    $os = Get-CimInstance Win32_OperatingSystem
    $isWin11 = $os.Caption -match 'Windows 11'
    $isWin10Recent = ($os.Caption -match 'Windows 10') -and ([int]$os.BuildNumber -ge 19041)

    if ($isWin11 -or $isWin10Recent) {
        Write-Host "[✓] Operating System: $($os.Caption) (Build $($os.BuildNumber))" -ForegroundColor Green
    } else {
        Write-Host "[✗] Operating System: $($os.Caption) (Build $($os.BuildNumber))" -ForegroundColor Red
        Write-Host "    Error: Sweepy requires Windows 10 Build 19041+ or Windows 11" -ForegroundColor Red
        exit 1
    }

    # PowerShell Version Check
    if ($PSVersionTable.PSVersion.Major -ge 5) {
         Write-Host "[✓] PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green
    } else {
         Write-Host "[✗] PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
         Write-Host "    Error: PowerShell 5.1+ required" -ForegroundColor Red
         exit 1
    }

    # Execution Policy Check (Informational, since we are running)
    $policy = Get-ExecutionPolicy
    if ($policy -ne 'Restricted') {
        Write-Host "[✓] Execution Policy: $policy" -ForegroundColor Green
    } else {
        # This code might not even run if it's restricted, but good to have
        Write-Host "[✗] Execution Policy: $policy" -ForegroundColor Red
        exit 1
    }

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "✅ All checks passed - Ready to proceed!`n" -ForegroundColor Green
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "❌ Error: Administrator privileges required for task installation" -ForegroundColor Red
        Write-Host "   Run PowerShell as Administrator or use:" -ForegroundColor Yellow
        Write-Host "   Start-Process pwsh -Verb RunAs -ArgumentList `"-File sweepy.ps1 $Command`"" -ForegroundColor Cyan
        exit 1
    }
}

# --- Main Execution Flow ---

# Create working directories
if (-not (Test-Path $ReportsDir)) { New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $LogsDir)) { New-Item -Path $LogsDir -ItemType Directory -Force | Out-Null }

Test-SystemRequirements

switch ($Command) {
    'scan' {
        Write-Log "Starting Scan..." -Color Cyan

        # 1. Determine paths
        $searchPaths = @()
        if ($Path) {
            $searchPaths = $Path
        } else {
            # Default locations
            $candidates = @(
                "$HOME\Documents\code",
                "$HOME\Desktop",
                "$HOME\dev",
                "$HOME\projects"
            )
            foreach ($c in $candidates) {
                if (Test-Path $c) { $searchPaths += $c }
            }
        }

        if ($searchPaths.Count -eq 0) {
            Write-Error "No paths found to scan. Use -Path to specify locations."
        }

        Write-Host "📂 Searching: $($searchPaths -join ', ')" -ForegroundColor Gray
        Write-Host "⏱️  Age threshold: $Days days" -ForegroundColor Gray
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

        # 2. Setup output file
        if (-not $OutFile) {
            $dateStr = Get-Date -Format "yyyy-MM-dd"
            $OutFile = Join-Path $ReportsDir "node-modules-$dateStr.txt"
        }

        # 3. Scan logic
        $staleFolders = @()
        $cutoffDate = (Get-Date).AddDays(-$Days)

        foreach ($root in $searchPaths) {
            if (-not (Test-Path $root)) {
                Write-Warning "Path not found: $root"
                continue
            }

            # Find all node_modules (depth limited for sanity, can increase later)
            # Using -Filter node_modules is faster
            Write-Progress -Activity "Scanning $root" -Status "Searching for node_modules..."

            $dirs = Get-ChildItem -Path $root -Directory -Filter "node_modules" -Recurse -ErrorAction SilentlyContinue

            $i = 0
            foreach ($dir in $dirs) {
                $i++
                Write-Progress -Activity "Analyzing candidates in $root" -Status "Checking $($dir.FullName)" -PercentComplete (($i / $dirs.Count) * 100)

                # Check exclusion patterns
                if ($Exclude) {
                    $skip = $false
                    foreach ($pattern in $Exclude) {
                        if ($dir.FullName -like $pattern) { $skip = $true; break }
                    }
                    if ($skip) { continue }
                }

                $isStale = $false
                $reason = ""
                $ageDays = 0

                if ($Legacy) {
                    # Option A: Check folder LastAccessTime
                    $lastAccess = $dir.LastAccessTime
                    if ($lastAccess -lt $cutoffDate) {
                        $isStale = $true
                        $ageDays = ((Get-Date) - $lastAccess).Days
                        $reason = "Last accessed $ageDays days ago"
                    }
                } else {
                    # Option B: Check package-lock.json or yarn.lock (Default)
                    $lockFile = Join-Path $dir.Parent.FullName "package-lock.json"
                    $yarnLock = Join-Path $dir.Parent.FullName "yarn.lock"

                    $targetFile = $null
                    if (Test-Path $lockFile) { $targetFile = Get-Item $lockFile }
                    elseif (Test-Path $yarnLock) { $targetFile = Get-Item $yarnLock }

                    if ($targetFile) {
                        if ($targetFile.LastWriteTime -lt $cutoffDate) {
                            $isStale = $true
                            $ageDays = ((Get-Date) - $targetFile.LastWriteTime).Days
                            $reason = "Lockfile modified $ageDays days ago"
                        }
                    } else {
                        # Fallback to LastWriteTime of the parent folder if no lockfile
                        # This avoids deleting active projects that just don't use lockfiles (rare but possible)
                        # Or we could treat 'no lockfile' as 'stale' if the folder itself is old.
                        # Let's use parent folder LastWriteTime as a proxy for activity.
                        $parent = $dir.Parent
                        if ($parent.LastWriteTime -lt $cutoffDate) {
                            $isStale = $true
                            $ageDays = ((Get-Date) - $parent.LastWriteTime).Days
                            $reason = "Parent folder modified $ageDays days ago"
                        }
                    }
                }

                if ($isStale) {
                    # Calculate size (this can be slow, maybe make it optional or estimate?)
                    # For now, let's do a quick measure
                    try {
                        $sizeMB = "{0:N2}" -f ((Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB)
                        Write-Host "   ✓ Found stale: $($dir.FullName)" -ForegroundColor Yellow
                        Write-Host "     ($reason, Size: $sizeMB MB)" -ForegroundColor DarkGray

                        $staleFolders += [PSCustomObject]@{
                            Path = $dir.FullName
                            SizeMB = $sizeMB
                            AgeDays = $ageDays
                        }
                    } catch {
                        Write-Warning "Could not access $($dir.FullName)"
                    }
                }
            }
        }

        # 4. Output results
        if ($staleFolders.Count -gt 0) {
            $staleFolders.Path | Out-File -FilePath $OutFile -Encoding utf8

            $totalSize = ($staleFolders | Measure-Object -Property SizeMB -Sum).Sum
            Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
            Write-Host "✅ Scan complete!" -ForegroundColor Green
            Write-Host "   Found: $($staleFolders.Count) stale node_modules" -ForegroundColor White
            Write-Host "   Total size: ~$('{0:N2}' -f $totalSize) MB" -ForegroundColor White
            Write-Host "   Report saved: $OutFile" -ForegroundColor Cyan
        } else {
            Write-Host "✅ Scan complete! No stale directories found." -ForegroundColor Green
        }
    }
    'clean' {
        Write-Log "Starting Clean..." -Color Cyan

        # 1. Determine Report File
        if (-not $Report) {
            $latest = Get-ChildItem -Path $ReportsDir -Filter "node-modules-*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                $Report = $latest.FullName
                Write-Host "📄 Using latest report: $Report" -ForegroundColor Gray
            } else {
                Write-Error "No report file specified and no recent reports found. Run 'scan' first."
            }
        }

        if (-not (Test-Path $Report)) {
            Write-Error "Report file not found: $Report"
        }

        # 2. Read and Validate Paths
        $paths = Get-Content -Path $Report
        if (-not $paths) {
            Write-Warning "Report file is empty. Nothing to clean."
            return
        }

        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host "📋 Preparing to clean $($paths.Count) directories..." -ForegroundColor White

        $validPaths = @()
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $validPaths += $p
            } else {
                Write-Warning "Skipping missing path: $p"
            }
        }

        if ($validPaths.Count -eq 0) {
            Write-Host "No valid paths found to delete." -ForegroundColor Yellow
            return
        }

        # 3. Interactive Selection (Out-GridView)
        if ($Interactive) {
            Write-Host "Opening Grid View for selection..." -ForegroundColor Cyan
            try {
                # Wrap in try/catch because Out-GridView requires a GUI environment
                $validPaths = $validPaths | Out-GridView -Title "Sweepy - Select folders to DELETE" -PassThru
                if (-not $validPaths) {
                    Write-Host "Action cancelled by user in Grid View." -ForegroundColor Yellow
                    return
                }
            } catch {
                Write-Warning "Interactive Grid View failed (environment might not support it). Proceeding with full list."
            }
        }

        # 4. Preview / Confirmation
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
        Write-Host "WOULD DELETE ($($validPaths.Count) directories):" -ForegroundColor White
        $validPaths | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

        if ($PSCmdlet.ShouldProcess("Delete $($validPaths.Count) directories", "Delete $($validPaths.Count) directories", "Confirm Delete")) {
             # If -WhatIf was passed, ShouldProcess returns false and prints text automatically.
             # If we are here, we are NOT in WhatIf mode (or user said yes to -Confirm?)
             # Wait, strict implementation of WhatIf requires wrapping the destructive action.
             # However, the PLAN calls for a custom "Type DELETE" prompt which is safer than standard Confirm.

             if ($Force) {
                 Write-Host "Force enabled. Skipping confirmation." -ForegroundColor Yellow
             } else {
                 Write-Host "⚠️  DESTRUCTIVE OPERATION - THIS CANNOT BE UNDONE" -ForegroundColor Red
                 Write-Host "Type 'DELETE' to confirm (case-sensitive): " -NoNewline -ForegroundColor Red
                 $input = Read-Host
                 if ($input -cne 'DELETE') {
                     Write-Host "❌ Confirmation failed. Aborting." -ForegroundColor Red
                     return
                 }
             }

             # 5. Execution
             $logFile = Join-Path $LogsDir "cleanup-$(Get-Date -Format 'yyyy-MM-dd-HHmm').log"
             $deletedCount = 0
             $failedCount = 0

             Write-Host "🗑️  Executing cleanup..." -ForegroundColor Cyan

             foreach ($p in $validPaths) {
                 # Double check existence just in case
                 if (Test-Path $p) {
                     try {
                         Write-Host "Deleting: $p ... " -NoNewline
                         Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
                         Write-Host "✓ Success" -ForegroundColor Green
                         Add-Content -Path $logFile -Value "[SUCCESS] $p"
                         $deletedCount++
                     } catch {
                         Write-Host "✗ Failed ($($_.Exception.Message))" -ForegroundColor Red
                         Add-Content -Path $logFile -Value "[FAILED] $p - $($_.Exception.Message)"
                         $failedCount++
                     }
                 }
             }

             Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
             Write-Host "✅ Cleanup complete!" -ForegroundColor Green
             Write-Host "   Deleted: $deletedCount" -ForegroundColor White
             Write-Host "   Failed:  $failedCount" -ForegroundColor White
             Write-Host "   Log:     $logFile" -ForegroundColor Cyan
        }
    }
    'install-task' {
        Assert-Admin
        Write-Log "Installing Scheduled Task..." -Color Cyan

        $TaskName = "Sweepy-NodeModules-Weekly"

        # Check if exists
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Write-Warning "Task '$TaskName' already exists. Reinstalling..."
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }

        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2:00AM

        # We need to run the script.
        # This assumes the script stays in the same location.
        $scriptPath = $PSCommandPath
        $action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-File `"$scriptPath`" scan"
        # Fallback to powershell.exe if pwsh is not available?
        # The system check ensures PS 5.1+, so 'powershell' is safer for general compat unless we know pwsh is there.
        # But 'pwsh' is for Core. Let's try to detect current shell.
        $shellExe = "powershell.exe"
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $shellExe = "pwsh"
        }
        $action = New-ScheduledTaskAction -Execute $shellExe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" scan"

        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries:$false -DontStopIfGoingOnBatteries:$false -StartWhenAvailable -RunOnlyIfNetworkAvailable:$false

        try {
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "Sweepy weekly scan for stale node_modules" | Out-Null
            Write-Host "✅ Task '$TaskName' installed successfully!" -ForegroundColor Green
            Write-Host "   Schedule: Every Sunday at 2:00 AM" -ForegroundColor Gray
            Write-Host "   Command: $shellExe -File $scriptPath scan" -ForegroundColor Gray
        } catch {
            Write-Error "Failed to register task: $($_.Exception.Message)"
        }
    }
    'uninstall-task' {
        Assert-Admin
        Write-Log "Uninstalling Scheduled Task..." -Color Cyan

        $TaskName = "Sweepy-NodeModules-Weekly"

        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            try {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
                Write-Host "✅ Task '$TaskName' removed successfully." -ForegroundColor Green
            } catch {
                Write-Error "Failed to remove task: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Task '$TaskName' not found."
        }
    }
}
