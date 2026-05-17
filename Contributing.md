# Contributing to M365 Toolkit

Thank you for your interest in contributing. This repository grows by administrators and consultants writing down what they fixed.

---

## Reporting Issues

When reporting a bug in an existing tool, please include:

- Output of the relevant diagnostic cmdlet (`Get-IRMConfiguration`, etc.)
- The tool's full console output (use `Start-Transcript` if helpful)
- Tenant licensing details (Business Premium, E3, E5, etc.)
- Any correlation IDs from failed Microsoft calls
- The PowerShell version (`$PSVersionTable.PSVersion`)

Please **redact any tenant identifiers, GUIDs tied to real client tenants, and email addresses** before posting publicly.

For new tool proposals, open an issue describing the fault, its symptoms, and the manual fix currently in use. Scope discussion before code saves everyone time.

---

## Adding a New Tool

Each tool lives in its own folder at the repository root:

```
<Tool-Name>/
├── README.md                          # Per-tool README
├── <Verb-Noun>.ps1                    # The script itself
└── docs/
    └── <Tool-Name>-HowTo.docx         # Optional how-to document
```

### Naming Conventions

- **Folder names**  
  PascalCase or Verb-Noun matching the script name (e.g. `Repair-MessageEncryption`, `Set-SafeLinksPolicy`)

- **Script names**  
  `Verb-Noun.ps1` using approved PowerShell verbs (`Repair-`, `Get-`, `Set-`, `Test-`, etc.); run `Get-Verb` if unsure

- **Document names**  
  Descriptive and human-readable

---

## Design Principles

All new tools should follow the same core principles as existing tools:

- **Diagnose before repairing**  
  Read state first, decide whether a change is required, then act; support `-WhatIf` via `[CmdletBinding(SupportsShouldProcess = $true)]`

- **PowerShell version bridging**  
  Some Microsoft modules only run in Windows PowerShell 5.1 (e.g. `AIPService`); shell out to `powershell.exe` for those calls rather than asking the user to switch shells

- **Module installation scope**  
  Install modules with `-Scope AllUsers` to avoid OneDrive-synced `Documents\PowerShell\Modules`, which corrupts DLLs and breaks module loads

- **Colour-coded output**  
  Use the standard helper pattern for `Write-Step`, `Write-Ok`, `Write-Warn`, `Write-Fail`, and `Write-Info`

- **Clean disconnect**  
  Tear down sessions in a `finally` block where appropriate

- **Document the root cause**  
  The per-tool README or how-to document should explain *why* the problem happens so the next engineer can recognise it from symptoms alone

- **Comment-based help**  
  Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`, and `.NOTES` so `Get-Help` returns useful output

- **No hardcoded tenant data**  
  No tenant IDs, GUIDs, domains, or user identifiers from real client tenants anywhere — including comments and examples

---

## Standard Output Helpers

For consistent presentation across all tools, use these output helpers:

```powershell
function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    [OK]   $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    [WARN] $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "    [FAIL] $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "    [INFO] $Message" -ForegroundColor Gray }
```

---

## Per-Tool README Template

Use this structure for each tool's README:

```markdown
# <Tool-Name> (PowerShell)

[badges]

One-sentence description of what the tool fixes.

Part of the [M365 Toolkit](../README.md).

## Symptoms

## Root Cause

## Repository Purpose

## Design Principles

## Environment & Deployment

## Usage

## Manual Procedure

## License
```

---

## Pull Request Checklist

Before submitting:

- [ ] Script runs cleanly against a healthy tenant with no false positives
- [ ] Script runs cleanly against a known-broken tenant and reports PASS after repair
- [ ] `-WhatIf` previews all changes without applying them
- [ ] Comment-based help is present and accurate
- [ ] Per-tool README follows the template
- [ ] No hardcoded tenant IDs, GUIDs, usernames, or domains
- [ ] No secrets, credentials, or access tokens anywhere in the code or git history
- [ ] Tested on PowerShell 7 (and Windows PowerShell 5.1 if applicable)
- [ ] Added to the available tools table in the top-level README

---

## Code Style

- Indentation: 4 spaces, no tabs
- Cmdlet names: full names, no aliases (`Where-Object` not `?`, `ForEach-Object` not `%`)
- Strings: single quotes unless interpolation is needed
- Avoid `-ErrorAction SilentlyContinue` unless deliberate — a surfaced bug is better than a silent one
- Use `$ErrorActionPreference = 'Stop'` at the top of scripts that need to fail fast

---

## License

By contributing, you agree your contributions will be licensed under the project's MIT licence.
