using namespace System.Net

param($Request, $TriggerMetadata)

# CORS headers
$corsHeaders = @{
    'Access-Control-Allow-Origin' = '*'
    'Access-Control-Allow-Methods' = 'POST, OPTIONS'
    'Access-Control-Allow-Headers' = 'Content-Type, Authorization'
}

# Handle OPTIONS preflight request
if ($Request.Method -eq 'OPTIONS') {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers = $corsHeaders
        Body = ""
    })
    return
}

try {
    Write-Host "Upload Users function triggered"
    
    # Parse request body
    $body = $Request.Body
    $csvContent = $body.csv
    $batchId = $body.batchId
    
    if ([string]::IsNullOrWhiteSpace($csvContent)) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers = $corsHeaders
            Body = @{error = "No CSV content provided"} | ConvertTo-Json
        })
        return
    }
    
    if ([string]::IsNullOrWhiteSpace($batchId)) {
        $batchId = (Get-Date).ToString("yyyy-MM-dd-HHmm")
    }
    
    Write-Host "Processing batch: $batchId"
    
    # Parse CSV
    $users = $csvContent | ConvertFrom-Csv
    
    if ($users.Count -eq 0) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers = $corsHeaders
            Body = @{error = "CSV contains no users"} | ConvertTo-Json
        })
        return
    }
    
    # Validate CSV has UPN column
    $firstUser = $users[0]
    $upnProperty = $firstUser.PSObject.Properties.Name | Where-Object { $_ -match '^(UPN|UserPrincipalName|Email)$' } | Select-Object -First 1
    
    if (-not $upnProperty) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Headers = $corsHeaders
            Body = @{error = "CSV must contain a column named 'UPN', 'UserPrincipalName', or 'Email'"} | ConvertTo-Json
        })
        return
    }
    
    Write-Host "Found UPN column: $upnProperty"
    
    # Get SharePoint site and list info from environment variables (set during deployment)
    $siteUrl = $env:SHAREPOINT_SITE_URL
    $listId = $env:SHAREPOINT_LIST_ID
    $siteName = $env:SHAREPOINT_SITE_NAME  # e.g., "MFAOps"
    
    if ([string]::IsNullOrWhiteSpace($siteUrl) -or [string]::IsNullOrWhiteSpace($listId)) {
        throw "SharePoint configuration not found. Ensure SHAREPOINT_SITE_URL and SHAREPOINT_LIST_ID are set."
    }
    
    # Get SharePoint hostname for Graph API
    $uri = [System.Uri]$siteUrl
    $spHostname = $uri.Host
    
    # Get Graph API access token using Managed Identity
    Write-Host "Getting Graph API access token..."
    Connect-AzAccount -Identity -ErrorAction Stop
    $token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
    
    # Get existing users from SharePoint using Graph API
    Write-Host "Checking for existing users..."
    $listItemsUrl = "https://graph.microsoft.com/v1.0/sites/$spHostname`:/sites/$siteName`:/lists/$listId/items?`$expand=fields(`$select=Title,Id)"
    $existingItemsResponse = Invoke-RestMethod -Uri $listItemsUrl -Headers @{
        Authorization = "Bearer $token"
        Accept = "application/json"
    } -Method Get
    
    $existingUpns = @{}
    foreach ($item in $existingItemsResponse.value) {
        if ($item.fields.Title) {
            $existingUpns[$item.fields.Title.ToLower()] = $item.id
        }
    }
    
    Write-Host "Found $($existingUpns.Count) existing users"
    
    # Process users
    $results = @{
        added = @()
        updated = @()
        skipped = @()
        errors = @()
        total = $users.Count
    }
    
    foreach ($user in $users) {
        $upn = $user.$upnProperty
        
        if ([string]::IsNullOrWhiteSpace($upn)) {
            $results.skipped += @{upn = "(empty)"; reason = "Empty UPN"}
            continue
        }
        
        # Validate email format
        if ($upn -notmatch '^[^@]+@[^@]+\.[^@]+$') {
            $results.skipped += @{upn = $upn; reason = "Invalid email format"}
            continue
        }
        
        try {
            $upnLower = $upn.ToLower()
            
            if ($existingUpns.ContainsKey($upnLower)) {
                # Update existing user using Graph API
                $itemId = $existingUpns[$upnLower]
                
                $updateUrl = "https://graph.microsoft.com/v1.0/sites/$spHostname`:/sites/$siteName`:/lists/$listId/items/$itemId/fields"
                $updateBody = @{
                    InviteStatus = "Pending"
                    MFARegistrationState = "Unknown"
                    SourceBatchId = $batchId
                } | ConvertTo-Json
                
                Invoke-RestMethod -Uri $updateUrl -Headers @{
                    Authorization = "Bearer $token"
                    "Content-Type" = "application/json"
                } -Method Patch -Body $updateBody | Out-Null
                
                $results.updated += $upn
                Write-Host "Updated: $upn"
            }
            else {
                # Add new user using Graph API
                $addUrl = "https://graph.microsoft.com/v1.0/sites/$spHostname`:/sites/$siteName`:/lists/$listId/items"
                $addBody = @{
                    fields = @{
                        Title = $upn
                        InviteStatus = "Pending"
                        MFARegistrationState = "Unknown"
                        InGroup = $false
                        ReminderCount = 0
                        SourceBatchId = $batchId
                    }
                } | ConvertTo-Json
                
                Invoke-RestMethod -Uri $addUrl -Headers @{
                    Authorization = "Bearer $token"
                    "Content-Type" = "application/json"
                } -Method Post -Body $addBody | Out-Null
                
                $results.added += $upn
                Write-Host "Added: $upn"
            }
        }
        catch {
            $results.errors += @{upn = $upn; error = $_.Exception.Message}
            Write-Host "Error processing $upn : $($_.Exception.Message)"
        }
    }
    
    Write-Host "Upload complete. Added: $($results.added.Count), Updated: $($results.updated.Count), Errors: $($results.errors.Count)"
    
    # Trigger Logic App to send invitation emails immediately
    $logicAppUrl = $env:LOGIC_APP_TRIGGER_URL
    Write-Host "Logic App Trigger URL configured: $($logicAppUrl)"
    
    if (-not [string]::IsNullOrWhiteSpace($logicAppUrl) -and $logicAppUrl -ne "NOT_SET_YET") {
        try {
            Write-Host "Triggering Logic App to send invitation emails..."
            Write-Host "  Getting Azure Management token..."
            
            # Get access token for Azure Management API using Managed Identity
            $mgmtToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
            Write-Host "  Token acquired: $($mgmtToken.Substring(0, 20))..."
            
            # Trigger Logic App using Management API
            $headers = @{
                'Authorization' = "Bearer $mgmtToken"
                'Content-Type' = 'application/json'
            }
            
            Write-Host "  Calling Logic App trigger: $logicAppUrl"
            $response = Invoke-RestMethod -Uri $logicAppUrl -Method Post -Headers $headers -Body "{}" -TimeoutSec 10
            Write-Host "✓ Logic App triggered successfully - invitation emails will be sent shortly"
            Write-Host "  Response: $($response | ConvertTo-Json -Compress)"
            $results.logicAppTriggered = $true
        }
        catch {
            Write-Host "⚠ Warning: Could not trigger Logic App: $($_.Exception.Message)"
            Write-Host "  Status Code: $($_.Exception.Response.StatusCode.value__)"
            Write-Host "  Emails will be sent on the next scheduled run"
            $results.logicAppTriggered = $false
            $results.triggerError = $_.Exception.Message
        }
    }
    else {
        Write-Host "ℹ Logic App trigger not configured (URL: $logicAppUrl)"
        Write-Host "  Emails will be sent on the next scheduled run"
        $results.logicAppTriggered = $false
    }
    
    # Return results
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers = $corsHeaders
        Body = ($results | ConvertTo-Json -Depth 5)
    })
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Headers = $corsHeaders
        Body = @{error = $_.Exception.Message} | ConvertTo-Json
    })
}
