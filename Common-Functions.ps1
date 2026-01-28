# Common Functions for MFA Onboarding Deployment
# Shared utilities for logging, error handling, and reporting

# Global variables
$script:LogFile = ""
$script:StartTime = Get-Date

function Initialize-Logging {
    param(
        [string]$LogFolder = "$PSScriptRoot\logs",
        [string]$LogPrefix = "deployment"
    )
    
    # Create logs folder if it doesn't exist
    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }
    
    # Create log file with timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $script:LogFile = Join-Path $LogFolder "$LogPrefix`_$timestamp.log"
    
    Write-Log "========================================" -NoConsole
    Write-Log "MFA Onboarding Deployment Log" -NoConsole
    Write-Log "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -NoConsole
    Write-Log "========================================" -NoConsole
    Write-Log ""
    
    return $script:LogFile
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage
    }
    
    # Write to console unless suppressed
    if (-not $NoConsole) {
        switch ($Level) {
            "ERROR" { Write-Host $Message -ForegroundColor Red }
            "WARNING" { Write-Host $Message -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $Message -ForegroundColor Green }
            "INFO" { Write-Host $Message -ForegroundColor Cyan }
            default { Write-Host $Message }
        }
    }
}

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [string]$StepName,
        [int]$MaxRetries = 3,
        [switch]$Critical
    )
    
    $attempt = 0
    $success = $false
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            Write-Log "Executing: $StepName (Attempt $attempt/$MaxRetries)" -Level INFO
            & $ScriptBlock
            $success = $true
            Write-Log "✓ $StepName completed successfully" -Level SUCCESS
        }
        catch {
            Write-Log "✗ $StepName failed: $($_.Exception.Message)" -Level ERROR
            Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
            
            if ($attempt -lt $MaxRetries) {
                $retry = Read-Host "Would you like to retry? (Y/N)"
                if ($retry -notmatch '^[Yy]') {
                    if ($Critical) {
                        Write-Log "Critical step failed. Deployment cannot continue." -Level ERROR
                        throw "Critical step failed: $StepName"
                    }
                    Write-Log "Skipping $StepName and continuing..." -Level WARNING
                    return $false
                }
            }
            else {
                if ($Critical) {
                    Write-Log "Maximum retries reached for critical step. Deployment cannot continue." -Level ERROR
                    throw "Critical step failed after $MaxRetries attempts: $StepName"
                }
                Write-Log "Maximum retries reached. Skipping $StepName..." -Level WARNING
                return $false
            }
        }
    }
    
    return $success
}

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

function New-DeploymentSummary {
    param(
        [string]$ConfigFile,
        [hashtable]$StepResults,
        [string]$OutputFile
    )
    
    $config = Get-IniContent -Path $ConfigFile
    $duration = (Get-Date) - $script:StartTime
    
    $summary = @"
================================================================================
    MFA ONBOARDING DEPLOYMENT - SUMMARY REPORT
================================================================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Duration: $($duration.ToString('hh\:mm\:ss'))
Log File: $script:LogFile

================================================================================
DEPLOYMENT STATUS
================================================================================
"@

    foreach ($step in $StepResults.Keys | Sort-Object) {
        $status = if ($StepResults[$step]) { "✓ SUCCESS" } else { "✗ FAILED" }
        $color = if ($StepResults[$step]) { "Green" } else { "Red" }
        $summary += "`n$step : $status"
    }

    $summary += @"

================================================================================
CONFIGURATION
================================================================================
Tenant ID       : $($config["Tenant"]["TenantId"])
Subscription ID : $($config["Tenant"]["SubscriptionId"])
Resource Group  : $($config["Azure"]["ResourceGroup"])
Region          : $($config["Azure"]["Region"])

================================================================================
SHAREPOINT
================================================================================
Site URL        : $($config["SharePoint"]["SiteUrl"])
Site Title      : $($config["SharePoint"]["SiteTitle"])
List Title      : $($config["SharePoint"]["ListTitle"])
App Reg Name    : $($config["SharePoint"]["AppRegName"])
Client ID       : $($config["SharePoint"]["ClientId"])
Certificate     : $($config["SharePoint"]["CertificatePath"])

================================================================================
SECURITY GROUP
================================================================================
Group Name      : $($config["Security"]["MFAGroupName"])
Group ID        : $($config["Security"]["MFAGroupId"])

================================================================================
AZURE RESOURCES
================================================================================
Function App    : $($config["Azure"]["FunctionAppName"])
Storage Account : $($config["Azure"]["StorageAccountName"])
Logic App       : $($config["LogicApp"]["LogicAppName"])

Function App URL: https://$($config["Azure"]["FunctionAppName"]).azurewebsites.net

================================================================================
EMAIL CONFIGURATION
================================================================================
Shared Mailbox  : $($config["Email"]["NoReplyMailbox"])
Display Name    : $($config["Email"]["MailboxName"])
Delegate        : $($config["Email"]["MailboxDelegate"])

================================================================================
UPLOAD PORTAL
================================================================================
"@

    if ($config["Azure"]["StorageAccountName"]) {
        $storageAccountName = $config["Azure"]["StorageAccountName"]
        $portalUrl = "https://$storageAccountName.z33.web.core.windows.net/upload-portal.html"
        $summary += "`nPortal URL      : $portalUrl"
    }
    
    $summary += "`nApp Reg Name    : $($config["UploadPortal"]["AppRegName"])"
    $summary += "`nClient ID       : $($config["UploadPortal"]["ClientId"])"

    $summary += @"


================================================================================
TESTING INSTRUCTIONS
================================================================================

1. TEST UPLOAD PORTAL
   URL: https://$($config["Azure"]["StorageAccountName"]).z33.web.core.windows.net/upload-portal.html
   
   Steps:
   a) Sign in with your Microsoft 365 admin account
   b) Prepare a test CSV with format:
      UPN
      testuser@yourdomain.com
   c) Upload the CSV file
   d) Check SharePoint list for the new entry

2. TEST SHAREPOINT LIST
   URL: $($config["SharePoint"]["SiteUrl"])/Lists/$($config["SharePoint"]["ListTitle"] -replace ' ','%20')
   
   Steps:
   a) Navigate to the SharePoint site
   b) Open the "$($config["SharePoint"]["ListTitle"])" list
   c) Verify you can see uploaded users
   d) Check that columns are populated correctly

3. TEST LOGIC APP
   Location: Azure Portal > Resource Groups > $($config["Azure"]["ResourceGroup"]) > $($config["LogicApp"]["LogicAppName"])
   
   Steps:
   a) Open Logic App in Azure Portal
   b) Click "Run Trigger" > "Recurrence"
   c) Monitor run history for success
   d) Check user received invitation email

4. TEST FUNCTION APP
   Enrol Endpoint: https://$($config["Azure"]["FunctionAppName"]).azurewebsites.net/api/track-mfa-click?user=test@example.com
   Upload Endpoint: https://$($config["Azure"]["FunctionAppName"]).azurewebsites.net/api/upload-users
   
   Steps:
   a) Test enrol endpoint in browser (should redirect)
   b) Upload endpoint tested via portal

5. TEST END-TO-END WORKFLOW
   a) Upload test user via portal
   b) Wait for Logic App to send invitation (runs every 5 minutes)
   c) User clicks link in email
   d) Verify user added to security group: $($config["Security"]["MFAGroupName"])
   e) User completes MFA setup at https://aka.ms/mfasetup
   f) Check SharePoint list for status updates

================================================================================
API CONNECTIONS (If Authorization Required)
================================================================================
Navigate to: Azure Portal > Resource Groups > $($config["Azure"]["ResourceGroup"]) > API Connections

Authorize these connections:
- sharepointonline
- office365  
- azuread

For each connection:
1. Click the connection name
2. Click "Edit API connection"
3. Click "Authorize"
4. Sign in with admin account
5. Click "Save"

================================================================================
TROUBLESHOOTING
================================================================================
- Check logs: $script:LogFile
- Function App logs: Azure Portal > Function App > Monitor
- Logic App runs: Azure Portal > Logic App > Runs history
- SharePoint issues: Verify certificate and app registration permissions
- Email issues: Check shared mailbox delegate permissions

================================================================================
NEXT STEPS
================================================================================
1. Review this summary and verify all URLs are accessible
2. Test the upload portal with a test user
3. Configure Conditional Access policy for the MFA group
4. Monitor Logic App for the first few runs
5. Train administrators on using the upload portal

================================================================================
"@

    # Save to file
    $summary | Out-File -FilePath $OutputFile -Encoding UTF8
    
    # Display to console
    Write-Host $summary
    
    Write-Log "Summary report saved to: $OutputFile" -Level SUCCESS
    
    return $OutputFile
}

# Functions are available when script is dot-sourced
# Export-ModuleMember is only needed for .psm1 module files
