# Resend-BrokenLinks.ps1
# Calls the Function App's reset-broken-links endpoint to reset every
# SharePoint list row with InviteStatus='Sent' back to 'Pending' with a
# fresh TrackingToken.
#
# The function uses the Function App's managed identity (Sites.ReadWrite.All
# already granted at deployment) — no user Graph consent required.
#
# Prerequisite: Run .\Apply-ScalingFix.ps1 first to deploy the reset-broken-links
# endpoint (if you haven't already after pulling the latest tool version).
#
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

    $config          = Get-IniContent -Path $configFile
    $resourceGroup   = $config["Azure"]["ResourceGroup"]
    $functionAppName = $config["FunctionApp"]["FunctionAppName"]
    if (-not $functionAppName) { $functionAppName = $config["Azure"]["FunctionAppName"] }

    if ([string]::IsNullOrWhiteSpace($resourceGroup))   { throw "Azure ResourceGroup not set in mfa-config.ini" }
    if ([string]::IsNullOrWhiteSpace($functionAppName)) { throw "FunctionApp name not set in mfa-config.ini" }

    Write-Host "Resource Group : $resourceGroup" -ForegroundColor Gray
    Write-Host "Function App   : $functionAppName`n" -ForegroundColor Gray

    # ── Verify az login ──────────────────────────────────────────────────────
    $accountJson = az account show 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Not logged in to Azure CLI. Run 'az login' first."
    }

    # ── Get the default host key for the function ───────────────────────────
    Write-Host "Getting function key..." -ForegroundColor Yellow
    $keysJson = az functionapp keys list `
        --resource-group $resourceGroup `
        --name $functionAppName `
        --query "functionKeys.default" -o tsv 2>&1

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($keysJson)) {
        # Fall back to master key
        Write-Host "  (falling back to master key)" -ForegroundColor DarkGray
        $keysJson = az functionapp keys list `
            --resource-group $resourceGroup `
            --name $functionAppName `
            --query "masterKey" -o tsv 2>&1
    }

    $functionKey = $keysJson.Trim()
    if ([string]::IsNullOrWhiteSpace($functionKey)) {
        throw "Could not retrieve a function key for $functionAppName"
    }
    Write-Host "✓ Function key obtained`n" -ForegroundColor Green

    # ── Build endpoint URL ───────────────────────────────────────────────────
    $resetUrl = "https://$functionAppName.azurewebsites.net/api/reset-broken-links?code=$functionKey"

    # ── Step 1: dry run to list what would be reset ──────────────────────────
    Write-Host "Querying SharePoint (dry run)..." -ForegroundColor Yellow
    $dryRunBody = @{ dryRun = $true } | ConvertTo-Json -Compress

    try {
        $dryResult = Invoke-RestMethod -Uri $resetUrl -Method Post -Body $dryRunBody -ContentType "application/json"
    } catch {
        $errDetail = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $s = $_.Exception.Response.GetResponseStream()
                $r = New-Object System.IO.StreamReader($s)
                $errDetail = $r.ReadToEnd()
            } catch {}
        }
        throw "Function call failed (is the reset-broken-links endpoint deployed? Run Apply-ScalingFix.ps1 first): $errDetail"
    }

    Write-Host "  Scanned $($dryResult.scanned) list item(s)" -ForegroundColor DarkGray

    if ($dryResult.sentFound -eq 0) {
        Write-Host "`n✓ No users with InviteStatus='Sent' found. Nothing to do." -ForegroundColor Green
        exit 0
    }

    Write-Host "`nFound $($dryResult.sentFound) user(s) with status 'Sent':" -ForegroundColor Yellow
    foreach ($u in $dryResult.users) {
        Write-Host "  $($u.upn)  (sent: $($u.inviteSentDate), reminders: $($u.reminderCount))" -ForegroundColor Gray
    }

    Write-Host ""
    $confirm = Read-Host "Reset all $($dryResult.sentFound) user(s) to Pending? (y/n)"
    if ($confirm -notmatch '^y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }

    # ── Step 2: actual reset ─────────────────────────────────────────────────
    Write-Host "`nResetting users to Pending..." -ForegroundColor Yellow
    $result = Invoke-RestMethod -Uri $resetUrl -Method Post -Body "{}" -ContentType "application/json"

    foreach ($u in $result.users) {
        Write-Host "  ✓ $($u.upn)" -ForegroundColor Green
    }
    foreach ($f in $result.failures) {
        Write-Host "  ✗ $($f.upn) — $($f.error)" -ForegroundColor Red
    }

    $summaryColor = if ($result.failed -gt 0) { "Yellow" } else { "Green" }
    Write-Host "`n============================================" -ForegroundColor $summaryColor
    Write-Host "  Reset complete: $($result.reset) succeeded, $($result.failed) failed" -ForegroundColor $summaryColor
    Write-Host "============================================`n" -ForegroundColor $summaryColor

    Write-Host "These users will receive a fresh email with a working link on the next" -ForegroundColor White
    Write-Host "Logic App run. To trigger it immediately, run:" -ForegroundColor White
    Write-Host ""

    $logicAppName = $config["LogicApp"]["LogicAppName"]
    if (-not [string]::IsNullOrWhiteSpace($logicAppName)) {
        Write-Host "  az logic workflow trigger run --resource-group $resourceGroup --workflow-name $logicAppName --trigger-name Recurrence" -ForegroundColor Cyan
    } else {
        Write-Host "  az logic workflow trigger run --resource-group $resourceGroup --workflow-name <LogicAppName> --trigger-name Recurrence" -ForegroundColor Cyan
    }
    Write-Host ""

} catch {
    Write-Host "`n✗ Error: $_" -ForegroundColor Red
    exit 1
}
