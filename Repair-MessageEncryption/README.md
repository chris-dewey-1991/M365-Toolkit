# Fix the Greyed-Out Encrypt Button in Outlook

A complete how-to guide for diagnosing and repairing Microsoft 365 Message Encryption when the Encrypt button is greyed out in Outlook.

Companion document to [`Repair-MessageEncryption.ps1`](../Repair-MessageEncryption.ps1).

---

## Summary

This document describes a recurring fault in Microsoft 365 tenants where the Encrypt button in Outlook is greyed out, preventing users from sending encrypted email. The most common root cause is a mismatch between Exchange Online's configured Rights Management licensing URL and the URL actually published by the tenant's Azure Information Protection service. This guide covers symptom identification, the automated repair, the manual repair, and troubleshooting.

---

## Symptoms

- The Encrypt button is greyed out in classic Outlook, new Outlook, and Outlook on the web
- Affected users hold valid Microsoft 365 Business Premium (or higher) licences
- `Test-IRMConfiguration` fails with: `Failed to acquire RMS templates`
- `Get-IRMConfiguration` shows `AzureRMSLicensingEnabled`, `InternalLicensingEnabled`, and `SimplifiedClientAccessEnabled` all set to `True` — the configuration looks correct on paper

---

## Root Cause

Exchange Online stores a `LicensingLocation` URL that points at the tenant's Azure Rights Management endpoint. The URL is tied to the tenant's RMS service ID (a GUID). If the tenant's RMS service has been reprovisioned, migrated, or had AIP toggled off and back on, the stored URL can become stale and no longer match the live endpoint.

When Exchange tries to fetch RMS templates from the stale URL, the request fails silently — the licensing flags remain `True`, but no templates are returned. Outlook clients receive no encryption templates from Exchange, so the Encrypt button has nothing to bind to and remains greyed out.

The fix is to query the live AIP service for its real licensing URL and update Exchange to use it.

---

## Prerequisites

- A Microsoft 365 tenant with Business Premium or higher (Business Premium, E3, E5, or standalone AIP P1/P2)
- A Global Administrator account in the tenant
- A Windows machine with PowerShell 7 (`pwsh`) installed; Windows PowerShell 5.1 must also be available (ships with Windows by default) — it is required for the `AIPService` module
- Local administrator rights on the machine for module installation

> **Note**  
> Microsoft has removed the GUI activation option for Azure Rights Management from the admin centre. PowerShell is the only supported method, even though the required `AIPService` module only runs in Windows PowerShell 5.1. The supplied script bridges both PowerShell versions automatically.

---

## Part 1: Automated Fix (Recommended)

The supplied PowerShell script `Repair-MessageEncryption.ps1` automates the entire workflow: diagnosis, AIP activation if required, URL comparison, repair, and verification.

### Step 1: Save the Script

The script lives in this folder alongside the README.

### Step 2: Open PowerShell 7 as Administrator

1. Press the Windows key, type `pwsh`, right-click **PowerShell 7** in the results, and choose **Run as administrator**.
2. Confirm the version by running:

   ```powershell
   $PSVersionTable.PSVersion
   ```

3. The major version must be `7`. If it shows `5`, you have opened Windows PowerShell instead — close it and find PowerShell 7, or install it from the Microsoft Store if it is missing.

### Step 3: Run the Script

Navigate to the script's folder and run it. To use the connected admin account as the test sender, run with no parameters:

```powershell
.\Repair-MessageEncryption.ps1
```

To specify a different test sender:

```powershell
.\Repair-MessageEncryption.ps1 -TestSender user@clientdomain.com
```

To preview what would change without making any changes:

```powershell
.\Repair-MessageEncryption.ps1 -WhatIf
```

### Step 4: Authenticate

The script prompts for two sign-ins:

- **Exchange Online** — typically opens a browser window for sign-in, or uses a device code if the browser path fails
- **AIPService** — a Windows sign-in dialog appears; use a Global Administrator account

> **Warning**  
> The AIPService sign-in window sometimes opens behind the PowerShell terminal. If the script appears to hang for more than 30 seconds at the AIP step, press `Alt+Tab` to find and complete the hidden sign-in.

### Step 5: Review the Output

The script reports each step with colour-coded status indicators. A successful run ends with:

```
[OK]   Message Encryption is working. Test-IRMConfiguration returned PASS.
```

If the final test fails, the script displays the error from `Test-IRMConfiguration`. Common causes are listed in the troubleshooting section.

### Step 6: Allow Time and Restart Outlook

- Wait 10 to 15 minutes for changes to propagate to Outlook clients
- Fully quit Outlook — check the system tray, right-click the icon, choose Quit; closing the window is not enough
- Reopen Outlook, start a new email, and check the Options ribbon; the Encrypt dropdown should now be active with options including Encrypt-Only and Do Not Forward

---

## Part 2: Manual Repair Procedure

Use these steps if the script cannot run in the target environment, or to understand what the script does. Run each block in the indicated PowerShell version.

### Step 1: Install Required Modules

In PowerShell 7 (as administrator):

```powershell
Install-Module -Name ExchangeOnlineManagement -Scope AllUsers -Force -AllowClobber
```

In Windows PowerShell 5.1 (as administrator):

```powershell
Install-Module -Name AIPService -Scope AllUsers -Force -AllowClobber
```

> **Tip**  
> Install modules to the `AllUsers` scope. The default `CurrentUser` scope places modules in the user's Documents folder, which is often synced by OneDrive — OneDrive sync causes assembly conflicts that break `ExchangeOnlineManagement`.

### Step 2: Connect to Exchange Online

In PowerShell 7:

```powershell
Connect-ExchangeOnline
```

If you receive the error `A window handle must be configured`, fall back to device code authentication:

```powershell
Connect-ExchangeOnline -Device
```

### Step 3: Capture the Current Exchange IRM Configuration

```powershell
Get-IRMConfiguration
```

Record the `LicensingLocation` value. It looks like:

```
https://a50ebff2-70e2-4215-8401-e30c7f56d45c.rms.eu.aadrm.com/_wmcs/licensing
```

### Step 4: Confirm the Symptom

```powershell
Test-IRMConfiguration -Sender admin@yourdomain.com
```

If the output includes `FAIL: Failed to acquire RMS templates` with `OVERALL RESULT: FAIL`, continue. If the test passes, the issue is not the URL mismatch — see the troubleshooting section.

### Step 5: Query the Real AIP Licensing URL

Open Windows PowerShell 5.1 as administrator and run:

```powershell
Import-Module AIPService
Connect-AipService
Get-AipService
(Get-AipServiceConfiguration).LicensingIntranetDistributionPointUrl
```

`Get-AipService` should return `Enabled`. If it returns `Disabled`, run `Enable-AipService` and wait 60 seconds before retrying.

Record the URL returned by `Get-AipServiceConfiguration`. It looks like:

```
https://db635290-33a4-4d93-bd54-3c11bf145d84.rms.eu.aadrm.com/_wmcs/licensing
```

### Step 6: Compare the URLs

Compare the GUID in the URL from Step 3 with the GUID in the URL from Step 5. If they differ, the cause is confirmed.

| Source | Example URL |
| --- | --- |
| Exchange Online (Step 3) | `https://a50ebff2-...rms.eu.aadrm.com/...` |
| AIP Service (Step 5) | `https://db635290-...rms.eu.aadrm.com/...` |

### Step 7: Apply the Fix

Return to your PowerShell 7 / Exchange Online session and update the URL, substituting the URL from Step 5:

```powershell
Set-IRMConfiguration -LicensingLocation "https://db635290-33a4-4d93-bd54-3c11bf145d84.rms.eu.aadrm.com/_wmcs/licensing"

Set-IRMConfiguration -InternalLicensingEnabled $false
Start-Sleep -Seconds 30
Set-IRMConfiguration -InternalLicensingEnabled $true
Start-Sleep -Seconds 90
```

Toggling `InternalLicensingEnabled` off and on forces Exchange to refresh its trusted publishing domain against the new URL.

### Step 8: Verify

```powershell
Test-IRMConfiguration -Sender admin@yourdomain.com
```

A successful result looks like:

```
Acquiring RMS Templates ...
    - PASS: RMS Templates acquired.
      Templates available: Confidential \ All Employees, Highly Confidential \ All Employees, Encrypt, Do Not Forward.
Verifying encryption ...
    - PASS: Encryption verified successfully.
Verifying decryption for recipient: admin@yourdomain.com ...
    - PASS: Decryption verified successfully.
Verifying IRM is enabled ...
    - PASS: IRM verified successfully.
OVERALL RESULT: PASS
```

### Step 9: Restart Outlook Clients

Wait 10 to 15 minutes, then fully quit and restart Outlook on each affected workstation. The Encrypt button should be active.

---

## Part 3: Troubleshooting

### `Connect-AipService` fails with credentials error

**Symptoms:** `The attempt to connect to the Azure Information Protection service failed`, often without a visible sign-in window.

**Causes and remedies:**

- Running in PowerShell 7 — `AIPService` only works in Windows PowerShell 5.1; close and reopen Windows PowerShell specifically
- Sign-in window hidden behind the terminal — `Alt+Tab` to find it
- Account is not a Global Administrator or is a personal Microsoft account rather than a tenant work account — use the correct admin account
- Account is a guest in another tenant — sign in with an account native to the tenant being repaired

### `Connect-ExchangeOnline` fails with "window handle must be configured"

This is a known issue with WAM (Windows Account Manager) brokered authentication in some PowerShell environments. Use the device code fallback:

```powershell
Connect-ExchangeOnline -Device
```

### Module loads from OneDrive and fails with assembly mismatch

**Symptoms:** Errors like `Could not load file or assembly Microsoft.Identity.Client.dll` with a path inside OneDrive.

**Cause:** PowerShell modules installed to the user scope land in Documents, which is OneDrive-synced. OneDrive locks and partially syncs DLLs, corrupting them.

**Remedy:** Remove the OneDrive copy and reinstall to `AllUsers`:

```powershell
Remove-Item "$env:USERPROFILE\OneDrive*\Documents\PowerShell\Modules\ExchangeOnlineManagement" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\OneDrive*\Documents\WindowsPowerShell\Modules\ExchangeOnlineManagement" -Recurse -Force -ErrorAction SilentlyContinue

Install-Module -Name ExchangeOnlineManagement -Scope AllUsers -Force -AllowClobber
```

### `Test-IRMConfiguration` still fails after URL fix

If URLs match but the test still fails, possible additional causes:

- `Get-AipService` returns `Disabled` — run `Enable-AipService` and wait 60 minutes for full propagation
- Tenant has never had AIP/RMS provisioned — the Templates list in `Get-AipServiceConfiguration` will be empty; open a Microsoft support ticket as backend provisioning is required
- AIP custom templates contain forbidden characters such as semicolons or colons in their names — remove or rename via the Purview portal
- Tenant-wide service incident — check the Microsoft 365 Service Health Dashboard

### Encrypt button still greyed out after `Test-IRMConfiguration` passes

If the server-side test passes but a specific user cannot see the Encrypt option:

- Check that the user has Azure Rights Management Service ticked under their licence assignments (admin.microsoft.com → Users → select user → Licenses and apps → expand the licence)
- Have the user sign out of Outlook fully and sign back in to pick up the entitlement
- Clear cached credentials in Credential Manager (Windows) — remove anything starting with `MicrosoftOffice`, `Outlook`, or `MSOIdentityCRL`
- Check whether the user has S/MIME selected under message options; if S/MIME is ticked but no S/MIME certificate is installed, the Encrypt button greys out — untick S/MIME
- Compare classic Outlook with Outlook on the web; if web works but desktop does not, the issue is local to the client; Online Repair via Control Panel → Programs is the usual fix

### When to escalate to Microsoft Support

Open a support ticket via admin.microsoft.com → Support → New service request if:

- `Connect-AipService` consistently fails for a Global Admin with a valid sign-in
- `Get-AipServiceConfiguration` shows an empty Templates list on a tenant that should have them
- `Test-IRMConfiguration` fails after both URL repair and tenant-wide service propagation time of 60 minutes or more

When raising the ticket, include the correlation IDs from any failed `Connect-AipService` attempts and the full output of `Get-IRMConfiguration`. Ask to be escalated to the Information Protection or Exchange Online engineering team — tier 1 will typically loop on the same diagnostic steps you have already run.

---

## Appendix A: Reference

### Key Cmdlets and Where to Run Them

| Cmdlet | PowerShell Version | Purpose |
| --- | --- | --- |
| `Get-IRMConfiguration` | PowerShell 7 (Exchange) | Read Exchange Online IRM settings |
| `Set-IRMConfiguration` | PowerShell 7 (Exchange) | Update Exchange IRM settings |
| `Test-IRMConfiguration` | PowerShell 7 (Exchange) | End-to-end encryption test |
| `Get-AipService` | Windows PowerShell 5.1 | Check if Azure RMS is enabled |
| `Enable-AipService` | Windows PowerShell 5.1 | Activate Azure RMS |
| `Get-AipServiceConfiguration` | Windows PowerShell 5.1 | Read AIP tenant config (incl. licensing URL) |

### Key `Get-IRMConfiguration` Values

In a healthy tenant after repair, these values should appear:

| Property | Expected | Meaning |
| --- | --- | --- |
| `InternalLicensingEnabled` | `True` | RMS active for internal recipients |
| `ExternalLicensingEnabled` | `True` | RMS active for external recipients |
| `AzureRMSLicensingEnabled` | `True` | Tenant uses Azure RMS (not on-prem AD RMS) |
| `SimplifiedClientAccessEnabled` | `True` | Master switch for the Encrypt button |
| `SimplifiedClientAccessEncryptOnlyDisabled` | `False` | Encrypt-Only option is permitted (double negative) |
| `SimplifiedClientAccessDoNotForwardDisabled` | `False` | Do Not Forward option is permitted (double negative) |
| `LicensingLocation` | GUID matches AIP service | Exchange points at the live RMS endpoint |

> **Note on double negatives**  
> The properties ending in `Disabled` use inverted logic. `False` means the feature is **enabled**. `True` means it is disabled. This is the opposite of the other flags in the same object.

### Useful Microsoft Documentation

- [Set up Microsoft Purview Message Encryption](https://learn.microsoft.com/en-us/purview/set-up-new-message-encryption-capabilities)
- [Resolve Microsoft Purview Message Encryption issues](https://learn.microsoft.com/en-us/microsoft-365/troubleshoot/office-message-encryption/fix-message-encryption-issue-microsoft-purview)
- [Connect to Exchange Online PowerShell](https://learn.microsoft.com/en-us/powershell/exchange/connect-to-exchange-online-powershell)
- [Activate AIP via PowerShell](https://learn.microsoft.com/en-us/azure/information-protection/activate-service)
