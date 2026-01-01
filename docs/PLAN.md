# Problem Statement
Automated Windows cleanup system to find and remove stale node_modules directories (parent not accessed in 14+ days). Must be:
* Git-safe (no sensitive paths exposed)
* Minimal and battle-tested (single script per task)
* Extensible for future cleanup modules
# Critical Review of Previous Plan
**Issues identified:**
* Over-engineered: Too many files (Find, Remove, Register, config, README per module)
* Premature abstraction: Nested module folders before they're needed
* Config file overhead: JSON config for something CLI args handle better
* CSV complexity: Overkill for a simple path list (NOTE: Plain text chosen for readability, not programmatic use)
* No path exclusion: Users unable to exclude active projects from cleanup
# Refined Solution
## Design Principles
* **KISS** - Single script with subcommands, not multiple scripts
* **Safe by default** - Dry-run mode, interactive confirmation for deletion
* **Zero config to start** - Sensible defaults, paths via CLI
* **Flat structure** - No nested folders until actually needed
## Single Script: `sweepy.ps1`
One script with subcommands:
```powershell
# Scan for stale node_modules
sweepy.ps1 scan [-Path C:\dev,D:\projects] [-Days 14] [-Out report.txt]
# Clean (delete) from scan report
sweepy.ps1 clean [-Report report.txt] [-Force] [-WhatIf]
# Install weekly scheduled task
sweepy.ps1 install-task
# Uninstall scheduled task
sweepy.ps1 uninstall-task
```
**Scan mode:**
* Searches specified paths (defaults to: `$HOME\Documents\code`, `$HOME\Desktop`, `$HOME\dev`, `$HOME\projects` - NOT all drives)
* **Staleness Detection** (choose one strategy - see recommendations below):
  * **Option A (Default)**: Check `node_modules` folder's own LastAccessTime > N days
  * **Option B (More reliable)**: Check `package-lock.json` or `yarn.lock` modification time > N days
  * **Option C (Most conservative)**: Use both - require BOTH to be stale
  * ⚠️ **WARNING**: LastAccessTime can be unreliable (disabled on NTFS for perf, reset by antivirus/indexing)
* Optional `-Exclude` parameter for path patterns to skip (e.g., `-Exclude "*active*","*production*"`)
* Outputs plain text list (one path per line)
* Shows size summary
* **Progress reporting**: Shows real-time scan progress with estimated completion time
**Clean mode (DESTRUCTIVE - Multiple safety checks):**
* Reads paths from scan report file
* Validates all paths exist AND user has delete permission before proceeding
* Shows detailed summary: count, total size, paths to delete
* **DEFAULT: Dry-run mode** - Shows what WOULD be deleted, requires explicit confirmation
* Interactive prompt: "Type 'DELETE' to confirm" (case-sensitive)
* -WhatIf flag: Preview only, no confirmation prompt, zero risk
* -Force flag: Skip confirmation (still shows summary first)
* **Error handling strategy**: Continue-on-error (delete all possible items, report failures at end)
  * Failed deletions are logged with reason (access denied, locked file, etc.)
  * Failed paths are excluded from future scans (optional `.sweepy-failed` file for manual review)
* Logs all deletions with timestamps for audit trail
* **Report validation**: Checksums report file to detect tampering before execution
**Task management:**
* Creates/removes Windows Scheduled Task (weekly Sunday 2 AM)
* Scan runs automatically, saves to `$HOME\.sweepy\reports\`
* User reviews and runs clean manually
## File Structure
```warp-runnable-command
$HOME\.sweepy\                    (created on first run, gitignored)
├── reports\                      (scan outputs)
│   └── node-modules-2026-01-01.txt
└── logs\                         (deletion logs)
    └── cleanup-2026-01-01.log
GitHub repo (atssj/sweepy):
├── sweepy.ps1                    (main script ~200 lines)
├── README.md                     (cool documentation)
├── LICENSE                       (MIT)
└── .gitignore
```
## Help Content (when running `sweepy` or `sweepy -h`)
```warp-runnable-command
Sweepy - Automated cleanup for stale node_modules
Usage: sweepy.ps1 <command> [options]
Commands:
  scan              Find stale node_modules directories
  clean             Delete node_modules from scan report
  install-task      Set up weekly automated scan
  uninstall-task    Remove scheduled task
  help              Show this help
Examples:
  # Scan default locations (C:\, D:\, etc.)
  sweepy.ps1 scan
  # Scan specific paths
  sweepy.ps1 scan -Path C:\dev,D:\projects -Days 30
  # Save scan to custom file
  sweepy.ps1 scan -Out my-report.txt
  # Preview only (100% safe, no confirmation needed)
  sweepy.ps1 clean -Report report.txt -WhatIf
  # Interactive delete (shows summary, asks "Type DELETE to confirm")
  sweepy.ps1 clean -Report report.txt
  # Skip confirmation (still shows summary first)
  sweepy.ps1 clean -Report report.txt -Force
  # Set up weekly Sunday 2 AM scan
  sweepy.ps1 install-task
Options:
  scan:
    -Path <paths>     Comma-separated paths to search (default: all drives)
    -Days <number>    Parent not accessed in N days (default: 14)
    -Out <file>       Output file (default: $HOME\.sweepy\reports\node-modules-DATE.txt)
  clean:
    -Report <file>    Input file from scan (default: latest report)
    -WhatIf           Preview only - shows what would be deleted (100% safe)
    -Force            Skip "Type DELETE" confirmation (still shows summary)
For detailed help: Get-Help .\sweepy.ps1 -Full
```
## Safety Mechanisms (Multi-layered Protection)
1. **Scan-only by default** - Scheduled task NEVER auto-deletes
2. **WhatIf mode** - Preview without any risk, no confirmation needed
3. **Interactive confirmation** - Must type 'DELETE' (case-sensitive) to proceed
4. **Path validation** - Verifies all paths exist before deletion
5. **Summary first** - Always shows what will be deleted with size
6. **Audit logging** - All deletions logged with timestamps
7. **Error handling** - Continues on error, reports failures
8. **Colored output** - Red warnings for destructive operations
## Progress Display (Verbose Real-time Feedback)
**Scan mode output:**
```warp-runnable-command
🔍 Sweepy - Scanning for stale node_modules...
📂 Searching: C:\dev, D:\projects
⏱️  Age threshold: 14 days
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/245] Checking: C:\dev\project1\node_modules
[2/245] Checking: C:\dev\project2\node_modules
   ✓ Found stale: C:\dev\project2\node_modules (45 days old, 234 MB)
[3/245] Checking: C:\dev\project3\node_modules
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Scan complete!
   Found: 12 stale node_modules
   Total size: 3.2 GB
   Report saved: C:\Users\ssaha\.sweepy\reports\node-modules-2026-01-01.txt
```
**Clean mode output (WhatIf):**
```warp-runnable-command
🧹 Sweepy - Preview Mode (WhatIf)
📄 Reading report: node-modules-2026-01-01.txt
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WOULD DELETE (12 directories):
  1. C:\dev\old-project\node_modules (234 MB)
  2. C:\projects\archived\node_modules (512 MB)
  ...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💾 Total space to reclaim: 3.2 GB
✓ Preview complete - nothing deleted
```
**Clean mode output (Interactive with detailed preview):**
```warp-runnable-command
🧹 Sweepy - Delete Mode
📄 Reading report: node-modules-2026-01-01.txt
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 CLEANUP PLAN - What will be done:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📂 Target Directories: 12 node_modules folders
💾 Total Size: 3.2 GB
⏱️  Age Criteria: Not accessed in 14+ days
📁 Source Report: node-modules-2026-01-01.txt
🗑️  Actions to be performed:
  ✓ Read paths from report file
  ✓ Validate each path exists
  ✓ Delete each directory recursively
  ✓ Log all operations with timestamps
  ✓ Report success/failure for each item
  ✓ Display final summary
📝 Directories to be deleted:
  1. C:\dev\old-project\node_modules
     ├─ Size: 234 MB
     ├─ Parent: C:\dev\old-project
     └─ Last accessed: 45 days ago
  2. C:\projects\archived\node_modules
     ├─ Size: 512 MB
     ├─ Parent: C:\projects\archived
     └─ Last accessed: 60 days ago
  3. C:\temp\test\node_modules
     ├─ Size: 128 MB
     ├─ Parent: C:\temp\test
     └─ Last accessed: 30 days ago
  ... (9 more directories)
📊 Summary:
  Total directories: 12
  Total size to reclaim: 3.2 GB
  Average age: 42 days
  Oldest: 90 days (C:\archive\legacy\node_modules)
  Largest: 512 MB (C:\projects\archived\node_modules)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[RED] ⚠️  DESTRUCTIVE OPERATION - THIS CANNOT BE UNDONE [/RED]
[RED] All listed directories will be permanently deleted [/RED]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[RED] Type 'DELETE' to confirm (case-sensitive): [/RED] DELETE
🗑️  Executing cleanup...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/12] Validating: C:\dev\old-project\node_modules... ✓ Exists
        Deleting... ✓ Success (234 MB freed)
[2/12] Validating: C:\projects\archived\node_modules... ✓ Exists
        Deleting... ✓ Success (512 MB freed)
[3/12] Validating: C:\temp\test\node_modules... ✓ Exists
        Deleting... ✗ Failed (Access denied)
[4/12] Validating: C:\workspace\demo\node_modules... ✓ Exists
        Deleting... ✓ Success (89 MB freed)
... (continuing with remaining directories)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Cleanup complete!
📊 Final Results:
  ✓ Successfully deleted: 11 of 12 directories
  ✗ Failed: 1 directory
  💾 Space freed: 2.9 GB
  ⏱️  Time taken: 23 seconds
  📝 Log file: C:\Users\ssaha\.sweepy\logs\cleanup-2026-01-01.log
⚠️  Failed deletions:
  ✗ C:\temp\test\node_modules (Access denied - may require admin)
```
**Task installation output:**
```warp-runnable-command
⚙️  Installing scheduled task...
   Task name: Sweepy-NodeModules-Weekly
   Schedule: Every Sunday at 2:00 AM
   Action: Scan and report (no deletion)
✅ Task installed successfully!
   View task: taskschd.msc
   Reports: C:\Users\ssaha\.sweepy\reports\
```
## Administrative Access Requirements
**When admin is needed:**
* ✅ **scan** - NO admin required (reads only)
* ✅ **clean** - NO admin required (unless deleting system-protected folders)
* ❌ **install-task** - YES, admin required (creates scheduled task)
* ❌ **uninstall-task** - YES, admin required (removes scheduled task)
**Note:** 95% of usage (scan/clean) works without admin privileges. Only task automation requires elevation.
**Scheduled task execution context:**
* Task runs in **user context** (not system), under current user's credentials
* Runs weekly Sunday 2 AM (if system is awake)
* User can manually run task anytime: `Start-ScheduledTask -TaskName "Sweepy-NodeModules-Weekly"`
* Reports saved to `$HOME\.sweepy\reports\` (user's home directory)
## System Requirements Check
**Startup validation (runs before any command):**
```powershell
# Check OS version - Windows 10 Build 19041+ or Windows 11
$os = Get-CimInstance Win32_OperatingSystem
$isWindows11 = $os.Caption -match 'Windows 11'
$isWindows10Recent = ($os.Caption -match 'Windows 10') -and ([int]$os.BuildNumber -ge 19041)

if (-not ($isWindows11 -or $isWindows10Recent)) {
    Write-Host "❌ Error: Sweepy requires Windows 10 Build 19041+ or Windows 11" -ForegroundColor Red
    Write-Host "   Detected: $($os.Caption) Build $($os.BuildNumber)" -ForegroundColor Red
    Write-Host ""
    Write-Host "   Please update Windows or use a newer version." -ForegroundColor Yellow
    exit 1
}

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "❌ Error: PowerShell 5.1+ required" -ForegroundColor Red
    Write-Host "   Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "   Download: https://aka.ms/powershell" -ForegroundColor Cyan
    exit 1
}

# Check execution policy
$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Host "❌ Error: PowerShell execution policy is 'Restricted'" -ForegroundColor Red
    Write-Host "   Current policy: $policy" -ForegroundColor Red
    Write-Host ""
    Write-Host "   To fix, run as Administrator:" -ForegroundColor Yellow
    Write-Host "   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
    exit 1
}

# Check if running as Administrator (for task installation only)
function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
```
**Validation messages (shown at startup of every command):**

Success case:
```warp-runnable-command
🔍 Sweepy v1.0 - System Requirements Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[✓] Operating System: Windows 11 Pro (Build 22631)
[✓] PowerShell Version: 7.6.0
[✓] Execution Policy: RemoteSigned
[✓] Disk Space: 512 GB available
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All checks passed - Ready to proceed!
```

Failure case (execution policy):
```warp-runnable-command
🔍 Sweepy v1.0 - System Requirements Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[✓] Operating System: Windows 10 Pro (Build 22000)
[✓] PowerShell Version: 5.1.0
[✗] Execution Policy: Restricted
    ❌ PowerShell execution policy is 'Restricted'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ System check failed - Cannot proceed

   To fix, run as Administrator:
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
**For install-task (additional admin check):**
```warp-runnable-command
🔍 Sweepy v1.0 - System Requirements Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[✓] Operating System: Windows 11 Pro (Build 22631)
[✓] PowerShell Version: 7.6.0
[✓] Execution Policy: RemoteSigned
[✗] Administrator Privileges: Not running as admin
    ❌ Required for task installation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Administrator privileges required
   
   Run PowerShell as Administrator or use:
   Start-Process pwsh -Verb RunAs -ArgumentList "-File sweepy.ps1 install-task"
```
**Admin check (for install-task only):**
```warp-runnable-command
❌ Error: Administrator privileges required for task installation
   Run PowerShell as Administrator or use:
   Start-Process pwsh -Verb RunAs -ArgumentList "-File sweepy.ps1 install-task"
```
## PowerShell Implementation (Windows 11 Optimized)
**Core Cmdlets (Safe & Efficient):**
* `Get-ChildItem -Directory -Filter "node_modules" -Recurse -ErrorAction SilentlyContinue`
    * Native directory traversal with built-in error handling
    * -Filter for performance (faster than -Include)
    * -Recurse with depth control to avoid infinite loops
* `Get-Item -Path $parent | Select-Object LastAccessTime`
    * Safe metadata access without modifying files
    * Uses filesystem metadata (instant, no scanning)
* `Remove-Item -Path $path -Recurse -Force -ErrorAction Stop`
    * Native recursive deletion
    * -Force handles readonly files
    * -ErrorAction Stop for proper error handling per item
* `Measure-Object -Property Length -Sum`
    * Fast size calculation using filesystem metadata
* `Register-ScheduledTask` / `Unregister-ScheduledTask`
    * Native Windows Task Scheduler cmdlets (PowerShell 5.1+)
    * Safer than schtasks.exe, better error handling
* `Test-Path -PathType Container`
    * Safe path validation before operations
* `New-Item -ItemType Directory -Force`
    * Idempotent directory creation
**Performance Optimizations:**
* Use `-Filter` instead of `-Include` (50x faster for large directories)
* Parallel processing for size calculations: `ForEach-Object -Parallel` (PowerShell 7+)
* Stream processing: Pipeline directly without loading all results in memory
* Avoid Get-ChildItem -Recurse on entire drives (limit search depth)
**Safety Features:**
* `$ErrorActionPreference = 'Stop'` for critical operations
* `$ConfirmPreference = 'High'` respects -WhatIf
* Try/Catch blocks around all file operations
* Validate paths with `Test-Path` before deletion
* Use `[System.IO.Directory]::Delete()` with error handling for stubborn directories
**PowerShell 7+ Enhancements (backward compatible):**
* Ternary operator: `$color = $success ? 'Green' : 'Red'`
* Pipeline parallelization for faster scanning
* Better error messages with $PSStyle
**Console Output:**
* `Write-Host` with `-ForegroundColor` for colors
* `$PSStyle.Foreground.Red` for PowerShell 7+ styling
* Fallback to basic colors for PowerShell 5.1
* Progress bars: `Write-Progress` for long operations
**Compatibility:**
* PowerShell 5.1+ (Windows 10/11 built-in)
* Enhanced features in PowerShell 7+ (optional)
* No external dependencies or modules required
* Works in both Windows PowerShell and PowerShell Core

---

## Known Limitations & Implementation Notes

### Staleness Detection Strategy (MUST DECIDE BEFORE CODING)

**Critical Decision:** How to reliably detect "stale" node_modules?

| Approach | Pros | Cons | Recommendation |
|----------|------|------|---|
| **LastAccessTime** | Fast, simple | Unreliable (NTFS disables by default, reset by antivirus) | Use as secondary indicator |
| **package-lock.json mtime** | Semantic (indicates project activity) | Requires file exists, slower | **DEFAULT for scan** |
| **Both (AND logic)** | Most conservative | Slowest, might miss some | Best safety for production |

**Decision:** Implement Option B (package-lock.json) as default, with `--legacy` flag for LastAccessTime fallback.

### Logging Rotation Strategy

* Keep last **5 scan reports** in `$HOME\.sweepy\reports\`
* Keep last **10 cleanup logs** in `$HOME\.sweepy\logs\`
* Auto-delete older files on first run each day
* Log format: `cleanup-YYYY-MM-DD-HHmm.log` for easy sorting

### Report File Format (Plain Text)

Plain text chosen for:
* Human readability (no parser needed for quick review)
* Simple CLI pipeline compatibility
* Git-safe (no binary, no config)

Format (one path per line):
```
C:\dev\old-project\node_modules
C:\projects\archived\node_modules
```

Each line is validated as existing path before clean operation.

### Interactive Mode Robustness

* **Issue**: Typing "DELETE" in interactive mode fails if output is piped/backgrounded
* **Solution**: Always provide `-WhatIf` (preview-only) and `-Force` (skip prompt) options
* **Default**: Interactive prompt (most users), but script must handle piped input gracefully
* **Testing required**: Test with `| tee report.log` to ensure prompt still works

### Permission Pre-check

Before attempting deletion, script should:
1. Test if user has read access to `$HOME\.sweepy\reports\`
2. Test if user has delete permission on **first item** from report
3. Warn if any paths are inaccessible before starting cleanup
4. Do NOT require admin for typical user-owned directories

### Cold Start Performance

**First run will be slow** if scanning default locations with many projects:
* Solution 1: Show **progress bar with ETA** during scan
* Solution 2: Limit **initial default search to user's home drive only**
* Solution 3: Document that first scan may take 2-5 minutes

Recommend: Implement all three.

### Report File Validation

* Before executing clean from a report file, validate:
  * File exists and is readable
  * File modification time is recent (< 1 hour old, warn if older)
  * File is not empty (must have at least 1 path)
  * All paths in report are valid absolute paths
* Consider: **Checksum file** (`report.txt.sha256`) to prevent tampering

### Scheduled Task Windows Behavior

* Task runs **weekly Sunday 2:00 AM** in **user context**
* If computer is asleep: **Windows will NOT wake it** (system dependent)
* If computer is in sleep mode: task runs immediately upon wake
* Scans can take 5-30 minutes depending on directory count
* **Reports are saved, NOT automatically deleted** (user must review + manually clean)
* User can check: `Get-ScheduledTask -TaskName "Sweepy-NodeModules-Weekly"`
* User can run manually: `Start-ScheduledTask -TaskName "Sweepy-NodeModules-Weekly"`

### Size Calculation Accuracy

Current plan uses: `Get-ChildItem | Measure-Object -Property Length -Sum`

**Issue**: This counts logical file sizes, not disk space used (varies with:
* NTFS cluster size (4KB vs 16KB+ clusters)
* Compression (if enabled)
* Deduplication

**Recommendation**: Accept approximation (within ~10%), document this in help text

### Error Handling Philosophy

**Continue-on-error strategy:**
* Delete as many paths as possible
* Log each failure with specific reason
* At end: "11 of 12 successful - 92% cleanup"
* Failed paths saved to `.sweepy-failed-YYYY-MM-DD.txt` for manual review
* Do NOT retry failed paths automatically

### Multi-language Considerations

* Interactive "Type DELETE" prompt works on **all keyboard layouts** (standard ASCII)
* Output uses emoji (supported on Windows 10+)
* No localization planned (English only for first version)

---

## Implementation Priorities

**PRIORITY 1 (Must Complete Before v1.0):**
- [ ] Choose staleness detection strategy (package-lock.json vs LastAccessTime)
- [ ] Implement error handling for failed deletions
- [ ] Add path validation + permission pre-checks
- [ ] Add progress reporting for scans
- [ ] Test interactive mode with piped output

**PRIORITY 2 (Should Complete Before v1.0):**
- [ ] Implement report file checksums
- [ ] Add log rotation (keep last 5 reports, 10 logs)
- [ ] Document LastAccessTime limitations in help
- [ ] Test cold start performance on large directories
- [ ] Add -MaxDepth parameter for scan scope limiting

**PRIORITY 3 (Nice to Have):**
- [ ] CSV report option for programmatic parsing
- [ ] Shell integration (.sweepy-exclude file support)
- [ ] Metrics/statistics dashboard
- [ ] Dry-run cost estimation before cleanup
