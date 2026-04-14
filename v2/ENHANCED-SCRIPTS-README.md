# Enhanced Deployment Scripts - Quick Reference

## What's New

### 1. Comprehensive Logging
- **All actions logged to file**: Every step is recorded with timestamps
- **Log location**: `logs\` folder with timestamped filenames
- **Log format**: `[2026-01-23 14:30:45] [INFO] Message`
- **Levels**: INFO, SUCCESS, WARNING, ERROR

### 2. Error Handling with Retry
- **Automatic retry prompts**: If a step fails, you'll be asked if you want to retry
- **Maximum 3 attempts**: Each step can be retried up to 3 times
- **Critical vs Optional**: Critical steps (01, 02, 04, 05) must succeed to continue
- **User control**: You decide whether to retry, skip, or abort

### 3. Comprehensive Summary Reports
- **Detailed deployment info**: Everything you need to know about what was deployed
- **All URLs included**: Direct links to resources, portals, and admin centers
- **Testing instructions**: Step-by-step guide on how to test each component
- **Configuration snapshot**: Summary of all settings from mfa-config.ini
- **Troubleshooting tips**: What to check if something isn't working

## New Scripts

### Common-Functions.ps1
Shared utilities used by both Part 1 and Part 2:
- `Initialize-Logging`: Sets up log file
- `Write-Log`: Logs to file and console
- `Invoke-WithRetry`: Runs a script with retry capability
- `New-DeploymentSummary`: Generates comprehensive summary report

### Create-TechnicalSummary.ps1
Standalone script that generates a comprehensive technical summary with:
- ✅ All Object IDs (App registrations, Service Principals, Groups)
- ✅ All Resource IDs (Full Azure resource paths)
- ✅ All URLs (Direct links to Azure Portal, SharePoint, etc.)
- ✅ Managed Identity Principal IDs
- ✅ API Connection details and status
- ✅ Certificate thumbprints
- ✅ Troubleshooting commands
- ✅ Backup & disaster recovery information

Can be run standalone anytime:
```powershell
.\Create-TechnicalSummary.ps1
```

### Run-Part1-Setup-Enhanced.ps1
Enhanced version of Part 1 with:
- ✅ Logging to `logs\Part1-Setup_TIMESTAMP.log`
- ✅ Retry prompts on errors
- ✅ Summary report with configuration details
- ✅ Verification steps for each resource

### Run-Part2-Deploy-Enhanced.ps1
Enhanced version of Part 2 with:
- ✅ Logging to `logs\Part2-Deploy_TIMESTAMP.log`
- ✅ Retry prompts on errors
- ✅ **Automatically captures Logic App JSON** to `logs\LogicApp-Deployed_TIMESTAMP.json`
- ✅ **Automatically generates Technical Summary** with all Object IDs and URLs
- ✅ Comprehensive summary report with ALL URLs
- ✅ Testing instructions for each component
- ✅ Troubleshooting section

## Usage

### Option 1: Use Enhanced Scripts (Recommended)
```powershell
# Part 1: Setup
.\Run-Part1-Setup-Enhanced.ps1

# Part 2: Deploy
.\Run-Part2-Deploy-Enhanced.ps1
```

### Option 2: Use Original Scripts
```powershell
# Part 1: Setup (original)
.\Run-Part1-Setup.ps1

# Part 2: Deploy (original)
.\Run-Part2-Deploy.ps1
```

## What Happens When a Step Fails

### Example Scenario
```
[2026-01-23 14:35:22] [INFO] Executing: Azure Resources Creation (Attempt 1/3)
[2026-01-23 14:35:45] [ERROR] Azure Resources Creation failed: Subscription not found
[2026-01-23 14:35:45] [ERROR] Stack trace: at line 45 in 04-Create-Azure-Resources.ps1

Would you like to retry? (Y/N): Y

[2026-01-23 14:36:10] [INFO] Executing: Azure Resources Creation (Attempt 2/3)
[2026-01-23 14:36:35] [SUCCESS] ✓ Azure Resources Creation completed successfully
```

### Your Options
- **Y (Yes)**: Retry the step immediately
- **N (No)**: 
  - If critical step → Deployment stops, fix issue manually
  - If optional step → Continue to next step

## Log Files

### Log File Naming
- Part 1: `logs\Part1-Setup_2026-01-23_143022.log`
- Part 2: `logs\Part2-Deploy_2026-01-23_150145.log`

### Log File Contents
Every log includes:
- Timestamp for each action
- Script execution details
- Error messages with stack traces
- Success confirmations
- User inputs and decisions

### Example Log Entry
```
[2026-01-23 14:30:45] [INFO] Part 1 deployment started
[2026-01-23 14:30:52] [INFO] Executing: Prerequisites & Configuration (Attempt 1/3)
[2026-01-23 14:31:15] [SUCCESS] ✓ Prerequisites & Configuration completed successfully
[2026-01-23 14:31:18] [INFO] Executing: SharePoint Site & List (Attempt 1/3)
[2026-01-23 14:32:40] [SUCCESS] ✓ SharePoint Site & List completed successfully
```

## Summary Reports

### Part 1 Summary
Saved to: `logs\Part1-Setup-Summary_TIMESTAMP.txt`

Includes:
- ✅ Deployment status for each step
- ✅ Configured tenant and subscription
- ✅ SharePoint site and list details
- ✅ Security group information
- ✅ Shared mailbox details
- ✅ Verification URLs for each resource
- ✅ Next steps

### Part 2 Summary (Comprehensive)
Saved to: `logs\DEPLOYMENT-COMPLETE-SUMMARY_TIMESTAMP.txt`

Includes **EVERYTHING**:
- ✅ All deployment statuses
- ✅ Complete configuration (tenant, subscription, resource group)
- ✅ SharePoint details with direct URLs
- ✅ Security group with Azure Portal link
- ✅ Azure resources (Function App, Storage, Logic App)
- ✅ Function App URLs for both endpoints
- ✅ Email configuration
- ✅ Upload Portal URL and credentials
- ✅ Step-by-step testing instructions for:
  - Upload Portal
  - SharePoint List
  - Logic App
  - Function App
  - End-to-end workflow
- ✅ API Connection authorization steps
- ✅ Troubleshooting tips
- ✅ Next steps

### Technical Summary (NEW!)
Saved to: `logs\TECHNICAL-SUMMARY_TIMESTAMP.txt`

**THE MOST COMPREHENSIVE TROUBLESHOOTING DOCUMENT**

Includes:
- ✅ **All Azure Resource IDs** (Full paths for automation)
- ✅ **All Object IDs** (App registrations, Service Principals, Security Groups)
- ✅ **Managed Identity Principal IDs** (Function App & Logic App)
- ✅ **All URLs** (Direct Azure Portal links, SharePoint, APIs)
- ✅ **API Connection Resource IDs and Status**
- ✅ **Certificate Thumbprints**
- ✅ **Storage Account Endpoints** (Blob, Queue, Table, File, Web)
- ✅ **Microsoft Graph API URLs** (For manual testing)
- ✅ **SharePoint REST API URLs**
- ✅ **Azure CLI Commands** (For troubleshooting)
- ✅ **PowerShell Commands** (For verification)
- ✅ **Backup & Disaster Recovery Instructions**
- ✅ **Security Notes** (Permissions, certificates, managed identities)

This file contains EVERYTHING needed for troubleshooting, automation, and reference.

### Logic App JSON (NEW!)
Saved to: `logs\LogicApp-Deployed_TIMESTAMP.json`

The **actual JSON definition** that was deployed to Azure Logic Apps.

Use this to:
- ✅ See exact workflow configuration
- ✅ Reference trigger and action settings
- ✅ Troubleshoot Logic App issues
- ✅ Redeploy if needed
- ✅ Compare deployments across tenants
- ✅ Document workflow for compliance

## Example Summary Report Structure

```
================================================================================
    MFA ONBOARDING DEPLOYMENT - SUMMARY REPORT
================================================================================
Generated: 2026-01-23 15:30:45
Duration: 01:25:30
Log File: logs\Part2-Deploy_2026-01-23_140515.log

================================================================================
DEPLOYMENT STATUS
================================================================================
Step 04: Azure Resources : ✓ SUCCESS
Step 05: Function App Configuration : ✓ SUCCESS
Step 06: Logic App Deployment : ✓ SUCCESS
Step 07: Upload Portal Deployment : ✓ SUCCESS
Fix: Function Authentication : ✓ SUCCESS
Fix: Graph Permissions : ✓ SUCCESS
Fix: Logic App Permissions : ✓ SUCCESS

================================================================================
CONFIGURATION
================================================================================
Tenant ID       : 74214193-01af-4cfe-9128-afdb4346dd3f
Subscription ID : abc123-def456-ghi789
Resource Group  : rg-mfa-onboarding
Region          : East US

================================================================================
SHAREPOINT
================================================================================
Site URL        : https://andykempdev.sharepoint.com/sites/MFAOps
...

[continues with all details, URLs, and testing instructions]
```

## Benefits

### 1. Troubleshooting Made Easy
- **Detailed logs**: Know exactly what happened and when
- **Error context**: Stack traces help identify root cause
- **Retry capability**: Fix issues and retry without starting over

### 2. Documentation
- **Deployment record**: Permanent record of what was deployed
- **Configuration snapshot**: Know exactly how everything was configured
- **Audit trail**: Timestamps and actions for compliance

### 3. Testing Guidance
- **Clear instructions**: No guessing how to test
- **Direct URLs**: Click and verify immediately
- **Expected outcomes**: Know what success looks like

### 4. Multi-Tenant Support
- **Separate logs per deployment**: Easy to track different tenants
- **Configuration comparison**: Compare summaries across tenants
- **Isolated troubleshooting**: Fix one tenant without affecting others

## Tips

### Review Logs After Deployment
Even if deployment succeeds, check logs for warnings:
```powershell
Get-Content logs\Part2-Deploy_*.log | Select-String "WARNING"
```

### Compare Deployments
```powershell
# Compare two tenant deployments
Compare-Object `
  (Get-Content logs\DEPLOYMENT-COMPLETE-SUMMARY_2026-01-23_143022.txt) `
  (Get-Content logs\DEPLOYMENT-COMPLETE-SUMMARY_2026-01-23_150145.txt)
```

### Archive Logs
```powershell
# Compress logs for long-term storage
Compress-Archive -Path logs\* -DestinationPath "deployment-archive-$(Get-Date -Format 'yyyy-MM-dd').zip"
```

## Migration from Original Scripts

The original scripts (`Run-Part1-Setup.ps1` and `Run-Part2-Deploy.ps1`) still work and are unchanged.

To use the new enhanced features:
1. Use `Run-Part1-Setup-Enhanced.ps1` instead of `Run-Part1-Setup.ps1`
2. Use `Run-Part2-Deploy-Enhanced.ps1` instead of `Run-Part2-Deploy.ps1`
3. That's it! Everything else works the same.

## Questions?

Check the summary report - it has testing instructions and troubleshooting tips!
