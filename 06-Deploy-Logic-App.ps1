# Step 06 - Deploy Logic App
# Creates API connections and deploys Logic App workflow

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
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )
    
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }
    
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
    
    Set-Content -Path $Path -Value ($output -join "`r`n") -NoNewline
}

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Step 06 - Deploy Logic App" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $config = Get-IniContent -Path $configFile
    
    # Ensure Azure connection
    $azContext = Get-AzContext
    if ($null -eq $azContext) {
        Connect-AzAccount
    }
    
    $resourceGroup = $config["Azure"]["ResourceGroup"]
    $region = $config["Azure"]["Region"]
    $logicAppName = $config["LogicApp"]["LogicAppName"]
    $recurrenceHours = $config["LogicApp"]["RecurrenceHours"]
    if ([string]::IsNullOrWhiteSpace($recurrenceHours)) { $recurrenceHours = "12" }
    $siteUrl = $config["SharePoint"]["SiteUrl"]
    $functionAppName = $config["Azure"]["FunctionAppName"]
    
    Write-Host "Logic App Name: $logicAppName" -ForegroundColor Gray
    Write-Host "Resource Group: $resourceGroup" -ForegroundColor Gray
    Write-Host "Recurrence: Every $recurrenceHours hour(s)`n" -ForegroundColor Gray
    
    # Create Logic App with Managed Identity
    Write-Host "Creating Logic App with Managed Identity..." -ForegroundColor Yellow
    
    $existingApp = Get-AzLogicApp -ResourceGroupName $resourceGroup -Name $logicAppName -ErrorAction SilentlyContinue
    
    if ($null -eq $existingApp) {
        # Create Logic App using Azure CLI (Consumption tier with Managed Identity)
        $subscriptionId = (Get-AzContext).Subscription.Id
        $logicAppResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName"
        
        $logicAppDefinition = @{
            location = $region
            identity = @{
                type = "SystemAssigned"
            }
            properties = @{
                state = "Enabled"
                definition = @{
                    '$schema' = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
                    contentVersion = "1.0.0.0"
                    triggers = @{}
                    actions = @{}
                    outputs = @{}
                }
            }
        }
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        $logicAppDefinition | ConvertTo-Json -Depth 10 | Set-Content $tempFile -Force
        
        Write-Host "Creating Logic App resource..." -ForegroundColor Yellow
        az rest --method PUT `
                --uri "https://management.azure.com$($logicAppResourceId)?api-version=2019-05-01" `
                --headers "Content-Type=application/json" `
                --body "@$tempFile" | Out-Null
        
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds 5
        
        $existingApp = Get-AzLogicApp -ResourceGroupName $resourceGroup -Name $logicAppName
        Write-Host "✓ Logic App created with Managed Identity" -ForegroundColor Green
    }
    else {
        Write-Host "✓ Logic App already exists" -ForegroundColor Green
    }
    
    # Get Managed Identity Principal ID
    Write-Host "`nGetting Logic App Managed Identity..." -ForegroundColor Yellow
    $logicAppResource = Get-AzResource -ResourceGroupName $resourceGroup -Name $logicAppName -ResourceType "Microsoft.Logic/workflows"
    
    if ($null -eq $logicAppResource.Identity -or $logicAppResource.Identity.Type -ne "SystemAssigned") {
        Write-Host "Enabling Managed Identity..." -ForegroundColor Yellow
        az logicapp identity assign --resource-group $resourceGroup --name $logicAppName
        Start-Sleep -Seconds 5
        $logicAppResource = Get-AzResource -ResourceGroupName $resourceGroup -Name $logicAppName -ResourceType "Microsoft.Logic/workflows"
    }
    
    $logicAppPrincipalId = $logicAppResource.Identity.PrincipalId
    Write-Host "✓ Managed Identity Principal ID: $logicAppPrincipalId" -ForegroundColor Green
    
    # Grant Graph API Permissions to Logic App
    Write-Host "`nGranting Graph API permissions to Logic App Managed Identity..." -ForegroundColor Yellow
    
    $graphAppId = "00000003-0000-0000-c000-000000000000"
    $permissions = @(
        @{Name="Directory.Read.All"; Id="7ab1d382-f21e-4acd-a863-ba3e13f7da61"}
        @{Name="User.Read.All"; Id="df021288-bdef-4463-88db-98f22de89214"}
        @{Name="UserAuthenticationMethod.Read.All"; Id="38d9df27-64da-44fd-b7c5-a6fbac20248f"}
        @{Name="GroupMember.ReadWrite.All"; Id="dbaae8cf-10b5-4b86-a4a1-f871c94c6695"}
        @{Name="Group.Read.All"; Id="5b567255-7703-4780-807c-7be8301ae99b"}
    )
    
    $graphServicePrincipalId = az ad sp list --filter "appId eq '$graphAppId'" --query "[0].id" -o tsv
    
    foreach ($perm in $permissions) {
        Write-Host "  Granting $($perm.Name)..." -ForegroundColor Yellow
        
        $body = @{
            principalId = $logicAppPrincipalId
            resourceId = $graphServicePrincipalId
            appRoleId = $perm.Id
        } | ConvertTo-Json
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        $body | Set-Content $tempFile -Force
        
        try {
            az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$logicAppPrincipalId/appRoleAssignments" --body `@$tempFile --headers "Content-Type=application/json" 2>$null
            Write-Host "  ✓ $($perm.Name) granted" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ $($perm.Name) may already be granted" -ForegroundColor Yellow
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Host "`n✓ Logic App Managed Identity configured with all permissions" -ForegroundColor Green
    
    # Create API Connections
    Write-Host "`nCreating API Connections..." -ForegroundColor Yellow
    
    $subscriptionId = (Get-AzContext).Subscription.Id
    $tenantId = $config["Tenant"]["TenantId"]
    
    # SharePoint API Connection
    $spoConnectionName = "sharepointonline"
    Write-Host "  Creating SharePoint Online connection..." -ForegroundColor Yellow
    
    $spoConnection = @{
        properties = @{
            displayName = "SharePoint Online"
            api = @{
                id = "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/sharepointonline"
            }
            parameterValues = @{}
        }
        location = $region
    }
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $spoConnection | ConvertTo-Json -Depth 10 | Set-Content $tempFile -Force
    
    az rest --method PUT `
            --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/$($spoConnectionName)?api-version=2016-06-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempFile" | Out-Null
    
    Remove-Item $tempFile -Force
    Write-Host "  ✓ SharePoint connection created" -ForegroundColor Green
    
    # Office 365 Outlook API Connection
    $outlookConnectionName = "office365"
    Write-Host "  Creating Office 365 Outlook connection..." -ForegroundColor Yellow
    
    $outlookConnection = @{
        properties = @{
            displayName = "Office 365 Outlook"
            api = @{
                id = "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/office365"
            }
            parameterValues = @{}
        }
        location = $region
    }
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $outlookConnection | ConvertTo-Json -Depth 10 | Set-Content $tempFile -Force
    
    az rest --method PUT `
            --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/$($outlookConnectionName)?api-version=2016-06-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempFile" | Out-Null
    
    Remove-Item $tempFile -Force
    Write-Host "  ✓ Office 365 connection created" -ForegroundColor Green
    
    # Azure AD (Entra ID) API Connection
    $azureadConnectionName = "azuread"
    Write-Host "  Creating Azure AD (Entra ID) connection..." -ForegroundColor Yellow
    
    $azureadConnection = @{
        properties = @{
            displayName = "Azure AD"
            api = @{
                id = "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/azuread"
            }
            parameterValues = @{}
        }
        location = $region
    }
    
    $tempFile = [System.IO.Path]::GetTempFileName()
    $azureadConnection | ConvertTo-Json -Depth 10 | Set-Content $tempFile -Force
    
    az rest --method PUT `
            --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/$($azureadConnectionName)?api-version=2016-06-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempFile" | Out-Null
    
    Remove-Item $tempFile -Force
    Write-Host "  ✓ Azure AD connection created" -ForegroundColor Green
    
    Write-Host "`n" -NoNewline
    Write-Host "IMPORTANT: " -ForegroundColor Yellow -NoNewline
    Write-Host "You need to authorize these connections in the Azure Portal:" -ForegroundColor White
    Write-Host "  1. Go to: Resource Groups > $resourceGroup > API Connections" -ForegroundColor Gray
    Write-Host "  2. Click on 'sharepointonline' and authorize it" -ForegroundColor Gray
    Write-Host "  3. Click on 'office365' and authorize it" -ForegroundColor Gray
    Write-Host "  4. Click on 'azuread' (Entra ID) and authorize it" -ForegroundColor Gray
    Write-Host "`nPress Enter after authorizing all three connections..." -ForegroundColor Yellow
    Read-Host
    
    # Check if Logic App JSON exists
    $logicAppJsonPath = Join-Path $PSScriptRoot "invite-orchestrator-TEMPLATE.json"
    if (-not (Test-Path $logicAppJsonPath)) {
        throw "Logic App JSON not found: $logicAppJsonPath"
    }
    
    Write-Host "Reading Logic App definition..." -ForegroundColor Yellow
    $logicAppJsonRaw_Initial = Get-Content $logicAppJsonPath -Raw -Encoding UTF8
    
    # Remove BOM if present
    if ($logicAppJsonRaw_Initial[0] -eq [char]0xFEFF) {
        $logicAppJsonRaw_Initial = $logicAppJsonRaw_Initial.Substring(1)
    }
    
    # Replace recurrence placeholder before parsing JSON
    $logicAppJsonRaw_Initial = $logicAppJsonRaw_Initial.Replace("RECURRENCE_HOURS_PLACEHOLDER", $recurrenceHours)
    
    $logicAppJson = $logicAppJsonRaw_Initial | ConvertFrom-Json
    
    # Extract List ID from SharePoint - need to get this
    Write-Host "Connecting to SharePoint to get List ID..." -ForegroundColor Yellow
    $clientId = $config["SharePoint"]["ClientId"]
    $thumbprint = $config["SharePoint"]["CertificateThumbprint"]
    $listTitle = $config["SharePoint"]["ListTitle"]
    $tenantId = $config["Tenant"]["TenantId"]
    
    try {
        Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantId
        $list = Get-PnPList -Identity $listTitle
        $listId = $list.Id.Guid
        Disconnect-PnPOnline
        Write-Host "✓ List ID: $listId" -ForegroundColor Green
        
        # Save ListId to INI file for other scripts
        Set-IniValue -Path $configFile -Section "SharePoint" -Key "ListId" -Value $listId
    }
    catch {
        throw "Failed to get SharePoint List ID: $($_.Exception.Message)"
    }
    
    # Update Logic App definition with deployment values
    Write-Host "`nUpdating Logic App definition with deployment values..." -ForegroundColor Yellow
    
    $functionUrl = "https://$functionAppName.azurewebsites.net/api/track-mfa-click"
    $noReplyMailbox = $config["Email"]["NoReplyMailbox"]
    $mfaGroupId = $config["Security"]["MFAGroupId"]
    
    # Read branding configuration
    $logoUrl = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("LogoUrl")) { $config["Branding"]["LogoUrl"] } else { $null }
    if ([string]::IsNullOrWhiteSpace($logoUrl)) {
        $logoUrl = "https://www.cygnetgroup.com/wp-content/uploads/2015/11/new-news-image.jpg"
    }
    
    $companyName = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("CompanyName")) { $config["Branding"]["CompanyName"] } else { "Cygnet Group" }
    $supportTeam = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("SupportTeam")) { $config["Branding"]["SupportTeam"] } else { "IT Security Team" }
    $supportEmail = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("SupportEmail")) { $config["Branding"]["SupportEmail"] } else { $noReplyMailbox }
    
    # Work with RAW JSON string to preserve @ symbols
    $logicAppJsonRaw = Get-Content $logicAppJsonPath -Raw -Encoding UTF8
    
    # Remove BOM if present
    if ($logicAppJsonRaw[0] -eq [char]0xFEFF) {
        $logicAppJsonRaw = $logicAppJsonRaw.Substring(1)
    }
    
    # Replace placeholders with actual values
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("RECURRENCE_HOURS_PLACEHOLDER", $recurrenceHours)
    Write-Host "  ✓ Recurrence: Every $recurrenceHours hour(s)" -ForegroundColor Gray
    
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
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_LOGO_URL", $logoUrl)
    Write-Host "  ✓ Logo URL: $logoUrl" -ForegroundColor Gray
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_COMPANY_NAME", $companyName)
    Write-Host "  ✓ Company Name: $companyName" -ForegroundColor Gray
    
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_SUPPORT_TEAM", $supportTeam)
    Write-Host "  ✓ Support Team: $supportTeam" -ForegroundColor Gray
    
    # Build footer with clickable mailto link
    $mailtoLink = "mailto:" + $supportEmail + "?subject=MFA%20Setup%20Query"
    $footer = "This is an automated message from $supportTeam.\u003cbr\u003eFor questions or assistance, please contact \u003ca href=\u0027" + $mailtoLink + "\u0027 style=\u0027color:#0078D4;text-decoration:none\u0027\u003e" + $supportEmail + "\u003c/a\u003e.\u003cbr\u003e\u003cbr\u003ePlease do not reply to this email as this is an unmonitored mailbox."
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_FOOTER", $footer)
    Write-Host "  ✓ Footer: Updated with clickable email (subject: MFA Setup Query)" -ForegroundColor Gray
    
    # Replace app store badge URLs with Microsoft official ones
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg", "https://mysignins.microsoft.com/images/ios-app-store-button.svg")
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png", "https://mysignins.microsoft.com/images/google-play-button.svg")
    Write-Host "  ✓ App Store URLs: Microsoft official badges" -ForegroundColor Gray
    
    # Update connection references
    $logicAppJsonRaw = $logicAppJsonRaw -replace '"/subscriptions/[a-z0-9\-]+/resourceGroups/[a-zA-Z0-9\-]+/providers/Microsoft\.Web/connections/sharepointonline[a-zA-Z0-9\-]*"', "`"/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/sharepointonline`""
    $logicAppJsonRaw = $logicAppJsonRaw -replace '"/subscriptions/[a-z0-9\-]+/resourceGroups/[a-zA-Z0-9\-]+/providers/Microsoft\.Web/connections/office365[a-zA-Z0-9\-]*"', "`"/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/office365`""
    $logicAppJsonRaw = $logicAppJsonRaw -replace '"/subscriptions/[a-z0-9\-]+/resourceGroups/[a-zA-Z0-9\-]+/providers/Microsoft\.Web/connections/azuread"', "`"/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/azuread`""
    $logicAppJsonRaw = $logicAppJsonRaw -replace '"connectionName":\s*"sharepointonline[^""]*"', "`"connectionName`": `"sharepointonline`""
    $logicAppJsonRaw = $logicAppJsonRaw -replace '"connectionName":\s*"office365[^""]*"', "`"connectionName`": `"office365`""
    
    Write-Host "✓ All deployment values updated" -ForegroundColor Green
    
    # Parse to extract definition and build ARM template
    Write-Host "`nDeploying Logic App workflow..." -ForegroundColor Yellow
    
    $logicAppObj = $logicAppJsonRaw | ConvertFrom-Json
    
    # Build ARM template - build location and parameters dynamically
    $armJson = @"
{
  "location": "$region",
  "properties": {
    "state": "Enabled",
    "definition": $($logicAppObj.properties.definition | ConvertTo-Json -Depth 100),
    "parameters": {
      "`$connections": {
        "value": {
          "sharepointonline": {
            "id": "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/sharepointonline",
            "connectionId": "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/sharepointonline",
            "connectionName": "sharepointonline"
          },
          "azuread": {
            "id": "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/azuread",
            "connectionId": "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/azuread",
            "connectionName": "azuread"
          },
          "office365-1": {
            "id": "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/office365",
            "connectionId": "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/office365",
            "connectionName": "office365"
          }
        }
      }
    }
  }
}
"@
    
    # Save to temp file
    $tempDeployFile = [System.IO.Path]::GetTempFileName()
    $armJson | Set-Content $tempDeployFile -Encoding UTF8
    
    $logicAppResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName"
    
    az rest --method PUT `
            --uri "https://management.azure.com$($logicAppResourceId)?api-version=2019-05-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempDeployFile" | Out-Null
    
    # Save deployed Logic App JSON for reference
    $deployedJsonFolder = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $deployedJsonFolder)) {
        New-Item -ItemType Directory -Path $deployedJsonFolder -Force | Out-Null
    }
    $deployedJsonFile = Join-Path $deployedJsonFolder "LogicApp-Deployed_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').json"
    Copy-Item $tempDeployFile $deployedJsonFile -Force
    Write-Host "  Logic App JSON saved to: $deployedJsonFile" -ForegroundColor Gray
    
    Remove-Item $tempDeployFile -Force -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Logic App workflow deployed" -ForegroundColor Green
    } else {
        throw "Logic App deployment failed"
    }
    
    # Get HTTP Trigger URL
    Write-Host "`nRetrieving Logic App HTTP trigger URL..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5  # Give Azure time to finalize deployment
    
    try {
        $triggerUrl = az rest --method POST `
            --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName/triggers/Manual_HTTP/listCallbackUrl?api-version=2016-06-01" `
            --query "value" -o tsv 2>$null
        
        if (-not [string]::IsNullOrWhiteSpace($triggerUrl)) {
            Write-Host "✓ HTTP Trigger URL retrieved" -ForegroundColor Green
            Write-Host "  URL: $($triggerUrl.Substring(0, [Math]::Min(60, $triggerUrl.Length)))..." -ForegroundColor Gray
            
            # Save to INI file
            Set-IniValue -Path $configFile -Section "LogicApp" -Key "TriggerUrl" -Value $triggerUrl
            Write-Host "✓ Trigger URL saved to INI file" -ForegroundColor Green
            
            # Update Function App environment variable
            Write-Host "`nUpdating Function App with trigger URL..." -ForegroundColor Yellow
            az functionapp config appsettings set `
                --resource-group $resourceGroup `
                --name $functionAppName `
                --settings "LOGIC_APP_TRIGGER_URL=$triggerUrl" | Out-Null
            
            Write-Host "✓ Function App updated with trigger URL" -ForegroundColor Green
        } else {
            Write-Host "⚠ Could not retrieve trigger URL - will be set to NOT_SET_YET" -ForegroundColor Yellow
            Write-Host "  You can run script 05 again after this to update it" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "⚠ Failed to get trigger URL: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Function App will use default 'NOT_SET_YET' value" -ForegroundColor Gray
    }
    
    # Verify Logic App exists
    Write-Host "`nVerifying Logic App deployment..." -ForegroundColor Yellow
    $deployed = Get-AzLogicApp -ResourceGroupName $resourceGroup -Name $logicAppName -ErrorAction SilentlyContinue
    
    if ($null -ne $deployed) {
        Write-Host "✓ Logic App verified" -ForegroundColor Green
        Write-Host "  Name: $($deployed.Name)" -ForegroundColor Gray
        Write-Host "  State: $($deployed.State)" -ForegroundColor Gray
        
        # Enable if disabled
        if ($deployed.State -ne "Enabled") {
            Write-Host "`nEnabling Logic App..." -ForegroundColor Yellow
            Set-AzLogicApp -ResourceGroupName $resourceGroup -Name $logicAppName -State Enabled -Force
            Write-Host "✓ Logic App enabled" -ForegroundColor Green
        }
    }
    else {
        Write-Host "⚠ Could not verify Logic App - please check manually" -ForegroundColor Yellow
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "✓ Step 06 Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    Write-Host "`nDeployment Summary:" -ForegroundColor Cyan
    Write-Host "  SharePoint Site: $siteUrl" -ForegroundColor Gray
    Write-Host "  SharePoint List ID: $listId" -ForegroundColor Gray
    Write-Host "  Function App: https://$functionAppName.azurewebsites.net" -ForegroundColor Gray
    Write-Host "  Logic App: $logicAppName" -ForegroundColor Gray
    Write-Host "    - HTTP Trigger: Enabled (triggered on user upload)" -ForegroundColor Gray
    Write-Host "    - Scheduled: Every 12 hours (backup)" -ForegroundColor Gray
    Write-Host "  Security Group: $($config['Security']['MFAGroupName'])" -ForegroundColor Gray
    Write-Host "  Email From: $noReplyMailbox" -ForegroundColor Gray
    
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
