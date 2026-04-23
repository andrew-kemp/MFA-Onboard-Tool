# Resend-BrokenLinks.ps1
# Resets all SharePoint list users with InviteStatus='Sent' back to 'Pending'
# so the Logic App re-sends them a fresh email with a working link.
#
# Uses the SharePoint REST API authenticated with an Azure CLI token for the
# customer's own SharePoint tenant. Because this is SharePoint's own API,
# authorization is controlled by SharePoint site permissions — if you're a
# site owner, this works. No Graph consent required.
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

    $config    = Get-IniContent -Path $configFile
    $siteUrl   = $config["SharePoint"]["SiteUrl"].TrimEnd('/')
    $listTitle = $config["SharePoint"]["ListTitle"]

    if ([string]::IsNullOrWhiteSpace($siteUrl))   { throw "SharePoint SiteUrl not set in mfa-config.ini" }
    if ([string]::IsNullOrWhiteSpace($listTitle)) { throw "SharePoint ListTitle not set in mfa-config.ini" }

    # Derive the SharePoint tenant root (https://<tenant>.sharepoint.com) for the token resource
    $siteUri     = [System.Uri]$siteUrl
    $spResource  = "https://$($siteUri.Host)"

    Write-Host "SharePoint site : $siteUrl"   -ForegroundColor Gray
    Write-Host "List            : $listTitle" -ForegroundColor Gray
    Write-Host "Resource        : $spResource`n" -ForegroundColor DarkGray

    # ── Get SharePoint access token via Azure CLI ─────────────────────────────
    Write-Host "Getting SharePoint access token (uses your Azure CLI login)..." -ForegroundColor Yellow
    $tokenJson = az account get-access-token --resource $spResource 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $tokenJson -ForegroundColor Red
        throw "Failed to get SharePoint access token. Run 'az login' first."
    }
    $token = ($tokenJson | ConvertFrom-Json).accessToken
    Write-Host "✓ Token obtained`n" -ForegroundColor Green

    $headers = @{
        Authorization = "Bearer $token"
        Accept        = "application/json;odata=nometadata"
    }

    # ── Encode the list title for URL ─────────────────────────────────────────
    $encodedTitle = [System.Uri]::EscapeDataString($listTitle)
    $listBase     = "$siteUrl/_api/web/lists/getbytitle('$encodedTitle')"

    # ── Fetch all Sent users ──────────────────────────────────────────────────
    Write-Host "Querying SharePoint for users with InviteStatus = 'Sent'..." -ForegroundColor Yellow

    $selectFields = "Id,Title,InviteStatus,InviteSentDate,ReminderCount"
    $filter       = "InviteStatus eq 'Sent'"
    $queryUrl     = "$listBase/items?`$select=$selectFields&`$filter=$([System.Uri]::EscapeDataString($filter))&`$top=5000"

    $sentItems = @()
    $nextUrl   = $queryUrl
    while ($nextUrl) {
        $page = Invoke-RestMethod -Uri $nextUrl -Headers $headers -Method Get
        if ($page.value) { $sentItems += $page.value }
        $nextUrl = $page.'odata.nextLink'
    }

    if ($sentItems.Count -eq 0) {
        Write-Host "`n✓ No users with InviteStatus='Sent' found. Nothing to do." -ForegroundColor Green
        exit 0
    }

    Write-Host "`nFound $($sentItems.Count) user(s) with status 'Sent':" -ForegroundColor Yellow
    foreach ($item in $sentItems) {
        Write-Host "  $($item.Title)  (sent: $($item.InviteSentDate), reminders: $($item.ReminderCount))" -ForegroundColor Gray
    }

    Write-Host ""
    $confirm = Read-Host "Reset all $($sentItems.Count) user(s) to Pending? (y/n)"
    if ($confirm -notmatch '^y') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }

    # ── Reset each user to Pending via SharePoint MERGE ───────────────────────
    Write-Host "`nResetting users to Pending..." -ForegroundColor Yellow
    $success = 0
    $failed  = 0

    $updateHeaders = @{
        Authorization    = "Bearer $token"
        Accept           = "application/json;odata=nometadata"
        "Content-Type"   = "application/json;odata=nometadata"
        "X-HTTP-Method"  = "MERGE"
        "If-Match"       = "*"
    }

    foreach ($item in $sentItems) {
        $upn    = $item.Title
        $itemId = $item.Id
        $updateBody = @{
            InviteStatus     = "Pending"
            LastChecked      = $null
            InviteSentDate   = $null
            ReminderCount    = 0
            LastReminderDate = $null
            TrackingToken    = [guid]::NewGuid().ToString()
        } | ConvertTo-Json -Compress

        try {
            Invoke-RestMethod -Uri "$listBase/items($itemId)" -Headers $updateHeaders -Method Post -Body $updateBody | Out-Null
            Write-Host "  ✓ $upn" -ForegroundColor Green
            $success++
        } catch {
            $errMsg = $_.Exception.Message
            if ($_.Exception.Response) {
                try {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $errMsg = $reader.ReadToEnd()
                } catch {}
            }
            Write-Host "  ✗ $upn — $errMsg" -ForegroundColor Red
            $failed++
        }
    }

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
    exit 1
}
