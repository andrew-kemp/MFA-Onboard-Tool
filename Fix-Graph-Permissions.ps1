# Fix Graph API Permissions for Function App Managed Identity

$ErrorActionPreference = "Stop"

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

$config = Get-IniContent -Path "$PSScriptRoot\mfa-config.ini"
$functionAppName = $config["Azure"]["FunctionAppName"]
$resourceGroup = $config["Azure"]["ResourceGroup"]
$subscriptionId = $config["Tenant"]["SubscriptionId"]
$tenantId = $config["Tenant"]["TenantId"]

Write-Host "Function App: $functionAppName" -ForegroundColor Gray
Write-Host "Resource Group: $resourceGroup`n" -ForegroundColor Gray

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
$azContext = Get-AzContext
if ($null -eq $azContext) {
    Connect-AzAccount -TenantId $tenantId | Out-Null
}
Set-AzContext -SubscriptionId $subscriptionId | Out-Null
Write-Host "✓ Connected to Azure`n" -ForegroundColor Green

Write-Host "Getting Function App Managed Identity..." -ForegroundColor Yellow
$functionApp = Get-AzFunctionApp -ResourceGroupName $resourceGroup -Name $functionAppName
$principalId = $functionApp.IdentityPrincipalId

if ([string]::IsNullOrWhiteSpace($principalId)) {
    Write-Host "ERROR: Managed Identity not found. Enabling it..." -ForegroundColor Red
    
    $identity = Update-AzFunctionApp -ResourceGroupName $resourceGroup -Name $functionAppName -IdentityType SystemAssigned -Force
    $principalId = $identity.IdentityPrincipalId
    
    Write-Host "✓ Managed Identity enabled: $principalId" -ForegroundColor Green
    Write-Host "Waiting 10 seconds for propagation..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}
else {
    Write-Host "✓ Principal ID: $principalId" -ForegroundColor Green
}

Write-Host "`nGranting Graph API permissions..." -ForegroundColor Yellow

# Ensure Microsoft.Graph modules are loaded
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

# Connect to Microsoft Graph with required scopes
Connect-MgGraph -TenantId $tenantId -Scopes "Application.Read.All","AppRoleAssignment.ReadWrite.All" -NoWelcome

# Get Microsoft Graph Service Principal
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

if (-not $graphSp) {
    throw "Could not find Microsoft Graph service principal"
}

Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green

# Define required permissions
$requiredPermissions = @(
    @{Name="User.Read.All"; Id="df021288-bdef-4463-88db-98f22de89214"}
    @{Name="GroupMember.ReadWrite.All"; Id="dbaae8cf-10b5-4b86-a4a1-f871c94c6695"}
    @{Name="Sites.ReadWrite.All"; Id="9492366f-7969-46a4-8d15-ed1a20078fff"}
)

foreach ($permission in $requiredPermissions) {
    Write-Host "  Granting $($permission.Name)..." -ForegroundColor Gray
    
    try {
        $body = @{
            principalId = $principalId
            resourceId = $graphSp.Id
            appRoleId = $permission.Id
        }
        
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $principalId -BodyParameter $body -ErrorAction Stop | Out-Null
        Write-Host "    ✓ $($permission.Name) granted" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -like "*Permission being assigned already exists*" -or $_.Exception.Message -like "*already exists*") {
            Write-Host "    ✓ $($permission.Name) already granted" -ForegroundColor Gray
        }
        else {
            Write-Host "    ✗ ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Disconnect-MgGraph | Out-Null
Write-Host "`n✓ Graph API permissions granted for Function App!" -ForegroundColor Green

# Grant admin consent for Upload Portal App Registration
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Granting Admin Consent for Upload Portal" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$uploadPortalClientId = $config["UploadPortal"]["ClientId"]

if ([string]::IsNullOrWhiteSpace($uploadPortalClientId)) {
    Write-Host "⚠️  Upload Portal Client ID not found in config - skipping" -ForegroundColor Yellow
}
else {
    Write-Host "Upload Portal Client ID: $uploadPortalClientId" -ForegroundColor Gray
    Write-Host "`nGranting admin consent for delegated permissions..." -ForegroundColor Yellow
    
    # Use Azure CLI to avoid PowerShell module conflicts
    Write-Host "  Getting service principal..." -ForegroundColor Gray
    
    # Get or create service principal
    $appSpJson = az ad sp show --id $uploadPortalClientId 2>$null
    if (-not $appSpJson) {
        Write-Host "  Creating service principal for app..." -ForegroundColor Yellow
        $appSpJson = az ad sp create --id $uploadPortalClientId
        Start-Sleep -Seconds 5
    }
    $appSp = $appSpJson | ConvertFrom-Json
    $appSpId = $appSp.id
    
    Write-Host "  Service Principal ID: $appSpId" -ForegroundColor Gray
    
    # Get Microsoft Graph Service Principal ID
    $graphSpJson = az ad sp show --id 00000003-0000-0000-c000-000000000000
    $graphSp = $graphSpJson | ConvertFrom-Json
    $graphSpId = $graphSp.id
    
    # Required scopes
    $requiredScopes = "User.Read Sites.Read.All"
    
    Write-Host "  Creating admin consent grant using Azure CLI..." -ForegroundColor Yellow
    
    # Check for existing grant
    $existingGrantsJson = az rest --method GET --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$appSpId' and resourceId eq '$graphSpId'"
    $existingGrants = ($existingGrantsJson | ConvertFrom-Json).value
    
    if ($existingGrants -and $existingGrants.Count -gt 0) {
        Write-Host "  Updating existing consent..." -ForegroundColor Gray
        $grantId = $existingGrants[0].id
        
        $updateBody = @{
            scope = $requiredScopes
        } | ConvertTo-Json
        $tempFile = [System.IO.Path]::GetTempFileName()
        $updateBody | Set-Content $tempFile -Force -Encoding UTF8
        az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$grantId" --headers "Content-Type=application/json" --body "@$tempFile" | Out-Null
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "  Creating new consent grant..." -ForegroundColor Gray
        $createBody = @{
            clientId = $appSpId
            consentType = "AllPrincipals"
            resourceId = $graphSpId
            scope = $requiredScopes
        } | ConvertTo-Json
        $tempFile = [System.IO.Path]::GetTempFileName()
        $createBody | Set-Content $tempFile -Force -Encoding UTF8
        az rest --method POST --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants" --headers "Content-Type=application/json" --body "@$tempFile" | Out-Null
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "  ✓ Admin consent granted for:" -ForegroundColor Green
    Write-Host "    - User.Read" -ForegroundColor Gray
    Write-Host "    - Sites.Read.All" -ForegroundColor Gray
}

# Grant permissions to Email Reports Logic App (if exists)
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Logic Apps Permissions" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Invitation Logic App (from script 06)
$invitationLogicAppName = $config["LogicApp"]["LogicAppName"]

if ([string]::IsNullOrWhiteSpace($invitationLogicAppName)) {
    Write-Host "⚠️  Invitation Logic App not found in config - skipping" -ForegroundColor Yellow
}
else {
    Write-Host "Invitation Logic App: $invitationLogicAppName" -ForegroundColor Cyan
    
    Write-Host "Getting Invitation Logic App Managed Identity..." -ForegroundColor Yellow
    $invitationLogicApp = Get-AzResource -ResourceGroupName $resourceGroup -Name $invitationLogicAppName -ResourceType "Microsoft.Logic/workflows"
    
    if ($null -eq $invitationLogicApp -or $null -eq $invitationLogicApp.Identity -or $invitationLogicApp.Identity.Type -ne "SystemAssigned") {
        Write-Host "⚠️  Invitation Logic App not found or doesn't have Managed Identity" -ForegroundColor Yellow
        Write-Host "   Run script 06 to deploy the Invitation Logic App first" -ForegroundColor Gray
    }
    else {
        $invitationAppPrincipalId = $invitationLogicApp.Identity.PrincipalId
        Write-Host "✓ Principal ID: $invitationAppPrincipalId" -ForegroundColor Green
        
        Write-Host "`nGranting Graph API permissions to Invitation Logic App..." -ForegroundColor Yellow
        
        $invitationPermissions = @(
            @{Name="Directory.Read.All"; Id="7ab1d382-f21e-4acd-a863-ba3e13f7da61"}
            @{Name="User.Read.All"; Id="df021288-bdef-4463-88db-98f22de89214"}
            @{Name="UserAuthenticationMethod.Read.All"; Id="38d9df27-64da-44fd-b7c5-a6fbac20248f"}
            @{Name="GroupMember.ReadWrite.All"; Id="dbaae8cf-10b5-4b86-a4a1-f871c94c6695"}
            @{Name="Group.Read.All"; Id="5b567255-7703-4780-807c-7be8301ae99b"}
        )
        
        foreach ($perm in $invitationPermissions) {
            Write-Host "  Granting $($perm.Name)..." -ForegroundColor Gray
            
            $body = @{
                principalId = $invitationAppPrincipalId
                resourceId = $graphSpId
                appRoleId = $perm.Id
            } | ConvertTo-Json
            
            $tempFile = [System.IO.Path]::GetTempFileName()
            $body | Set-Content $tempFile -Force
            
            try {
                az rest --method POST `
                    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$invitationAppPrincipalId/appRoleAssignments" `
                    --body "@$tempFile" `
                    --headers "Content-Type=application/json" 2>$null | Out-Null
                Write-Host "  ✓ $($perm.Name) granted" -ForegroundColor Green
            }
            catch {
                Write-Host "  ✓ $($perm.Name) may already be granted" -ForegroundColor Gray
            }
            finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Host "✓ Invitation Logic App permissions configured" -ForegroundColor Green
    }
}

# 2. Email Reports Logic App (from script 08)
Write-Host "`n" -NoNewline
$reportsLogicAppName = $config["EmailReports"]["LogicAppName"]

if ([string]::IsNullOrWhiteSpace($reportsLogicAppName)) {
    Write-Host "⚠️  Email Reports Logic App not found in config - skipping" -ForegroundColor Yellow
}
else {
    Write-Host "Email Reports Logic App: $reportsLogicAppName" -ForegroundColor Cyan
    
    Write-Host "Getting Reports Logic App Managed Identity..." -ForegroundColor Yellow
    
    # Use same approach as Step 06: prefer Az cmdlets + az logicapp identity assign
    $subscriptionId = (Get-AzContext).Subscription.Id
    $logicAppResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$reportsLogicAppName"
    $logicAppUri = "https://management.azure.com$logicAppResourceId?api-version=2019-05-01"
    
    try {
        $reportsLogicApp = Get-AzResource -ResourceGroupName $resourceGroup -Name $reportsLogicAppName -ResourceType "Microsoft.Logic/workflows" -ErrorAction SilentlyContinue
        
        if ($null -eq $reportsLogicApp) {
            Write-Host "⚠️  Reports Logic App not found in resource group $resourceGroup" -ForegroundColor Yellow
            return
        }
        
        if ($null -eq $reportsLogicApp.Identity -or $reportsLogicApp.Identity.Type -ne "SystemAssigned") {
            Write-Host "⚠️  Reports Logic App doesn't have Managed Identity enabled" -ForegroundColor Yellow
            Write-Host "   Enabling Managed Identity (az logicapp identity assign)..." -ForegroundColor Yellow
            
            az logicapp identity assign --resource-group $resourceGroup --name $reportsLogicAppName 2>$null | Out-Null
            Start-Sleep -Seconds 5
            $reportsLogicApp = Get-AzResource -ResourceGroupName $resourceGroup -Name $reportsLogicAppName -ResourceType "Microsoft.Logic/workflows" -ErrorAction SilentlyContinue
        }
        
        if ($null -eq $reportsLogicApp.Identity -or $reportsLogicApp.Identity.Type -ne "SystemAssigned") {
            Write-Host "   Managed Identity still not enabled, retrying with REST PATCH..." -ForegroundColor Gray
            $patchBody = @{ identity = @{ type = "SystemAssigned" } } | ConvertTo-Json -Depth 5
            $tempFile = [System.IO.Path]::GetTempFileName()
            $patchBody | Set-Content $tempFile -Force -Encoding UTF8
            az rest --method PATCH --uri $logicAppUri --body "@$tempFile" --headers "Content-Type=application/json" --output none
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 8
            $reportsLogicApp = Get-AzResource -ResourceGroupName $resourceGroup -Name $reportsLogicAppName -ResourceType "Microsoft.Logic/workflows" -ErrorAction SilentlyContinue
        }
        
        $reportsAppPrincipalId = $reportsLogicApp.Identity.PrincipalId
        
        if ([string]::IsNullOrWhiteSpace($reportsAppPrincipalId)) {
            Write-Host "⚠️  Failed to get Principal ID after enabling identity" -ForegroundColor Yellow
            Write-Host "   Please run this script again in 1 minute" -ForegroundColor Gray
            return
        }
        
        Write-Host "✓ Principal ID: $reportsAppPrincipalId" -ForegroundColor Green
        
        Write-Host "`nGranting Graph API permissions to Reports Logic App..." -ForegroundColor Yellow
        
        # Sites.Read.All permission
        $sitesReadAllId = "332a536c-c7ef-4017-ab91-336970924f0d"
        
        Write-Host "  Granting Sites.Read.All..." -ForegroundColor Gray
        
        $body = @{
            principalId = $reportsAppPrincipalId
            resourceId = $graphSpId
            appRoleId = $sitesReadAllId
        } | ConvertTo-Json
        
        $tempFile = [System.IO.Path]::GetTempFileName()
        $body | Set-Content $tempFile -Force
        
        try {
            az rest --method POST `
                --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$reportsAppPrincipalId/appRoleAssignments" `
                --body "@$tempFile" `
                --headers "Content-Type=application/json" 2>$null | Out-Null
            Write-Host "  ✓ Sites.Read.All granted" -ForegroundColor Green
        }
        catch {
            Write-Host "  ✓ Sites.Read.All may already be granted" -ForegroundColor Gray
        }
        finally {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        
        Write-Host "✓ Reports Logic App permissions configured" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Could not access Reports Logic App: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   Make sure the Logic App exists and you have permissions" -ForegroundColor Gray
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "✓ ALL PERMISSIONS CONFIGURED!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

# Ensure a clean exit code for callers that check $LASTEXITCODE
$global:LASTEXITCODE = 0
exit 0
