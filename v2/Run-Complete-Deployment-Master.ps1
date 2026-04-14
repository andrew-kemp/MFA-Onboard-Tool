# Master Script - COMPLETE DEPLOYMENT
# Runs EVERYTHING: Steps 01-08 + All Fix/Permission Scripts + Generates Final Report
# This is the ONE-SHOT complete deployment
# SUPPORTS RESUME: Can restart from a specific step using -StartFromStep parameter

param(
    [int]$StartFromStep = 1,  # Which step to start from (1-12)
    [switch]$Resume           # Automatically resume from last completed step
)

# Check PowerShell 7 requirement
if (-not ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7)) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "ERROR: PowerShell 7+ Required" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    Write-Host "This script must be run in PowerShell 7+ (pwsh.exe), not Windows PowerShell." -ForegroundColor Yellow
    Write-Host "`nTo install PowerShell 7, run this command in an elevated PowerShell window:" -ForegroundColor Cyan
    Write-Host "`nwinget install --id Microsoft.Powershell --source winget" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "`nAlternatively, download from: https://aka.ms/powershell-release?tag=stable" -ForegroundColor Gray
    Write-Host "`nAfter installation, open PowerShell 7 and re-run this script.`n" -ForegroundColor Yellow
    exit 1
}

$ErrorActionPreference = "Continue"

# Import common functions
. "$PSScriptRoot\Common-Functions.ps1"

# Initialize logging
$logFile = Initialize-Logging -LogPrefix "Complete-Deployment"
$script:StartTime = Get-Date

# State file to track completed steps
$stateFile = Join-Path $PSScriptRoot "logs\deployment-state.json"

# Load previous state if resuming
if ($Resume -and (Test-Path $stateFile)) {
    $state = Get-Content $stateFile | ConvertFrom-Json
    $StartFromStep = $state.LastCompletedStep + 1
    Write-Host "📋 Resuming from Step $StartFromStep..." -ForegroundColor Cyan
}

# Function to save state
function Save-DeploymentState {
    param([int]$CompletedStep)
    
    $stateDir = Split-Path $stateFile -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    
    @{
        LastCompletedStep = $CompletedStep
        LastUpdated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Set-Content $stateFile
    
    Write-Log "State saved: Completed step $CompletedStep" -Level INFO
}

# Function to check Azure login
function Test-AzureLogin {
    param([string]$RequiredTenantId)
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            return $false
        }
        if ($RequiredTenantId -and $context.Tenant.Id -ne $RequiredTenantId) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

# Read tenant ID from config
$configFile = Join-Path $PSScriptRoot "mfa-config.ini"
function Get-IniValue {
    param([string]$Path, [string]$Section, [string]$Key)
    $content = Get-Content $Path
    $inSection = $false
    foreach ($line in $content) {
        if ($line -match "^\[$Section\]") { $inSection = $true }
        elseif ($line -match "^\[.*\]") { $inSection = $false }
        elseif ($inSection -and $line -match "^$Key\s*=\s*(.*)$") {
            return $matches[1].Trim()
        }
    }
    return $null
}

$tenantId = Get-IniValue -Path $configFile -Section "Tenant" -Key "TenantId"

Write-Host "\n" -NoNewline
Write-Host "╔" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║" -ForegroundColor Cyan
Write-Host "  MFA ONBOARDING - COMPLETE END-TO-END DEPLOYMENT" -ForegroundColor Cyan
Write-Host "║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Log "Complete deployment started" -Level INFO

# Display deployment steps with status indicators
function Show-StepStatus {
    param([int]$StepNum, [string]$StepName, [int]$StartFrom)
    
    if ($StepNum -lt $StartFrom) {
        Write-Host "  ✓ $StepNum - $StepName" -ForegroundColor Green
    } elseif ($StepNum -eq $StartFrom) {
        Write-Host "  ▶ $StepNum - $StepName (STARTING HERE)" -ForegroundColor Yellow
    } else {
        Write-Host "  ○ $StepNum - $StepName" -ForegroundColor Gray
    }
}

Write-Host "This master script will execute deployment steps:" -ForegroundColor Yellow
if ($StartFromStep -gt 1) {
    Write-Host "  (Resuming from Step $StartFromStep - previous steps shown as completed)`n" -ForegroundColor Cyan
} else {
    Write-Host "  (Running complete deployment from the beginning)`n" -ForegroundColor Cyan
}

Write-Host "`n📋 PART 1 - Prerequisites & Setup:" -ForegroundColor Cyan
Show-StepStatus 1 "Install Prerequisites" $StartFromStep
Show-StepStatus 2 "Provision SharePoint" $StartFromStep
Show-StepStatus 3 "Create Shared Mailbox" $StartFromStep

Write-Host "`n📋 PART 2 - Azure & Deployment:" -ForegroundColor Cyan
Show-StepStatus 4 "Create Azure Resources" $StartFromStep
Show-StepStatus 5 "Configure Function App" $StartFromStep
Show-StepStatus 6 "Deploy Logic App (Invitations)" $StartFromStep
Show-StepStatus 7 "Deploy Upload Portal" $StartFromStep
Show-StepStatus 8 "Deploy Email Reports" $StartFromStep

Write-Host "`n🔧 Post-Deployment Fixes & Permissions:" -ForegroundColor Cyan
Show-StepStatus 9 "Function Authentication" $StartFromStep
Show-StepStatus 10 "Graph Permissions" $StartFromStep
Show-StepStatus 11 "Logic App Permissions" $StartFromStep

Write-Host "`n📊 Final Report:" -ForegroundColor Cyan
Show-StepStatus 12 "Generate Interactive HTML Report" $StartFromStep

Write-Host "`n📁 Log file: $logFile" -ForegroundColor Gray
Write-Host "📁 State file: $stateFile`n" -ForegroundColor Gray

if ($StartFromStep -eq 1) {
    $confirmation = Read-Host "⚠️  This will run the complete deployment (~30 minutes). Continue? (Y/N)"
} else {
    $confirmation = Read-Host "⚠️  Resume deployment from Step $StartFromStep? (Y/N)"
}
if ($confirmation -notmatch '^[Yy]') {
    Write-Log "Deployment cancelled by user" -Level WARNING
    Write-Host "`nCancelled by user." -ForegroundColor Yellow
    exit 0
}

$stepResults = @{}

# ============================================================================
# PART 1 - Prerequisites & Setup
# ============================================================================

Write-Host "`n$('='*70)" -ForegroundColor Magenta
Write-Host "PART 1 - PREREQUISITES & SETUP" -ForegroundColor Magenta
Write-Host "$('='*70)`n" -ForegroundColor Magenta

# Step 01 - Install Prerequisites
if ($StartFromStep -le 1) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 01 - INSTALL PREREQUISITES" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Step 01: Install Prerequisites"] = Invoke-WithRetry -Critical -StepName "Install Prerequisites" -ScriptBlock {
        & "$PSScriptRoot\01-Install-Prerequisites.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 01: Install Prerequisites"]) {
        Save-DeploymentState -CompletedStep 1
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 01 - Install Prerequisites (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 01: Install Prerequisites"] = $true
}

# Step 02 - Provision SharePoint
if ($StartFromStep -le 2) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 02 - PROVISION SHAREPOINT" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Step 02: Provision SharePoint"] = Invoke-WithRetry -Critical -StepName "Provision SharePoint" -ScriptBlock {
        & "$PSScriptRoot\02-Provision-SharePoint.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 02: Provision SharePoint"]) {
        Save-DeploymentState -CompletedStep 2
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 02 - Provision SharePoint (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 02: Provision SharePoint"] = $true
}

# Step 03 - Create Shared Mailbox
if ($StartFromStep -le 3) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 03 - CREATE SHARED MAILBOX" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Step 03: Create Shared Mailbox"] = Invoke-WithRetry -Critical -StepName "Create Shared Mailbox" -ScriptBlock {
        & "$PSScriptRoot\03-Create-Shared-Mailbox.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 03: Create Shared Mailbox"]) {
        Save-DeploymentState -CompletedStep 3
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 03 - Create Shared Mailbox (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 03: Create Shared Mailbox"] = $true
}

# ============================================================================
# PART 2 - Azure & Deployment
# ============================================================================

Write-Host "`n$('='*70)" -ForegroundColor Magenta
Write-Host "PART 2 - AZURE RESOURCES & DEPLOYMENT" -ForegroundColor Magenta
Write-Host "$('='*70)`n" -ForegroundColor Magenta

# Step 04 - Azure Resources
if ($StartFromStep -le 4) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 04 - CREATE AZURE RESOURCES" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Step 04: Azure Resources"] = Invoke-WithRetry -Critical -StepName "Azure Resources Creation" -ScriptBlock {
        & "$PSScriptRoot\04-Create-Azure-Resources.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 04: Azure Resources"]) {
        Save-DeploymentState -CompletedStep 4
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 04 - Create Azure Resources (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 04: Azure Resources"] = $true
}

# Step 05 - Function App
if ($StartFromStep -le 5) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 05 - CONFIGURE FUNCTION APP" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Step 05: Function App Configuration"] = Invoke-WithRetry -Critical -StepName "Function App Configuration" -ScriptBlock {
        & "$PSScriptRoot\05-Configure-Function-App.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 05: Function App Configuration"]) {
        Save-DeploymentState -CompletedStep 5
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 05 - Configure Function App (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 05: Function App Configuration"] = $true
}

# Step 06 - Logic App
if ($StartFromStep -le 6) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 06 - DEPLOY LOGIC APP (INVITATIONS)" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Step 06: Logic App Deployment"] = Invoke-WithRetry -StepName "Logic App Deployment" -ScriptBlock {
        & "$PSScriptRoot\06-Deploy-Logic-App.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 06: Logic App Deployment"]) {
        Save-DeploymentState -CompletedStep 6
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 06 - Deploy Logic App (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 06: Logic App Deployment"] = $true
}

# Step 07 - Upload Portal
if ($StartFromStep -le 7) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 07 - DEPLOY UPLOAD PORTAL" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta
    
    # Check Azure PowerShell login before Step 07
    Write-Host "🔐 Checking Azure authentication..." -ForegroundColor Cyan
    if (-not (Test-AzureLogin -RequiredTenantId $tenantId)) {
        Write-Host "⚠️  Azure PowerShell login required for tenant: $tenantId" -ForegroundColor Yellow
        Write-Host "Initiating interactive login..." -ForegroundColor Cyan
        
        try {
            Connect-AzAccount -TenantId $tenantId -ErrorAction Stop | Out-Null
            Write-Host "✓ Azure PowerShell authentication successful" -ForegroundColor Green
        }
        catch {
            Write-Host "✗ Azure PowerShell login failed: $_" -ForegroundColor Red
            Write-Log "Azure PowerShell login failed before Step 07: $_" -Level ERROR
            throw "Azure authentication required. Please run: Connect-AzAccount -TenantId $tenantId"
        }
    } else {
        Write-Host "✓ Already authenticated to Azure PowerShell (Tenant: $tenantId)" -ForegroundColor Green
    }
    
    # Also check Azure CLI login
    Write-Host "🔐 Checking Azure CLI authentication..." -ForegroundColor Cyan
    try {
        $azAccount = az account show 2>&1 | ConvertFrom-Json
        if ($azAccount.tenantId -ne $tenantId) {
            Write-Host "⚠️  Azure CLI login required for correct tenant" -ForegroundColor Yellow
            az login --tenant $tenantId --only-show-errors
        }
        Write-Host "✓ Azure CLI authenticated (Tenant: $tenantId)" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Azure CLI login required" -ForegroundColor Yellow
        az login --tenant $tenantId --only-show-errors
        Write-Host "✓ Azure CLI authentication successful" -ForegroundColor Green
    }

    $stepResults["Step 07: Upload Portal Deployment"] = Invoke-WithRetry -StepName "Upload Portal Deployment" -ScriptBlock {
        & "$PSScriptRoot\07-Deploy-Upload-Portal1.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 07: Upload Portal Deployment"]) {
        Save-DeploymentState -CompletedStep 7
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 07 - Deploy Upload Portal (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 07: Upload Portal Deployment"] = $true
}

# Step 08 - Email Reports
if ($StartFromStep -le 8) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "STEP 08 - DEPLOY EMAIL REPORTS" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Step 08: Email Reports Setup"] = Invoke-WithRetry -StepName "Email Reports Setup" -ScriptBlock {
        & "$PSScriptRoot\08-Deploy-Email-Reports.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Step 08: Email Reports Setup"]) {
        Save-DeploymentState -CompletedStep 8
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Step 08 - Deploy Email Reports (already completed)" -ForegroundColor DarkGreen
    $stepResults["Step 08: Email Reports Setup"] = $true
}

# ============================================================================
# Post-Deployment Fixes & Permissions
# ============================================================================

Write-Host "`n$('='*70)" -ForegroundColor Magenta
Write-Host "POST-DEPLOYMENT FIXES & PERMISSIONS" -ForegroundColor Magenta
Write-Host "$('='*70)`n" -ForegroundColor Magenta

# Fix - Function Authentication (Step 9)
if ($StartFromStep -le 9) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "FIX - FUNCTION AUTHENTICATION" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Fix: Function Authentication"] = Invoke-WithRetry -StepName "Function Authentication Setup" -ScriptBlock {
        & "$PSScriptRoot\Fix-Function-Auth.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Fix: Function Authentication"]) {
        Save-DeploymentState -CompletedStep 9
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Fix - Function Authentication (already completed)" -ForegroundColor DarkGreen
    $stepResults["Fix: Function Authentication"] = $true
}

# Fix - Graph Permissions (Step 10)
if ($StartFromStep -le 10) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "FIX - GRAPH PERMISSIONS" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Fix: Graph Permissions"] = Invoke-WithRetry -StepName "Graph Permissions Setup" -ScriptBlock {
        & "$PSScriptRoot\Fix-Graph-Permissions.ps1"
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Fix: Graph Permissions"]) {
        Save-DeploymentState -CompletedStep 10
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Fix - Graph Permissions (already completed)" -ForegroundColor DarkGreen
    $stepResults["Fix: Graph Permissions"] = $true
}

# Fix - Logic App Permissions (Step 11)
if ($StartFromStep -le 11) {
    Write-Host "`n$('-'*70)" -ForegroundColor Magenta
    Write-Host "FIX - LOGIC APP PERMISSIONS" -ForegroundColor Magenta
    Write-Host "$('-'*70)`n" -ForegroundColor Magenta

    $stepResults["Fix: Logic App Permissions"] = Invoke-WithRetry -StepName "Logic App Permissions Setup" -ScriptBlock {
        & "$PSScriptRoot\Check-LogicApp-Permissions.ps1" -AddPermissions
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            throw "Script exited with code $LASTEXITCODE"
        }
    }
    
    if ($stepResults["Fix: Logic App Permissions"]) {
        Save-DeploymentState -CompletedStep 11
    }
    Start-Sleep -Seconds 3
} else {
    Write-Host "`n[SKIPPED] Fix - Logic App Permissions (already completed)" -ForegroundColor DarkGreen
    $stepResults["Fix: Logic App Permissions"] = $true
}

# ============================================================================
# Generate Final Report
# ============================================================================

# Generate Final Report (Step 12)
if ($StartFromStep -le 12) {
    Write-Host "`n$('='*70)" -ForegroundColor Cyan
    Write-Host "GENERATING FINAL DEPLOYMENT REPORT" -ForegroundColor Cyan
    Write-Host "$('='*70)`n" -ForegroundColor Cyan

    $configFile = Join-Path $PSScriptRoot "mfa-config.ini"

    Write-Host "Creating interactive HTML deployment report with all links and next steps..." -ForegroundColor Yellow
    $reportFile = & "$PSScriptRoot\Generate-Deployment-Report.ps1" -ConfigFile $configFile -StepResults $stepResults
    
    Save-DeploymentState -CompletedStep 12
} else {
    Write-Host "`n[SKIPPED] Final Report Generation (already completed)" -ForegroundColor DarkGreen
    $reportFile = Get-ChildItem "$PSScriptRoot\logs\DEPLOYMENT-REPORT*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

# ============================================================================
# Final Summary
# ============================================================================

$allSuccess = $true
foreach ($result in $stepResults.Values) {
    if (-not $result) { $allSuccess = $false; break }
}

$duration = (Get-Date) - $script:StartTime

if ($allSuccess) {
    Write-Host "`n$('='*70)" -ForegroundColor Green
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║" -ForegroundColor Green
    Write-Host "  ✓ COMPLETE DEPLOYMENT SUCCESSFUL!" -ForegroundColor Green
    Write-Host "║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host "$('='*70)`n" -ForegroundColor Green
    
    Write-Host "⏱️  Total Duration: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    
    Write-Host "`n📄 Reports Generated:" -ForegroundColor Cyan
    Write-Host "  📊 Interactive Report: $reportFile" -ForegroundColor Gray
    Write-Host "  📋 Deployment Log    : $logFile" -ForegroundColor Gray
    
    Write-Host "`nOpening deployment report in your default browser..." -ForegroundColor Cyan
    Write-Host "(Report contains all links, resources, and next steps)" -ForegroundColor Gray
    
    Start-Sleep -Seconds 2
    
    try {
        Start-Process $reportFile
        Write-Host "✓ Report opened successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Could not open report automatically. Please open manually:" -ForegroundColor Yellow
        Write-Host "  $reportFile" -ForegroundColor Gray
    }
    
    Write-Host "`n" -NoNewline
    Write-Host "✨ ALL SYSTEMS READY - YOUR DEPLOYMENT IS COMPLETE!" -ForegroundColor Green
    Write-Host "`nThe report contains:" -ForegroundColor Cyan
    Write-Host "  ✓ All deployment step statuses" -ForegroundColor Gray
    Write-Host "  ✓ Quick access links to all portals and services" -ForegroundColor Gray
    Write-Host "  ✓ Azure resources and IDs (copyable)" -ForegroundColor Gray
    Write-Host "  ✓ Detailed next steps and checklist" -ForegroundColor Gray
    Write-Host "  ✓ Troubleshooting guide" -ForegroundColor Gray
    Write-Host "`n" -NoNewline
    
    Write-Log "Complete deployment finished successfully" -Level SUCCESS
    exit 0
    
} else {
    Write-Host "`n$('='*70)" -ForegroundColor Red
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║" -ForegroundColor Red
    Write-Host "  ✗ DEPLOYMENT COMPLETED WITH ERRORS" -ForegroundColor Red
    Write-Host "║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host "$('='*70)`n" -ForegroundColor Red
    
    Write-Host "⏱️  Duration Before Error: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    
    Write-Host "`n❌ One or more steps failed. Check these files:" -ForegroundColor Yellow
    Write-Host "  📊 Deployment Report: $reportFile" -ForegroundColor Gray
    Write-Host "  📋 Deployment Log   : $logFile" -ForegroundColor Gray
    
    Write-Host "`nStep Results Summary:" -ForegroundColor Yellow
    foreach ($step in $stepResults.Keys) {
        $status = if ($stepResults[$step]) { "✓" } else { "✗" }
        $color = if ($stepResults[$step]) { "Green" } else { "Red" }
        Write-Host "  [$status] $step" -ForegroundColor $color
    }
    
    Write-Host "`nOpening report to review failed steps..." -ForegroundColor Cyan
    try {
        Start-Process $reportFile
    }
    catch {
        Write-Host "⚠️  Could not open report automatically:" -ForegroundColor Yellow
        Write-Host "  $reportFile" -ForegroundColor Gray
    }
    
    Write-Host "`n" -NoNewline
    
    Write-Log "Complete deployment finished with errors" -Level ERROR
    exit 1
}
