# Step 05 - Deploy Function App
# Simple deployment based on Deploy-Updated-Function.ps1

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

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Step 05 - Deploy Function App" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $config = Get-IniContent -Path $configFile
    
    $functionAppName = $config["Azure"]["FunctionAppName"]
    $resourceGroup = $config["Azure"]["ResourceGroup"]
    $siteUrl = $config["SharePoint"]["SiteUrl"]
    $listTitle = $config["SharePoint"]["ListTitle"]
    $groupId = $config["Security"]["MFAGroupId"]
    $clientId = $config["SharePoint"]["ClientId"]
    $thumbprint = $config["SharePoint"]["CertificateThumbprint"]
    $tenantId = $config["Tenant"]["TenantId"]
    $subscriptionId = $config["Tenant"]["SubscriptionId"]
    
    Write-Host "Target Configuration from INI:" -ForegroundColor Cyan
    Write-Host "  Tenant ID: $tenantId" -ForegroundColor Gray
    Write-Host "  Subscription ID: $subscriptionId" -ForegroundColor Gray
    Write-Host "  Resource Group: $resourceGroup" -ForegroundColor Gray
    Write-Host "  Function App: $functionAppName" -ForegroundColor Gray
    Write-Host "  SharePoint: $siteUrl" -ForegroundColor Gray
    
    # Get SharePoint List ID
    Write-Host "`nGetting SharePoint List ID..." -ForegroundColor Yellow
    Import-Module PnP.PowerShell -ErrorAction Stop
    Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantId
    $list = Get-PnPList -Identity $listTitle
    $listId = $list.Id.Guid
    Disconnect-PnPOnline
    Write-Host "✓ List ID: $listId" -ForegroundColor Green
    
    # Extract hostname from SharePoint URL
    $siteHostname = ([System.Uri]$siteUrl).Host
    
    # Function code uses environment variables (set later in this script)
    # No need to update function code files - they read from $env:MFA_GROUP_ID, etc.
    Write-Host "`nValidating function code..." -ForegroundColor Yellow
    $functionCodePath = Join-Path $PSScriptRoot "function-code"
    $runPs1Path = Join-Path $functionCodePath "enrol\run.ps1"
    
    if (-not (Test-Path $runPs1Path)) {
        throw "Function code not found at: $runPs1Path"
    }
    
    Write-Host "✓ Function code ready (uses environment variables)" -ForegroundColor Green
    
    # Package function code
    Write-Host "`nPackaging function code..." -ForegroundColor Yellow
    $zipPath = Join-Path $PSScriptRoot "function-deploy.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    
    Compress-Archive -Path "$functionCodePath\*" -DestinationPath $zipPath -Force
    Write-Host "✓ Package created" -ForegroundColor Green
    
    # Check Azure CLI
    Write-Host "`nChecking Azure CLI..." -ForegroundColor Yellow
    $account = az account show 2>$null | ConvertFrom-Json
    
    # Check if logged in AND if logged into correct tenant
    $needsLogin = $false
    if (-not $account) {
        Write-Host "Not logged in to Azure CLI." -ForegroundColor Yellow
        $needsLogin = $true
    } elseif ($account.tenantId -ne $tenantId) {
        Write-Host "⚠ Logged into wrong tenant!" -ForegroundColor Yellow
        Write-Host "  Current tenant: $($account.tenantId)" -ForegroundColor Gray
        Write-Host "  Required tenant: $tenantId" -ForegroundColor Gray
        Write-Host "  Current user: $($account.user.name)" -ForegroundColor Gray
        $needsLogin = $true
    } else {
        Write-Host "✓ Already logged in as: $($account.user.name)" -ForegroundColor Green
        Write-Host "  Tenant: $($account.tenantId)" -ForegroundColor Gray
    }
    
    if ($needsLogin) {
        Write-Host "`nLogging out and re-connecting to correct tenant..." -ForegroundColor Yellow
        az logout 2>&1 | Out-Null
        Write-Host "Running 'az login' for tenant: $tenantId" -ForegroundColor Yellow
        az login --tenant $tenantId
        $account = az account show | ConvertFrom-Json
        Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green
    }
    
    # Set the correct subscription
    Write-Host "`nSetting subscription: $subscriptionId" -ForegroundColor Yellow
    az account set --subscription $subscriptionId
    $account = az account show | ConvertFrom-Json
    Write-Host "✓ Using subscription: $($account.name)" -ForegroundColor Green
    Write-Host "  Account: $($account.user.name)" -ForegroundColor Gray
    
    # Deploy to Function App
    Write-Host "`nDeploying to Function App..." -ForegroundColor Yellow
    Write-Host "This may take 1-2 minutes..." -ForegroundColor Yellow
    
    $deployResult = az functionapp deployment source config-zip `
        --resource-group $resourceGroup `
        --name $functionAppName `
        --src $zipPath `
        2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Deployment failed!" -ForegroundColor Red
        Write-Host $deployResult -ForegroundColor Red
        throw "Deployment failed"
    }
    
    Write-Host "✓ Deployment successful!" -ForegroundColor Green
    
    # Configure environment variables for upload-users function
    Write-Host "`nConfiguring Function App environment variables..." -ForegroundColor Yellow
    
    # Extract site name from SharePoint URL (e.g., "MFA" from "https://tenant.sharepoint.com/sites/MFA")
    $siteName = ([System.Uri]$siteUrl).AbsolutePath.TrimStart('/sites/').TrimEnd('/')
    
    # Get Security Group ID from INI
    $mfaGroupId = $config["Security"]["MFAGroupId"]
    
    # Get Logic App trigger URL (if available - will be set after Logic App deployment)
    $logicAppTriggerUrl = $config["LogicApp"]["TriggerUrl"]
    if ([string]::IsNullOrWhiteSpace($logicAppTriggerUrl)) {
        $logicAppTriggerUrl = "NOT_SET_YET"
        Write-Host "  Note: Logic App trigger URL not set - will be configured after Logic App deployment" -ForegroundColor Gray
    }
    
    az functionapp config appsettings set `
        --resource-group $resourceGroup `
        --name $functionAppName `
        --settings `
            "SHAREPOINT_SITE_URL=$siteUrl" `
            "SHAREPOINT_LIST_ID=$listId" `
            "SHAREPOINT_SITE_NAME=$siteName" `
            "MFA_GROUP_ID=$mfaGroupId" `
            "LOGIC_APP_TRIGGER_URL=$logicAppTriggerUrl" `
        2>&1 | Out-Null
    
    Write-Host "✓ Environment variables configured" -ForegroundColor Green
    Write-Host "  Site Name: $siteName" -ForegroundColor Gray
    Write-Host "  Site URL: $siteUrl" -ForegroundColor Gray
    Write-Host "  List ID: $listId" -ForegroundColor Gray
    Write-Host "  MFA Group ID: $mfaGroupId" -ForegroundColor Gray
    Write-Host "  Logic App Trigger URL: $(if ($logicAppTriggerUrl -eq 'NOT_SET_YET') { 'Will be set by script 06' } else { 'Configured' })" -ForegroundColor Gray
    
    # Restart Function App to load new functions
    Write-Host "`nRestarting Function App to load deployed functions..." -ForegroundColor Yellow
    az functionapp restart --resource-group $resourceGroup --name $functionAppName 2>&1 | Out-Null
    Write-Host "✓ Function App restarted" -ForegroundColor Green
    
    # Clean up
    Remove-Item $zipPath -Force
    
    # Wait for deployment and restart to complete
    Write-Host "`nWaiting 60 seconds for deployment to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
    
    # Test endpoint
    Write-Host "Testing Function App..." -ForegroundColor Yellow
    $testUrl = "https://$functionAppName.azurewebsites.net/api/track-mfa-click?user=test@example.com"
    
    try {
        $response = Invoke-WebRequest -Uri $testUrl -MaximumRedirection 0 -ErrorAction SilentlyContinue
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 302) {
            Write-Host "✓ Function App working correctly (redirect)" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ Status: $($_.Exception.Response.StatusCode)" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "✓ Step 05 Completed!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    # Show final deployment summary with tenant/subscription info
    $finalAccount = az account show | ConvertFrom-Json
    Write-Host "`nDeployment Summary:" -ForegroundColor Cyan
    Write-Host "  ✓ Deployed by: $($finalAccount.user.name)" -ForegroundColor Green
    Write-Host "  ✓ Tenant: $($finalAccount.tenantId)" -ForegroundColor Green
    Write-Host "  ✓ Subscription: $($finalAccount.name)" -ForegroundColor Green
    Write-Host "  ✓ Resource Group: $resourceGroup" -ForegroundColor Green
    Write-Host "  ✓ Function App: $functionAppName" -ForegroundColor Green
    Write-Host "`nFunction App Endpoints:" -ForegroundColor Cyan
    Write-Host "  Track MFA Click: https://$functionAppName.azurewebsites.net/api/track-mfa-click" -ForegroundColor White
    Write-Host "  Upload Users: https://$functionAppName.azurewebsites.net/api/upload-users" -ForegroundColor White
    
}
catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
