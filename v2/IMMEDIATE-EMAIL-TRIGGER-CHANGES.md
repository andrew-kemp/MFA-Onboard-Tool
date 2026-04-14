# Immediate Email Trigger - Implementation Summary

## Overview
Modified the MFA onboarding system to send invitation emails immediately after users are uploaded, instead of waiting for the scheduled Logic App run (every 12 hours).

## How It Works
1. **User uploads via portal** (CSV or manual entry)
2. **upload-users Function** processes users and adds them to SharePoint
3. **Function triggers Logic App** via HTTP POST immediately
4. **Logic App sends emails** to all pending users right away
5. **Scheduled backup** runs every 12 hours to catch any missed users

## Files Modified

### 1. invite-orchestrator-fixed.json
**Change**: Added HTTP trigger to Logic App workflow

**Location**: Line 4-15 (triggers section)

**Details**:
- Added `Manual_HTTP` trigger alongside existing `Recurrence` trigger
- Accepts JSON payload with: `batchId`, `usersAdded`, `triggerTime`
- Logic App can now be triggered both on-demand AND on schedule

```json
"triggers": {
    "Manual_HTTP": {
        "type": "Request",
        "kind": "Http",
        "inputs": {
            "schema": {
                "type": "object",
                "properties": {
                    "batchId": {"type": "string"},
                    "usersAdded": {"type": "integer"},
                    "triggerTime": {"type": "string"}
                }
            }
        }
    },
    "Recurrence": {
        "type": "Recurrence",
        "recurrence": {
            "interval": 12,
            "frequency": "Hour"
        }
    }
}
```

### 2. 06-Deploy-Logic-App.ps1
**Changes**: 
- Added `Set-IniValue` function for saving configuration
- Retrieves HTTP trigger URL after deployment
- Saves trigger URL to mfa-config.ini
- Updates Function App environment variable automatically

**New Code** (after line 373):
```powershell
# Get HTTP Trigger URL
Write-Host "`nRetrieving Logic App HTTP trigger URL..." -ForegroundColor Yellow
Start-Sleep -Seconds 5  # Give Azure time to finalize deployment

try {
    $triggerUrl = az rest --method POST `
        --uri "https://management.azure.com/.../triggers/Manual_HTTP/listCallbackUrl?api-version=2016-06-01" `
        --query "value" -o tsv 2>$null
    
    if (-not [string]::IsNullOrWhiteSpace($triggerUrl)) {
        Write-Host "✓ HTTP Trigger URL retrieved" -ForegroundColor Green
        
        # Save to INI file
        Set-IniValue -Path $configFile -Section "LogicApp" -Key "TriggerUrl" -Value $triggerUrl
        
        # Update Function App environment variable
        az functionapp config appsettings set `
            --resource-group $resourceGroup `
            --name $functionAppName `
            --settings "LOGIC_APP_TRIGGER_URL=$triggerUrl" | Out-Null
        
        Write-Host "✓ Function App updated with trigger URL" -ForegroundColor Green
    }
}
catch {
    Write-Host "⚠ Failed to get trigger URL" -ForegroundColor Yellow
}
```

### 3. function-code/upload-users/run.ps1
**Change**: Added Logic App trigger call after successful upload

**Location**: After "Upload complete" message (around line 180)

**Details**:
- Reads `LOGIC_APP_TRIGGER_URL` from environment variables
- Makes HTTP POST to Logic App with batch details
- Non-critical operation (warns if fails, continues anyway)
- Adds `logicAppTriggered: true/false` to response

```powershell
# Trigger Logic App to send invitations immediately
$logicAppUrl = $env:LOGIC_APP_TRIGGER_URL
if (-not [string]::IsNullOrWhiteSpace($logicAppUrl) -and $logicAppUrl -ne "NOT_SET_YET") {
    Write-Host "Triggering Logic App to send invitations..." -ForegroundColor Yellow
    try {
        $triggerBody = @{
            batchId = $batchId
            usersAdded = $results.added.Count
            triggerTime = (Get-Date).ToString("o")
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $logicAppUrl -Method Post -Body $triggerBody `
            -ContentType "application/json" -TimeoutSec 5 | Out-Null
        
        Write-Host "✓ Logic App triggered successfully" -ForegroundColor Green
        $results.logicAppTriggered = $true
    }
    catch {
        Write-Host "⚠ Failed to trigger Logic App: $($_.Exception.Message)" -ForegroundColor Yellow
        $results.logicAppTriggered = $false
    }
}
```

### 4. 05-Configure-Function-App.ps1
**Change**: Added `LOGIC_APP_TRIGGER_URL` environment variable

**Location**: Line 165 (in environment variable configuration)

**Details**:
- Reads from `config["LogicApp"]["TriggerUrl"]`
- Sets to "NOT_SET_YET" if not available (will be updated by script 06)
- Includes logging to show trigger URL status

```powershell
$logicAppTriggerUrl = if ($config["LogicApp"] -and $config["LogicApp"]["TriggerUrl"]) {
    $config["LogicApp"]["TriggerUrl"]
} else {
    "NOT_SET_YET"
}
Write-Host "  Logic App Trigger URL: $(if ($logicAppTriggerUrl -eq 'NOT_SET_YET') { 'Will be set by script 06' } else { 'Configured' })" -ForegroundColor Gray
```

## Configuration File Update
The `mfa-config.ini` file now includes:

```ini
[LogicApp]
TriggerUrl = https://{region}.logic.azure.com:443/workflows/{guid}/triggers/Manual_HTTP/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2FManual_HTTP%2Frun&sv=1.0&sig={signature}
```

This is automatically populated by script 06 after Logic App deployment.

## Deployment Order
The deployment order ensures everything is configured correctly:

1. **Script 05** (Configure Function App): Sets `LOGIC_APP_TRIGGER_URL` to "NOT_SET_YET"
2. **Script 06** (Deploy Logic App): 
   - Deploys Logic App with HTTP trigger
   - Retrieves trigger URL
   - Saves to INI file
   - Updates Function App environment variable with actual URL
3. **Function App**: Now has the real trigger URL and can call Logic App immediately

## Testing
After deployment:
1. Upload users via the portal (CSV or manual)
2. Check Function App response - should show `"logicAppTriggered": true`
3. Check user emails - invitations should arrive within 1-2 minutes
4. Scheduled backup still runs every 12 hours as safety net

## Fallback Behavior
- If HTTP trigger URL is not set or is "NOT_SET_YET", function continues without error
- If HTTP call fails, function logs warning but upload still succeeds
- Scheduled Logic App run (every 12 hours) will catch any users that didn't get immediate emails

## Benefits
- **Immediate delivery**: Users get invitation emails within 1-2 minutes of upload
- **Better UX**: No waiting up to 12 hours for invitations
- **Redundancy**: Scheduled trigger provides backup if HTTP trigger fails
- **Non-blocking**: Failed triggers don't prevent user upload from succeeding
- **Flexible**: Can be triggered manually, on-demand, or on schedule
