# M365 Toolkit (PowerShell)

[![powershell](https://img.shields.io/badge/Powershell-7%2B-blue)](https://img.shields.io/badge/Powershell-7%2B-blue)
[![platform](https://img.shields.io/badge/Platform-Windows-lightgrey)](https://img.shields.io/badge/Platform-Windows-lightgrey)
[![license](https://img.shields.io/badge/License-MIT-green)](https://img.shields.io/badge/License-MIT-green)

A centralized collection of **PowerShell scripts for diagnosing and repairing Microsoft 365 tenant faults**.

This repository is intended for **MSPs, IT consultants, and enterprise administrators**, providing reliable automation for the kind of recurring Microsoft 365 issues that are not well covered by official documentation.

---

## Repository Purpose

The goal of this repository is to provide **production-ready PowerShell tooling** to diagnose and remediate Microsoft 365 tenant faults in a consistent and repeatable way.

Scripts in this repository are designed to:

- Diagnose tenant state before making changes
- Be safe to preview using `-WhatIf` before committing changes
- Bridge PowerShell 5.1 and PowerShell 7 transparently where Microsoft modules require it
- Provide clear pass/fail validation suitable for ticket evidence
- Disconnect cleanly from all services on exit

---

## Scope

This repository focuses on Microsoft 365 tenant-level configuration faults, including:

- Exchange Online and Message Encryption
- Azure Information Protection and Azure Rights Management
- Microsoft Purview and information protection
- Identity and licensing configuration

Tools are added as new recurring faults are identified across client tenants. Each tool lives in its own folder with a dedicated README and how-to document.

---

## Available Tools

| Tool | Purpose |
| --- | --- |
| [`Repair-MessageEncryption`](./Repair-MessageEncryption) | Repairs the greyed-out Encrypt button in Outlook caused by an Exchange `LicensingLocation` URL that no longer matches the tenant's live Azure RMS endpoint. |

---

## Design Principles

All scripts in this repository follow the same core principles:

- **Diagnose before repairing**  
  Read tenant state first, decide whether a change is required, then act

- **Preview-friendly**  
  Every repair script supports `-WhatIf` for safe rehearsal against client tenants

- **PowerShell version bridging**  
  Modern Exchange and Graph tasks run in PowerShell 7; legacy `AIPService` calls are shelled out to Windows PowerShell 5.1 automatically

- **Robust output**  
  Colour-coded step output suitable for live demonstration or ticket evidence

- **Defensive execution**  
  Validation of module installs, authentication, service state, and final tests before reporting success

- **Clean disconnect**  
  Sessions are torn down at the end of each run to avoid leaking credentials between client tenants

---

## Environment & Deployment

These scripts are designed to be executed by an administrator on a Windows workstation:

- Microsoft 365 Business Premium or higher (per-tool requirements may vary)
- Windows 10 or Windows 11
- PowerShell 7 installed alongside the in-box Windows PowerShell 5.1
- A Global Administrator account in the target tenant

They are suitable for use in:

- MSP-managed client tenants
- Corporate Microsoft 365 environments
- Hybrid and fully cloud-managed deployments

---

## Contributing

If a recurring Microsoft 365 fault would benefit from this treatment, contributions are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the tool template, design principles, and PR checklist.

---

## License

Released under the [MIT License](./LICENSE).
