# Sweepy 🧹

Automated cleanup for stale `node_modules` directories on Windows.

## Overview

Sweepy finds and removes old, unused `node_modules` folders that are consuming disk space. It's safe by default with multiple layers of protection:

- **Scan-only by default** - Scheduled tasks never auto-delete
- **WhatIf preview mode** - See what would be deleted before anything happens
- **Interactive confirmation** - Must type 'DELETE' to proceed
- **Audit logging** - All deletions logged with timestamps
- **Error resilience** - Continues on errors, reports failures

## Quick Start

### Installation

1. **Ensure PowerShell execution policy allows scripts:**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Install via npm:**
   ```bash
   npm install -g sweepy-cli
   ```

### Usage

```bash
# Scan for stale node_modules (no deletion)
sweepy scan

# Preview what would be deleted (safe, no confirmation needed)
sweepy clean -Report report.txt -WhatIf

# Interactive cleanup (shows summary, asks for confirmation)
sweepy clean -Report report.txt

# Skip confirmation (still shows summary first)
sweepy clean -Report report.txt -Force

# Set up weekly automated scans (admin required)
sweepy install-task
```

> **Note:** You can still run the script directly using `.\sweepy.ps1` if you downloaded the source.

## Features

### Scan Mode
- Searches specified paths for stale `node_modules`
- Detects staleness using `package-lock.json` modification time (or `LastAccessTime` fallback)
- Generates plain-text report of findings
- Shows total disk space that can be reclaimed

### Clean Mode
- Preview with `-WhatIf` flag (zero risk)
- Interactive confirmation with case-sensitive "DELETE" prompt
- Continue-on-error: deletes as many as possible, reports failures
- Detailed logging with timestamps

### Task Automation
- Weekly scheduled scan (Sunday 2 AM)
- Runs in user context (no special permissions needed)
- Reports saved for manual review
- User manually runs cleanup (no auto-deletion)

## System Requirements

- **Windows 10** Build 19041+ or **Windows 11**
- **PowerShell** 5.1+
- Execution policy: RemoteSigned (or higher)

## Documentation

See [docs/PLAN.md](docs/PLAN.md) for:
- Complete design specification
- Implementation details
- Safety mechanisms
- Known limitations
- Implementation priorities

## Safety Features

1. **Scan-only by default** - Scheduled task never auto-deletes
2. **WhatIf mode** - Preview without any risk
3. **Interactive confirmation** - Must type 'DELETE' (case-sensitive)
4. **Path validation** - Verifies all paths exist before deletion
5. **Summary first** - Always shows what will be deleted with size
6. **Audit logging** - All operations logged with timestamps
7. **Error handling** - Continues on error, reports failures
8. **Permission pre-checks** - Tests access before attempting deletion

## License

MIT

## Development Status

🚧 **In Development** - Implementation in progress. See [docs/PLAN.md](docs/PLAN.md) for design specifications and implementation roadmap.

## Contributing

Contributions welcome! Please note:
- This is a Windows-only tool (PowerShell)
- Primary focus: robustness and safety
- No external dependencies
- Works with PowerShell 5.1+ and PowerShell 7+

## Issues & Feedback

Found a bug? Have a feature request? [Open an issue!](../../issues)

---

**Sweepy** - Keeping your disk clean, one `node_modules` at a time.
