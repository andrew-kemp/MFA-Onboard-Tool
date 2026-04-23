# Resend-BrokenLinks.ps1
# Resets all SharePoint list users with InviteStatus='Sent' back to 'Pending'
# so the Logic App re-sends them a fresh email with a working link.
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

    $config     = Get-IniContent -Path $configFile
    $siteUrl    = $config["SharePoint"]["SiteUrl"]
    $listTitle  = $config["SharePoint"]["ListTitle"]
    $listId     = $config["SharePoint"]["ListId"]   # may be empty on older installs

    if ([string]::IsNullOrWhiteSpace($siteUrl)) { throw "SharePoint SiteUrl not set in mfa-config.ini" }

    Write-Host "SharePoint site : $siteUrl" -ForegroundColor Gray
    Write-Host "List            : $listTitle`n" -ForegroundColor Gray

    # ── Get Graph access token via Azure CLI ──────────────────────────────────
    Write-Host "Getting Graph API access token..." -ForegroundColor Yellow
    $tokenJson   = az account get-access-token --resource https://graph.microsoft.com 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Not logged in to Azure CLI. Running az login..." -ForegroundColor Yellow
        az login --use-device-code | Out-Null
        $tokenJson = az account get-access-token --resource https://graph.microsoft.com 2>&1
    }
    $accessToken = ($tokenJson | ConvertFrom-Json).accessToken
    $headers = @{ Authorization = "Bearer $accessToken"; "Content-Type" = "application/json" }
    Write-Host "✓ Token obtained`n" -ForegroundColor Green

    # ── Resolve SharePoint site ID via Graph ──────────────────────────────────
    $uri       = [System.Uri]$siteUrl
    $spHost    = $uri.Host
    $sitePath  = $uri.AbsolutePath.TrimStart("/")   # e.g. "sites/MFAOps"
    $siteResp  = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$spHost`:/$sitePath" -Headers $headers
    $siteId    = $siteResp.id
    Write-Host "✓ Site ID: $siteId" -ForegroundColor Green

    # ── Resolve list ID if not in config ─────────────────────────────────────
    if ([string]::IsNullOrWhiteSpace($listId)) {
        if ([string]::IsNullOrWhiteSpace($listTitle)) { throw "SharePoint ListTitle not set in mfa-config.ini" }
        Write-Host "Looking up list '$listTitle'..." -ForegroundColor Yellow
        $listsResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists?`$filter=displayName eq '$listTitle'" -Headers $headers
        $listId    = $listsResp.value[0].id
        if ([string]::IsNullOrWhiteSpace($listId)) { throw "List '$listTitle' not found in SharePoint site" }
    }
    Write-Host "✓ List ID: $listId`n" -ForegroundColor Green

    # ── Fetch all Sent users (paginated) ──────────────────────────────────────
    Write-Host "Querying SharePoint for users with InviteStatus = 'Sent'..." -ForegroundColor Yellow
    $sentItems = [System.Collections.Generic.List[object]]::new()

    # SharePoint list filters on non-indexed custom columns require this header
    $filterHeaders = @{
        Authorization    = "Bearer $accessToken"
        "Content-Type"   = "application/json"
        Prefer           = "HonorNonIndexedQueriesWarningMayFailRandomly"
    }

    # Fetch all items and filter client-side — works regardless of indexed columns
    $nextUrl = "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items?`$expand=fields(`$select=id,Title,InviteStatus,InviteSentDate,ReminderCount)&`$top=500"

    Write-Host "  (fetching all list items and filtering client-side)" -ForegroundColor DarkGray
    $totalFetched = 0
    do {
        $resp    = Invoke-RestMethod -Uri $nextUrl -Headers $filterHeaders
        foreach ($item in $resp.value) {
            $totalFetched++
            if ($item.fields.InviteStatus -eq 'Sent') {
                $sentItems.Add($item)
            }
        }
        $nextUrl = $resp.'@odata.nextLink'
    } while ($nextUrl)

    Write-Host "  Scanned $totalFetched total list items" -ForegroundColor DarkGray

    if ($sentItems.Count -eq 0) {
        Write-Host "`n✓ No users with InviteStatus='Sent' found. Nothing to do." -ForegroundColor Green
        exit 0
    }

    Write-Host "`nFound $($sentItems.Count) user(s) with status 'Sent':" -ForegroundColor Yellow
    foreach ($item in $sentItems) {
        $upn  = $item.fields.Title
        $sent = $item.fields.InviteSentDate
        $reminders = $item.fields.ReminderCount
        Write-Host "  $upn  (sent: $sent, reminders: $reminders)" -ForegroundColor Gray
    }

    Write-Host ""
    $confirm = Read-Host "Reset all $($sentItems.Count) user(s) to Pending? (y/n)"
    if ($confirm -notmatch '^y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }

    # ── Reset each user to Pending ────────────────────────────────────────────
    Write-Host "`nResetting users to Pending..." -ForegroundColor Yellow
    $success = 0
    $failed  = 0

    foreach ($item in $sentItems) {
        $itemId = $item.id
        $upn    = $item.fields.Title
        $patchBody = @{
            fields = @{
                InviteStatus    = "Pending"
                LastChecked     = $null
                InviteSentDate  = $null
                ReminderCount   = 0
                LastReminderDate = $null
                TrackingToken   = [guid]::NewGuid().ToString()
            }
        } | ConvertTo-Json -Depth 5

        try {
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/lists/$listId/items/$itemId" `
                -Method PATCH -Headers $headers -Body $patchBody | Out-Null
            Write-Host "  ✓ $upn" -ForegroundColor Green
            $success++
        } catch {
            Write-Host "  ✗ $upn — $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }

    Write-Host "`n============================================" -ForegroundColor $(if ($failed -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Reset complete: $success succeeded, $failed failed" -ForegroundColor $(if ($failed -gt 0) { "Yellow" } else { "Green" })
    Write-Host "============================================`n" -ForegroundColor $(if ($failed -gt 0) { "Yellow" } else { "Green" })

    Write-Host "These users will receive a fresh email with a working link on the next" -ForegroundColor White
    Write-Host "Logic App run. To trigger it immediately, run:" -ForegroundColor White
    Write-Host ""

    # Print the trigger command using config values
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
    exit 1
}
