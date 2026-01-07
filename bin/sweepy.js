#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

// Path to the PowerShell script
const psScriptPath = path.join(__dirname, '..', 'sweepy.ps1');

// Determine which PowerShell executable to use
// Prefer 'pwsh' (PowerShell Core) if available, otherwise 'powershell' (Windows PowerShell)
// Since we can't easily check for command existence in a cross-platform way without deps,
// and we are on Windows (os: win32), we can try to guess or just default to powershell.
// However, the ps1 script checks for PS 5.1+, so 'powershell' is the safest default for Windows.
const shell = 'powershell.exe';

// Construct arguments
// -NoProfile: Faster startup, avoid profile pollution
// -ExecutionPolicy Bypass: Ensure script runs even if policy is Restricted (scope is process only)
// -File: The script to run
const args = [
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', psScriptPath,
  ...process.argv.slice(2) // Pass through all user arguments
];

// Spawn the PowerShell process
const child = spawn(shell, args, {
  stdio: 'inherit', // Important: Inherit stdin/stdout/stderr for interactive prompts
  windowsHide: false
});

child.on('error', (err) => {
  if (err.code === 'ENOENT') {
    console.error(`Error: Could not find '${shell}'. Please ensure PowerShell is installed.`);
  } else {
    console.error('Error starting Sweepy:', err);
  }
  process.exit(1);
});

child.on('close', (code) => {
  process.exit(code);
});
