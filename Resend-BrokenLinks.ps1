# Resend-BrokenLinks.ps1
# Resets all SharePoint list users with InviteStatus='Sent' back to 'Pending'
# so the Logic App re-sends them a fresh email with a working link.
#
# Uses PnP PowerShell (SharePoint site-owner auth) — no Graph consent required.
# Run from the deployment folder (same location as mfa-config.ini).

$ErrorActionPreference = "Stop"
$configFile = "$PSScriptRoot\mfa-config.ini"

function Get-IniContent {
    param([string]$Path)
    $ini = @{}
    $section = ""
    switch -regex -file $Path {
        "^\[(.+)\]$" {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        "(.+?)\s*=\s*(.*)" {
            $name  = $matches[1]
            $value = $matches[2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

try {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  MFA Onboarding - Resend Broken Links" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan

    if (-not (Test-Path $configFile)) {
        throw "Config file not found: $configFile`nRun this script from the deployment folder."
    }

    $config    = Get-IniContent -Path $configFile
    $siteUrl   = $config["SharePoint"]["SiteUrl"]
    $listTitle = $config["SharePoint"]["ListTitle"]
    $clientId  = $config["SharePoint"]["ClientId"]

    if ([string]::IsNullOrWhiteSpace($siteUrl))   { throw "SharePoint SiteUrl not set in mfa-config.ini" }
    if ([string]::IsNullOrWhiteSpace($listTitle)) { throw "SharePoint ListTitle not set in mfa-config.ini" }

    Write-Host "SharePoint site : $siteUrl" -ForegroundColor Gray
    Write-Host "List            : $listTitle`n" -ForegroundColor Gray

    # ── Ensure PnP module is available ────────────────────────────────────────
    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        Write-Host "PnP.PowerShell module not found — installing..." -ForegroundColor Yellow
        Install-Module -Name PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module PnP.PowerShell -ErrorAction Stop

    # ── Connect to SharePoint ─────────────────────────────────────────────────
    Write-Host "Connecting to SharePoint (interactive login)..." -ForegroundColor Yellow
    if (-not [string]::IsNullOrWhiteSpace($clientId)) {
        Connect-PnPOnline -Url $siteUrl -Interactive -ClientId $clientId
    } else {
        Connect-PnPOnline -Url $siteUrl -Interactive
    }
    Write-Host "✓ Connected to SharePoint`n" -ForegroundColor Green

    # ── Fetch all Sent users ──────────────────────────────────────────────────
    Write-Host "Querying SharePoint for users with InviteStatus = 'Sent'..." -ForegroundColor Yellow
    $allItems  = Get-PnPListItem -List $listTitle -PageSize 500 -Fields "Title","InviteStatus","InviteSentDate","ReminderCount"
    $sentItems = @($allItems | Where-Object { $_["InviteStatus"] -eq "Sent" })

    Write-Host "  Scanned $($allItems.Count) total list items" -ForegroundColor DarkGray

    if ($sentItems.Count -eq 0) {
        Write-Host "`n✓ No users with InviteStatus='Sent' found. Nothing to do." -ForegroundColor Green
        Disconnect-PnPOnline
        exit 0
    }

    Write-Host "`nFound $($sentItems.Count) user(s) with status 'Sent':" -ForegroundColor Yellow
    foreach ($item in $sentItems) {
        $upn       = $item["Title"]
        $sent      = $item["InviteSentDate"]
        $reminders = $item["ReminderCount"]
        Write-Host "  $upn  (sent: $sent, reminders: $reminders)" -ForegroundColor Gray
    }

    Write-Host ""
    $confirm = Read-Host "Reset all $($sentItems.Count) user(s) to Pending? (y/n)"
    if ($confirm -notmatch '^y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        Disconnect-PnPOnline
        exit 0
    }

    # ── Reset each user to Pending ────────────────────────────────────────────
    Write-Host "`nResetting users to Pending..." -ForegroundColor Yellow
    $success = 0
    $failed  = 0

    foreach ($item in $sentItems) {
        $itemId = $item.Id
        $upn    = $item["Title"]
        try {
            Set-PnPListItem -List $listTitle -Identity $itemId -Values @{
                InviteStatus     = "Pending"
                LastChecked      = $null
                InviteSentDate   = $null
                ReminderCount    = 0
                LastReminderDate = $null
                TrackingToken    = [guid]::NewGuid().ToString()
            } | Out-Null
            Write-Host "  ✓ $upn" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "  ✗ $upn — $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }

    Disconnect-PnPOnline

    $summaryColor = if ($failed -gt 0) { "Yellow" } else { "Green" }
    Write-Host "`n============================================" -ForegroundColor $summaryColor
    Write-Host "  Reset complete: $success succeeded, $failed failed" -ForegroundColor $summaryColor
    Write-Host "============================================`n" -ForegroundColor $summaryColor

    Write-Host "These users will receive a fresh email with a working link on the next" -ForegroundColor White
    Write-Host "Logic App run. To trigger it immediately, run:" -ForegroundColor White
    Write-Host ""

    $resourceGroup = $config["Azure"]["ResourceGroup"]
    $logicAppName  = $config["LogicApp"]["LogicAppName"]
    if (-not [string]::IsNullOrWhiteSpace($resourceGroup) -and -not [string]::IsNullOrWhiteSpace($logicAppName)) {
        Write-Host "  az logic workflow trigger run --resource-group $resourceGroup --workflow-name $logicAppName --trigger-name Recurrence" -ForegroundColor Cyan
    } else {
        Write-Host "  az logic workflow trigger run --resource-group <ResourceGroup> --workflow-name <LogicAppName> --trigger-name Recurrence" -ForegroundColor Cyan
    }
    Write-Host ""

} catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch {}
    exit 1
}
