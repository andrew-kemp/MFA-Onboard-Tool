# Step 03 - Create Azure Resources
# Creates Resource Group, Storage Account, and Function App

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
    
    $content = Get-Content $Path
    $inSection = $false
    $found = $false
    $sectionExists = $false
    $newContent = @()
    
    foreach ($line in $content) {
        if ($line -match "^\[$Section\]") {
            $inSection = $true
            $sectionExists = $true
            $newContent += $line
        }
        elseif ($line -match "^\[.*\]") {
            if ($inSection -and -not $found) {
                $newContent += "$Key=$Value"
                $found = $true
            }
            $inSection = $false
            $newContent += $line
        }
        elseif ($inSection -and $line -match "^$Key=") {
            $newContent += "$Key=$Value"
            $found = $true
        }
        else {
            $newContent += $line
        }
    }
    
    if ($inSection -and -not $found) {
        $newContent += "$Key=$Value"
    }
    
    if (-not $sectionExists) {
        $newContent += ""
        $newContent += "[$Section]"
        $newContent += "$Key=$Value"
    }
    
    $newContent | Set-Content $Path -Force
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
    
    # Ensure INI file exists
    if (-not (Test-Path $configFile)) {
        Write-Host "Creating new configuration file: $configFile" -ForegroundColor Yellow
        "# MFA Onboarding Configuration" | Set-Content $configFile
    }
    
    $config = Get-IniContent -Path $configFile
    
    # Get required values (prompt if missing)
    Write-Host "Checking configuration..." -ForegroundColor Yellow
    
    $tenantId = Get-IniValueOrPrompt -Path $configFile -Section "Tenant" -Key "TenantId" `
        -Prompt "Tenant ID (e.g., contoso.onmicrosoft.com or guid)"
    
    $subscriptionId = Get-IniValueOrPrompt -Path $configFile -Section "Tenant" -Key "SubscriptionId" `
        -Prompt "Azure Subscription ID"
    
    $rgName = Get-IniValueOrPrompt -Path $configFile -Section "Azure" -Key "ResourceGroup" `
        -Prompt "Resource Group name" `
        -Default "rg-mfa-onboarding"
    
    $region = Get-IniValueOrPrompt -Path $configFile -Section "Azure" -Key "Region" `
        -Prompt "Azure region" `
        -Default "uksouth"
    
    Write-Host "✓ Configuration loaded" -ForegroundColor Green
    
    # Connect to Azure
    Write-Host "`nConnecting to Azure..." -ForegroundColor Yellow
    try {
        Connect-AzAccount -TenantId $tenantId -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
        Write-Host "✓ Connected to Azure" -ForegroundColor Green
        Write-Host "  Tenant: $tenantId" -ForegroundColor Gray
        Write-Host "  Subscription: $subscriptionId" -ForegroundColor Gray
    }
    catch {
        Write-Host "ERROR: Failed to connect to Azure: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
    # Create or get Resource Group
    Write-Host "`nChecking Resource Group: $rgName" -ForegroundColor Yellow
    $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
    if ($null -eq $rg) {
        Write-Host "Creating Resource Group..." -ForegroundColor Yellow
        $rg = New-AzResourceGroup -Name $rgName -Location $region
        Write-Host "✓ Resource Group created" -ForegroundColor Green
    }
    else {
        Write-Host "✓ Resource Group exists" -ForegroundColor Green
    }
    
    # Check if names already exist in INI, otherwise generate new ones
    $storageName = $config["Azure"]["StorageAccountName"]
    $functionAppName = $config["Azure"]["FunctionAppName"]
    
    if ([string]::IsNullOrWhiteSpace($storageName) -or [string]::IsNullOrWhiteSpace($functionAppName)) {
        Write-Host "Generating unique resource names..." -ForegroundColor Yellow
        $random = Get-Random -Minimum 100000 -Maximum 999999
        $storageName = "stmfa$random"
        $functionAppName = "func-mfa-enrol-$random"
        
        Set-IniValue -Path $configFile -Section "Azure" -Key "StorageAccountName" -Value $storageName
        Set-IniValue -Path $configFile -Section "Azure" -Key "FunctionAppName" -Value $functionAppName
        Write-Host "✓ Names generated and saved to INI" -ForegroundColor Green
    } else {
        Write-Host "Using existing resource names from INI:" -ForegroundColor Yellow
        Write-Host "  Storage: $storageName" -ForegroundColor Gray
        Write-Host "  Function App: $functionAppName" -ForegroundColor Gray
    }
    
    # Create Storage Account
    Write-Host "`nCreating Storage Account: $storageName" -ForegroundColor Yellow
    $existingStorage = Get-AzStorageAccount -ResourceGroupName $rgName -Name $storageName -ErrorAction SilentlyContinue
    if ($null -eq $existingStorage) {
        $storage = New-AzStorageAccount -ResourceGroupName $rgName -Name $storageName -Location $region -SkuName Standard_LRS -Kind StorageV2
        Write-Host "✓ Storage Account created" -ForegroundColor Green
    } else {
        Write-Host "✓ Storage Account already exists" -ForegroundColor Green
        $storage = $existingStorage
    }
    
    # Create Function App
    Write-Host "`nCreating Function App: $functionAppName" -ForegroundColor Yellow
    
    # Check if Function App already exists
    $existingFunctionApp = Get-AzFunctionApp -ResourceGroupName $rgName -Name $functionAppName -ErrorAction SilentlyContinue
    if ($null -ne $existingFunctionApp) {
        Write-Host "✓ Function App already exists" -ForegroundColor Green
        $functionApp = $existingFunctionApp
    } else {
        Write-Host "This may take 2-3 minutes..." -ForegroundColor Gray
        try {
            $functionApp = New-AzFunctionApp -ResourceGroupName $rgName -Name $functionAppName -Location $region -StorageAccountName $storageName -Runtime PowerShell -RuntimeVersion 7.4 -FunctionsVersion 4 -OSType Windows -ErrorAction Stop
            
            # Verify Function App was created successfully
            if ($null -eq $functionApp) {
                throw "Function App creation returned null"
            }
            
            # Wait a moment and verify it exists
            Start-Sleep -Seconds 10
            $verifyApp = Get-AzFunctionApp -ResourceGroupName $rgName -Name $functionAppName -ErrorAction SilentlyContinue
            if ($null -eq $verifyApp) {
                throw "Function App was not created successfully"
            }
            
            Write-Host "✓ Function App created" -ForegroundColor Green
        }
        catch {
            Write-Host "✗ Function App creation FAILED: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "`nTrying to verify if Function App exists anyway..." -ForegroundColor Yellow
            Start-Sleep -Seconds 15
            $verifyApp = Get-AzFunctionApp -ResourceGroupName $rgName -Name $functionAppName -ErrorAction SilentlyContinue
            
            if ($null -eq $verifyApp) {
                Write-Host "✗ Function App does not exist. Creation failed completely." -ForegroundColor Red
                throw "Function App creation failed and cannot be verified"
            }
            else {
                Write-Host "✓ Function App exists despite timeout. Continuing..." -ForegroundColor Yellow
                $functionApp = $verifyApp
            }
        }
    }
    
    # Enable Managed Identity
    Write-Host "`nEnabling Managed Identity..." -ForegroundColor Yellow
    $identity = Update-AzFunctionApp -ResourceGroupName $rgName -Name $functionAppName -IdentityType SystemAssigned -Force
    $principalId = $identity.IdentityPrincipalId
    
    Write-Host "✓ Managed Identity enabled" -ForegroundColor Green
    Write-Host "  Principal ID: $principalId" -ForegroundColor Gray
    
    Set-IniValue -Path $configFile -Section "Azure" -Key "MFAPrincipalId" -Value $principalId
    
    Write-Host "`n✓ Step 03 completed successfully!" -ForegroundColor Green
    Write-Host "  Storage: $storageName" -ForegroundColor Gray
    Write-Host "  Function App: $functionAppName" -ForegroundColor Gray
    Write-Host "  Principal ID: $principalId" -ForegroundColor Gray
    
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
