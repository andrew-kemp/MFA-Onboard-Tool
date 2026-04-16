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
    
    # ── Operations Group (Mail-Enabled Security Group) ────────────
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Operations Group (Mail-Enabled Security Group)" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "A mail-enabled security group can centralise access to the shared" -ForegroundColor Gray
    Write-Host "mailbox and SharePoint site. Add/remove team members in one place." -ForegroundColor Gray
    
    $opsGroupName  = $config["OpsGroup"]["OpsGroupName"]
    $opsGroupEmail = $config["OpsGroup"]["OpsGroupEmail"]
    
    if ([string]::IsNullOrWhiteSpace($opsGroupName)) {
        $opsGroupName = Read-Host "`n  Ops group display name (e.g. MFA Operations Team, or Enter to skip)"
    }
    
    if (-not [string]::IsNullOrWhiteSpace($opsGroupName)) {
        if ([string]::IsNullOrWhiteSpace($opsGroupEmail)) {
            $defaultAlias = ($opsGroupName -replace '[^a-zA-Z0-9-]', '-').ToLower()
            $domain = ($mailboxAddress -split '@')[1]
            $opsGroupEmail = Read-Host "  Ops group email [$defaultAlias@$domain]"
            if ([string]::IsNullOrWhiteSpace($opsGroupEmail)) { $opsGroupEmail = "$defaultAlias@$domain" }
        }
        
        Write-Host "`n  Creating mail-enabled security group..." -ForegroundColor Yellow
        Write-Host "    Name:  $opsGroupName" -ForegroundColor Gray
        Write-Host "    Email: $opsGroupEmail" -ForegroundColor Gray
        
        try {
            Connect-ExchangeOnline -ShowBanner:$false
            
            # Check if group already exists
            $existingGroup = Get-DistributionGroup -Identity $opsGroupEmail -ErrorAction SilentlyContinue
            if ($existingGroup) {
                Write-Host "  ✓ Group already exists" -ForegroundColor Green
                $groupId = $existingGroup.ExternalDirectoryObjectId
            } else {
                $newGroup = New-DistributionGroup -Name $opsGroupName `
                    -PrimarySmtpAddress $opsGroupEmail `
                    -Type Security `
                    -MemberDepartRestriction Closed `
                    -MemberJoinRestriction Closed
                Write-Host "  ✓ Mail-enabled security group created" -ForegroundColor Green
                $groupId = $newGroup.ExternalDirectoryObjectId
                
                # Wait for provisioning
                Start-Sleep -Seconds 10
            }
            
            # Add initial member (delegate user)
            if (-not [string]::IsNullOrWhiteSpace($delegateUser)) {
                try {
                    Add-DistributionGroupMember -Identity $opsGroupEmail -Member $delegateUser -ErrorAction Stop
                    Write-Host "  ✓ Added $delegateUser to group" -ForegroundColor Green
                } catch {
                    if ($_.Exception.Message -match 'already a member') {
                        Write-Host "  ✓ $delegateUser already a member" -ForegroundColor Green
                    } else {
                        Write-Warning "  Could not add member: $($_.Exception.Message)"
                    }
                }
            }
            
            # Grant group access to shared mailbox
            Write-Host "`n  Granting group access to shared mailbox..." -ForegroundColor Yellow
            try {
                Add-MailboxPermission -Identity $mailboxAddress -User $opsGroupEmail -AccessRights FullAccess -InheritanceType All -AutoMapping $false -ErrorAction Stop | Out-Null
                Write-Host "  ✓ FullAccess granted to group" -ForegroundColor Green
            } catch {
                Write-Warning "  FullAccess: $($_.Exception.Message)"
            }
            try {
                Add-RecipientPermission -Identity $mailboxAddress -Trustee $opsGroupEmail -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Host "  ✓ SendAs granted to group" -ForegroundColor Green
            } catch {
                Write-Warning "  SendAs: $($_.Exception.Message)"
            }
            
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            
            # Save to INI
            Set-IniValue -Path $configFile -Section "OpsGroup" -Key "OpsGroupName" -Value $opsGroupName
            Set-IniValue -Path $configFile -Section "OpsGroup" -Key "OpsGroupEmail" -Value $opsGroupEmail
            if (-not [string]::IsNullOrWhiteSpace($groupId)) {
                Set-IniValue -Path $configFile -Section "OpsGroup" -Key "OpsGroupId" -Value $groupId
            }
            
            Write-Host "`n  ✓ Operations group configured" -ForegroundColor Green
            Write-Host "    Members of $opsGroupEmail will have access to:" -ForegroundColor Gray
            Write-Host "    - Shared mailbox ($mailboxAddress)" -ForegroundColor Gray
            Write-Host "    - SharePoint site (configured in Step 02)" -ForegroundColor Gray
        } catch {
            Write-Warning "Failed to create ops group: $($_.Exception.Message)"
            Write-Host "  You can create it later via Update-Deployment.ps1 -Permissions" -ForegroundColor Yellow
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "`n  Skipping operations group. You can create one later via Update-Deployment.ps1" -ForegroundColor Gray
    }
    
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
