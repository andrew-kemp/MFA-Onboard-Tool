# Check and Add Managed Identity Permissions for Logic App
# This script checks if the Logic App has the required Graph API permissions
# and optionally adds them if missing

param(
    [Parameter(Mandatory=$false)]
    [switch]$AddPermissions
)

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

$config = Get-IniContent -Path $configFile
$LogicAppName = $config["LogicApp"]["LogicAppName"]
$subscriptionId = $config["Tenant"]["SubscriptionId"]
$tenantId = $config["Tenant"]["TenantId"]

Write-Host "`n=== Logic App Managed Identity Permission Checker ===" -ForegroundColor Cyan
Write-Host "Logic App: $LogicAppName`n" -ForegroundColor Yellow

# Connect to Azure
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
$azContext = Get-AzContext
if ($null -eq $azContext) {
    Connect-AzAccount -TenantId $tenantId | Out-Null
}
Set-AzContext -SubscriptionId $subscriptionId | Out-Null
Write-Host "✓ Connected to Azure`n" -ForegroundColor Green

# Get Microsoft Graph Service Principal via Azure CLI (avoids Microsoft.Graph module DLL conflicts)
Write-Host "Getting Microsoft Graph Service Principal..." -ForegroundColor Yellow
$graphSpJson = az ad sp show --id 00000003-0000-0000-c000-000000000000 2>$null
if (-not $graphSpJson) {
    Write-Host "✗ Could not find Microsoft Graph Service Principal" -ForegroundColor Red
    exit 1
}
$graphApp = $graphSpJson | ConvertFrom-Json
Write-Host "✓ Found Microsoft Graph`n" -ForegroundColor Green

# Get the Logic App's Managed Identity (Service Principal) via Azure CLI
Write-Host "Looking for Logic App Managed Identity..." -ForegroundColor Yellow
$spListJson = az ad sp list --filter "displayName eq '$LogicAppName'" --query "[0]" 2>$null
if (-not $spListJson -or $spListJson -eq "null") {
    Write-Host "✗ Logic App Managed Identity not found with name: $LogicAppName" -ForegroundColor Red
    Write-Host "Please ensure the Logic App has System Managed Identity enabled.`n" -ForegroundColor Yellow
    exit 1
}
$logicAppIdentity = $spListJson | ConvertFrom-Json

Write-Host "✓ Found Managed Identity" -ForegroundColor Green
Write-Host "  Display Name: $($logicAppIdentity.displayName)" -ForegroundColor Gray
Write-Host "  Object ID: $($logicAppIdentity.id)" -ForegroundColor Gray
Write-Host "  App ID: $($logicAppIdentity.appId)`n" -ForegroundColor Gray

# Define required permissions
$requiredPermissions = @(
    @{
        Name = "Directory.Read.All"
        Description = "Read directory data"
    },
    @{
        Name = "User.Read.All"
        Description = "Read all users' full profiles"
    },
    @{
        Name = "UserAuthenticationMethod.ReadWrite.All"
        Description = "Read and write all users' authentication methods"
    },
    @{
        Name = "GroupMember.ReadWrite.All"
        Description = "Read and write group memberships"
    },
    @{
        Name = "Group.Read.All"
        Description = "Read all groups"
    }
)

# Get current app role assignments for the Logic App via az rest
Write-Host "Checking current permissions..." -ForegroundColor Yellow
$assignmentsJson = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($logicAppIdentity.id)/appRoleAssignments" 2>$null
$currentAssignments = ($assignmentsJson | ConvertFrom-Json).value

# Build a lookup of well-known permission IDs from Graph SP's appRoles
$graphRolesJson = az rest --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($graphApp.id)?`$select=appRoles" 2>$null
$graphRoles = ($graphRolesJson | ConvertFrom-Json).appRoles

Write-Host "`n--- Current Graph API Permissions ---" -ForegroundColor Cyan
$hasAllPermissions = $true
$missingPermissions = @()

foreach ($requiredPerm in $requiredPermissions) {
    $permName = $requiredPerm.Name
    $permDescription = $requiredPerm.Description
    
    # Find the app role in Graph
    $appRole = $graphRoles | Where-Object { $_.value -eq $permName }
    
    if (-not $appRole) {
        Write-Host "⚠ Permission definition not found: $permName" -ForegroundColor Yellow
        continue
    }
    
    # Check if assigned
    $assignment = $currentAssignments | Where-Object { 
        $_.appRoleId -eq $appRole.id -and $_.resourceId -eq $graphApp.id 
    }
    
    if ($assignment) {
        Write-Host "✓ $permName" -ForegroundColor Green
        Write-Host "  $permDescription" -ForegroundColor Gray
    } else {
        Write-Host "✗ $permName (MISSING)" -ForegroundColor Red
        Write-Host "  $permDescription" -ForegroundColor Gray
        $hasAllPermissions = $false
        $missingPermissions += @{
            Name = $permName
            Description = $permDescription
            AppRoleId = $appRole.id
        }
    }
}

Write-Host ""

# Summary
if ($hasAllPermissions) {
    Write-Host "=== RESULT: All required permissions are assigned ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host "=== RESULT: Missing $($missingPermissions.Count) permission(s) ===" -ForegroundColor Red
    
    if ($AddPermissions) {
        Write-Host "`nAdding missing permissions..." -ForegroundColor Yellow
        
        foreach ($missingPerm in $missingPermissions) {
            Write-Host "  Adding $($missingPerm.Name)..." -ForegroundColor Yellow
            
            $body = @{
                principalId = $logicAppIdentity.id
                resourceId  = $graphApp.id
                appRoleId   = $missingPerm.AppRoleId
            } | ConvertTo-Json
            
            $tempFile = [System.IO.Path]::GetTempFileName()
            $body | Set-Content $tempFile -Force
            
            try {
                az rest --method POST `
                    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($logicAppIdentity.id)/appRoleAssignments" `
                    --body "@$tempFile" `
                    --headers "Content-Type=application/json" 2>$null | Out-Null
                Write-Host "  ✓ Added $($missingPerm.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "  ✓ $($missingPerm.Name) may already be granted" -ForegroundColor Gray
            }
            finally {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        Write-Host "`n✓ Permission assignment complete!" -ForegroundColor Green
        Write-Host "⚠ Note: It may take 5-10 minutes for permissions to propagate." -ForegroundColor Yellow
        
    } else {
        Write-Host "`nTo add missing permissions, run:" -ForegroundColor Yellow
        Write-Host "  .\Check-LogicApp-Permissions.ps1 -AddPermissions`n" -ForegroundColor Cyan
    }
}
Write-Host ""
