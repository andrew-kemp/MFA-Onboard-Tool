# Update-Deployment.ps1
# Update an existing MFA Onboarding deployment with new code, branding, or permissions
# Safe to re-run multiple times (idempotent)
#
# Usage:
#   .\Update-Deployment.ps1                          # Interactive menu
#   .\Update-Deployment.ps1 -UpdateAll               # Apply all updates
#   .\Update-Deployment.ps1 -FunctionCode            # Redeploy function code only
#   .\Update-Deployment.ps1 -LogicApp                # Redeploy Logic App only
#   .\Update-Deployment.ps1 -Branding                # Update branding/email wording
#   .\Update-Deployment.ps1 -Permissions             # Fix permissions
#   .\Update-Deployment.ps1 -SharePointSchema        # Add any missing list fields
#   .\Update-Deployment.ps1 -BackfillTokens          # Generate tracking tokens for existing users

param(
    [switch]$UpdateAll,
    [switch]$FunctionCode,
    [switch]$LogicApp,
    [switch]$Branding,
    [switch]$Permissions,
    [switch]$SharePointSchema,
    [switch]$BackfillTokens
)

$ErrorActionPreference = "Stop"
$configFile = "$PSScriptRoot\mfa-config.ini"

# ============================================================
# HELPER FUNCTIONS
# ============================================================

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
    $content = Get-Content $Path
    $inSection = $false
    $keyFound = $false

    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match "^\[$Section\]$") { $inSection = $true; continue }
        if ($content[$i] -match "^\[.+\]$") { 
            if ($inSection -and -not $keyFound) {
                # Key not found in section; insert before next section
                $content = $content[0..($i-1)] + "$Key=$Value" + $content[$i..($content.Count-1)]
                $keyFound = $true
            }
            $inSection = $false
        }
        if ($inSection -and $content[$i] -match "^$Key\s*=") {
            $content[$i] = "$Key=$Value"
            $keyFound = $true
        }
    }
    if (-not $keyFound -and $inSection) {
        $content += "$Key=$Value"
    }
    Set-Content $Path $content
}

function Write-Step  { param([string]$Message) Write-Host "`n  $Message" -ForegroundColor Cyan }
function Write-OK    { param([string]$Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Skip  { param([string]$Message) Write-Host "  → $Message (skipped)" -ForegroundColor DarkGray }
function Write-Warn  { param([string]$Message) Write-Host "  ⚠ $Message" -ForegroundColor Yellow }
function Write-Fail  { param([string]$Message) Write-Host "  ✗ $Message" -ForegroundColor Red }

function Ensure-AzureConnected {
    param([hashtable]$Config)
    $tenantId = $Config["Tenant"]["TenantId"]
    $subscriptionId = $Config["Tenant"]["SubscriptionId"]

    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if ($null -eq $azContext -or $azContext.Tenant.Id -ne $tenantId) {
        Write-Step "Connecting to Azure..."
        if (-not [string]::IsNullOrWhiteSpace($tenantId)) {
            Connect-AzAccount -TenantId $tenantId | Out-Null
        } else {
            Connect-AzAccount | Out-Null
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($subscriptionId)) {
        Set-AzContext -SubscriptionId $subscriptionId | Out-Null
    }
    Write-OK "Azure connected"
}

function Ensure-PnPConnected {
    param([hashtable]$Config)
    $siteUrl = $Config["SharePoint"]["SiteUrl"]
    $clientId = $Config["SharePoint"]["ClientId"]
    $thumbprint = $Config["SharePoint"]["CertificateThumbprint"]
    $tenantId = $Config["Tenant"]["TenantId"]

    try {
        $ctx = Get-PnPConnection -ErrorAction Stop
        if ($ctx.Url -eq $siteUrl) { return }
    } catch { }

    Write-Step "Connecting to SharePoint..."
    if (-not [string]::IsNullOrWhiteSpace($clientId) -and -not [string]::IsNullOrWhiteSpace($thumbprint)) {
        Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantId
    } else {
        Connect-PnPOnline -Url $siteUrl -Interactive
    }
    Write-OK "SharePoint connected: $siteUrl"
}

# ============================================================
# UPDATE TASKS
# ============================================================

function Update-SharePointSchema {
    param([hashtable]$Config)
    Write-Host "`n────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  SharePoint Schema Update" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan

    Ensure-PnPConnected -Config $Config
    $listTitle = $Config["SharePoint"]["ListTitle"]
    if ([string]::IsNullOrWhiteSpace($listTitle)) { $listTitle = "MFA Onboarding" }

    # Define expected fields (InternalName → Type, DisplayName)
    $expectedFields = [ordered]@{
        "InviteStatus"         = @{ Type = "Choice"; Display = "Invite Status"; Extra = @{ Choices = "Pending","Sent","Clicked","AddedToGroup","Active","Skipped Registered","Error" } }
        "MFARegistrationState" = @{ Type = "Choice"; Display = "MFA Registration State"; Extra = @{ Choices = "Unknown","Not Registered","Registered" } }
        "InGroup"              = @{ Type = "Boolean"; Display = "In Group" }
        "InviteSentDate"       = @{ Type = "DateTime"; Display = "Invite Sent Date" }
        "ClickedLinkDate"      = @{ Type = "DateTime"; Display = "Clicked Link Date" }
        "AddedToGroupDate"     = @{ Type = "DateTime"; Display = "Added To Group Date" }
        "MFARegistrationDate"  = @{ Type = "DateTime"; Display = "MFA Registration Date" }
        "LastChecked"          = @{ Type = "DateTime"; Display = "Last Checked" }
        "ReminderCount"        = @{ Type = "Number"; Display = "Reminder Count" }
        "LastReminderDate"     = @{ Type = "DateTime"; Display = "Last Reminder Date" }
        "SourceBatchId"        = @{ Type = "Text"; Display = "Source Batch Id" }
        "TrackingToken"        = @{ Type = "Text"; Display = "Tracking Token" }
        "CorrelationId"        = @{ Type = "Text"; Display = "Correlation Id" }
        "Notes"                = @{ Type = "Note"; Display = "Notes" }
        "DisplayName"          = @{ Type = "Text"; Display = "Display Name" }
        "Department"           = @{ Type = "Text"; Display = "Department" }
        "JobTitle"             = @{ Type = "Text"; Display = "Job Title" }
        "ManagerUPN"           = @{ Type = "Text"; Display = "Manager UPN" }
        "ObjectId"             = @{ Type = "Text"; Display = "Object Id" }
        "UserType"             = @{ Type = "Text"; Display = "User Type" }
    }

    # Get existing fields
    $existingFields = Get-PnPField -List $listTitle | Select-Object -ExpandProperty InternalName
    $added = 0

    foreach ($fieldName in $expectedFields.Keys) {
        if ($fieldName -in $existingFields) {
            Write-Skip "$fieldName already exists"
            continue
        }
        $f = $expectedFields[$fieldName]
        $params = @{
            List = $listTitle
            DisplayName = $f.Display
            InternalName = $fieldName
            Type = $f.Type
        }
        if ($f.Extra -and $f.Extra.Choices) {
            $params["Choices"] = $f.Extra.Choices
        }
        Add-PnPField @params | Out-Null
        Write-OK "Added field: $fieldName ($($f.Type))"
        $added++
    }

    if ($added -eq 0) {
        Write-OK "Schema is up to date (all $($expectedFields.Count) fields present)"
    } else {
        Write-OK "$added new field(s) added"
    }
}

function Update-FunctionCode {
    param([hashtable]$Config)
    Write-Host "`n────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  Function App Code Deployment" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan

    Ensure-AzureConnected -Config $Config
    Ensure-PnPConnected -Config $Config

    $rg = $Config["Azure"]["ResourceGroup"]
    $funcName = $Config["Azure"]["FunctionAppName"]
    $siteUrl = $Config["SharePoint"]["SiteUrl"]
    $groupId = $Config["Security"]["MFAGroupId"]
    $listTitle = $Config["SharePoint"]["ListTitle"]
    if ([string]::IsNullOrWhiteSpace($listTitle)) { $listTitle = "MFA Onboarding" }

    # Get list ID from SharePoint
    Write-Step "Getting SharePoint List ID..."
    $list = Get-PnPList -Identity $listTitle
    $listId = $list.Id.ToString()
    Write-OK "List ID: $listId"

    # Extract site name from URL
    $siteName = ($siteUrl -split '/sites/')[-1].TrimEnd('/')

    # Package function code
    Write-Step "Packaging function code..."
    $functionCodePath = Join-Path $PSScriptRoot "function-code"
    $zipPath = Join-Path $PSScriptRoot "function-deploy.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path "$functionCodePath\*" -DestinationPath $zipPath
    Write-OK "Created deployment package"

    # Deploy
    Write-Step "Deploying to $funcName..."
    az functionapp deployment source config-zip `
        --resource-group $rg `
        --name $funcName `
        --src $zipPath 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) { throw "Function App deployment failed" }
    Write-OK "Code deployed"

    # Remove temp zip
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # Update env vars
    Write-Step "Updating environment variables..."
    $logicAppTriggerUrl = $Config["LogicApp"]["TriggerUrl"]
    if ([string]::IsNullOrWhiteSpace($logicAppTriggerUrl)) { $logicAppTriggerUrl = "NOT_SET_YET" }

    az functionapp config appsettings set `
        --resource-group $rg `
        --name $funcName `
        --settings `
            "SHAREPOINT_SITE_URL=$siteUrl" `
            "SHAREPOINT_LIST_ID=$listId" `
            "SHAREPOINT_SITE_NAME=$siteName" `
            "MFA_GROUP_ID=$groupId" `
            "LOGIC_APP_TRIGGER_URL=$logicAppTriggerUrl" 2>&1 | Out-Null
    Write-OK "Environment variables set"

    # Restart
    Write-Step "Restarting Function App..."
    az functionapp restart --resource-group $rg --name $funcName 2>&1 | Out-Null
    Write-OK "Function App restarted"

    # Save list ID back to config
    Set-IniValue -Path $configFile -Section "SharePoint" -Key "ListId" -Value $listId
}

function Update-LogicApp {
    param([hashtable]$Config)
    Write-Host "`n────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  Logic App Redeployment" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan

    # Delegate to the existing 06b script which handles all placeholder replacement
    Write-Step "Running Logic App redeploy script..."
    $script06b = Join-Path $PSScriptRoot "06b-Redeploy-Logic-App-Only.ps1"
    if (-not (Test-Path $script06b)) {
        throw "06b-Redeploy-Logic-App-Only.ps1 not found"
    }
    & $script06b
    if ($LASTEXITCODE -ne 0) { throw "Logic App redeployment failed" }
}

function Update-Branding {
    param([hashtable]$Config)
    Write-Host "`n────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  Branding & Email Configuration" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan

    Write-Host "`n  Current branding settings:" -ForegroundColor Gray
    $logoUrl = if ($Config.ContainsKey("Branding")) { $Config["Branding"]["LogoUrl"] } else { "" }
    $companyName = if ($Config.ContainsKey("Branding")) { $Config["Branding"]["CompanyName"] } else { "" }
    $supportTeam = if ($Config.ContainsKey("Branding")) { $Config["Branding"]["SupportTeam"] } else { "" }
    $supportEmail = if ($Config.ContainsKey("Branding")) { $Config["Branding"]["SupportEmail"] } else { "" }

    Write-Host "    Logo URL:      $(if ($logoUrl) { $logoUrl } else { '(none)' })" -ForegroundColor Gray
    Write-Host "    Company Name:  $(if ($companyName) { $companyName } else { '(none)' })" -ForegroundColor Gray
    Write-Host "    Support Team:  $(if ($supportTeam) { $supportTeam } else { 'IT Security Team' })" -ForegroundColor Gray
    Write-Host "    Support Email: $(if ($supportEmail) { $supportEmail } else { '(uses mailbox)' })" -ForegroundColor Gray

    Write-Host "`n  Enter new values (press Enter to keep current):" -ForegroundColor Yellow

    $newLogo = Read-Host "    Logo URL [$logoUrl]"
    if (-not [string]::IsNullOrWhiteSpace($newLogo)) {
        Set-IniValue -Path $configFile -Section "Branding" -Key "LogoUrl" -Value $newLogo
        Write-OK "Logo URL updated"
    }

    $newCompany = Read-Host "    Company Name [$companyName]"
    if (-not [string]::IsNullOrWhiteSpace($newCompany)) {
        Set-IniValue -Path $configFile -Section "Branding" -Key "CompanyName" -Value $newCompany
        Write-OK "Company Name updated"
    }

    $newTeam = Read-Host "    Support Team [$supportTeam]"
    if (-not [string]::IsNullOrWhiteSpace($newTeam)) {
        Set-IniValue -Path $configFile -Section "Branding" -Key "SupportTeam" -Value $newTeam
        Write-OK "Support Team updated"
    }

    $newEmail = Read-Host "    Support Email [$supportEmail]"
    if (-not [string]::IsNullOrWhiteSpace($newEmail)) {
        Set-IniValue -Path $configFile -Section "Branding" -Key "SupportEmail" -Value $newEmail
        Write-OK "Support Email updated"
    }

    $recurrence = $Config["LogicApp"]["RecurrenceHours"]
    $newRecurrence = Read-Host "    Check frequency in hours [$recurrence]"
    if (-not [string]::IsNullOrWhiteSpace($newRecurrence)) {
        Set-IniValue -Path $configFile -Section "LogicApp" -Key "RecurrenceHours" -Value $newRecurrence
        Write-OK "Recurrence updated to every $newRecurrence hour(s)"
    }

    # Offer to redeploy Logic App with new branding
    $deploy = Read-Host "`n  Redeploy Logic App with updated branding? (Y/N)"
    if ($deploy -match '^[Yy]') {
        Update-LogicApp -Config (Get-IniContent -Path $configFile)
    } else {
        Write-Warn "Branding saved to config but NOT deployed yet. Run with -LogicApp to deploy."
    }
}

function Update-Permissions {
    param([hashtable]$Config)
    Write-Host "`n────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  Permissions Update" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan

    Ensure-AzureConnected -Config $Config

    Write-Host "
  What would you like to update?

    [1] Fix Function App Graph permissions (User.Read.All, Group.ReadWrite.All)
    [2] Fix Logic App API connection permissions
    [3] Add delegate to shared mailbox
    [4] Add user to Upload Portal app registration
    [5] All of the above
    [0] Back
" -ForegroundColor White

    $choice = Read-Host "  Select option"

    switch ($choice) {
        "1" {
            Write-Step "Running Graph permissions fix..."
            & "$PSScriptRoot\Fix-Graph-Permissions.ps1"
        }
        "2" {
            Write-Step "Running Logic App permissions check..."
            & "$PSScriptRoot\Check-LogicApp-Permissions.ps1" -AddPermissions
        }
        "3" {
            $delegate = Read-Host "  Enter delegate email address"
            if (-not [string]::IsNullOrWhiteSpace($delegate)) {
                $mailbox = $Config["Email"]["NoReplyMailbox"]
                Write-Step "Adding $delegate to $mailbox..."
                try {
                    Connect-ExchangeOnline -ShowBanner:$false
                    Add-MailboxPermission -Identity $mailbox -User $delegate -AccessRights FullAccess -AutoMapping $true -ErrorAction Stop | Out-Null
                    Add-RecipientPermission -Identity $mailbox -Trustee $delegate -AccessRights SendAs -Confirm:$false -ErrorAction Stop | Out-Null
                    Write-OK "$delegate added with FullAccess and SendAs"
                    Disconnect-ExchangeOnline -Confirm:$false
                } catch {
                    Write-Fail "Failed: $($_.Exception.Message)"
                }
            }
        }
        "4" {
            Write-Step "Adding redirect URI for Upload Portal..."
            $portalAppName = $Config["UploadPortal"]["AppRegName"]
            $newUri = Read-Host "  Enter new redirect URI (e.g., https://newsite.z33.web.core.windows.net/upload-portal.html)"
            if (-not [string]::IsNullOrWhiteSpace($newUri) -and -not [string]::IsNullOrWhiteSpace($portalAppName)) {
                try {
                    $app = Get-AzADApplication -DisplayName $portalAppName
                    $existing = $app.Spa.RedirectUri
                    if ($newUri -notin $existing) {
                        $existing += $newUri
                        Update-AzADApplication -ObjectId $app.Id -SPARedirectUri $existing
                        Write-OK "Added redirect URI: $newUri"
                    } else {
                        Write-Skip "URI already registered"
                    }
                } catch {
                    Write-Fail "Failed: $($_.Exception.Message)"
                }
            }
        }
        "5" {
            Write-Step "Running all permission fixes..."
            & "$PSScriptRoot\Fix-Graph-Permissions.ps1"
            & "$PSScriptRoot\Check-LogicApp-Permissions.ps1" -AddPermissions
            Write-OK "All permission scripts completed"
        }
        default { return }
    }
}

function Invoke-BackfillTokens {
    param([hashtable]$Config)
    Write-Host "`n────────────────────────────────────────" -ForegroundColor DarkCyan
    Write-Host "  Backfill Tracking Tokens" -ForegroundColor Cyan
    Write-Host "────────────────────────────────────────" -ForegroundColor DarkCyan

    Ensure-PnPConnected -Config $Config
    $listTitle = $Config["SharePoint"]["ListTitle"]
    if ([string]::IsNullOrWhiteSpace($listTitle)) { $listTitle = "MFA Onboarding" }

    Write-Step "Querying users without tracking tokens..."
    
    # Get all list items
    $items = Get-PnPListItem -List $listTitle -PageSize 500

    $needsToken = $items | Where-Object { [string]::IsNullOrWhiteSpace($_.FieldValues["TrackingToken"]) }
    $total = @($items).Count
    $missing = @($needsToken).Count

    if ($missing -eq 0) {
        Write-OK "All $total users already have tracking tokens"
        return
    }

    Write-Warn "$missing of $total users need tracking tokens"
    $confirm = Read-Host "  Generate tokens for $missing users? (Y/N)"
    if ($confirm -notmatch '^[Yy]') { return }

    $updated = 0
    foreach ($item in $needsToken) {
        $token = [guid]::NewGuid().ToString()
        Set-PnPListItem -List $listTitle -Identity $item.Id -Values @{ "TrackingToken" = $token } | Out-Null
        $updated++
        if ($updated % 50 -eq 0) { Write-Host "    Processed $updated / $missing..." -ForegroundColor Gray }
    }
    Write-OK "Generated tracking tokens for $updated users"
}

# ============================================================
# MAIN
# ============================================================

# Banner
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MFA Onboarding - Update Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Validate config exists
if (-not (Test-Path $configFile)) {
    Write-Fail "Configuration file not found: $configFile"
    Write-Host "  Run a full deployment first before using the update tool." -ForegroundColor Yellow
    exit 1
}

$config = Get-IniContent -Path $configFile

# Determine which updates to run
$anySwitch = $UpdateAll -or $FunctionCode -or $LogicApp -or $Branding -or $Permissions -or $SharePointSchema -or $BackfillTokens

if (-not $anySwitch) {
    # Show interactive menu
    Write-Host "
  Choose an update option:

    [1] Update All              - Full update (schema + functions + Logic App)
    [2] Function Code           - Redeploy Azure Functions only
    [3] Logic App               - Redeploy Logic App workflow only
    [4] Branding / Emails       - Change logo, company name, email wording
    [5] Permissions             - Fix or add user permissions
    [6] SharePoint Schema       - Add any missing list fields
    [7] Backfill Tokens         - Generate tracking tokens for existing users
    [0] Exit
" -ForegroundColor White

    $choice = Read-Host "  Select option"

    switch ($choice) {
        "1" { $UpdateAll = $true }
        "2" { $FunctionCode = $true }
        "3" { $LogicApp = $true }
        "4" { $Branding = $true }
        "5" { $Permissions = $true }
        "6" { $SharePointSchema = $true }
        "7" { $BackfillTokens = $true }
        default { Write-Host "`n  Exiting.`n" -ForegroundColor Gray; exit 0 }
    }
}

try {
    if ($UpdateAll) {
        Update-SharePointSchema -Config $config
        Invoke-BackfillTokens -Config $config
        Update-FunctionCode -Config $config
        Update-LogicApp -Config $config
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  ✓ All Updates Applied Successfully!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green
    }
    else {
        if ($SharePointSchema) { Update-SharePointSchema -Config $config }
        if ($BackfillTokens)   { Invoke-BackfillTokens -Config $config }
        if ($FunctionCode)     { Update-FunctionCode -Config $config }
        if ($LogicApp)         { Update-LogicApp -Config $config }
        if ($Branding)         { Update-Branding -Config $config }
        if ($Permissions)      { Update-Permissions -Config $config }

        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "  ✓ Update Complete!" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Green
    }
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
