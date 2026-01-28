param(
    [string]$InstallPath = ""
)

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

function Get-InstallFolder {
    param([string]$DefaultPath)
    $folder = Read-Host "Enter install location (default: $DefaultPath)"
    if ([string]::IsNullOrWhiteSpace($folder)) { $folder = $DefaultPath }
    if (Test-Path $folder) {
        $useExisting = Read-Host "Folder exists. Use existing folder? (Y/N)"
        if ($useExisting -notin @('Y','y')) {
            $folder = Read-Host "Enter new folder name to create under $DefaultPath (e.g. MFA-Onboard-Tool)"
            if ([string]::IsNullOrWhiteSpace($folder)) { $folder = "$DefaultPath\MFA-Onboard-Tool" }
            $folder = Join-Path $DefaultPath $folder
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }
    } else {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    return $folder
}

if ([string]::IsNullOrWhiteSpace($InstallPath)) {
    $InstallPath = Get-InstallFolder "C:\Scripts"
}

$repoUrl = "https://github.com/andrew-kemp/MFA-Onboard-Tool/archive/refs/heads/main.zip"
$zipFile = "$env:TEMP\MFA-Onboard-Tool.zip"

Write-Host "Downloading MFA-Onboard-Tool repo..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $repoUrl -OutFile $zipFile

Write-Host "Extracting files to $InstallPath..." -ForegroundColor Cyan
Expand-Archive -Path $zipFile -DestinationPath $InstallPath -Force

$repoFolder = Join-Path $InstallPath "MFA-Onboard-Tool-main"
Set-Location $repoFolder

Write-Host "Starting complete deployment..." -ForegroundColor Cyan
./Run-Complete-Deployment-Master.ps1
