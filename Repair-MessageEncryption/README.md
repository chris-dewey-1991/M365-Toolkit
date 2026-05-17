# Repair-MessageEncryption (PowerShell)

[![powershell](https://img.shields.io/badge/Powershell-7%2B-blue)](https://img.shields.io/badge/Powershell-7%2B-blue)
[![platform](https://img.shields.io/badge/Platform-Windows-lightgrey)](https://img.shields.io/badge/Platform-Windows-lightgrey)
[![license](https://img.shields.io/badge/License-MIT-green)](https://img.shields.io/badge/License-MIT-green)

A PowerShell tool for **diagnosing and repairing the greyed-out Encrypt button in Outlook** on Microsoft 365 tenants.

Part of the [M365 Toolkit](../README.md).

---

## Symptoms

The Encrypt button in Outlook is greyed out for users on tenants where:

- The user holds a Microsoft 365 Business Premium licence (or higher)
- `Get-IRMConfiguration` reports `InternalLicensingEnabled`, `AzureRMSLicensingEnabled`, and `SimplifiedClientAccessEnabled` all set to `True`
- `Test-IRMConfiguration` fails with `Failed to acquire RMS templates`
- The issue is present in classic Outlook, new Outlook, and Outlook on the web

---

## Root Cause

Exchange Online stores a `LicensingLocation` URL pointing at the tenant's Azure Rights Management endpoint. The URL contains a GUID tied to the tenant's RMS service ID. If RMS has been reprovisioned, migrated, or toggled off and on, this stored URL can go stale and no longer match the URL the live AIP service is actually publishing on.

When Exchange asks the stale URL for templates, the request fails silently. The licensing flags remain `True`, but Outlook never receives encryption templates and the Encrypt button has nothing to bind to.

The fix is to query the live AIP service for its real licensing URL and update Exchange Online to use it.

---

## Repository Purpose

The goal of this tool is to **automate the full diagnostic and repair workflow** for the licensing URL mismatch, in a way that is safe to run against client tenants.

The script is designed to:

- Detect whether the issue is the licensing URL mismatch or a different fault
- Activate Azure Rights Management if the tenant requires it
- Update Exchange Online's `LicensingLocation` only when a mismatch is confirmed
- Force a trusted publishing domain refresh by toggling `InternalLicensingEnabled`
- Verify the repair with `Test-IRMConfiguration`

---

## Design Principles

The script follows the same core principles as the rest of the M365 Toolkit:

- **Diagnose before repairing**  
  No changes are made until a confirmed URL mismatch is detected

- **Preview-friendly**  
  `-WhatIf` previews every change without committing anything

- **PowerShell version bridging**  
  Runs in PowerShell 7 and shells out to Windows PowerShell 5.1 internally for the `AIPService` module, which does not run in PowerShell 7

- **Robust output**  
  Colour-coded step output with clear `[OK]`, `[WARN]`, and `[FAIL]` markers

- **Defensive execution**  
  Validates module installs, authentication, service state, and final test results

- **Clean disconnect**  
  Disconnects Exchange Online and AIPService sessions on exit

---

## Environment & Deployment

This tool is designed to be executed by an administrator on a Windows workstation:

- Microsoft 365 Business Premium or higher with Azure RMS / AIP P1
- Windows 10 or Windows 11
- PowerShell 7 (`pwsh`) installed alongside Windows PowerShell 5.1
- A Global Administrator account in the target tenant
- Local administrator rights on the workstation for module installation

It is suitable for use in:

- MSP-managed client tenants
- Corporate Microsoft 365 environments
- Hybrid and fully cloud-managed deployments

---

## Usage

Run from PowerShell 7 as administrator, from the `Repair-MessageEncryption` folder:

```powershell
# Preview what would change against the client tenant
.\Repair-MessageEncryption.ps1 -WhatIf

# Diagnose and repair, using the signed-in admin as the test sender
.\Repair-MessageEncryption.ps1

# Or specify a different test sender in the client tenant
.\Repair-MessageEncryption.ps1 -TestSender admin@clientdomain.com
```

The script prompts for two sign-ins:

- **Exchange Online** — browser or device code authentication, signed in as the client tenant's Global Admin
- **AIPService** — a Windows sign-in dialog; if the script appears to hang, press `Alt+Tab` to find a dialog that has opened behind the terminal

After a successful run, allow 10 to 15 minutes for changes to propagate, then have the user fully quit and restart Outlook from the system tray.

---

## Manual Procedure

A full manual procedure, with step-by-step instructions and troubleshooting for every error encountered during development, is provided in the [how-to document](./docs/Fix-Outlook-Encrypt-Button-HowTo.docx).

---

## License

Released under the [MIT License](../LICENSE).
