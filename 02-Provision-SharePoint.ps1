# Step 02 - Provision SharePoint Site and List
# Creates SharePoint site with MFA tracking list and app registration

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
    
    # If section exists but key not found, add it
    if ($inSection -and -not $found) {
        $newContent += "$Key=$Value"
    }
    
    # If section doesn't exist, add it with the key
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
    
    $config = Get-IniContent -Path $Path
    $value = $config[$Section][$Key]
    
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
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Step 02 - SharePoint Site and List" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Ensure INI file exists
    if (-not (Test-Path $configFile)) {
        Write-Host "Creating new configuration file: $configFile" -ForegroundColor Yellow
        "# MFA Onboarding Configuration" | Set-Content $configFile
    }
    
    $config = Get-IniContent -Path $configFile
    
    # Get required values (prompt if missing)
    Write-Host "Checking configuration..." -ForegroundColor Yellow
    
    $siteUrl = Get-IniValueOrPrompt -Path $configFile -Section "SharePoint" -Key "SiteUrl" `
        -Prompt "SharePoint Site URL (e.g., https://yourtenant.sharepoint.com/sites/MFAOps)" `
        -Default "https://yourtenant.sharepoint.com/sites/MFAOps"
    
    $listTitle = Get-IniValueOrPrompt -Path $configFile -Section "SharePoint" -Key "ListTitle" `
        -Prompt "SharePoint List Title" `
        -Default "MFA Enrollment Tracking"
    
    $siteOwner = Get-IniValueOrPrompt -Path $configFile -Section "SharePoint" -Key "SiteOwner" `
        -Prompt "Site Owner Email"
    
    $appRegName = Get-IniValueOrPrompt -Path $configFile -Section "SharePoint" -Key "AppRegName" `
        -Prompt "SharePoint App Registration Name" `
        -Default "SPO-MFA-Automation"
    
    $tenantId = Get-IniValueOrPrompt -Path $configFile -Section "Tenant" -Key "TenantId" `
        -Prompt "Tenant ID (e.g., contoso.onmicrosoft.com or guid)"
    
    Write-Host "`n✓ Configuration loaded" -ForegroundColor Green
    
    # Continue with existing logic
    if ([string]::IsNullOrWhiteSpace($listTitle)) {
        $listTitle = "MFA Onboarding"
    }
    
    $siteOwner = $config["SharePoint"]["SiteOwner"]
    if ([string]::IsNullOrWhiteSpace($siteOwner)) {
        throw "SharePoint Site Owner not configured. Please run Step 01 first."
    }
    
    $tenantId = $config["Tenant"]["TenantId"]
    if ([string]::IsNullOrWhiteSpace($tenantId)) {
        throw "Tenant ID not configured. Please run Step 01 first."
    }
    
    # Extract tenant name from site URL
    $tenantName = $siteUrl -replace '.*://([^.]+)\..*', '$1'
    $adminUrl = "https://$tenantName-admin.sharepoint.com"
    
    # Site title from config (set in Step 01)
    $siteTitle = $config["SharePoint"]["SiteTitle"]
    if ([string]::IsNullOrWhiteSpace($siteTitle)) {
        $siteTitle = "MFA Operations" # Fallback default
    }
    
    Write-Host "Configuration loaded from Step 01:" -ForegroundColor Gray
    Write-Host "  Site URL: $siteUrl" -ForegroundColor Gray
    Write-Host "  Site Title: $siteTitle" -ForegroundColor Gray
    Write-Host "  List: $listTitle" -ForegroundColor Gray
    Write-Host "  Site Owner: $siteOwner" -ForegroundColor Gray
    Write-Host "  Tenant: $tenantId" -ForegroundColor Gray
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "App Registration & Certificate" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # App registration name from config (set in Step 01)
    $appName = $config["SharePoint"]["AppRegName"]
    if ([string]::IsNullOrWhiteSpace($appName)) {
        $appName = "SPO-Automation-MFA" # Fallback default
    }
    $certFolder = Join-Path $PSScriptRoot "cert-output"
    if (-not (Test-Path $certFolder)) {
        New-Item -ItemType Directory -Path $certFolder -Force | Out-Null
    }
    
    # Prompt for cert password with confirmation
    Write-Host "Certificate password will be used to secure the PFX file." -ForegroundColor Yellow
    $match = $false
    do {
        $certPassword = Read-Host -AsSecureString "Enter a password for the certificate (keep it safe)"
        $certPasswordConfirm = Read-Host -AsSecureString "Confirm certificate password"
        
        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($certPassword)
        $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($certPasswordConfirm)
        try {
            $pwd1 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
            $pwd2 = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
            
            if ([string]::IsNullOrWhiteSpace($pwd1) -or [string]::IsNullOrWhiteSpace($pwd2)) {
                Write-Warning "Password cannot be empty. Please try again."
                $match = $false
                continue
            }
            
            if ($pwd1 -cne $pwd2) {
                Write-Warning "Passwords do not match (case-sensitive). Please try again."
                $match = $false
            } else {
                Write-Host "Password confirmed." -ForegroundColor Green
                $match = $true
            }
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
        }
    } while (-not $match)
    
    # Register app with PnP (creates app, cert, and permissions)
    Write-Host "`nCreating Entra App Registration (browser login will open)..." -ForegroundColor Cyan
    $regOutput = Register-PnPAzureADApp `
        -ApplicationName $appName `
        -Tenant $tenantId `
        -Store CurrentUser `
        -OutPath $certFolder `
        -GraphApplicationPermissions "Sites.ReadWrite.All","Reports.Read.All" `
        -SharePointApplicationPermissions "Sites.FullControl.All" `
        -ErrorAction Stop
    
    Write-Host "✓ App Registration created!" -ForegroundColor Green
    
    # Extract ClientId
    $clientId = $regOutput.'AzureAppId/ClientId'
    if (-not $clientId) { $clientId = $regOutput.AzureAppId }
    if (-not $clientId) { $clientId = $regOutput.ClientId }
    
    Write-Host "  Client ID: $clientId" -ForegroundColor Gray
    Write-Host "`nWaiting 60 seconds for permissions to propagate..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
    
    # Re-export certificate with user's password
    Write-Host "Exporting certificate with your password..." -ForegroundColor Cyan
    $storeCert = Get-ChildItem Cert:\CurrentUser\My | 
        Where-Object { $_.Subject -like "*CN=$appName*" -and $_.HasPrivateKey } | 
        Sort-Object NotAfter -Descending | 
        Select-Object -First 1
    
    if (-not $storeCert) {
        $storeCert = Get-ChildItem Cert:\CurrentUser\My | 
            Where-Object { $_.Subject -like "*$appName*" -and $_.HasPrivateKey } | 
            Sort-Object NotAfter -Descending | 
            Select-Object -First 1
    }
    
    if (-not $storeCert) {
        throw "Could not find certificate for '$appName' in CurrentUser store."
    }
    
    $pfxPath = Join-Path $certFolder "$appName.pfx"
    Export-PfxCertificate -Cert $storeCert -FilePath $pfxPath -Password $certPassword -Force | Out-Null
    Write-Host "✓ Certificate exported: $pfxPath" -ForegroundColor Green
    Write-Host "  Thumbprint: $($storeCert.Thumbprint)" -ForegroundColor Gray
    
    # Save to ini
    Set-IniValue -Path $configFile -Section "SharePoint" -Key "ClientId" -Value $clientId
    Set-IniValue -Path $configFile -Section "SharePoint" -Key "CertificatePath" -Value $pfxPath
    Set-IniValue -Path $configFile -Section "SharePoint" -Key "CertificateThumbprint" -Value $storeCert.Thumbprint
    
    # Build admin consent URL
    $adminConsentUrl = "https://login.microsoftonline.com/$tenantId/adminconsent?client_id=$clientId"
    
    Write-Host "`nWaiting additional 30 seconds for certificate registration to complete..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Connect to SharePoint Admin - reuse the certificate password from earlier
    Write-Host "Connecting to SharePoint Admin: $adminUrl" -ForegroundColor Yellow
    Write-Host "Using certificate password from earlier..." -ForegroundColor Gray
    try {
        Connect-PnPOnline -Url $adminUrl -ClientId $clientId -Tenant $tenantId -CertificatePath $pfxPath -CertificatePassword $certPassword
    } catch {
        Write-Host "Connection failed with stored password. Trying thumbprint authentication..." -ForegroundColor Yellow
        try {
            Connect-PnPOnline -Url $adminUrl -ClientId $clientId -Tenant $tenantId -Thumbprint $storeCert.Thumbprint
        } catch {
            Write-Host "Thumbprint failed. Please enter certificate password manually:" -ForegroundColor Yellow
            $manualPwd = Read-Host -AsSecureString "Enter certificate password"
            Connect-PnPOnline -Url $adminUrl -ClientId $clientId -Tenant $tenantId -CertificatePath $pfxPath -CertificatePassword $manualPwd
        }
    }
    
    Write-Host "✓ Connected to SharePoint Admin" -ForegroundColor Green
    
    # Create site if missing
    $existing = Get-PnPTenantSite -Url $siteUrl -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Host "`nCreating Communication site: $siteUrl" -ForegroundColor Cyan
        Write-Host "  Owner: $siteOwner" -ForegroundColor Gray
        Write-Host "  Title: $siteTitle" -ForegroundColor Gray
        try {
            New-PnPSite -Type CommunicationSite -Title $siteTitle -Url $siteUrl -Owner $siteOwner -Wait
            Write-Host "✓ Site created" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -match 'Unauthorized') {
                Write-Warning "Unauthorized. Admin consent may be required."
                Write-Host "Opening admin consent URL..." -ForegroundColor Yellow
                Write-Host "  $adminConsentUrl" -ForegroundColor Cyan
                try { Start-Process $adminConsentUrl | Out-Null } catch {}
                Read-Host "After granting consent in browser, press Enter to retry"
                
                try {
                    Connect-PnPOnline -Url $adminUrl -ClientId $clientId -Tenant $tenantId -CertificatePath $pfxPath -CertificatePassword $connectPwd
                } catch {
                    Connect-PnPOnline -Url $adminUrl -ClientId $clientId -Tenant $tenantId -Thumbprint $storeCert.Thumbprint
                }
                New-PnPSite -Type CommunicationSite -Title $siteTitle -Url $siteUrl -Owner $siteOwner -Wait
            } else {
                throw
            }
        }
        
        # Wait for site to be ready
        Write-Host "Waiting for site to be ready..." -ForegroundColor Yellow
        for ($i = 0; $i -lt 10; $i++) {
            Start-Sleep -Seconds 15
            $existing = Get-PnPTenantSite -Url $siteUrl -ErrorAction SilentlyContinue
            if ($existing) { break }
        }
    } else {
        Write-Host "✓ Site already exists" -ForegroundColor Green
    }
    
    Disconnect-PnPOnline
    
    # Connect to the site directly - reuse certificate password
    Write-Host "`nConnecting to site: $siteUrl" -ForegroundColor Yellow
    Write-Host "Using certificate password from earlier..." -ForegroundColor Gray
    try {
        Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Tenant $tenantId -CertificatePath $pfxPath -CertificatePassword $certPassword
    } catch {
        Write-Host "Connection failed. Trying thumbprint authentication..." -ForegroundColor Yellow
        try {
            Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Tenant $tenantId -Thumbprint $storeCert.Thumbprint
        } catch {
            Write-Host "Please enter certificate password manually:" -ForegroundColor Yellow
            $manualPwd2 = Read-Host -AsSecureString "Enter certificate password"
            Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Tenant $tenantId -CertificatePath $pfxPath -CertificatePassword $manualPwd2
        }
    }
    
    Write-Host "✓ Connected to site" -ForegroundColor Green
    Write-Host "`nChecking for list: $listTitle" -ForegroundColor Yellow
    $list = Get-PnPList -Identity $listTitle -ErrorAction SilentlyContinue
    
    if ($null -eq $list) {
        Write-Host "Creating list: $listTitle" -ForegroundColor Yellow
        $list = New-PnPList -Title $listTitle -Template GenericList -Url "MFA-Onboarding" -OnQuickLaunch
        
        Write-Host "Configuring list columns..." -ForegroundColor Yellow
        
        # Make Title act as UPN and index it
        Set-PnPField -List $listTitle -Identity "Title" -Values @{ Title='UPN'; Required=$true }
        Set-PnPField -List $listTitle -Identity "Title" -Values @{ Indexed=$true }
        
        # Choice fields for process state
        Add-PnPField -List $listTitle -DisplayName "Invite Status" -InternalName "InviteStatus" -Type Choice -Choices "Pending","Sent","Clicked","AddedToGroup","Active","Skipped Registered","Error" -AddToDefaultView
        Add-PnPField -List $listTitle -DisplayName "MFA Registration State" -InternalName "MFARegistrationState" -Type Choice -Choices "Unknown","Not Registered","Registered" -AddToDefaultView
        
        # Boolean for group membership
        Add-PnPField -List $listTitle -DisplayName "In Group" -InternalName "InGroup" -Type Boolean -AddToDefaultView
        
        # Dates and operational fields
        Add-PnPField -List $listTitle -DisplayName "Invite Sent Date" -InternalName "InviteSentDate" -Type DateTime -AddToDefaultView
        Add-PnPField -List $listTitle -DisplayName "Clicked Link Date" -InternalName "ClickedLinkDate" -Type DateTime -AddToDefaultView
        Add-PnPField -List $listTitle -DisplayName "Added To Group Date" -InternalName "AddedToGroupDate" -Type DateTime -AddToDefaultView
        Add-PnPField -List $listTitle -DisplayName "MFA Registration Date" -InternalName "MFARegistrationDate" -Type DateTime -AddToDefaultView
        Add-PnPField -List $listTitle -DisplayName "Last Checked" -InternalName "LastChecked" -Type DateTime
        Add-PnPField -List $listTitle -DisplayName "Reminder Count" -InternalName "ReminderCount" -Type Number
        Add-PnPField -List $listTitle -DisplayName "Last Reminder Date" -InternalName "LastReminderDate" -Type DateTime
        Add-PnPField -List $listTitle -DisplayName "Source Batch Id" -InternalName "SourceBatchId" -Type Text
        Add-PnPField -List $listTitle -DisplayName "Correlation Id" -InternalName "CorrelationId" -Type Text
        Add-PnPField -List $listTitle -DisplayName "Notes" -InternalName "Notes" -Type Note
        
        # Optional attributes read from Entra during orchestration
        Add-PnPField -List $listTitle -DisplayName "Display Name" -InternalName "DisplayName" -Type Text
        Add-PnPField -List $listTitle -DisplayName "Department" -InternalName "Department" -Type Text
        Add-PnPField -List $listTitle -DisplayName "Job Title" -InternalName "JobTitle" -Type Text
        Add-PnPField -List $listTitle -DisplayName "Manager UPN" -InternalName "ManagerUPN" -Type Text
        Add-PnPField -List $listTitle -DisplayName "Object Id" -InternalName "ObjectId" -Type Text
        Add-PnPField -List $listTitle -DisplayName "User Type" -InternalName "UserType" -Type Text
        
        # Index the two state columns used by Logic Apps filters
        Set-PnPField -List $listTitle -Identity "InviteStatus" -Values @{ Indexed=$true }
        Set-PnPField -List $listTitle -Identity "MFARegistrationState" -Values @{ Indexed=$true }
        
        Write-Host "✓ List created with all columns and indexes" -ForegroundColor Green
    }
    else {
        Write-Host "✓ List already exists" -ForegroundColor Green
    }
    
    $listId = $list.Id.Guid
    Write-Host "  List ID: $listId" -ForegroundColor Gray
    
    # Save ListId to INI file
    Set-IniValue -Path $configFile -Section "SharePoint" -Key "ListId" -Value $listId
    
    Disconnect-PnPOnline
    
    # Read group configuration (created in Step 01)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Security Group Verification" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    $groupId = $config["Security"]["MFAGroupId"]
    $groupName = $config["Security"]["MFAGroupName"]
    
    if ([string]::IsNullOrWhiteSpace($groupId)) {
        Write-Host "⚠ WARNING: No security group configured. Please run Step 01 first." -ForegroundColor Yellow
        Write-Host "Continuing without group validation..." -ForegroundColor Gray
    } else {
        Write-Host "✓ Using security group: $groupName" -ForegroundColor Green
        Write-Host "  Object ID: $groupId" -ForegroundColor Gray
    }
    
    Write-Host "`n✓ Step 02 completed successfully!" -ForegroundColor Green
    Write-Host "`nConfiguration Summary:" -ForegroundColor Cyan
    Write-Host "  Site URL: $siteUrl" -ForegroundColor Gray
    Write-Host "  List: $listTitle" -ForegroundColor Gray
    Write-Host "  Client ID: $clientId" -ForegroundColor Gray
    Write-Host "  Group: $groupName ($groupId)" -ForegroundColor Gray
    Write-Host "  Certificate: $pfxPath" -ForegroundColor Gray
    
    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

