<#
.SYNOPSIS
    Diagnoses and repairs Microsoft 365 Message Encryption / "Encrypt button greyed out" issues.

.DESCRIPTION
    This script handles the common case where Exchange Online's IRM LicensingLocation is
    pointing at a stale or incorrect Azure RMS endpoint, causing Test-IRMConfiguration
    to fail with "Failed to acquire RMS templates" and the Encrypt button to be greyed
    out in Outlook.

    The script:
      1. Connects to Exchange Online (PowerShell 7).
      2. Connects to AIPService (Windows PowerShell 5.1 in a child process).
      3. Confirms Azure RMS is activated; activates it if not.
      4. Compares the AIP service's actual licensing URL with the URL Exchange is
         configured to use.
      5. If they differ, updates Exchange to use the correct URL and refreshes IRM.
      6. Verifies the fix with Test-IRMConfiguration.

.PARAMETER TestSender
    An email address in the tenant used for Test-IRMConfiguration. Defaults to the
    signed-in admin account.

.PARAMETER WhatIf
    Show what would change without making changes.

.NOTES
    Requirements:
      - Run from PowerShell 7 (pwsh) as administrator.
      - Windows PowerShell 5.1 must be available on the machine (it ships with Windows).
      - The signed-in account must be Global Admin or have equivalent IRM/AIP rights.
      - Modules ExchangeOnlineManagement and AIPService will be installed if missing.

    AIPService only runs in Windows PowerShell 5.1, so the script shells out to 5.1
    for those calls and stays in PowerShell 7 for everything else.

.EXAMPLE
    .\Repair-MessageEncryption.ps1 -TestSender admin@contoso.com

.EXAMPLE
    .\Repair-MessageEncryption.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string]$TestSender
)

$ErrorActionPreference = 'Stop'

function Write-Step    { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Message) Write-Host "    [OK]   $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "    [WARN] $Message" -ForegroundColor Yellow }
function Write-Fail    { param([string]$Message) Write-Host "    [FAIL] $Message" -ForegroundColor Red }
function Write-Info    { param([string]$Message) Write-Host "    [INFO] $Message" -ForegroundColor Gray }

# -----------------------------------------------------------------------------
# Pre-flight checks
# -----------------------------------------------------------------------------
Write-Step "Pre-flight checks"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Fail "This script must be run from PowerShell 7 (pwsh), not Windows PowerShell 5.1."
    Write-Info "AIPService cmdlets will be invoked in a child PowerShell 5.1 process automatically."
    exit 1
}
Write-Ok "Running on PowerShell $($PSVersionTable.PSVersion)"

$winPsPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $winPsPath)) {
    Write-Fail "Windows PowerShell 5.1 not found at $winPsPath. AIPService cmdlets cannot be invoked."
    exit 1
}
Write-Ok "Windows PowerShell 5.1 found at $winPsPath"

# -----------------------------------------------------------------------------
# Module installation
# -----------------------------------------------------------------------------
Write-Step "Ensuring required modules are installed"

# ExchangeOnlineManagement (PowerShell 7)
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Info "Installing ExchangeOnlineManagement to AllUsers scope..."
    Install-Module -Name ExchangeOnlineManagement -Scope AllUsers -Force -AllowClobber
}
Write-Ok "ExchangeOnlineManagement is available"

# AIPService (Windows PowerShell 5.1) - install via 5.1 child process to ensure correct location
$aipCheck = & $winPsPath -NoProfile -Command "if (Get-Module -ListAvailable -Name AIPService) { 'present' } else { 'missing' }"
if ($aipCheck -ne 'present') {
    Write-Info "Installing AIPService module via Windows PowerShell 5.1..."
    & $winPsPath -NoProfile -Command "Install-Module -Name AIPService -Scope AllUsers -Force -AllowClobber"
}
Write-Ok "AIPService is available in Windows PowerShell 5.1"

# -----------------------------------------------------------------------------
# Connect to Exchange Online
# -----------------------------------------------------------------------------
Write-Step "Connecting to Exchange Online"
try {
    $existing = Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Connected' -and $_.TokenStatus -eq 'Active' }
    if ($existing) {
        Write-Ok "Already connected to Exchange Online as $($existing.UserPrincipalName)"
    } else {
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        Write-Ok "Connected to Exchange Online"
    }
} catch {
    Write-Warn "Standard connection failed: $($_.Exception.Message)"
    Write-Info "Falling back to device code authentication..."
    Connect-ExchangeOnline -Device -ShowBanner:$false
    Write-Ok "Connected to Exchange Online via device code"
}

# Default test sender to the connected user if not provided
if (-not $TestSender) {
    $conn = Get-ConnectionInformation | Where-Object { $_.State -eq 'Connected' } | Select-Object -First 1
    if ($conn -and $conn.UserPrincipalName) {
        $TestSender = $conn.UserPrincipalName
        Write-Info "TestSender not specified, using connected admin account: $TestSender"
    } else {
        Write-Fail "Could not determine TestSender automatically. Re-run with -TestSender <user@domain.com>."
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Read current Exchange IRM config
# -----------------------------------------------------------------------------
Write-Step "Reading current Exchange IRM configuration"
$irm = Get-IRMConfiguration

Write-Info "InternalLicensingEnabled : $($irm.InternalLicensingEnabled)"
Write-Info "AzureRMSLicensingEnabled : $($irm.AzureRMSLicensingEnabled)"
Write-Info "SimplifiedClientAccessEnabled : $($irm.SimplifiedClientAccessEnabled)"

$currentLicensingUrl = $null
if ($irm.LicensingLocation -and $irm.LicensingLocation.Count -gt 0) {
    $currentLicensingUrl = $irm.LicensingLocation[0].ToString()
    Write-Info "Current LicensingLocation: $currentLicensingUrl"
} else {
    Write-Warn "LicensingLocation is empty"
}

# -----------------------------------------------------------------------------
# Query AIP service via Windows PowerShell 5.1
# -----------------------------------------------------------------------------
Write-Step "Querying Azure Information Protection service (via Windows PowerShell 5.1)"
Write-Info "A sign-in window may appear for the AIPService connection. Sign in as Global Admin."

$aipScript = @'
$ErrorActionPreference = 'Stop'
try {
    Import-Module AIPService -ErrorAction Stop
    Connect-AipService -ErrorAction Stop | Out-Null

    $status = Get-AipService
    $config = Get-AipServiceConfiguration

    [PSCustomObject]@{
        Status               = "$status"
        FunctionalState      = "$($config.FunctionalState)"
        RmsServiceId         = "$($config.RightsManagementServiceId)"
        IntranetLicensingUrl = "$($config.LicensingIntranetDistributionPointUrl)"
        ExtranetLicensingUrl = "$($config.LicensingExtranetDistributionPointUrl)"
        TemplateCount        = $config.Templates.Count
        Error                = $null
    } | ConvertTo-Json -Compress

    Disconnect-AipService | Out-Null
}
catch {
    [PSCustomObject]@{
        Status               = $null
        FunctionalState      = $null
        RmsServiceId         = $null
        IntranetLicensingUrl = $null
        ExtranetLicensingUrl = $null
        TemplateCount        = $null
        Error                = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
'@

$aipResultJson = & $winPsPath -NoProfile -Command $aipScript
$aipResult = $aipResultJson | ConvertFrom-Json

if ($aipResult.Error) {
    Write-Fail "AIPService query failed: $($aipResult.Error)"
    Write-Info "Common causes: account lacks Global Admin role; AIPService module install failed; sign-in window was hidden behind PowerShell."
    Write-Info "Try opening Windows PowerShell 5.1 as admin and running: Import-Module AIPService; Connect-AipService"
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    exit 1
}

Write-Ok "AIP service status: $($aipResult.Status)"
Write-Info "Functional state : $($aipResult.FunctionalState)"
Write-Info "RMS service ID   : $($aipResult.RmsServiceId)"
Write-Info "Templates available: $($aipResult.TemplateCount)"
Write-Info "AIP licensing URL: $($aipResult.IntranetLicensingUrl)"

# -----------------------------------------------------------------------------
# Activate AIP if disabled
# -----------------------------------------------------------------------------
if ($aipResult.Status -ne 'Enabled') {
    Write-Step "Azure RMS is not enabled — activating"
    if ($PSCmdlet.ShouldProcess("Azure Information Protection service", "Enable-AipService")) {
        $enableScript = @'
Import-Module AIPService
Connect-AipService | Out-Null
Enable-AipService
Disconnect-AipService | Out-Null
'@
        & $winPsPath -NoProfile -Command $enableScript
        Write-Ok "Activation requested. Waiting 60 seconds for propagation..."
        Start-Sleep -Seconds 60
    }
} else {
    Write-Ok "Azure RMS is already enabled"
}

# -----------------------------------------------------------------------------
# Compare and fix the licensing URL
# -----------------------------------------------------------------------------
Write-Step "Comparing licensing URLs"

$correctUrl = $aipResult.IntranetLicensingUrl

if (-not $correctUrl) {
    Write-Fail "AIP did not return a licensing URL. Cannot proceed."
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    exit 1
}

$urlsMatch = ($currentLicensingUrl -and ($currentLicensingUrl.TrimEnd('/') -ieq $correctUrl.TrimEnd('/')))

if ($urlsMatch) {
    Write-Ok "Exchange LicensingLocation already matches AIP licensing URL"
} else {
    Write-Warn "MISMATCH detected:"
    Write-Info "  Exchange currently uses: $currentLicensingUrl"
    Write-Info "  AIP service publishes  : $correctUrl"

    if ($PSCmdlet.ShouldProcess("Exchange Online IRM configuration", "Set LicensingLocation to $correctUrl and refresh")) {
        Write-Step "Updating Exchange IRM LicensingLocation"
        Set-IRMConfiguration -LicensingLocation $correctUrl
        Write-Ok "LicensingLocation updated"

        Write-Step "Refreshing IRM (toggle InternalLicensing off then on)"
        Set-IRMConfiguration -InternalLicensingEnabled $false
        Write-Info "Disabled internal licensing, waiting 30 seconds..."
        Start-Sleep -Seconds 30
        Set-IRMConfiguration -InternalLicensingEnabled $true
        Write-Info "Re-enabled internal licensing, waiting 90 seconds for propagation..."
        Start-Sleep -Seconds 90
        Write-Ok "Refresh complete"
    }
}

# -----------------------------------------------------------------------------
# Ensure other key flags are correct
# -----------------------------------------------------------------------------
Write-Step "Verifying other IRM flags are set correctly"
$needsUpdate = $false
$updates = @{}

if (-not $irm.AzureRMSLicensingEnabled) {
    $updates['AzureRMSLicensingEnabled'] = $true
    $needsUpdate = $true
}
if (-not $irm.SimplifiedClientAccessEnabled) {
    $updates['SimplifiedClientAccessEnabled'] = $true
    $needsUpdate = $true
}

if ($needsUpdate) {
    Write-Warn "The following flags need to be enabled: $($updates.Keys -join ', ')"
    if ($PSCmdlet.ShouldProcess("Exchange Online IRM configuration", "Enable additional flags")) {
        Set-IRMConfiguration @updates
        Write-Ok "Flags updated"
    }
} else {
    Write-Ok "All key flags are already enabled"
}

# -----------------------------------------------------------------------------
# Final verification
# -----------------------------------------------------------------------------
Write-Step "Running Test-IRMConfiguration"
try {
    $testResult = Test-IRMConfiguration -Sender $TestSender
    $testResult | Format-List

    $resultText = $testResult.Results -join "`n"
    if ($resultText -match 'OVERALL RESULT:\s*PASS') {
        Write-Host ""
        Write-Ok "Message Encryption is working. Test-IRMConfiguration returned PASS."
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  - Allow 10-15 minutes for changes to propagate to Outlook clients."
        Write-Host "  - Fully quit Outlook (check the system tray) and restart it."
        Write-Host "  - Confirm each user has 'Azure Rights Management Service' enabled in their licence assignments."
    } else {
        Write-Fail "Test-IRMConfiguration did not return PASS. Review the output above."
        Write-Info "If this persists, open a Microsoft support ticket with the Information Protection / Exchange Online team."
    }
} catch {
    Write-Fail "Test-IRMConfiguration threw an error: $($_.Exception.Message)"
}

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
Write-Step "Disconnecting from Exchange Online"
Disconnect-ExchangeOnline -Confirm:$false | Out-Null
Write-Ok "Done"