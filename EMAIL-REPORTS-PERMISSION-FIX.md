# Email Reports Logic App - Permission Fix

## Problem
The Email Reports Logic App (script 08) was failing with error:
```
WorkflowManagedIdentityNotSpecified - The workflow 'logic-mfa-reports-720355' does not 
have managed identity enabled or the identity has been deleted.
```

## Root Cause
1. Script 08 was trying to grant Graph API permissions using Microsoft.Graph PowerShell module
2. This module has version conflicts (same issue we fixed in Fix-Graph-Permissions.ps1)
3. The permissions weren't being granted properly, or the managed identity wasn't being recognized

## Solution
Centralized all permission management in the **Fix-Graph-Permissions.ps1** script:

### Changes Made

#### 1. **08-Deploy-Email-Reports.ps1** (Lines 454-484)
**Changed from**: Microsoft.Graph PowerShell module (Import-Module, Connect-MgGraph, Get-MgServicePrincipal)  
**Changed to**: Azure CLI REST API (az rest)

```powershell
# OLD CODE (removed):
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Connect-MgGraph -TenantId $config["Tenant"]["TenantId"] -Scopes "Application.Read.All","AppRoleAssignment.ReadWrite.All" -NoWelcome
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $principalId -BodyParameter $body | Out-Null
Disconnect-MgGraph | Out-Null

# NEW CODE (using Azure CLI):
$graphAppId = "00000003-0000-0000-c000-000000000000"
$sitesReadAllId = "332a536c-c7ef-4017-ab91-336970924f0d"
$graphSpId = az ad sp list --filter "appId eq '$graphAppId'" --query "[0].id" -o tsv
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments" --body "@$tempFile" --headers "Content-Type=application/json"
```

#### 2. **Fix-Graph-Permissions.ps1** (Added new section at end)
Added Email Reports Logic App permissions section:

```powershell
# Grant permissions to Email Reports Logic App (if exists)
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Email Reports Logic App Permissions" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$reportsLogicAppName = $config["EmailReports"]["LogicAppName"]

if ([string]::IsNullOrWhiteSpace($reportsLogicAppName)) {
    Write-Host "⚠️  Email Reports Logic App not found in config - skipping" -ForegroundColor Yellow
}
else {
    Write-Host "Reports Logic App: $reportsLogicAppName" -ForegroundColor Gray
    
    # Get Logic App Managed Identity
    $reportsLogicApp = Get-AzResource -ResourceGroupName $resourceGroup -Name $reportsLogicAppName -ResourceType "Microsoft.Logic/workflows"
    
    if ($null -eq $reportsLogicApp.Identity) {
        Write-Host "⚠️  Reports Logic App doesn't have Managed Identity" -ForegroundColor Yellow
    }
    else {
        $reportsAppPrincipalId = $reportsLogicApp.Identity.PrincipalId
        
        # Grant Sites.Read.All permission
        $body = @{
            principalId = $reportsAppPrincipalId
            resourceId = $graphSpId
            appRoleId = "332a536c-c7ef-4017-ab91-336970924f0d"  # Sites.Read.All
        } | ConvertTo-Json
        
        az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$reportsAppPrincipalId/appRoleAssignments" --body "@$tempFile" --headers "Content-Type=application/json"
        
        Write-Host "✓ Sites.Read.All granted" -ForegroundColor Green
    }
}
```

### Permissions Granted
The Email Reports Logic App now gets:
- **Sites.Read.All** - Application permission to read SharePoint sites and lists via Graph API

### How to Apply the Fix

#### If you haven't deployed the Reports Logic App yet:
1. Copy updated files from `C:\ANdyKempDev` to your deployment directory
2. Run: `.\08-Deploy-Email-Reports.ps1`
3. **Authorize Office 365 connection** in Azure Portal (manual step)
4. Run: `.\Fix-Graph-Permissions.ps1` (grants all permissions)

#### If you already deployed and got the error:
1. Copy updated `Fix-Graph-Permissions.ps1` from `C:\ANdyKempDev`
2. Run: `.\Fix-Graph-Permissions.ps1`
3. Wait 2-3 minutes for permissions to propagate
4. Test the Logic App again (Azure Portal > Logic Apps > Run Trigger)

### Configuration File
The Reports Logic App name is stored in `mfa-config.ini`:
```ini
[EmailReports]
LogicAppName = logic-mfa-reports-720355
Recipients = admin@domain.com
Frequency = Day
```

### Manual Steps Still Required
Even with automated permission granting, you **must manually authorize** the Office 365 API connection:

1. Azure Portal → Resource Groups → Your Resource Group
2. Click **Connections** → **office365-reports**
3. Click **Edit API connection**
4. Click **Authorize** → Sign in with admin account
5. Click **Save**

This is required because the Logic App uses Office 365 Outlook connector to send emails, which needs delegated (user) authentication.

### Verification
After running Fix-Graph-Permissions.ps1, verify permissions:

```powershell
# Check if permissions were granted
$reportsLogicAppName = "logic-mfa-reports-720355"  # Your Logic App name
$reportsLogicApp = Get-AzResource -ResourceGroupName "Multi-Factor-Auth-RG" -Name $reportsLogicAppName -ResourceType "Microsoft.Logic/workflows"
$principalId = $reportsLogicApp.Identity.PrincipalId

# List app role assignments
az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments" --query "value[].{Permission:appRoleId, Resource:resourceDisplayName}"
```

Expected output should show:
- **Sites.Read.All** permission assigned to **Microsoft Graph**

### Troubleshooting

**Error: "WorkflowManagedIdentityNotSpecified"**
- **Cause**: Managed identity not enabled or permissions not granted
- **Solution**: Run `.\Fix-Graph-Permissions.ps1`, wait 2-3 minutes

**Error: "The request failed due to a network issue"**
- **Cause**: Office 365 connection not authorized
- **Solution**: Authorize the connection manually in Azure Portal (see Manual Steps above)

**Error: "Forbidden" or "Access denied"**
- **Cause**: Sites.Read.All permission not granted or not propagated
- **Solution**: Wait 5 minutes for Azure AD propagation, then retry

### Architecture Summary
All permission management is now centralized:

```
Fix-Graph-Permissions.ps1
├── Function App Permissions
│   ├── User.Read.All
│   ├── GroupMember.ReadWrite.All
│   └── Sites.ReadWrite.All
├── Upload Portal Permissions
│   ├── User.Read (delegated)
│   └── Sites.Read.All (delegated)
└── Email Reports Logic App Permissions
    └── Sites.Read.All (application)
```

**Benefits**:
- Single script to fix all permission issues
- No PowerShell module version conflicts
- Azure CLI works reliably
- Easy to rerun if permissions get removed
