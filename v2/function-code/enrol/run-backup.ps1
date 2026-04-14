using namespace System.Net

param($Request, $TriggerMetadata)

# Get user email from query string
$userEmail = $Request.Query.user

if (-not $userEmail) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Missing user parameter"
    })
    return
}

Write-Host "Processing MFA click tracking for user: $userEmail"

try {
    # Get access token using Managed Identity
    $tokenResponse = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://graph.microsoft.com' -Headers @{Metadata="true"}
    $accessToken = $tokenResponse.access_token

    # Configuration
    $groupId = "8fca5ba6-a9b4-4bb6-a720-914e48098276"
    $siteUrl = "https://andykempdev.sharepoint.com/sites/MFAOps"
    $listId = "2ec02b4c-c793-497b-a7de-897c66e779f5"

    # Get user ID from email
    $userResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$userEmail" -Headers @{
        Authorization = "Bearer $accessToken"
    } -Method Get

    $userId = $userResponse.id
    Write-Host "Found user ID: $userId"

    # Add user to MFA Registration group
    try {
        $addMemberBody = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" -Headers @{
            Authorization = "Bearer $accessToken"
            "Content-Type" = "application/json"
        } -Method Post -Body $addMemberBody

        Write-Host "Successfully added user to MFA Registration group"
    }
    catch {
        # User might already be in group - that's okay
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "User already in group (this is fine)"
        }
        else {
            Write-Host "Error adding to group: $_"
        }
    }

    # Get SharePoint access token - SKIP FOR NOW TO DEBUG
    # $spTokenResponse = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://andykempdev.sharepoint.com' -Headers @{Metadata="true"}
    # $spAccessToken = $spTokenResponse.access_token

    Write-Host "Skipping SharePoint update for now - debugging"

    # Get list item for this user - COMMENTED OUT
    # $listItemsUrl = "$siteUrl/_api/web/lists(guid'$listId')/items?`$filter=Title eq '$userEmail'"
    Write-Host "Skipping SharePoint update for now - debugging"
    
    # COMMENTED OUT SHAREPOINT CODE
    # $listItems = Invoke-RestMethod -Uri $listItemsUrl -Headers @{
    #     Authorization = "Bearer $spAccessToken"
    #     Accept = "application/json;odata=verbose"
    # } -Method Get

    # if ($listItems.d.results.Count -gt 0) {
    #     $itemId = $listItems.d.results[0].Id
    #     Write-Host "Successfully updated ClickedLinkDate in SharePoint"
    # }
    # else {
    #     Write-Host "Warning: User not found in SharePoint list"
    # }

    # Redirect to Microsoft MFA setup page
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Redirect
        Headers = @{
            Location = "https://aka.ms/mfasetup"
        }
        Body = "Redirecting to MFA setup..."
    })

    Write-Host "Successfully processed click tracking for $userEmail"
}
catch {
    Write-Host "ERROR: $_"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = "Error processing request: $_"
    })
}
