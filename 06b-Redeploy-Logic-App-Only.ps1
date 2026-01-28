# Step 06b - Quick Redeploy Logic App (No Connector Changes)
# Updates only the Logic App workflow definition, preserves existing connections

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
    Write-Host "Step 06b - Quick Redeploy Logic App" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $config = Get-IniContent -Path $configFile
    
    # Get tenant ID from config
    $tenantId = $config["Tenant"]["TenantId"]
    $subscriptionId = $config["Tenant"]["SubscriptionId"]
    
    # Ensure Azure connection with correct tenant
    Write-Host "Connecting to Azure..." -ForegroundColor Yellow
    $azContext = Get-AzContext
    if ($null -eq $azContext -or $azContext.Tenant.Id -ne $tenantId) {
        if (-not [string]::IsNullOrWhiteSpace($tenantId)) {
            Connect-AzAccount -TenantId $tenantId
        } else {
            Connect-AzAccount
        }
        $azContext = Get-AzContext
    }
    
    # Set correct subscription if specified
    if (-not [string]::IsNullOrWhiteSpace($subscriptionId) -and $azContext.Subscription.Id -ne $subscriptionId) {
        Set-AzContext -SubscriptionId $subscriptionId | Out-Null
    }
    
    Write-Host "✓ Connected to Azure" -ForegroundColor Green
    Write-Host "  Tenant: $($azContext.Tenant.Id)" -ForegroundColor Gray
    Write-Host "  Subscription: $($azContext.Subscription.Name)`n" -ForegroundColor Gray
    
    $resourceGroup = $config["Azure"]["ResourceGroup"]
    $region = $config["Azure"]["Region"]
    $logicAppName = $config["LogicApp"]["LogicAppName"]
    $recurrenceHours = $config["LogicApp"]["RecurrenceHours"]
    if ([string]::IsNullOrWhiteSpace($recurrenceHours)) { $recurrenceHours = "12" }
    $siteUrl = $config["SharePoint"]["SiteUrl"]
    $listId = $config["SharePoint"]["ListId"]
    $functionAppName = $config["Azure"]["FunctionAppName"]
    $noReplyMailbox = $config["Email"]["NoReplyMailbox"]
    $mfaGroupId = $config["Security"]["MFAGroupId"]
    
    Write-Host "Configuration:" -ForegroundColor Gray
    Write-Host "  Logic App: $logicAppName" -ForegroundColor Gray
    Write-Host "  Resource Group: $resourceGroup" -ForegroundColor Gray
    Write-Host "  Recurrence: Every $recurrenceHours hour(s)" -ForegroundColor Gray
    Write-Host "  SharePoint: $siteUrl" -ForegroundColor Gray
    Write-Host "  List ID: $listId`n" -ForegroundColor Gray
    
    # Check if Logic App TEMPLATE exists
    $logicAppJsonPath = Join-Path $PSScriptRoot "invite-orchestrator-TEMPLATE.json"
    if (-not (Test-Path $logicAppJsonPath)) {
        throw "Logic App TEMPLATE not found: $logicAppJsonPath"
    }
    
    Write-Host "Reading Logic App template..." -ForegroundColor Yellow
    $logicAppJsonRaw = Get-Content $logicAppJsonPath -Raw -Encoding UTF8
    
    # Remove BOM if present
    if ($logicAppJsonRaw[0] -eq [char]0xFEFF) {
        $logicAppJsonRaw = $logicAppJsonRaw.Substring(1)
    }
    
    # Read branding configuration
    $logoUrl = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("LogoUrl")) { $config["Branding"]["LogoUrl"] } else { "" }
    $companyName = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("CompanyName")) { $config["Branding"]["CompanyName"] } else { "" }
    $supportTeam = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("SupportTeam")) { $config["Branding"]["SupportTeam"] } else { "IT Security Team" }
    $supportEmail = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("SupportEmail")) { $config["Branding"]["SupportEmail"] } else { $noReplyMailbox }
    
    Write-Host "Updating values from INI..." -ForegroundColor Yellow
    
    # Replace placeholders with actual values
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("RECURRENCE_HOURS_PLACEHOLDER", $recurrenceHours)
    Write-Host "  ✓ Recurrence: Every $recurrenceHours hour(s)" -ForegroundColor Gray
    
    $functionUrl = "https://$functionAppName.azurewebsites.net/api/track-mfa-click"
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_FUNCTION_URL", $functionUrl)
    Write-Host "  ✓ Function URL: $functionUrl" -ForegroundColor Gray
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_SHAREPOINT_SITE_URL", $siteUrl)
    Write-Host "  ✓ SharePoint URL: $siteUrl" -ForegroundColor Gray
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_GROUP_ID", $mfaGroupId)
    Write-Host "  ✓ Group ID: $mfaGroupId" -ForegroundColor Gray
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_LIST_ID", $listId)
    Write-Host "  ✓ List ID: $listId" -ForegroundColor Gray
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_EMAIL", $noReplyMailbox)
    Write-Host "  ✓ Email From: $noReplyMailbox" -ForegroundColor Gray
    
    # Handle logo - if no URL provided, hide the entire logo section in emails
    if ([string]::IsNullOrWhiteSpace($logoUrl)) {
        # Hide logo section by setting display:none on logo-header div
        $logicAppJsonRaw = $logicAppJsonRaw -replace '(\.logo-header\{[^}]*?)\}', '$1;display:none}'
        $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_LOGO_URL", "")
        Write-Host "  ✓ Logo: None (hidden)" -ForegroundColor Gray
    } else {
        $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_LOGO_URL", $logoUrl)
        Write-Host "  ✓ Logo URL: $logoUrl" -ForegroundColor Gray
    }
    
    if ([string]::IsNullOrWhiteSpace($companyName)) {
        $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_COMPANY_NAME", "Company Logo")
        Write-Host "  ✓ Company Name: (default)" -ForegroundColor Gray
    } else {
        $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_COMPANY_NAME", $companyName)
        Write-Host "  ✓ Company Name: $companyName" -ForegroundColor Gray
    }
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_SUPPORT_TEAM", $supportTeam)
    Write-Host "  ✓ Support Team: $supportTeam" -ForegroundColor Gray
    
    # Build footer with clickable mailto link
    $mailtoLink = "mailto:" + $supportEmail + "?subject=MFA%20Setup%20Query"
    $footer = "This is an automated message from $supportTeam.\u003cbr\u003eFor questions or assistance, please contact \u003ca href=\u0027" + $mailtoLink + "\u0027 style=\u0027color:#0078D4;text-decoration:none\u0027\u003e" + $supportEmail + "\u003c/a\u003e.\u003cbr\u003e\u003cbr\u003ePlease do not reply to this email as this is an unmonitored mailbox."
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_FOOTER", $footer)
    Write-Host "  ✓ Footer: Updated with clickable email`n" -ForegroundColor Gray
    
    # Replace app store badge URLs with Microsoft official ones
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg", "https://mysignins.microsoft.com/images/ios-app-store-button.svg")
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png", "https://mysignins.microsoft.com/images/google-play-button.svg")
    Write-Host "  ✓ App Store URLs: Microsoft official badges`n" -ForegroundColor Gray
    
    # Verify Azure connection is still active
    try {
        $null = Get-AzContext -ErrorAction Stop
    }
    catch {
        Write-Host "Azure session expired, reconnecting..." -ForegroundColor Yellow
        if (-not [string]::IsNullOrWhiteSpace($tenantId)) {
            Connect-AzAccount -TenantId $tenantId
        } else {
            Connect-AzAccount
        }
        if (-not [string]::IsNullOrWhiteSpace($subscriptionId)) {
            Set-AzContext -SubscriptionId $subscriptionId | Out-Null
        }
    }
    
    # Get existing Logic App to preserve connections
    Write-Host "Getting existing Logic App connections..." -ForegroundColor Yellow
    $existingApp = Get-AzLogicApp -ResourceGroupName $resourceGroup -Name $logicAppName -ErrorAction Stop
    Write-Host "✓ Found existing Logic App`n" -ForegroundColor Green
    
    # Parse JSON to get definition, build parameters from existing app
    $logicAppJson = $logicAppJsonRaw | ConvertFrom-Json
    
    # Build ARM template - use existing connections and region from config
    $armJson = @{
        location = $region
        identity = @{
            type = "SystemAssigned"
        }
        properties = @{
            state = "Enabled"
            definition = $logicAppJson.properties.definition
            parameters = @{
                '$connections' = @{
                    value = $existingApp.Parameters.'$connections'.Value
                }
            }
        }
    } | ConvertTo-Json -Depth 100
    
    # Save to temp file
    Write-Host "Deploying Logic App to Azure..." -ForegroundColor Yellow
    $tempDeployFile = [System.IO.Path]::GetTempFileName()
    $armJson | Set-Content $tempDeployFile -Encoding UTF8
    
    $logicAppResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName"
    
    az rest --method PUT `
            --uri "https://management.azure.com$($logicAppResourceId)?api-version=2019-05-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempDeployFile" | Out-Null
    
    Remove-Item $tempDeployFile -Force -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Logic App workflow deployed`n" -ForegroundColor Green
    } else {
        throw "Logic App deployment failed"
    }
    
    # Verify deployment
    Write-Host "Verifying deployment..." -ForegroundColor Yellow
    $deployed = Get-AzLogicApp -ResourceGroupName $resourceGroup -Name $logicAppName -ErrorAction SilentlyContinue
    
    if ($null -ne $deployed) {
        Write-Host "✓ Logic App verified" -ForegroundColor Green
        Write-Host "  Name: $($deployed.Name)" -ForegroundColor Gray
        Write-Host "  State: $($deployed.State)`n" -ForegroundColor Gray
    }
    
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "✓ Logic App Redeployed Successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
