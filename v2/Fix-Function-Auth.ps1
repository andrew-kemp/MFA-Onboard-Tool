# Fix Function App Authentication
# Disables built-in authentication to allow anonymous access

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
    Write-Host "`n=== Fix Function App Authentication ===" -ForegroundColor Cyan
    
    $config = Get-IniContent -Path $configFile
    $functionAppName = $config["Azure"]["FunctionAppName"]
    $resourceGroup = $config["Azure"]["ResourceGroup"]
    $subscriptionId = $config["Tenant"]["SubscriptionId"]
    $tenantId = $config["Tenant"]["TenantId"]
    
    Write-Host "Function App: $functionAppName" -ForegroundColor Gray
    Write-Host "Resource Group: $resourceGroup`n" -ForegroundColor Gray
    
    # Check Azure CLI
    Write-Host "Checking Azure CLI..." -ForegroundColor Yellow
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Host "Not logged in. Running 'az login'..." -ForegroundColor Yellow
        az login --tenant $tenantId
        $account = az account show | ConvertFrom-Json
    }
    
    # Set the correct subscription
    Write-Host "Setting subscription: $subscriptionId" -ForegroundColor Yellow
    az account set --subscription $subscriptionId
    Write-Host "✓ Logged in as: $($account.user.name)`n" -ForegroundColor Green
    
    # Disable built-in authentication
    Write-Host "Disabling built-in authentication..." -ForegroundColor Yellow
    az webapp auth update `
        --resource-group $resourceGroup `
        --name $functionAppName `
        --enabled false 2>&1 | Out-Null
    
    Write-Host "✓ Built-in authentication disabled`n" -ForegroundColor Green
    
    # Update CORS settings
    Write-Host "Configuring CORS..." -ForegroundColor Yellow
    az functionapp cors remove `
        --resource-group $resourceGroup `
        --name $functionAppName `
        --allowed-origins "*" 2>&1 | Out-Null
    
    az functionapp cors add `
        --resource-group $resourceGroup `
        --name $functionAppName `
        --allowed-origins "*" 2>&1 | Out-Null
    
    Write-Host "✓ CORS configured`n" -ForegroundColor Green
    
    Write-Host "✓ Function App authentication fixed!" -ForegroundColor Green
    Write-Host "`nPlease wait 1-2 minutes for changes to propagate, then try uploading again.`n" -ForegroundColor Yellow
}
catch {
    Write-Host "`nERROR: $_" -ForegroundColor Red
    exit 1
}
