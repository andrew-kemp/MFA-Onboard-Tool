using namespace System.Net

param($Request, $TriggerMetadata)

# Accept token parameter (preferred) or legacy user parameter
$trackingToken = $Request.Query.token
$userEmail = $Request.Query.user
$lookupByToken = $false

if (-not $trackingToken -and -not $userEmail) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Missing token or user parameter"
    })
    return
}

if ($trackingToken) {
    $lookupByToken = $true
    Write-Host "Processing MFA click tracking via token: $($trackingToken.Substring(0, 8))..."
} else {
    Write-Host "Processing MFA click tracking for user: $userEmail (legacy mode)"
}

try {
    # Get access token using Managed Identity (no Azure modules needed)
    $tokenAuthURI = $env:MSI_ENDPOINT + "?resource=https://graph.microsoft.com&api-version=2017-09-01"
    $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$env:MSI_SECRET"} -Uri $tokenAuthURI
    $token = $tokenResponse.access_token
    
    Write-Host "Successfully obtained access token via Managed Identity"
    
    # Get configuration from environment variables (set from INI file)
    $groupId = $env:MFA_GROUP_ID
    $siteUrl = $env:SHAREPOINT_SITE_URL
    $listId = $env:SHAREPOINT_LIST_ID
    
    if (-not $groupId) {
        throw "MFA_GROUP_ID environment variable not set"
    }
    if (-not $siteUrl) {
        throw "SHAREPOINT_SITE_URL environment variable not set"
    }
    if (-not $listId) {
        throw "SHAREPOINT_LIST_ID environment variable not set"
    }
    
    Write-Host "Configuration loaded from environment variables"
    Write-Host "  Group ID: $groupId"
    Write-Host "  Site URL: $siteUrl"
    Write-Host "  List ID: $listId"

    # Extract site path from URL for Graph API
    $siteUri = [System.Uri]$siteUrl
    $siteDomain = $siteUri.Host
    $sitePath = $siteUri.AbsolutePath

    # Resolve user from SharePoint (token lookup) or use provided UPN
    $spItemId = $null
    if ($lookupByToken) {
        $listItemsUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$filter=fields/TrackingToken eq '$trackingToken'&`$expand=fields"
        $listItems = Invoke-RestMethod -Uri $listItemsUrl -Headers @{
            Authorization = "Bearer $token"
        } -Method Get

        if ($listItems.value.Count -eq 0) {
            Write-Host "Warning: Token not found in SharePoint list"
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = 302
                Headers = @{ "Location" = "https://aka.ms/mfasetup" }
                Body = "Redirecting to MFA setup..."
            })
            return
        }

        $spItem = $listItems.value[0]
        $userEmail = $spItem.fields.Title
        $spItemId = $spItem.id

        # Duplicate click protection
        if ($spItem.fields.ClickedLinkDate) {
            Write-Host "User $userEmail already clicked on $($spItem.fields.ClickedLinkDate) - skipping"
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = 302
                Headers = @{ "Location" = "https://aka.ms/mfasetup" }
                Body = "Redirecting to MFA setup..."
            })
            return
        }

        Write-Host "Resolved token to user: $userEmail (Item ID: $spItemId)"
    }

    # Get user ID from email
    $userResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$userEmail" -Headers @{
        Authorization = "Bearer $token"
    } -Method Get

    $userId = $userResponse.id
    Write-Host "Found user ID: $userId"

    # Add user to MFA Registration group
    $addedToGroup = $false
    $alreadyInGroup = $false
    try {
        $addMemberBody = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" -Headers @{
            Authorization = "Bearer $token"
            "Content-Type" = "application/json"
        } -Method Post -Body $addMemberBody

        Write-Host "Successfully added user to MFA Registration group"
        $addedToGroup = $true
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "User already in group (this is fine)"
            $alreadyInGroup = $true
            $addedToGroup = $true
        }
        else {
            Write-Host "Error adding to group: $_"
        }
    }

    # Update SharePoint list with ClickedLinkDate and GroupAdded status
    try {
        Write-Host "Updating SharePoint list..."

        # If we haven't looked up SharePoint yet (legacy UPN mode), do it now
        if (-not $spItemId) {
            $listItemsUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$filter=fields/Title eq '$userEmail'&`$expand=fields"
            $listItems = Invoke-RestMethod -Uri $listItemsUrl -Headers @{
                Authorization = "Bearer $token"
            } -Method Get

            if ($listItems.value.Count -gt 0) {
                $spItemId = $listItems.value[0].id
            } else {
                Write-Host "Warning: User not found in SharePoint list"
            }
        }

        if ($spItemId) {
            $updateUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items/$spItemId/fields"
            $currentTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            $updateBody = @{
                ClickedLinkDate = $currentTime
                InGroup = $addedToGroup
                AddedToGroupDate = if ($addedToGroup) { $currentTime } else { $null }
                InviteStatus = "Sent"
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $updateUrl -Headers @{
                Authorization = "Bearer $token"
                "Content-Type" = "application/json"
            } -Method Patch -Body $updateBody

            Write-Host "Successfully updated SharePoint list:"
            Write-Host "  - ClickedLinkDate: $currentTime"
            Write-Host "  - InGroup: $(if ($addedToGroup) { 'True' } else { 'False' })"
            Write-Host "  - InviteStatus: Sent (kept for Logic App monitoring)"
        }
    }
    catch {
        Write-Host "Warning: Could not update SharePoint (non-critical): $_"
        Write-Host "Error details: $($_.Exception.Message)"
    }

    # Check if request is from browser (User-Agent header) or API call (Upload Portal)
    $userAgent = $Request.Headers.'User-Agent'
    $acceptHeader = $Request.Headers.'Accept'
    
    # If Accept header contains "application/json" or no User-Agent, return JSON (Upload Portal)
    $returnJson = ($acceptHeader -like "*application/json*") -or ([string]::IsNullOrEmpty($userAgent))
    
    if ($returnJson) {
        # Return JSON for Upload Portal / API calls
        $jsonResponse = @{
            success = $true
            message = if ($alreadyInGroup) { "User already in group" } else { "User added to group" }
            userEmail = $userEmail
            addedToGroup = $addedToGroup
            alreadyInGroup = $alreadyInGroup
        } | ConvertTo-Json
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Headers = @{
                "Content-Type" = "application/json; charset=utf-8"
            }
            Body = $jsonResponse
        })
        
        Write-Host "Successfully processed API request for $userEmail (JSON response)"
        return
    }
    
    # For browser/email clicks: Simple redirect to MFA setup (PowerShell Functions don't render HTML properly)
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = 302
        Headers = @{
            "Location" = "https://aka.ms/mfasetup"
        }
        Body = "Redirecting to MFA setup..."
    })
    
    Write-Host "Successfully processed click tracking for $userEmail (redirect response)"
}
catch {
    Write-Host "ERROR: $_"
    Write-Host "Error Details: $($_.Exception.Message)"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "Error processing request: $($_.Exception.Message)"
    })
}







