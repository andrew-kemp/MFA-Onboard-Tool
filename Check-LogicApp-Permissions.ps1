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

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow

# Ensure clean session
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

# Import required modules
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Applications -ErrorAction Stop

Connect-MgGraph -TenantId $tenantId -Scopes "Directory.Read.All","Application.Read.All","AppRoleAssignment.ReadWrite.All" -NoWelcome

# Verify connection
$context = Get-MgContext
if (-not $context) {
    Write-Host "✗ Failed to establish Graph connection" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green
Write-Host "  Account: $($context.Account)" -ForegroundColor Gray
Write-Host ""

# Get the Logic App's Managed Identity (Service Principal)
Write-Host "Looking for Logic App Managed Identity..." -ForegroundColor Yellow
try {
    $logicAppIdentity = Get-MgServicePrincipal -Filter "displayName eq '$LogicAppName'" -ErrorAction Stop
    
    if (-not $logicAppIdentity) {
        Write-Host "✗ Logic App Managed Identity not found with name: $LogicAppName" -ForegroundColor Red
        Write-Host "Please ensure the Logic App has System Managed Identity enabled.`n" -ForegroundColor Yellow
        Disconnect-MgGraph | Out-Null
        exit 1
    }
    
    Write-Host "✓ Found Managed Identity" -ForegroundColor Green
    Write-Host "  Display Name: $($logicAppIdentity.DisplayName)" -ForegroundColor Gray
    Write-Host "  Object ID: $($logicAppIdentity.Id)" -ForegroundColor Gray
    Write-Host "  App ID: $($logicAppIdentity.AppId)`n" -ForegroundColor Gray
} catch {
    Write-Host "✗ Error finding Logic App Managed Identity" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    exit 1
}

# Get Microsoft Graph Service Principal
Write-Host "Getting Microsoft Graph Service Principal..." -ForegroundColor Yellow
try {
    $graphApp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
    Write-Host "✓ Found Microsoft Graph`n" -ForegroundColor Green
} catch {
    Write-Host "✗ Error finding Microsoft Graph Service Principal" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    exit 1
}

# Define required permissions
$requiredPermissions = @(
    @{
        Name = "User.Read.All"
        Description = "Read all users' full profiles"
    },
    @{
        Name = "UserAuthenticationMethod.ReadWrite.All"
        Description = "Read and write all users' authentication methods"
    },
    @{
        Name = "GroupMember.Read.All"
        Description = "Read group memberships"
    }
)

# Get current app role assignments for the Logic App
Write-Host "Checking current permissions..." -ForegroundColor Yellow
$currentAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $logicAppIdentity.Id -All

Write-Host "`n--- Current Graph API Permissions ---" -ForegroundColor Cyan
$hasAllPermissions = $true
$missingPermissions = @()

foreach ($requiredPerm in $requiredPermissions) {
    $permName = $requiredPerm.Name
    $permDescription = $requiredPerm.Description
    
    # Find the app role in Graph
    $appRole = $graphApp.AppRoles | Where-Object { $_.Value -eq $permName }
    
    if (-not $appRole) {
        Write-Host "⚠ Permission definition not found: $permName" -ForegroundColor Yellow
        continue
    }
    
    # Check if assigned
    $assignment = $currentAssignments | Where-Object { 
        $_.AppRoleId -eq $appRole.Id -and $_.ResourceId -eq $graphApp.Id 
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
            AppRole = $appRole
        }
    }
}

Write-Host ""

# Summary
if ($hasAllPermissions) {
    Write-Host "=== RESULT: All required permissions are assigned ===" -ForegroundColor Green
    Disconnect-MgGraph | Out-Null
    exit 0
} else {
    Write-Host "=== RESULT: Missing $($missingPermissions.Count) permission(s) ===" -ForegroundColor Red
    
    if ($AddPermissions) {
        Write-Host "`nAdding missing permissions..." -ForegroundColor Yellow
        
        foreach ($missingPerm in $missingPermissions) {
            try {
                Write-Host "  Adding $($missingPerm.Name)..." -ForegroundColor Yellow
                
                New-MgServicePrincipalAppRoleAssignment `
                    -ServicePrincipalId $logicAppIdentity.Id `
                    -PrincipalId $logicAppIdentity.Id `
                    -ResourceId $graphApp.Id `
                    -AppRoleId $missingPerm.AppRole.Id `
                    -ErrorAction Stop | Out-Null
                
                Write-Host "  ✓ Added $($missingPerm.Name)" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed to add $($missingPerm.Name)" -ForegroundColor Red
                Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
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
