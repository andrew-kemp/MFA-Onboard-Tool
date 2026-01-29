# Step 08 - Deploy Email Reports Logic App
# Creates a Logic App that sends daily/weekly MFA rollout status reports

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
    
    # Ensure file exists
    if (-not (Test-Path $Path)) {
        "# MFA Onboarding Configuration" | Set-Content $Path
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
    
    Set-Content -Path $Path -Value ($output -join "`r`n") -Force
}

function Get-IniValueOrPrompt {
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [string]$Prompt,
        [string]$Default = ""
    )
    
    if (Test-Path $Path) {
        $config = Get-IniContent -Path $Path
        $value = $config[$Section][$Key]
    } else {
        $value = $null
    }
    
    if ([string]::IsNullOrWhiteSpace($value)) {
        if ([string]::IsNullOrWhiteSpace($Default)) {
            $value = Read-Host $Prompt
        } else {
            $input = Read-Host "$Prompt [$Default]"
            $value = if ([string]::IsNullOrWhiteSpace($input)) { $Default } else { $input }
        }
        Set-IniValue -Path $Path -Section $Section -Key $Key -Value $value
    }
    
    return $value
}

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Step 08 - Deploy Email Reports Logic App" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Ensure INI file exists
    if (-not (Test-Path $configFile)) {
        Write-Host "Creating new configuration file: $configFile" -ForegroundColor Yellow
        "# MFA Onboarding Configuration" | Set-Content $configFile
    }
    
    $config = Get-IniContent -Path $configFile
    
    # Get required values (prompt if missing)
    Write-Host "Checking configuration..." -ForegroundColor Yellow
    
    $resourceGroup = Get-IniValueOrPrompt -Path $configFile -Section "Azure" -Key "ResourceGroup" `
        -Prompt "Resource Group name" `
        -Default "rg-mfa-onboarding"
    
    $region = Get-IniValueOrPrompt -Path $configFile -Section "Azure" -Key "Region" `
        -Prompt "Azure region" `
        -Default "uksouth"
    
    $siteUrl = Get-IniValueOrPrompt -Path $configFile -Section "SharePoint" -Key "SiteUrl" `
        -Prompt "SharePoint Site URL"
    
    $listId = Get-IniValueOrPrompt -Path $configFile -Section "SharePoint" -Key "ListId" `
        -Prompt "SharePoint List ID"
    
    $tenantId = Get-IniValueOrPrompt -Path $configFile -Section "Tenant" -Key "TenantId" `
        -Prompt "Tenant ID"
    
    Write-Host "✓ Configuration loaded" -ForegroundColor Green
    Write-Host "✓ Configuration loaded" -ForegroundColor Green
    
    # Ensure Azure connection
    $azContext = Get-AzContext
    if ($null -eq $azContext) {
        Connect-AzAccount
    }
    
    $reportsLogicAppName = "logic-mfa-reports-$(Get-Random -Minimum 100000 -Maximum 999999)"
    
    # Get report recipients from user
    Write-Host "Email Report Configuration" -ForegroundColor Yellow
    Write-Host "Enter email addresses to receive reports (comma-separated):" -ForegroundColor Gray
    $reportRecipients = Read-Host "Recipients"
    if ([string]::IsNullOrWhiteSpace($reportRecipients)) {
        $reportRecipients = $azContext.Account.Id
        Write-Host "  Using current user: $reportRecipients" -ForegroundColor Gray
    }
    
    Write-Host "`nSelect report frequency:" -ForegroundColor Yellow
    Write-Host "  1) Daily (9 AM)" -ForegroundColor Gray
    Write-Host "  2) Weekly (Monday 9 AM)" -ForegroundColor Gray
    Write-Host "  3) Both Daily and Weekly" -ForegroundColor Gray
    $freqChoice = Read-Host "Choice (1-3)"
    
    $recurrence = switch ($freqChoice) {
        "1" { "Day"; break }
        "2" { "Week"; break }
        "3" { "Day"; break }
        default { "Day" }
    }
    
    Write-Host "`nCreating Logic App with Managed Identity..." -ForegroundColor Yellow
    
    $subscriptionId = (Get-AzContext).Subscription.Id
    $logicAppResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$reportsLogicAppName"
    
    # Create minimal Logic App with managed identity
    $initialLogicApp = @{
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
            }
        }
    }
    
    $tempInitialFile = [System.IO.Path]::GetTempFileName()
    $initialLogicApp | ConvertTo-Json -Depth 10 | Set-Content $tempInitialFile -Force -Encoding UTF8
    
    $createResponseJson = az rest --method PUT `
        --uri "https://management.azure.com$($logicAppResourceId)?api-version=2019-05-01" `
        --headers "Content-Type=application/json" `
        --body "@$tempInitialFile"
    
    Remove-Item $tempInitialFile -Force -ErrorAction SilentlyContinue
    
    $createResponse = $createResponseJson | ConvertFrom-Json
    $principalId = $createResponse.identity.principalId
    
    Write-Host "✓ Logic App created: $reportsLogicAppName" -ForegroundColor Green
    Write-Host "  Managed Identity Principal ID: $principalId" -ForegroundColor Gray
    
    # Save to INI
    Set-IniValue -Path $configFile -Section "EmailReports" -Key "LogicAppName" -Value $reportsLogicAppName
    Set-IniValue -Path $configFile -Section "EmailReports" -Key "Recipients" -Value $reportRecipients
    Set-IniValue -Path $configFile -Section "EmailReports" -Key "Frequency" -Value $recurrence
    
    Write-Host "`nCreating Office 365 API connection..." -ForegroundColor Yellow

    $subscriptionId = (Get-AzContext).Subscription.Id
    $office365ConnectionName = "office365-reports"

    $office365Connection = @{
        properties = @{
            displayName = "Office 365 Reports"
            api = @{
                id = "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/office365"
            }
            parameterValues = @{}
        }
        location = $region
    }

    $tempFile = [System.IO.Path]::GetTempFileName()
    $office365Connection | ConvertTo-Json -Depth 10 | Set-Content $tempFile -Force

    az rest --method PUT `
            --uri "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/$($office365ConnectionName)?api-version=2016-06-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempFile" | Out-Null

    Remove-Item $tempFile -Force
    Write-Host "✓ Office 365 connection created" -ForegroundColor Green

    Write-Host "`nAuthorize the Office 365 connection now:" -ForegroundColor Yellow
    Write-Host "  Azure Portal > Resource Groups > $resourceGroup > Connections > $office365ConnectionName" -ForegroundColor Gray
    Write-Host "  Click 'Edit API connection' > 'Authorize' > sign in > 'Save'" -ForegroundColor Gray
    Read-Host "Press ENTER after you authorize to continue"
    
    # Build Logic App workflow
    Write-Host "`nBuilding email report workflow..." -ForegroundColor Yellow

    # Use configured storage account to build portal URL for email template
    $portalUrl = "https://$($config['Azure']['StorageAccountName']).z33.web.core.windows.net/upload-portal.html"
    
    # Get branding configuration
    $logoUrl = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("LogoUrl")) { $config["Branding"]["LogoUrl"] } else { "" }
    $companyName = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("CompanyName")) { $config["Branding"]["CompanyName"] } else { "" }
    
    # Build logo header HTML if logo URL is provided
    $logoHeaderHtml = ""
    if (-not [string]::IsNullOrWhiteSpace($logoUrl)) {
        $altText = if ([string]::IsNullOrWhiteSpace($companyName)) { "Company Logo" } else { $companyName }
        $logoHeaderHtml = "<div style='background: #fff; padding: 15px; text-align: center; border-bottom: 1px solid #e0e0e0;'><img src='$logoUrl' alt='$altText' style='max-width: 200px; height: auto;' /></div>"
    }

    $rawEmailTemplate = @'
<html><body style="font-family: Segoe UI, Arial, sans-serif;"><div style="max-width: 600px; margin: 0 auto; padding: 20px;">LOGO_PLACEHOLDER<div style="background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); color: white; padding: 30px; border-radius: 12px; margin-bottom: 20px;"><h1 style="margin: 0; font-size: 28px;">📊 MFA Rollout Report</h1><p style="margin: 10px 0 0 0; opacity: 0.9;">@{utcNow('dddd, MMMM dd, yyyy')}</p></div><div style="background: #f5f5f5; padding: 20px; border-radius: 8px; margin-bottom: 20px;"><h2 style="margin-top: 0; color: #333;">Executive Summary</h2><table style="width: 100%; border-collapse: collapse;"><tr><td style="padding: 15px; background: white; border-radius: 8px; text-align: center; margin: 5px;"><div style="font-size: 36px; font-weight: bold; color: #1e3c72;">@{variables('totalCount')}</div><div style="font-size: 14px; color: #666;">Total Users</div></td><td style="padding: 15px; background: white; border-radius: 8px; text-align: center; margin: 5px;"><div style="font-size: 36px; font-weight: bold; color: #4caf50;">@{variables('completedCount')}</div><div style="font-size: 14px; color: #666;">Completed</div></td></tr><tr><td style="padding: 15px; background: white; border-radius: 8px; text-align: center; margin: 5px;"><div style="font-size: 36px; font-weight: bold; color: #ff9800;">@{variables('pendingCount')}</div><div style="font-size: 14px; color: #666;">Pending</div></td><td style="padding: 15px; background: white; border-radius: 8px; text-align: center; margin: 5px;"><div style="font-size: 36px; font-weight: bold; color: #1e3c72;">@{outputs('Calculate_Completion_Rate')}%</div><div style="font-size: 14px; color: #666;">Completion Rate</div></td></tr></table></div><div style="background: white; padding: 20px; border-radius: 8px; border: 1px solid #e0e0e0;"><h3 style="margin-top: 0; color: #333;">Quick Links</h3><p><a href="$SITE_URL" style="color: #1e3c72; text-decoration: none;">📋 View SharePoint List</a></p><p><a href="$PORTAL_URL" style="color: #1e3c72; text-decoration: none;">📤 Upload Portal</a></p></div><div style="margin-top: 20px; padding: 15px; background: #e3f2fd; border-radius: 8px; border-left: 4px solid #2196f3;"><p style="margin: 0; font-size: 14px; color: #1976d2;"><strong>💡 Tip:</strong> Log in to the Upload Portal and visit the Reports tab for detailed analytics and user-level breakdowns.</p></div></div></body></html>
'@

    $emailTemplate = $rawEmailTemplate.Replace('LOGO_PLACEHOLDER', $logoHeaderHtml).Replace('$SITE_URL', $siteUrl).Replace('$PORTAL_URL', $portalUrl)
    
    # Extract site domain and path for Graph API
    $siteUri = [System.Uri]$siteUrl
    $siteDomain = $siteUri.Host
    $sitePath = $siteUri.AbsolutePath
    
    $workflow = @{
        location = $region
        identity = @{
            type = "SystemAssigned"
        }
        properties = @{
            state = "Enabled"
            definition = @{
                '$schema' = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
                contentVersion = "1.0.0.0"
                parameters = @{
                    '$connections' = @{
                        defaultValue = @{}
                        type = "Object"
                    }
                }
                triggers = @{
                    Recurrence = @{
                        recurrence = @{
                            frequency = $recurrence
                            interval = 1
                            schedule = @{
                                hours = @("9")
                                minutes = @(0)
                            }
                        }
                        type = "Recurrence"
                    }
                }
                actions = @{
                    'Get_SharePoint_List_Items' = @{
                        runAfter = @{}
                        type = "Http"
                        inputs = @{
                            uri = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$expand=fields&`$top=5000"
                            method = "GET"
                            authentication = @{
                                type = "ManagedServiceIdentity"
                                audience = "https://graph.microsoft.com"
                            }
                        }
                    }
                    'Parse_Items' = @{
                        runAfter = @{
                            'Get_SharePoint_List_Items' = @("Succeeded")
                        }
                        type = "ParseJson"
                        inputs = @{
                            content = "@body('Get_SharePoint_List_Items')"
                            schema = @{
                                type = "object"
                                properties = @{
                                    value = @{
                                        type = "array"
                                        items = @{
                                            type = "object"
                                            properties = @{
                                                fields = @{ type = "object" }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    'Initialize_Total_Count' = @{
                        runAfter = @{
                            'Parse_Items' = @("Succeeded")
                        }
                        type = "InitializeVariable"
                        inputs = @{
                            variables = @(
                                @{
                                    name = "totalCount"
                                    type = "integer"
                                    value = "@length(body('Parse_Items')?['value'])"
                                }
                            )
                        }
                    }
                    'Initialize_Completed_Count' = @{
                        runAfter = @{
                            'Initialize_Total_Count' = @("Succeeded")
                        }
                        type = "InitializeVariable"
                        inputs = @{
                            variables = @(
                                @{
                                    name = "completedCount"
                                    type = "integer"
                                    value = 0
                                }
                            )
                        }
                    }
                    'Initialize_Pending_Count' = @{
                        runAfter = @{
                            'Initialize_Completed_Count' = @("Succeeded")
                        }
                        type = "InitializeVariable"
                        inputs = @{
                            variables = @(
                                @{
                                    name = "pendingCount"
                                    type = "integer"
                                    value = 0
                                }
                            )
                        }
                    }
                    'Count_Statuses' = @{
                        runAfter = @{
                            'Initialize_Pending_Count' = @("Succeeded")
                        }
                        type = "Foreach"
                        foreach = "@body('Parse_Items')?['value']"
                        actions = @{
                            'Check_Status' = @{
                                type = "If"
                                expression = @{
                                    or = @(
                                        @{ equals = @("@items('Count_Statuses')?['fields']?['InGroup']", $true) }
                                        @{ equals = @("@items('Count_Statuses')?['fields']?['InviteStatus']", "AddedToGroup") }
                                        @{ equals = @("@items('Count_Statuses')?['fields']?['InviteStatus']", "Active") }
                                    )
                                }
                                actions = @{
                                    'Increment_Completed' = @{
                                        type = "IncrementVariable"
                                        inputs = @{
                                            name = "completedCount"
                                            value = 1
                                        }
                                    }
                                }
                                else = @{
                                    actions = @{
                                        'Increment_Pending' = @{
                                            type = "IncrementVariable"
                                            inputs = @{
                                                name = "pendingCount"
                                                value = 1
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    'Calculate_Completion_Rate' = @{
                        runAfter = @{
                            'Count_Statuses' = @("Succeeded")
                        }
                        type = "Compose"
                        inputs = "@if(greater(variables('totalCount'), 0), div(mul(variables('completedCount'), 100), variables('totalCount')), 0)"
                    }
                    'Build_Email_Body' = @{
                        runAfter = @{
                            'Calculate_Completion_Rate' = @("Succeeded")
                        }
                        type = "Compose"
                        inputs = $emailTemplate
                    }
                    'Send_Email' = @{
                        runAfter = @{
                            'Build_Email_Body' = @("Succeeded")
                        }
                        type = "ApiConnection"
                        inputs = @{
                            host = @{
                                connection = @{
                                    name = "@parameters('`$connections')['office365']['connectionId']"
                                }
                            }
                            method = "post"
                            body = @{
                                To = $reportRecipients
                                Subject = "MFA Rollout Report - @{utcNow('yyyy-MM-dd')} - @{outputs('Calculate_Completion_Rate')}% Complete"
                                Body = "@{outputs('Build_Email_Body')}"
                                Importance = "Normal"
                            }
                            path = "/v2/Mail"
                        }
                    }
                }
            }
            parameters = @{
                '$connections' = @{
                    value = @{
                        office365 = @{
                            connectionId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/$office365ConnectionName"
                            connectionName = $office365ConnectionName
                            id = "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$region/managedApis/office365"
                        }
                    }
                }
            }
        }
    }
    
        # Optional local HTML preview of the report email
        $previewChoice = Read-Host "Generate a local HTML preview of the report email? (Y/N, default N)"
        if ($previewChoice -match "^(?i:y)") {
        $previewHtml = $emailTemplate
        $previewHtml = $previewHtml.Replace("@{variables('totalCount')}", "120")
        $previewHtml = $previewHtml.Replace("@{variables('completedCount')}", "90")
        $previewHtml = $previewHtml.Replace("@{variables('pendingCount')}", "30")
        $previewHtml = $previewHtml.Replace("@{outputs('Calculate_Completion_Rate')}", "75")
        $previewHtml = $previewHtml.Replace("@{utcNow('dddd, MMMM dd, yyyy')}", (Get-Date -Format "dddd, MMMM dd, yyyy"))

        if (-not (Test-Path "$PSScriptRoot\logs")) { New-Item -ItemType Directory -Path "$PSScriptRoot\logs" -Force | Out-Null }
        $previewPath = "$PSScriptRoot\logs\email-report-preview.html"
        $previewHtml | Set-Content $previewPath -Encoding UTF8 -Force
        Write-Host "✓ Preview saved: $previewPath" -ForegroundColor Green

        $openChoice = Read-Host "Open the preview in your browser now? (Y/N, default Y)"
        if ($openChoice -notmatch "^(?i:n)") { Start-Process $previewPath }
        }

        # Deploy Logic App
        $tempDeployFile = [System.IO.Path]::GetTempFileName()
        $workflow | ConvertTo-Json -Depth 50 | Set-Content $tempDeployFile -Force

        $logicAppResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$reportsLogicAppName"

        az rest --method PUT `
            --uri "https://management.azure.com$($logicAppResourceId)?api-version=2019-05-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempDeployFile" | Out-Null

        Remove-Item $tempDeployFile -Force

        Write-Host "✓ Email Reports Logic App deployed" -ForegroundColor Green
    
    # Get the managed identity principal ID after deployment
    Write-Host "`nRetrieving Managed Identity Principal ID..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3  # Give Azure time to finalize
    
    $deployedLogicAppJson = az rest --method GET `
        --uri "https://management.azure.com$($logicAppResourceId)?api-version=2019-05-01"
    $deployedLogicApp = $deployedLogicAppJson | ConvertFrom-Json
    $principalId = $deployedLogicApp.identity.principalId
    
    if ([string]::IsNullOrWhiteSpace($principalId)) {
        Write-Host "⚠️  Warning: Could not retrieve Principal ID. Run Fix-Graph-Permissions.ps1 to grant permissions." -ForegroundColor Yellow
    }
    else {
        Write-Host "✓ Principal ID: $principalId" -ForegroundColor Green
    }
    
    # Grant Graph API permissions to Logic App Managed Identity
    Write-Host "`nGranting Microsoft Graph permissions to Reports Logic App..." -ForegroundColor Yellow
    
    $graphAppId = "00000003-0000-0000-c000-000000000000"
    $sitesReadAllId = "332a536c-c7ef-4017-ab91-336970924f0d"  # Sites.Read.All
    
    # Get Graph Service Principal ID
    $graphSpId = az ad sp list --filter "appId eq '$graphAppId'" --query "[0].id" -o tsv
    
    if ([string]::IsNullOrWhiteSpace($graphSpId)) {
        Write-Host "⚠️  Could not find Microsoft Graph service principal" -ForegroundColor Yellow
    }
    elseif ([string]::IsNullOrWhiteSpace($principalId)) {
        Write-Host "⚠️  No Principal ID available, skipping permission grant" -ForegroundColor Yellow
        Write-Host "   Run Fix-Graph-Permissions.ps1 after deployment" -ForegroundColor Gray
    }
    else {
        Write-Host "  Granting Sites.Read.All..." -ForegroundColor Yellow
        
        $body = @{
            principalId = $principalId
            resourceId = $graphSpId
            appRoleId = $sitesReadAllId
        } | ConvertTo-Json
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        $body | Set-Content $tempFile -Force
        
        $grantSuccess = $false
        try {
            $grantResult = az rest --method POST `
                --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments" `
                --body "@$tempFile" `
                --headers "Content-Type=application/json" 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Sites.Read.All permission granted" -ForegroundColor Green
                $grantSuccess = $true
            }
            else {
                $errorMsg = $grantResult | Out-String
                if ($errorMsg -like "*already exists*") {
                    Write-Host "  ✓ Sites.Read.All already granted" -ForegroundColor Gray
                    $grantSuccess = $true
                }
                else {
                    Write-Host "  ⚠️  Permission grant failed: $errorMsg" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "  ⚠️  Exception during permission grant: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        
        if ($grantSuccess) {
            Write-Host "`n⏳ Waiting 30 seconds for Azure AD permission propagation..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
            Write-Host "✓ Permission propagation complete" -ForegroundColor Green
        }
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "✓ Step 08 Completed Successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    
    Write-Host "`n📧 EMAIL REPORTS CONFIGURED:" -ForegroundColor Cyan
    Write-Host "`nLogic App: $reportsLogicAppName" -ForegroundColor Gray
    Write-Host "Recipients: $reportRecipients" -ForegroundColor Gray
    Write-Host "Frequency: $recurrence at 9:00 AM" -ForegroundColor Gray
    
    Write-Host "`n⚠️  IMPORTANT:" -ForegroundColor Yellow
    Write-Host "  1. Authorize the Office 365 connection in Azure Portal" -ForegroundColor Gray
    Write-Host "  2. Navigate to: Resource Groups > $resourceGroup > Connections > $office365ConnectionName" -ForegroundColor Gray
    Write-Host "  3. Click 'Edit API connection' > 'Authorize' > Sign in > 'Save'" -ForegroundColor Gray
    
    Write-Host "`n🧪 TEST:" -ForegroundColor Cyan
    Write-Host "  Run the Logic App manually to test: Azure Portal > Logic Apps > $reportsLogicAppName > Run Trigger`n" -ForegroundColor Gray
    
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
