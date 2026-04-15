# Setup.ps1 - Single entry point for MFA Onboarding Tool
# Detects whether this is a fresh install or existing deployment and routes accordingly
# Can self-update from GitHub before running

param(
    [switch]$SkipUpdate   # Skip the "check for updates" prompt (used by Get-MFAOnboarder after fresh download)
)

# ── PowerShell 7 check ──────────────────────────────────────────
if (-not ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion.Major -ge 7)) {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "ERROR: PowerShell 7+ Required" -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Red
    Write-Host "This script must be run in PowerShell 7+ (pwsh.exe), not Windows PowerShell." -ForegroundColor Yellow
    Write-Host "`nTo install PowerShell 7:" -ForegroundColor Cyan
    Write-Host "  winget install --id Microsoft.Powershell --source winget" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "`nThen reopen as pwsh and re-run this script.`n" -ForegroundColor Yellow
    exit 1
}

# ── Self-update function ────────────────────────────────────────
function Update-ScriptsFromGitHub {
    $repoUrl = "https://github.com/andrew-kemp/MFA-Onboard-Tool/archive/refs/heads/main.zip"
    $zipFile = Join-Path $env:TEMP "MFA-Onboard-Tool-update.zip"
    $extractDir = Join-Path $env:TEMP "MFA-Onboard-Tool-update"

    try {
        Write-Host "  Downloading latest version from GitHub..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $repoUrl -OutFile $zipFile -ErrorAction Stop

        # Clean previous extract if any
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force

        # The ZIP extracts to MFA-Onboard-Tool-main/v2/ — that's where the latest scripts live
        $sourceDir = Join-Path $extractDir "MFA-Onboard-Tool-main\v2"
        if (-not (Test-Path $sourceDir)) {
            # Fallback if repo restructures to root
            $sourceDir = Join-Path $extractDir "MFA-Onboard-Tool-main"
        }

        # Copy script files over current installation, preserving local-only files
        $preservePatterns = @("mfa-config.ini", "*.bak", "cert-output", "logs")
        $filesToCopy = Get-ChildItem -Path $sourceDir -Recurse -File | Where-Object {
            $relativePath = $_.FullName.Substring($sourceDir.Length + 1)
            $skip = $false
            foreach ($pattern in $preservePatterns) {
                if ($relativePath -like "$pattern*") { $skip = $true; break }
            }
            -not $skip
        }

        $copied = 0
        foreach ($file in $filesToCopy) {
            $relativePath = $file.FullName.Substring($sourceDir.Length + 1)
            $destPath = Join-Path $PSScriptRoot $relativePath
            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item $file.FullName $destPath -Force
            $copied++
        }

        # Clean up temp files
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "  Updated $copied files to latest version." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Failed to download update: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Continuing with current version." -ForegroundColor Yellow
        return $false
    }
}

# ── Detect existing deployment ──────────────────────────────────
$configFile  = Join-Path $PSScriptRoot "mfa-config.ini"
$stateFile   = Join-Path $PSScriptRoot "logs\deployment-state.json"
$isExisting  = $false
$tenantLabel = ""

# Check for a root-level config from an original (pre-v2) install
$parentConfig = Join-Path (Split-Path $PSScriptRoot -Parent) "mfa-config.ini"
if (-not (Test-Path $configFile) -and (Test-Path $parentConfig)) {
    # Read parent config to check if it has real values
    $parentIni = @{}; $sec = ""
    switch -regex -file $parentConfig {
        "^\[(.+)\]$"       { $sec = $matches[1]; $parentIni[$sec] = @{} }
        "(.+?)\s*=\s*(.*)" { $parentIni[$sec][$matches[1]] = $matches[2] }
    }
    $pTenant = $parentIni["Tenant"]["TenantId"]
    $pFunc   = $parentIni["Azure"]["FunctionAppName"]

    if (-not [string]::IsNullOrWhiteSpace($pTenant) -and -not [string]::IsNullOrWhiteSpace($pFunc)) {
        Write-Host "`n  Found existing config from original install:" -ForegroundColor Yellow
        Write-Host "    $parentConfig" -ForegroundColor Gray
        Write-Host "    Tenant: $pTenant  |  Function App: $pFunc" -ForegroundColor Gray
        $migrate = Read-Host "`n  Migrate this config to v2? (Y/N)"
        if ($migrate -match '^[Yy]') {
            Copy-Item $parentConfig $configFile -Force
            Write-Host "  ✓ Config copied to v2 folder" -ForegroundColor Green
        }
    }
}

if (Test-Path $configFile) {
    # Read INI to check if it has real values (not just a blank template)
    $iniContent = @{}
    $section = ""
    switch -regex -file $configFile {
        "^\[(.+)\]$"       { $section = $matches[1]; $iniContent[$section] = @{} }
        "(.+?)\s*=\s*(.*)" { $iniContent[$section][$matches[1]] = $matches[2] }
    }

    $tenantId = $iniContent["Tenant"]["TenantId"]
    $funcApp  = $iniContent["Azure"]["FunctionAppName"]

    # Consider it an existing deployment if TenantId AND at least one auto-filled value exist
    if (-not [string]::IsNullOrWhiteSpace($tenantId) -and -not [string]::IsNullOrWhiteSpace($funcApp)) {
        $isExisting  = $true
        $tenantLabel = $tenantId
    }
}

# ── Banner ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MFA Onboarding Tool - Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($isExisting) {
    # ── Existing deployment detected ────────────────────────────
    Write-Host "`n  Existing deployment detected" -ForegroundColor Green
    Write-Host "    Tenant:       $tenantLabel" -ForegroundColor Gray
    Write-Host "    Function App: $funcApp" -ForegroundColor Gray

    # Check resume state
    $resumeInfo = ""
    if (Test-Path $stateFile) {
        try {
            $state = Get-Content $stateFile -Raw | ConvertFrom-Json
            if ($state.LastCompletedStep -lt 12) {
                $resumeInfo = " (paused at step $($state.LastCompletedStep))"
            }
        } catch { }
    }

    Write-Host "
  What would you like to do?

    [1] Update existing deployment    - Change branding, redeploy code, fix permissions
    [2] Pull latest scripts + update  - Download newest code from GitHub, then update
    [3] Fresh install (overwrite)     - Full deployment from scratch
    [4] Resume previous install$resumeInfo      - Continue where the last install left off
    [5] Quick fix (pull + permissions) - Download latest code and fix all permissions
    [0] Exit
" -ForegroundColor White

    $choice = Read-Host "  Select option"

    switch ($choice) {
        "1" {
            Write-Host "`n  Launching Update Tool...`n" -ForegroundColor Cyan
            & "$PSScriptRoot\Update-Deployment.ps1"
        }
        "2" {
            $updated = Update-ScriptsFromGitHub
            if ($updated) {
                Write-Host "`n  Launching Update Tool with latest code...`n" -ForegroundColor Cyan
                & "$PSScriptRoot\Update-Deployment.ps1"
            }
        }
        "5" {
            Write-Host "`n  Pulling latest scripts..." -ForegroundColor Cyan
            $updated = Update-ScriptsFromGitHub
            Write-Host "`n  Running permission fixes...`n" -ForegroundColor Cyan
            & "$PSScriptRoot\Update-Deployment.ps1" -QuickFix
        }
        "3" {
            $confirm = Read-Host "  This will overwrite the current config. Are you sure? (Y/N)"
            if ($confirm -match '^[Yy]') {
                # Back up current config
                $backupName = "mfa-config.$(Get-Date -Format 'yyyyMMdd-HHmmss').ini.bak"
                Copy-Item $configFile (Join-Path $PSScriptRoot $backupName)
                Write-Host "  Config backed up to $backupName" -ForegroundColor Gray

                Write-Host "`n  Launching Full Deployment...`n" -ForegroundColor Cyan
                & "$PSScriptRoot\Run-Complete-Deployment-Master.ps1"
            } else {
                Write-Host "`n  Cancelled.`n" -ForegroundColor Gray
            }
        }
        "4" {
            Write-Host "`n  Resuming Deployment...`n" -ForegroundColor Cyan
            & "$PSScriptRoot\Run-Complete-Deployment-Master.ps1" -Resume
        }
        default {
            Write-Host "`n  Exiting.`n" -ForegroundColor Gray
        }
    }

} else {
    # ── No existing deployment ──────────────────────────────────
    Write-Host "`n  No existing deployment found in this folder." -ForegroundColor Yellow
    Write-Host "  This will set up a new MFA Onboarding deployment." -ForegroundColor Gray

    # Offer to pull latest unless we just came from Get-MFAOnboarder (which already downloaded)
    if (-not $SkipUpdate) {
        $pullLatest = Read-Host "`n  Download latest scripts from GitHub first? (Y/N)"
        if ($pullLatest -match '^[Yy]') {
            Update-ScriptsFromGitHub
        }
    }

    Write-Host "
  What would you like to do?

    [1] New deployment   - Full guided setup (recommended)
    [0] Exit
" -ForegroundColor White

    $choice = Read-Host "  Select option"

    switch ($choice) {
        "1" {
            Write-Host "`n  Launching Full Deployment...`n" -ForegroundColor Cyan
            & "$PSScriptRoot\Run-Complete-Deployment-Master.ps1"
        }
        default {
            Write-Host "`n  Exiting.`n" -ForegroundColor Gray
        }
    }
}
