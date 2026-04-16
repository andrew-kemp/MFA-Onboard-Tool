using namespace System.Net

param($Request, $TriggerMetadata)

# 1x1 transparent GIF (43 bytes)
$pixelBytes = [Convert]::FromBase64String("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")

# Try to record the open event — fire-and-forget, never block the pixel
try {
    $token = $Request.Query.token
    if (-not [string]::IsNullOrWhiteSpace($token)) {

        $siteUrl  = $env:SHAREPOINT_SITE_URL
        $listId   = $env:SHAREPOINT_LIST_ID

        if ($siteUrl -and $listId) {
            # Get Managed Identity token for Graph
            $resource = "https://graph.microsoft.com"
            $tokenResponse = Invoke-RestMethod -Uri "$($env:IDENTITY_ENDPOINT)?resource=$resource&api-version=2019-08-01" `
                -Headers @{ "X-IDENTITY-HEADER" = $env:IDENTITY_HEADER } -Method Get

            $graphHeaders = @{
                "Authorization" = "Bearer $($tokenResponse.access_token)"
                "Content-Type"  = "application/json"
            }

            # Look up item by TrackingToken
            $filter = "fields/TrackingToken eq '$($token -replace "'","''")'"
            $encodedSiteUrl = [System.Web.HttpUtility]::UrlEncode($siteUrl)
            $searchUrl = "https://graph.microsoft.com/v1.0/sites/$($siteUrl -replace 'https://','' -replace '/',':/')/lists/$listId/items?`$filter=$filter&`$select=id,fields&`$expand=fields"

            $result = Invoke-RestMethod -Uri $searchUrl -Headers $graphHeaders -Method Get

            if ($result.value.Count -gt 0) {
                $itemId = $result.value[0].id
                # Only stamp EmailOpenedDate if not already set
                $existingOpened = $result.value[0].fields.EmailOpenedDate
                if ([string]::IsNullOrWhiteSpace($existingOpened)) {
                    $patchBody = @{ EmailOpenedDate = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json
                    $patchUrl = "https://graph.microsoft.com/v1.0/sites/$($siteUrl -replace 'https://','' -replace '/',':/')/lists/$listId/items/$itemId/fields"
                    Invoke-RestMethod -Uri $patchUrl -Headers $graphHeaders -Method Patch -Body $patchBody | Out-Null
                    Write-Host "Tracked email open for token: $token"
                }
            }
        }
    }
} catch {
    Write-Host "Track-open warning (non-blocking): $($_.Exception.Message)"
}

# Always return the pixel, regardless of tracking success
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode  = [HttpStatusCode]::OK
    Headers     = @{ "Content-Type" = "image/gif"; "Cache-Control" = "no-store, no-cache, must-revalidate" }
    Body        = $pixelBytes
})
