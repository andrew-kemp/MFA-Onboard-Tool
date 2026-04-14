# Create Technical Summary with Object IDs, Resource IDs, and URLs
# This provides comprehensive troubleshooting information

param(
    [string]$ConfigFile = "$PSScriptRoot\mfa-config.ini",
    [string]$OutputFile = "$PSScriptRoot\logs\TECHNICAL-SUMMARY_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"
)

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

Write-Host "Generating Technical Summary..." -ForegroundColor Cyan

$config = Get-IniContent -Path $ConfigFile

# Get Azure context
try {
    $azContext = Get-AzContext -ErrorAction Stop
    $subscriptionId = $azContext.Subscription.Id
    $tenantId = $config["Tenant"]["TenantId"]
    $resourceGroup = $config["Azure"]["ResourceGroup"]
}
catch {
    Write-Host "Error: Not logged into Azure. Run Connect-AzAccount first." -ForegroundColor Red
    exit 1
}

# Gather resource details
Write-Host "Gathering resource information..." -ForegroundColor Yellow

$functionAppDetails = $null
$storageAccountDetails = $null
$logicAppDetails = $null
$functionAppIdentity = $null
$logicAppIdentity = $null

try {
    if ($config["Azure"]["FunctionAppName"]) {
        $functionAppDetails = Get-AzWebApp -ResourceGroupName $resourceGroup -Name $config["Azure"]["FunctionAppName"] -ErrorAction SilentlyContinue
        if ($functionAppDetails) {
            $functionAppIdentity = $functionAppDetails.Identity.PrincipalId
        }
    }
    
    if ($config["Azure"]["StorageAccountName"]) {
        $storageAccountDetails = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $config["Azure"]["StorageAccountName"] -ErrorAction SilentlyContinue
    }
    
    if ($config["LogicApp"]["LogicAppName"]) {
        $logicAppDetails = Get-AzLogicApp -ResourceGroupName $resourceGroup -Name $config["LogicApp"]["LogicAppName"] -ErrorAction SilentlyContinue
        if ($logicAppDetails) {
            $logicAppIdentity = $logicAppDetails.Identity.PrincipalId
        }
    }
}
catch {
    Write-Host "Warning: Could not retrieve some resource details" -ForegroundColor Yellow
}

# Get API connections
$apiConnections = @()
try {
    $connectionsJson = az resource list --resource-group $resourceGroup --resource-type "Microsoft.Web/connections" --query "[].{name:name, id:id, location:location}" -o json 2>$null
    if ($connectionsJson) {
        $apiConnections = $connectionsJson | ConvertFrom-Json
    }
}
catch {
    Write-Host "Warning: Could not retrieve API connections" -ForegroundColor Yellow
}

# Find most recent Logic App JSON
$logicAppJson = ""
$logicAppJsonFiles = Get-ChildItem -Path "$PSScriptRoot\logs\LogicApp-Deployed_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($logicAppJsonFiles) {
    $logicAppJson = $logicAppJsonFiles[0].FullName
}

# Build technical summary
$summary = @"
================================================================================
  MFA ONBOARDING - TECHNICAL SUMMARY FOR TROUBLESHOOTING
================================================================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Deployed By: $($azContext.Account.Id)

This document contains all Object IDs, Resource IDs, URLs, and technical 
details needed for troubleshooting and automation.

================================================================================
AZURE TENANT & SUBSCRIPTION
================================================================================
Tenant ID           : $tenantId
Tenant Domain       : $($azContext.Tenant.Directory)
Subscription ID     : $subscriptionId
Subscription Name   : $($azContext.Subscription.Name)
Resource Group      : $resourceGroup
Region              : $($config["Azure"]["Region"])

Azure Portal - Resource Group:
  https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourcegroups/$resourceGroup/overview

================================================================================
SHAREPOINT ONLINE
================================================================================
Site URL            : $($config["SharePoint"]["SiteUrl"])
Site Title          : $($config["SharePoint"]["SiteTitle"])
List Title          : $($config["SharePoint"]["ListTitle"])
List ID (GUID)      : $($config["SharePoint"]["ListId"])

App Registration:
  Name              : $($config["SharePoint"]["AppRegName"])
  Client ID         : $($config["SharePoint"]["ClientId"])
  Object ID         : $($config["SharePoint"]["AppObjectId"])
  Certificate Path  : $($config["SharePoint"]["CertificatePath"])
  Cert Thumbprint   : $($config["SharePoint"]["CertificateThumbprint"])

Direct URLs:
  Site              : $($config["SharePoint"]["SiteUrl"])
  List              : $($config["SharePoint"]["SiteUrl"])/Lists/$($config["SharePoint"]["ListTitle"] -replace ' ','%20')
  List Settings     : $($config["SharePoint"]["SiteUrl"])/_layouts/15/listedit.aspx?List={$($config["SharePoint"]["ListId"])}

SharePoint REST API:
  List Items        : $($config["SharePoint"]["SiteUrl"])/_api/web/lists(guid'$($config["SharePoint"]["ListId"])')/items

Azure AD App Registration:
  https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$($config["SharePoint"]["ClientId"])/isMSAApp~/false

================================================================================
SECURITY GROUP
================================================================================
Group Name          : $($config["Security"]["MFAGroupName"])
Group ID (Object ID): $($config["Security"]["MFAGroupId"])
Description         : Users enrolled in MFA onboarding process

Azure Portal:
  https://portal.azure.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/$($config["Security"]["MFAGroupId"])

Microsoft Graph API:
  GET https://graph.microsoft.com/v1.0/groups/$($config["Security"]["MFAGroupId"])
  GET https://graph.microsoft.com/v1.0/groups/$($config["Security"]["MFAGroupId"])/members

================================================================================
AZURE FUNCTION APP
================================================================================
Function App Name   : $($config["Azure"]["FunctionAppName"])
Runtime Stack       : PowerShell 7.4
Hosting Plan        : Consumption (Y1)
State               : $($functionAppDetails.State)
"@

if ($functionAppDetails) {
    $summary += @"

Azure Resource ID:
  $($functionAppDetails.Id)

Managed Identity (System-Assigned):
  Principal ID      : $functionAppIdentity
  Type              : SystemAssigned
  
  Use this Principal ID to grant permissions in Azure AD and other resources.
  
Default Hostname    : $($functionAppDetails.DefaultHostName)

"@
}

$summary += @"
Function Endpoints:
  Track MFA Click   : https://$($config["Azure"]["FunctionAppName"]).azurewebsites.net/api/track-mfa-click
                      Parameters: ?user={upn}
                      Example: ?user=john@contoso.com
  
  Upload Users      : https://$($config["Azure"]["FunctionAppName"]).azurewebsites.net/api/upload-users
                      Method: POST
                      Body: CSV file with UPN column

Azure Portal:
  Overview          : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$($config["Azure"]["FunctionAppName"])/appServices
  Functions         : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$($config["Azure"]["FunctionAppName"])/functions
  Log Stream        : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$($config["Azure"]["FunctionAppName"])/logStream
  App Insights      : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$($config["Azure"]["FunctionAppName"])/appInsights

Configuration:
  Source Code       : $(Split-Path $ConfigFile -Parent)\function-code\
  Deployment        : Via ZIP deployment from script 05

================================================================================
AZURE STORAGE ACCOUNT
================================================================================
Storage Account Name: $($config["Azure"]["StorageAccountName"])
SKU                 : Standard_LRS
Kind                : StorageV2
"@

if ($storageAccountDetails) {
    $summary += @"

Azure Resource ID:
  $($storageAccountDetails.Id)

Primary Endpoints:
  Blob              : $($storageAccountDetails.PrimaryEndpoints.Blob)
  Queue             : $($storageAccountDetails.PrimaryEndpoints.Queue)
  Table             : $($storageAccountDetails.PrimaryEndpoints.Table)
  File              : $($storageAccountDetails.PrimaryEndpoints.File)
  Web (Static Site) : $($storageAccountDetails.PrimaryEndpoints.Web)

"@
}

$summary += @"
Static Website:
  Enabled           : Yes
  Index Document    : index.html
  Upload Portal URL : https://$($config["Azure"]["StorageAccountName"]).z33.web.core.windows.net/upload-portal.html

Azure Portal:
  Overview          : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$($config["Azure"]["StorageAccountName"])/overview
  Static Website    : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$($config["Azure"]["StorageAccountName"])/staticwebsite
  Containers        : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$($config["Azure"]["StorageAccountName"])/containers

================================================================================
AZURE LOGIC APP
================================================================================
Logic App Name      : $($config["LogicApp"]["LogicAppName"])
Type                : Consumption
Trigger             : Recurrence (Every 12 hours)
"@

if ($logicAppDetails) {
    $summary += @"
State               : $($logicAppDetails.State)
Location            : $($logicAppDetails.Location)

Azure Resource ID:
  $($logicAppDetails.Id)

"@
    if ($logicAppIdentity) {
        $summary += @"
Managed Identity (System-Assigned):
  Principal ID      : $logicAppIdentity
  Type              : SystemAssigned

"@
    }
}

$summary += @"
Workflow:
  1. Trigger: Runs every 12 hours
  2. Get pending users from SharePoint list
  3. For each user, send invitation email via Office 365
  4. Update SharePoint list item

Logic App Definition:
  JSON File         : $logicAppJson

Azure Portal:
  Designer          : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$($config["LogicApp"]["LogicAppName"])/logicApp
  Runs History      : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$($config["LogicApp"]["LogicAppName"])/runs
  Code View         : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$($config["LogicApp"]["LogicAppName"])/codeView

Manual Trigger:
  Click "Run Trigger" button in Azure Portal Logic App Overview

================================================================================
API CONNECTIONS
================================================================================
"@

if ($apiConnections.Count -gt 0) {
    foreach ($conn in $apiConnections) {
        $summary += @"

Connection: $($conn.name)
  Resource ID       : $($conn.id)
  Location          : $($conn.location)
  Portal Link       : https://portal.azure.com/#@$tenantId/resource$($conn.id)/overview

"@
    }
    
    $summary += @"

Authorization Status:
  To check authorization status, run:
  az resource show --ids "$($apiConnections[0].id)" --query "properties.statuses[0].status"

To Authorize:
  1. Go to: https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/overview
  2. Filter by type: Microsoft.Web/connections
  3. Click each connection > Edit API connection > Authorize > Sign in > Save

"@
}
else {
    $summary += @"
No API connections found. These should be created by script 06.

Expected connections:
  - sharepointonline
  - office365
  - azuread

"@
}

$summary += @"
================================================================================
EMAIL CONFIGURATION
================================================================================
Shared Mailbox      : $($config["Email"]["NoReplyMailbox"])
Display Name        : $($config["Email"]["MailboxName"])
Delegate            : $($config["Email"]["MailboxDelegate"])

Permissions:
  Delegate must have "Send As" permission on shared mailbox

Microsoft 365 Admin Center:
  Mailboxes         : https://admin.microsoft.com/AdminPortal/Home#/mailboxes
  Search for        : $($config["Email"]["NoReplyMailbox"])

Exchange Online PowerShell:
  Get-Mailbox "$($config["Email"]["NoReplyMailbox"])"
  Get-RecipientPermission "$($config["Email"]["NoReplyMailbox"])"

================================================================================
UPLOAD PORTAL
================================================================================
Portal URL          : https://$($config["Azure"]["StorageAccountName"]).z33.web.core.windows.net/upload-portal.html

App Registration:
  Name              : $($config["UploadPortal"]["AppRegName"])
  Client ID         : $($config["UploadPortal"]["ClientId"])
  Object ID         : $($config["UploadPortal"]["AppObjectId"])

Azure AD Configuration:
  App Registration  : https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/$($config["UploadPortal"]["ClientId"])/isMSAApp~/false
  
Redirect URIs:
  https://$($config["Azure"]["StorageAccountName"]).z33.web.core.windows.net/upload-portal.html

API Permissions:
  Microsoft Graph   : User.Read (Delegated)

Authentication Flow:
  1. User navigates to portal
  2. MSAL.js redirects to Azure AD login
  3. User authenticates with M365 account
  4. Token issued for upload-users Function App endpoint
  5. CSV or manual entry submitted to Function App

================================================================================
FULL RESOURCE IDS (For Azure CLI/PowerShell/ARM Templates)
================================================================================

Resource Group:
  /subscriptions/$subscriptionId/resourceGroups/$resourceGroup

Function App:
  /subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$($config["Azure"]["FunctionAppName"])

Storage Account:
  /subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Storage/storageAccounts/$($config["Azure"]["StorageAccountName"])

Logic App:
  /subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$($config["LogicApp"]["LogicAppName"])

================================================================================
AZURE AD OBJECT IDS
================================================================================

SharePoint App Registration:
  Client ID         : $($config["SharePoint"]["ClientId"])
  Object ID         : $($config["SharePoint"]["AppObjectId"])

Upload Portal App Registration:
  Client ID         : $($config["UploadPortal"]["ClientId"])
  Object ID         : $($config["UploadPortal"]["AppObjectId"])

Security Group:
  Group ID          : $($config["Security"]["MFAGroupId"])

Function App Managed Identity:
  Principal ID      : $functionAppIdentity

Logic App Managed Identity:
  Principal ID      : $logicAppIdentity

================================================================================
COMMON TROUBLESHOOTING COMMANDS
================================================================================

Check Function App Status:
  az functionapp show --name "$($config["Azure"]["FunctionAppName"])" --resource-group "$resourceGroup"

View Function App Logs:
  az webapp log tail --name "$($config["Azure"]["FunctionAppName"])" --resource-group "$resourceGroup"

Check Logic App Runs:
  az logic workflow show --name "$($config["LogicApp"]["LogicAppName"])" --resource-group "$resourceGroup"

Check API Connection Authorization:
  az resource show --ids "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/connections/sharepointonline"

Query SharePoint List (Graph API):
  Invoke-RestMethod -Method Get -Uri "$($config["SharePoint"]["SiteUrl"])/_api/web/lists(guid'$($config["SharePoint"]["ListId"])')/items" -Headers @{Accept="application/json"}

Check Group Members:
  az ad group member list --group "$($config["Security"]["MFAGroupId"])"

Test Function App Endpoint:
  Invoke-WebRequest -Uri "https://$($config["Azure"]["FunctionAppName"]).azurewebsites.net/api/track-mfa-click?user=test@example.com"

================================================================================
BACKUP & DISASTER RECOVERY
================================================================================

Critical Files to Backup:
  1. $ConfigFile
  2. $(Split-Path $ConfigFile -Parent)\cert-output\
  3. $(Split-Path $ConfigFile -Parent)\logs\
  4. $logicAppJson

Export App Registrations:
  SharePoint App    : az ad app show --id $($config["SharePoint"]["ClientId"])
  Upload Portal App : az ad app show --id $($config["UploadPortal"]["ClientId"])

Export Logic App Definition:
  az logic workflow show --name "$($config["LogicApp"]["LogicAppName"])" --resource-group "$resourceGroup" > logic-app-backup.json

================================================================================
MONITORING & DIAGNOSTICS
================================================================================

Application Insights:
  Function App      : https://portal.azure.com/#@$tenantId/resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Web/sites/$($config["Azure"]["FunctionAppName"])/appInsights

Log Analytics Queries:
  Function Invocations:
    requests | where cloud_RoleName == "$($config["Azure"]["FunctionAppName"])"
  
  Function Errors:
    exceptions | where cloud_RoleName == "$($config["Azure"]["FunctionAppName"])"

Logic App Diagnostics:
  Enable diagnostic settings to send logs to Log Analytics workspace

SharePoint List Monitoring:
  Monitor list views and modifications via SharePoint audit logs

================================================================================
SECURITY NOTES
================================================================================

Certificates:
  - SharePoint certificate expires: [Check certificate expiry date]
  - Renew certificate before expiry and update app registration

Managed Identities:
  - Function App and Logic App use system-assigned managed identities
  - No passwords or secrets to manage
  - Permissions granted via Azure RBAC and Microsoft Graph

API Permissions:
  Function App Managed Identity needs:
    - Group.ReadWrite.All (Microsoft Graph)
    - SharePoint Site permissions
  
  Logic App connections require:
    - User authentication for API connections
    - Re-authorize if password changes

Conditional Access:
  - Consider excluding service accounts from MFA requirements
  - Test policies with pilot users before full deployment

================================================================================
ADDITIONAL RESOURCES
================================================================================

Source Code Location:
  $(Split-Path $ConfigFile -Parent)

Deployment Scripts:
  Part 1: $(Split-Path $ConfigFile -Parent)\Run-Part1-Setup-Enhanced.ps1
  Part 2: $(Split-Path $ConfigFile -Parent)\Run-Part2-Deploy-Enhanced.ps1

Documentation:
  README: $(Split-Path $ConfigFile -Parent)\README.md
  Enhanced Scripts: $(Split-Path $ConfigFile -Parent)\ENHANCED-SCRIPTS-README.md

================================================================================
END OF TECHNICAL SUMMARY
================================================================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
File: $OutputFile
"@

# Save to file
$summary | Out-File -FilePath $OutputFile -Encoding UTF8

Write-Host "`n$summary`n" -ForegroundColor Gray
Write-Host "Technical summary saved to:" -ForegroundColor Green
Write-Host "  $OutputFile`n" -ForegroundColor Cyan

# Return file path
return $OutputFile
