# Step 07 - Deploy Upload Portal
# Creates Azure Storage Static Website and deploys upload portal

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
            $name = $matches[1]
            $value = $matches[2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

function Set-IniValue {
    param([string]$Path, [string]$Section, [string]$Key, [string]$Value)
    
    # Read the INI file using the parser to get structured data
    $ini = Get-IniContent -Path $Path
    
    # Ensure section exists
    if (-not $ini.ContainsKey($Section)) {
        $ini[$Section] = @{}
    }
    
    # Set the value
    $ini[$Section][$Key] = $Value
    
    # Write back to file (this prevents duplicates by rebuilding the file)
    $output = @()
    foreach ($sectionName in $ini.Keys) {
        $output += "[$sectionName]"
        foreach ($keyName in $ini[$sectionName].Keys) {
            $output += "$keyName=$($ini[$sectionName][$keyName])"
        }
        $output += ""
    }
    
    Set-Content -Path $Path -Value ($output -join "`r`n") -Force
}

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Step 07 - Deploy Upload Portal" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $config = Get-IniContent -Path $configFile
    
    $azContext = Get-AzContext
    if ($null -eq $azContext) {
        Connect-AzAccount
    }
    
    # Set the correct subscription
    $subscriptionId = $config["Tenant"]["SubscriptionId"]
    Set-AzContext -SubscriptionId $subscriptionId | Out-Null
    
    $resourceGroup = $config["Azure"]["ResourceGroup"]
    $storageAccountName = $config["Azure"]["StorageAccountName"]
    $functionAppName = $config["Azure"]["FunctionAppName"]
    $siteUrl = $config["SharePoint"]["SiteUrl"]
    
    # Parse site URL to get list ID - need to connect to SharePoint
    Write-Host "Getting SharePoint List ID..." -ForegroundColor Yellow
    $clientId = $config["SharePoint"]["ClientId"]
    $thumbprint = $config["SharePoint"]["CertificateThumbprint"]
    $listTitle = $config["SharePoint"]["ListTitle"]
    $tenantId = $config["Tenant"]["TenantId"]
    
    Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantId
    $list = Get-PnPList -Identity $listTitle
    $listId = $list.Id.Guid
    Disconnect-PnPOnline
    Write-Host "✓ List ID: $listId" -ForegroundColor Green
    
    # Add SourceBatchId column if doesn't exist
    Write-Host "Ensuring SourceBatchId column exists..." -ForegroundColor Yellow
    Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantId
    $field = Get-PnPField -List $listTitle -Identity "SourceBatchId" -ErrorAction SilentlyContinue
    if ($null -eq $field) {
        Add-PnPField -List $listTitle -DisplayName "Source Batch ID" -InternalName "SourceBatchId" -Type Text -AddToDefaultView
        Write-Host "✓ SourceBatchId column created" -ForegroundColor Green
    } else {
        Write-Host "✓ SourceBatchId column exists" -ForegroundColor Green
    }
    Disconnect-PnPOnline
    
    # Configure Function App environment variables for upload function
    Write-Host "`nConfiguring Function App environment variables..." -ForegroundColor Yellow
    az functionapp config appsettings set --resource-group $resourceGroup --name $functionAppName --settings "SHAREPOINT_SITE_URL=$siteUrl" "SHAREPOINT_LIST_ID=$listId" | Out-Null
    Write-Host "✓ Environment variables configured" -ForegroundColor Green
    
    # Note: Function code deployment is handled by Step 05
    # Step 07 only configures additional environment variables needed for the upload function
    
    # Enable static website on storage account
    Write-Host "`nEnabling static website hosting..." -ForegroundColor Yellow
    az storage blob service-properties update --account-name $storageAccountName --static-website --index-document upload-portal.html --auth-mode login | Out-Null
    Write-Host "✓ Static website enabled" -ForegroundColor Green
    
    # Get the actual static website URL from Azure
    Write-Host "Getting static website URL..." -ForegroundColor Yellow
    $storageAccount = az storage account show --name $storageAccountName --resource-group $resourceGroup | ConvertFrom-Json
    $staticWebsiteUrl = $storageAccount.primaryEndpoints.web.TrimEnd('/')
    Write-Host "✓ Static website URL: $staticWebsiteUrl" -ForegroundColor Gray
    
    # Create App Registration for portal authentication
    Write-Host "`nCreating App Registration for portal..." -ForegroundColor Yellow
    $appName = $config["UploadPortal"]["AppRegName"]
    if ([string]::IsNullOrWhiteSpace($appName)) {
        $appName = "MFA-Upload-Portal" # Fallback default
    }
    
    # Check if app already exists
    $existingApp = Get-AzADApplication -DisplayName $appName
    
    if ($null -eq $existingApp) {
        # Create new app with SPA platform
        $app = New-AzADApplication -DisplayName $appName
        $appClientId = $app.AppId
        $appObjectId = $app.Id
        Write-Host "✓ App Registration created" -ForegroundColor Green
        Write-Host "  Client ID: $appClientId" -ForegroundColor Gray
        
        # Configure SPA redirect URIs
        Write-Host "Configuring SPA platform..." -ForegroundColor Yellow
        $spa = New-Object -TypeName Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.MicrosoftGraphSpaApplication
        $spa.RedirectUri = @("$staticWebsiteUrl/upload-portal.html")
        Update-AzADApplication -ObjectId $appObjectId -SPARedirectUri $spa.RedirectUri
        Write-Host "✓ SPA platform configured" -ForegroundColor Green
        
        # Add Microsoft Graph permissions
        Write-Host "Adding Microsoft Graph permissions..." -ForegroundColor Yellow
        $graphSp = Get-AzADServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"
        $userReadPermission = $graphSp.Oauth2PermissionScope | Where-Object { $_.Value -eq "User.Read" }
        $sitesReadPermission = $graphSp.Oauth2PermissionScope | Where-Object { $_.Value -eq "Sites.Read.All" }
        
        Add-AzADAppPermission -ObjectId $appObjectId -ApiId "00000003-0000-0000-c000-000000000000" -PermissionId $userReadPermission.Id -Type Scope
        Add-AzADAppPermission -ObjectId $appObjectId -ApiId "00000003-0000-0000-c000-000000000000" -PermissionId $sitesReadPermission.Id -Type Scope
        Write-Host "✓ User.Read and Sites.Read.All permissions added" -ForegroundColor Green
        
        Write-Host "⚠️  Admin consent required: Please go to Azure Portal > App Registrations > $appName > API Permissions > Grant admin consent" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    } else {
        $appClientId = $existingApp.AppId
        $appObjectId = $existingApp.Id
        Write-Host "✓ Using existing App Registration" -ForegroundColor Green
        Write-Host "  Client ID: $appClientId" -ForegroundColor Gray
        
        # Update redirect URI if needed
        Write-Host "Updating SPA redirect URI..." -ForegroundColor Yellow
        $spa = New-Object -TypeName Microsoft.Azure.PowerShell.Cmdlets.Resources.MSGraph.Models.ApiV10.MicrosoftGraphSpaApplication
        $spa.RedirectUri = @("$staticWebsiteUrl/upload-portal.html")
        Update-AzADApplication -ObjectId $appObjectId -SPARedirectUri $spa.RedirectUri
        Write-Host "✓ SPA redirect URI updated" -ForegroundColor Green
    }
    
    # Save to ini
    Set-IniValue -Path $configFile -Section "UploadPortal" -Key "ClientId" -Value $appClientId
    Set-IniValue -Path $configFile -Section "UploadPortal" -Key "AppName" -Value $appName
    Write-Host "✓ Configuration saved to ini file" -ForegroundColor Green
    
    # Update HTML with configuration
    Write-Host "`nConfiguring portal HTML..." -ForegroundColor Yellow
    $htmlPath = Join-Path $PSScriptRoot "portal\upload-portal.html"
    $htmlContent = Get-Content $htmlPath -Raw
    
    $htmlContent = $htmlContent -replace 'YOUR_CLIENT_ID_HERE', $appClientId
    $htmlContent = $htmlContent -replace 'YOUR_TENANT_ID_HERE', $azContext.Tenant.Id
    $htmlContent = $htmlContent -replace 'YOUR_FUNCTION_APP_URL_HERE', "https://$functionAppName.azurewebsites.net"
    $htmlContent = $htmlContent -replace 'YOUR_SHAREPOINT_SITE_URL_HERE', $siteUrl
    $htmlContent = $htmlContent -replace 'YOUR_SHAREPOINT_LIST_ID_HERE', $listId
    
    $tempHtmlPath = Join-Path $PSScriptRoot "portal\upload-portal-configured.html"
    $htmlContent | Set-Content $tempHtmlPath -Force
    
    # Upload to storage
    Write-Host "Uploading portal to storage..." -ForegroundColor Yellow
    
    # Ensure current user has Storage Blob Data Contributor role
    $azContext = Get-AzContext
    $currentUserId = (Get-AzADUser -UserPrincipalName $azContext.Account.Id).Id
    if (-not $currentUserId) {
        $currentUserId = $azContext.Account.Id
    }
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName
    
    Write-Host "Assigning Storage Blob Data Contributor role..." -ForegroundColor Yellow
    try {
        New-AzRoleAssignment -ObjectId $currentUserId -RoleDefinitionName "Storage Blob Data Contributor" -Scope $storageAccount.Id -ErrorAction SilentlyContinue | Out-Null
    } catch {
        # Role may already be assigned
    }
    Write-Host "✓ Role assigned" -ForegroundColor Green
    
    Write-Host "Waiting for role assignment to propagate (60 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60  # Allow role to propagate
    
    # Upload using storage context with retry logic
    $uploadSuccess = $false
    $retryCount = 0
    $maxRetries = 3
    
    while (-not $uploadSuccess -and $retryCount -lt $maxRetries) {
        try {
            $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
            Set-AzStorageBlobContent -File $tempHtmlPath -Container '$web' -Blob "upload-portal.html" -Context $ctx -Properties @{"ContentType"="text/html"} -Force | Out-Null
            $uploadSuccess = $true
        } catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "⚠️  Upload failed (attempt $retryCount/$maxRetries). Waiting 30 seconds for role propagation..." -ForegroundColor Yellow
                Start-Sleep -Seconds 30
            } else {
                throw "Failed to upload after $maxRetries attempts. Role assignment may not have propagated. Error: $($_.Exception.Message)"
            }
        }
    }
    
    Remove-Item $tempHtmlPath -Force -ErrorAction SilentlyContinue
    Write-Host "✓ Portal uploaded" -ForegroundColor Green
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "✓ Step 07 Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    Write-Host "`n📊 UPLOAD PORTAL DEPLOYED:" -ForegroundColor Cyan
    Write-Host "`n🌐 Portal URL:" -ForegroundColor Yellow
    Write-Host "   $staticWebsiteUrl/upload-portal.html" -ForegroundColor White
    Write-Host "`n✨ Portal Features:" -ForegroundColor Cyan
    Write-Host "   📁 CSV Upload - Upload users from CSV file" -ForegroundColor Gray
    Write-Host "   ✏️  Manual Entry - Enter users one by one" -ForegroundColor Gray
    Write-Host "   📊 Reports - View real-time MFA rollout progress" -ForegroundColor Gray
    Write-Host "`n📤 Function Endpoint:" -ForegroundColor Cyan
    Write-Host "   https://$functionAppName.azurewebsites.net/api/upload-users" -ForegroundColor Gray
    Write-Host "`n🔐 App Registration:" -ForegroundColor Cyan
    Write-Host "   Name: $appName" -ForegroundColor Gray
    Write-Host "   Client ID: $appClientId" -ForegroundColor Gray
    Write-Host "   Permissions: User.Read, Sites.Read.All" -ForegroundColor Green
    Write-Host "`n⚠️  IMPORTANT: Grant admin consent in Azure Portal for the app permissions" -ForegroundColor Yellow
    Write-Host "`n✅ All configuration automated - portal ready to use!`n" -ForegroundColor Green
    
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
