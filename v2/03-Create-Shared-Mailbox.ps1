# Step 03 - Create Exchange Online Shared Mailbox
# Creates shared mailbox for sending MFA onboarding emails

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
    param(
        [string]$Path,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )
    $content = Get-Content $Path
    $inSection = $false
    $found = $false
    $newContent = @()
    
    foreach ($line in $content) {
        if ($line -match "^\[$Section\]") {
            $inSection = $true
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
    
    $newContent | Set-Content $Path -Force
}

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Step 03 - Exchange Shared Mailbox" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $config = Get-IniContent -Path $configFile
    
    # Check if ExchangeOnlineManagement module is available
    Write-Host "Checking for ExchangeOnlineManagement module..." -ForegroundColor Yellow
    $exoModule = Get-Module -ListAvailable -Name ExchangeOnlineManagement
    if (-not $exoModule) {
        Write-Host "Installing ExchangeOnlineManagement module..." -ForegroundColor Yellow
        Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
        Write-Host "✓ Module installed" -ForegroundColor Green
    }
    
    # Import module
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    
    # Connect to Exchange Online
    Write-Host "`nConnecting to Exchange Online (interactive login will open)..." -ForegroundColor Cyan
    try {
        Connect-ExchangeOnline -ShowBanner:$false
        Write-Host "✓ Connected to Exchange Online" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to connect to Exchange Online" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
    
    # Get mailbox email from config (set in Step 01)
    $mailboxAddress = $config["Email"]["NoReplyMailbox"]
    $mailboxName = $config["Email"]["MailboxName"]
    
    if ([string]::IsNullOrWhiteSpace($mailboxAddress)) {
        Write-Host "ERROR: Mailbox email not configured. Please run Step 01 first." -ForegroundColor Red
        exit 1
    }
    
    if ([string]::IsNullOrWhiteSpace($mailboxName)) {
        $mailboxName = "MFA Registration"
    }
    
    Write-Host "`nShared Mailbox Configuration:" -ForegroundColor Cyan
    Write-Host "  Email: $mailboxAddress" -ForegroundColor Gray
    Write-Host "  Display Name: $mailboxName" -ForegroundColor Gray
    
    # Check if mailbox already exists
    Write-Host "`nChecking if mailbox exists..." -ForegroundColor Yellow
    $existingMbx = Get-Mailbox -Identity $mailboxAddress -ErrorAction SilentlyContinue
    
    if ($existingMbx) {
        Write-Host "✓ Mailbox already exists: $mailboxAddress" -ForegroundColor Green
        Write-Host "  Type: $($existingMbx.RecipientTypeDetails)" -ForegroundColor Gray
        
        if ($existingMbx.RecipientTypeDetails -ne "SharedMailbox") {
            Write-Warning "This mailbox is not a shared mailbox. It's a $($existingMbx.RecipientTypeDetails)."
            $convert = Read-Host "Would you like to use it anyway? (Y/N)"
            if ($convert -ne "Y") {
                Write-Host "Please specify a different email address or create the shared mailbox manually." -ForegroundColor Yellow
                exit 1
            }
        }
    }
    else {
        # Create new shared mailbox
        Write-Host "`nCreating shared mailbox..." -ForegroundColor Cyan
        try {
            $newMbx = New-Mailbox -Shared -Name $mailboxName -PrimarySmtpAddress $mailboxAddress
            Write-Host "✓ Shared mailbox created successfully!" -ForegroundColor Green
            Write-Host "  Address: $mailboxAddress" -ForegroundColor Gray
            Write-Host "  Name: $mailboxName" -ForegroundColor Gray
            
            # Wait for mailbox to be fully provisioned
            Write-Host "`nWaiting for mailbox provisioning (30 seconds)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
        catch {
            Write-Host "ERROR: Failed to create shared mailbox" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host "`nYou may need to create this manually with:" -ForegroundColor Yellow
            Write-Host "  New-Mailbox -Shared -Name `"$mailboxName`" -PrimarySmtpAddress $mailboxAddress" -ForegroundColor Gray
            exit 1
        }
    }
    
    # Grant mailbox permissions to delegate user (from Step 01 config)
    $delegateUser = $config["Email"]["MailboxDelegate"]
    if (-not [string]::IsNullOrWhiteSpace($delegateUser)) {
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Mailbox Permissions" -ForegroundColor Cyan
        Write-Host "========================================`n" -ForegroundColor Cyan
        Write-Host "Granting permissions to delegate user: $delegateUser" -ForegroundColor Yellow
        
        # Grant FullAccess permission
        try {
            Add-MailboxPermission -Identity $mailboxAddress -User $delegateUser -AccessRights FullAccess -InheritanceType All -AutoMapping $true | Out-Null
            Write-Host "✓ FullAccess permission granted" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to grant FullAccess permission: $($_.Exception.Message)"
        }
        
        # Grant SendAs permission
        try {
            Add-RecipientPermission -Identity $mailboxAddress -Trustee $delegateUser -AccessRights SendAs -Confirm:$false | Out-Null
            Write-Host "✓ SendAs permission granted" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to grant SendAs permission: $($_.Exception.Message)"
        }
        
        Write-Host "`nUser $delegateUser can now:" -ForegroundColor Cyan
        Write-Host "  - Access the mailbox in Outlook" -ForegroundColor Gray
        Write-Host "  - Send emails as $mailboxAddress" -ForegroundColor Gray
    } else {
        Write-Host "`n[INFO] No delegate user configured. Skipping permission assignment." -ForegroundColor Gray
        Write-Host "The Logic App will send using its Managed Identity." -ForegroundColor Gray
    }
    
    # Disconnect from Exchange Online
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    
    # Save to ini file
    Write-Host "`nSaving configuration..." -ForegroundColor Yellow
    Set-IniValue -Path $configFile -Section "Email" -Key "NoReplyMailbox" -Value $mailboxAddress
    Write-Host "✓ Configuration saved" -ForegroundColor Green
    
    Write-Host "`n✓ Step 03 completed successfully!" -ForegroundColor Green
    Write-Host "`nShared Mailbox Details:" -ForegroundColor Cyan
    Write-Host "  Email: $mailboxAddress" -ForegroundColor Gray
    Write-Host "  Name: $mailboxName" -ForegroundColor Gray
    Write-Host "`nThis mailbox will be used by the Logic App to send MFA onboarding emails." -ForegroundColor Yellow
    
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    # Try to disconnect
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    
    exit 1
}
