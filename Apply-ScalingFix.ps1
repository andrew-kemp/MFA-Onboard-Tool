# Apply-ScalingFix.ps1
# Applies scaling fixes to an existing MFA Onboarding deployment:
#   - Logic App: pagination, throttle limit, smart 24h skip filter
#   - Function App: paginated duplicate-detection on upload
#
# Run from the folder where mfa-config.ini lives.

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
            $name  = $matches[1]
            $value = $matches[2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

try {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  MFA Onboarding - Apply Scaling Fix" -ForegroundColor Cyan
    Write-Host "============================================`n" -ForegroundColor Cyan

    if (-not (Test-Path $configFile)) {
        throw "Config file not found: $configFile`nRun this script from the deployment folder."
    }

    $config = Get-IniContent -Path $configFile

    $tenantId        = $config["Tenant"]["TenantId"]
    $subscriptionId  = $config["Tenant"]["SubscriptionId"]
    $resourceGroup   = $config["Azure"]["ResourceGroup"]
    $region          = $config["Azure"]["Region"]
    $logicAppName    = $config["LogicApp"]["LogicAppName"]
    $functionAppName = $config["Azure"]["FunctionAppName"]
    $recurrenceHours = $config["LogicApp"]["RecurrenceHours"]
    if ([string]::IsNullOrWhiteSpace($recurrenceHours)) { $recurrenceHours = "12" }
    $siteUrl         = $config["SharePoint"]["SiteUrl"]
    $listId          = $config["SharePoint"]["ListId"]
    $noReplyMailbox  = $config["Email"]["NoReplyMailbox"]
    $mfaGroupId      = $config["Security"]["MFAGroupId"]

    Write-Host "Configuration:" -ForegroundColor Gray
    Write-Host "  Resource Group : $resourceGroup"   -ForegroundColor Gray
    Write-Host "  Logic App      : $logicAppName"    -ForegroundColor Gray
    Write-Host "  Function App   : $functionAppName" -ForegroundColor Gray
    Write-Host "  SharePoint     : $siteUrl`n"       -ForegroundColor Gray

    # ── Azure connection ──────────────────────────────────────────────────────
    Write-Host "Connecting to Azure..." -ForegroundColor Yellow
    $azContext = Get-AzContext
    if ($null -eq $azContext -or $azContext.Tenant.Id -ne $tenantId) {
        if (-not [string]::IsNullOrWhiteSpace($tenantId)) {
            Connect-AzAccount -TenantId $tenantId
        } else {
            Connect-AzAccount
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($subscriptionId)) {
        Set-AzContext -SubscriptionId $subscriptionId | Out-Null
    }
    $azContext = Get-AzContext
    Write-Host "✓ Connected: $($azContext.Account.Id)" -ForegroundColor Green
    Write-Host "  Tenant      : $($azContext.Tenant.Id)" -ForegroundColor Gray
    Write-Host "  Subscription: $($azContext.Subscription.Name)`n" -ForegroundColor Gray

    # ── Azure CLI login check ─────────────────────────────────────────────────
    Write-Host "Checking Azure CLI..." -ForegroundColor Yellow
    $account = az account show 2>$null | ConvertFrom-Json
    $needsLogin = (-not $account) -or ($account.tenantId -ne $tenantId)
    if ($needsLogin) {
        az logout 2>&1 | Out-Null
        az login --tenant $tenantId
        az account set --subscription $subscriptionId
    } else {
        az account set --subscription $subscriptionId | Out-Null
    }
    Write-Host "✓ Azure CLI ready`n" -ForegroundColor Green

    # ════════════════════════════════════════════════════════════════════════════
    # PART 1 — Redeploy Logic App with scaling fixes
    # ════════════════════════════════════════════════════════════════════════════
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host "PART 1: Redeploying Logic App" -ForegroundColor Cyan
    Write-Host "--------------------------------------------`n" -ForegroundColor Cyan

    $logicAppJsonPath = Join-Path $PSScriptRoot "invite-orchestrator-TEMPLATE.json"
    if (-not (Test-Path $logicAppJsonPath)) {
        throw "Logic App template not found: $logicAppJsonPath"
    }

    Write-Host "Reading template..." -ForegroundColor Yellow
    $logicAppJsonRaw = Get-Content $logicAppJsonPath -Raw -Encoding UTF8
    if ($logicAppJsonRaw[0] -eq [char]0xFEFF) {
        $logicAppJsonRaw = $logicAppJsonRaw.Substring(1)
    }

    # Branding
    $logoUrl     = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("LogoUrl"))      { $config["Branding"]["LogoUrl"] }      else { "" }
    $companyName = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("CompanyName"))  { $config["Branding"]["CompanyName"] }  else { "" }
    $supportTeam = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("SupportTeam")) { $config["Branding"]["SupportTeam"] } else { "IT Security Team" }
    $supportEmail = if ($config.ContainsKey("Branding") -and $config["Branding"].ContainsKey("SupportEmail")) { $config["Branding"]["SupportEmail"] } else { $noReplyMailbox }

    Write-Host "Substituting placeholders..." -ForegroundColor Yellow

    $logicAppJsonRaw = $logicAppJsonRaw.Replace("RECURRENCE_HOURS_PLACEHOLDER", $recurrenceHours)
    $functionUrl  = "https://$functionAppName.azurewebsites.net/api/track-mfa-click"
    $trackOpenUrl = "https://$functionAppName.azurewebsites.net/api/track-open"
    $resendUrl    = "https://$functionAppName.azurewebsites.net/api/resend"
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_FUNCTION_URL",          $functionUrl)
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_TRACK_OPEN_URL",        $trackOpenUrl)
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_RESEND_URL",            $resendUrl)
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_SHAREPOINT_SITE_URL",   $siteUrl)
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_GROUP_ID",              $mfaGroupId)
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_LIST_ID",               $listId)
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_EMAIL",                 $noReplyMailbox)

    $emailSubject    = if ($config.ContainsKey("Email") -and $config["Email"].ContainsKey("EmailSubject")    -and -not [string]::IsNullOrWhiteSpace($config["Email"]["EmailSubject"]))    { $config["Email"]["EmailSubject"] }    else { "Action Required: Set Up Multi-Factor Authentication (MFA)" }
    $reminderSubject = if ($config.ContainsKey("Email") -and $config["Email"].ContainsKey("ReminderSubject") -and -not [string]::IsNullOrWhiteSpace($config["Email"]["ReminderSubject"])) { $config["Email"]["ReminderSubject"] } else { "Reminder #@{item()?['ReminderCount']}: MFA Setup Still Pending" }
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_SUBJECT",          $emailSubject)
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_REMINDER_SUBJECT", $reminderSubject)

    if ([string]::IsNullOrWhiteSpace($logoUrl)) {
        $logicAppJsonRaw = $logicAppJsonRaw.Replace("\u003cdiv class=\u0027logo-header\u0027\u003e\u003cimg src=\u0027PLACEHOLDER_LOGO_URL\u0027 alt=\u0027PLACEHOLDER_COMPANY_NAME\u0027/\u003e\u003c/div\u003e", "")
    } else {
        $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_LOGO_URL", $logoUrl)
    }
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_COMPANY_NAME", $(if ([string]::IsNullOrWhiteSpace($companyName)) { "Company Logo" } else { $companyName }))
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_SUPPORT_TEAM", $supportTeam)

    $mailtoLink = "mailto:" + $supportEmail + "?subject=MFA%20Setup%20Query"
    $footer = "This is an automated message from $supportTeam.\u003cbr\u003eFor questions or assistance, please contact \u003ca href=\u0027" + $mailtoLink + "\u0027 style=\u0027color:#0078D4;text-decoration:none\u0027\u003e" + $supportEmail + "\u003c/a\u003e.\u003cbr\u003e\u003cbr\u003ePlease do not reply to this email as this is an unmonitored mailbox."
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("PLACEHOLDER_FOOTER", $footer)

    $logicAppJsonRaw = $logicAppJsonRaw.Replace("https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg", "https://mysignins.microsoft.com/images/ios-app-store-button.svg")
    $logicAppJsonRaw = $logicAppJsonRaw.Replace("https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png", "https://mysignins.microsoft.com/images/google-play-button.svg")

    Write-Host "✓ Placeholders substituted`n" -ForegroundColor Green

    # Get existing connections so they are preserved
    Write-Host "Fetching existing Logic App connections..." -ForegroundColor Yellow
    $existingApp = Get-AzLogicApp -ResourceGroupName $resourceGroup -Name $logicAppName -ErrorAction Stop
    Write-Host "✓ Existing Logic App found`n" -ForegroundColor Green

    $logicAppJson = $logicAppJsonRaw | ConvertFrom-Json
    $armJson = @{
        location   = $region
        identity   = @{ type = "SystemAssigned" }
        properties = @{
            state      = "Enabled"
            definition = $logicAppJson.properties.definition
            parameters = @{
                '$connections' = @{
                    value = $existingApp.Parameters.'$connections'.Value
                }
            }
        }
    } | ConvertTo-Json -Depth 100

    Write-Host "Deploying Logic App..." -ForegroundColor Yellow
    $tempFile = [System.IO.Path]::GetTempFileName()
    $armJson | Set-Content $tempFile -Encoding UTF8

    $logicAppResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName"
    az rest --method PUT `
            --uri "https://management.azure.com$($logicAppResourceId)?api-version=2019-05-01" `
            --headers "Content-Type=application/json" `
            --body "@$tempFile" | Out-Null

    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0) { throw "Logic App deployment failed" }
    Write-Host "✓ Logic App redeployed with scaling fixes`n" -ForegroundColor Green

    Write-Host "  Fixes applied:" -ForegroundColor Gray
    Write-Host "  [1] Pagination enabled  - fetches all users (not just first 100)" -ForegroundColor Gray
    Write-Host "  [2] Active filter removed - completed users no longer re-processed" -ForegroundColor Gray
    Write-Host "  [3] Concurrency = 5    - prevents Graph API throttling (429 errors)" -ForegroundColor Gray
    Write-Host "  [4] 24h skip filter    - Sent users not re-checked until due`n" -ForegroundColor Gray

    # ════════════════════════════════════════════════════════════════════════════
    # PART 2 — Redeploy Function App with paginated duplicate detection
    # ════════════════════════════════════════════════════════════════════════════
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host "PART 2: Redeploying Function App" -ForegroundColor Cyan
    Write-Host "--------------------------------------------`n" -ForegroundColor Cyan

    $functionCodePath = Join-Path $PSScriptRoot "function-code"
    if (-not (Test-Path $functionCodePath)) {
        throw "function-code folder not found: $functionCodePath"
    }

    # Package
    Write-Host "Packaging function code..." -ForegroundColor Yellow
    $zipPath = Join-Path $PSScriptRoot "function-deploy.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path "$functionCodePath\*" -DestinationPath $zipPath -Force
    Write-Host "✓ Package created`n" -ForegroundColor Green

    # Deploy zip
    Write-Host "Deploying to Function App (this takes ~1-2 minutes)..." -ForegroundColor Yellow
    $deployResult = az functionapp deployment source config-zip `
        --resource-group $resourceGroup `
        --name $functionAppName `
        --src $zipPath `
        2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host $deployResult -ForegroundColor Red
        throw "Function App deployment failed"
    }
    Write-Host "✓ Function App code deployed`n" -ForegroundColor Green

    # Restart
    Write-Host "Restarting Function App..." -ForegroundColor Yellow
    az functionapp restart --resource-group $resourceGroup --name $functionAppName 2>&1 | Out-Null
    Write-Host "✓ Function App restarted`n" -ForegroundColor Green

    Write-Host "  Fixes applied:" -ForegroundColor Gray
    Write-Host "  [5] Paginated duplicate check - existing-user lookup handles >100 list entries`n" -ForegroundColor Gray

    # Clean up zip
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # ── Summary ───────────────────────────────────────────────────────────────
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  All scaling fixes applied successfully!" -ForegroundColor Green
    Write-Host "============================================`n" -ForegroundColor Green
    Write-Host "You can now upload your user CSV. The Logic App will:" -ForegroundColor White
    Write-Host "  - Send emails to all new Pending users immediately" -ForegroundColor Gray
    Write-Host "  - Re-check Sent users once every 24 hours" -ForegroundColor Gray
    Write-Host "  - Skip users who have already completed MFA (Active)" -ForegroundColor Gray
    Write-Host "  - Scale safely to 13,000+ users without throttling`n" -ForegroundColor Gray

    exit 0
}
catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
