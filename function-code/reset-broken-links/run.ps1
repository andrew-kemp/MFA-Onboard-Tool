using namespace System.Net

param($Request, $TriggerMetadata)

# ────────────────────────────────────────────────────────────────────────────
# reset-broken-links function
# Admin endpoint — resets every SharePoint list row where InviteStatus='Sent'
# back to 'Pending' with a fresh TrackingToken so the Logic App re-sends a
# working link. Called by Resend-BrokenLinks.ps1.
# Uses the Function App's managed identity (Sites.ReadWrite.All granted at
# deployment time).
# ────────────────────────────────────────────────────────────────────────────

$summary = [ordered]@{
    success     = $false
    scanned     = 0
    sentFound   = 0
    reset       = 0
    failed      = 0
    failures    = @()
    users       = @()
    message     = ""
}

try {
    # ── Get access token via Managed Identity ────────────────────────────────
    if ($env:IDENTITY_ENDPOINT) {
        $tokenAuthURI = $env:IDENTITY_ENDPOINT + "?resource=https://graph.microsoft.com&api-version=2019-08-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER"=$env:IDENTITY_HEADER} -Uri $tokenAuthURI
    } elseif ($env:MSI_ENDPOINT) {
        $tokenAuthURI = $env:MSI_ENDPOINT + "?resource=https://graph.microsoft.com&api-version=2017-09-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"=$env:MSI_SECRET} -Uri $tokenAuthURI
    } else {
        throw "No Managed Identity endpoint found. Ensure System Assigned Managed Identity is enabled."
    }
    $token = $tokenResponse.access_token

    # ── Configuration ────────────────────────────────────────────────────────
    $siteUrl = $env:SHAREPOINT_SITE_URL
    $listId  = $env:SHAREPOINT_LIST_ID
    if (-not $siteUrl) { throw "SHAREPOINT_SITE_URL not set" }
    if (-not $listId)  { throw "SHAREPOINT_LIST_ID not set" }

    $siteUri    = [System.Uri]$siteUrl
    $siteDomain = $siteUri.Host
    $sitePath   = $siteUri.AbsolutePath

    $graphHeaders = @{
        Authorization   = "Bearer $token"
        "Content-Type"  = "application/json"
    }

    # ── Fetch all list items (paginated) and filter client-side ──────────────
    $allItems = @()
    $nextUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$expand=fields(`$select=Title,InviteStatus,InviteSentDate,ReminderCount)&`$top=500"

    while ($nextUrl) {
        $page = Invoke-RestMethod -Uri $nextUrl -Headers @{ Authorization = "Bearer $token" } -Method Get
        if ($page.value) { $allItems += $page.value }
        $nextUrl = $page.'@odata.nextLink'
    }

    $summary.scanned = $allItems.Count

    $sentItems = @($allItems | Where-Object { $_.fields.InviteStatus -eq 'Sent' })
    $summary.sentFound = $sentItems.Count

    if ($sentItems.Count -eq 0) {
        $summary.success = $true
        $summary.message = "No users with InviteStatus='Sent' found."
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode  = [HttpStatusCode]::OK
            ContentType = "application/json; charset=utf-8"
            Body        = ($summary | ConvertTo-Json -Depth 4)
        })
        return
    }

    # ── Check dryRun parameter ───────────────────────────────────────────────
    $body    = $null
    if ($Request.Body) {
        if ($Request.Body -is [string]) {
            try { $body = $Request.Body | ConvertFrom-Json -ErrorAction Stop } catch { $body = $null }
        } else {
            $body = $Request.Body
        }
    }
    $dryRun = $false
    if ($body -and $body.dryRun) { $dryRun = [bool]$body.dryRun }

    if ($dryRun) {
        $summary.success = $true
        $summary.users   = @($sentItems | ForEach-Object {
            [ordered]@{
                upn            = $_.fields.Title
                inviteSentDate = $_.fields.InviteSentDate
                reminderCount  = $_.fields.ReminderCount
            }
        })
        $summary.message = "Dry run — no changes applied. $($sentItems.Count) user(s) would be reset."
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode  = [HttpStatusCode]::OK
            ContentType = "application/json; charset=utf-8"
            Body        = ($summary | ConvertTo-Json -Depth 4)
        })
        return
    }

    # ── Reset each Sent row back to Pending ──────────────────────────────────
    foreach ($item in $sentItems) {
        $itemId = $item.id
        $upn    = $item.fields.Title

        $patchUrl  = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items/$itemId/fields"
        $patchBody = @{
            InviteStatus     = "Pending"
            LastChecked      = $null
            InviteSentDate   = $null
            ReminderCount    = 0
            LastReminderDate = $null
            TrackingToken    = [guid]::NewGuid().ToString()
        } | ConvertTo-Json -Compress

        try {
            Invoke-RestMethod -Uri $patchUrl -Headers $graphHeaders -Method Patch -Body $patchBody | Out-Null
            $summary.reset++
            $summary.users += [ordered]@{ upn = $upn; status = "reset" }
        } catch {
            $summary.failed++
            $errMsg = $_.Exception.Message
            $summary.failures += [ordered]@{ upn = $upn; error = $errMsg }
        }
    }

    $summary.success = ($summary.failed -eq 0)
    $summary.message = "Reset $($summary.reset) of $($summary.sentFound) user(s). Failed: $($summary.failed)."

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::OK
        ContentType = "application/json; charset=utf-8"
        Body        = ($summary | ConvertTo-Json -Depth 4)
    })
}
catch {
    $summary.message = "Error: $($_.Exception.Message)"
    Write-Host "ERROR: $($_.Exception.Message)"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::InternalServerError
        ContentType = "application/json; charset=utf-8"
        Body        = ($summary | ConvertTo-Json -Depth 4)
    })
}
