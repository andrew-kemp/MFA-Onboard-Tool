# Resume Deployment Guide

## Overview
The master deployment script now supports **resume functionality**, allowing you to restart from any step without re-running completed steps.

## How It Works

### State Tracking
- The script automatically saves progress after each successful step
- State is stored in: `logs\deployment-state.json`
- This tracks the last completed step number

### Step Numbers
1. Install Prerequisites
2. Provision SharePoint
3. Create Shared Mailbox
4. Create Azure Resources
5. Configure Function App
6. Deploy Logic App (Invitations)
7. Deploy Upload Portal
8. Deploy Email Reports
9. Function Authentication Fix
10. Graph Permissions Fix
11. Logic App Permissions Fix
12. Generate Final Report

## Usage Options

### Option 1: Manual Resume from Specific Step
```powershell
.\Run-Complete-Deployment-Master.ps1 -StartFromStep 7
```
This will:
- Mark steps 1-6 as completed (shown with ✓)
- Start execution from step 7 onwards

### Option 2: Automatic Resume
```powershell
.\Run-Complete-Deployment-Master.ps1 -Resume
```
This will:
- Read the last completed step from `deployment-state.json`
- Automatically resume from the next step
- Perfect if a deployment was interrupted

### Option 3: Fresh Start
```powershell
.\Run-Complete-Deployment-Master.ps1
```
or
```powershell
.\Run-Complete-Deployment-Master.ps1 -StartFromStep 1
```
This runs the complete deployment from the beginning.

## Your Current Situation

Since steps 1-6 completed successfully, you can now run:

```powershell
.\Run-Complete-Deployment-Master.ps1 -StartFromStep 7
```

This will:
1. Show steps 1-6 as completed (✓ green checkmarks)
2. Show step 7 as starting point (▶ yellow)
3. Show steps 8-12 as pending (○ gray)
4. **Check Azure authentication** before step 7
5. Prompt for `Connect-AzAccount` if needed
6. Continue with steps 7-12

## Azure Authentication

The script now automatically checks Azure authentication before Step 07:
- It verifies you're logged into the correct tenant
- If not authenticated, it prompts for interactive login with MFA
- Uses the tenant ID from `mfa-config.ini`

## Visual Indicators

When the script runs, you'll see:
- **✓** (Green) - Step already completed
- **▶** (Yellow) - Current step starting
- **○** (Gray) - Step pending
- **[SKIPPED]** (Dark Green) - Step skipped due to prior completion

## State File Location

The state file is saved at:
```
C:\MFA\MFA-Registration-main\logs\deployment-state.json
```

Content example:
```json
{
  "LastCompletedStep": 6,
  "LastUpdated": "2026-01-26 16:30:15"
}
```

## Manually Editing State (Advanced)

If you need to manually set the last completed step:

1. Edit `logs\deployment-state.json`:
```json
{
  "LastCompletedStep": 6,
  "LastUpdated": "2026-01-26 16:30:15"
}
```

2. Then run with `-Resume`:
```powershell
.\Run-Complete-Deployment-Master.ps1 -Resume
```

Or simply delete the file to start fresh:
```powershell
Remove-Item logs\deployment-state.json
```

## Logs

- **Deployment Log**: `logs\Complete-Deployment_YYYY-MM-DD_HHMMSS.log`
- **State File**: `logs\deployment-state.json`

## Examples

### Resume from Step 7 (your current need)
```powershell
cd C:\MFA\MFA-Registration-main
.\Run-Complete-Deployment-Master.ps1 -StartFromStep 7
```

### Resume after interruption
```powershell
.\Run-Complete-Deployment-Master.ps1 -Resume
```

### Run only the permission fixes (steps 9-11)
```powershell
.\Run-Complete-Deployment-Master.ps1 -StartFromStep 9
```

### Start completely fresh
```powershell
Remove-Item logs\deployment-state.json -ErrorAction SilentlyContinue
.\Run-Complete-Deployment-Master.ps1
```

## Troubleshooting

### "State file not found" when using -Resume
- This is normal if you haven't run the deployment before
- The state file is only created after the first successful step
- Solution: Use `-StartFromStep` instead

### Steps marked as skipped but need to re-run
- Edit `logs\deployment-state.json` and reduce the `LastCompletedStep` number
- Or use `-StartFromStep` with the step you want to start from
- Or delete the state file to start fresh

### Azure authentication fails
- The script will prompt you to login interactively
- It checks authentication before Step 07
- Make sure to complete MFA when prompted
- If it continues to fail, manually run:
  ```powershell
  Connect-AzAccount -TenantId <your-tenant-id>
  ```

## Next Steps for Your Deployment

To complete your deployment from step 7 onwards:

1. **Run the resume command**:
   ```powershell
   .\Run-Complete-Deployment-Master.ps1 -StartFromStep 7
   ```

2. **Watch for Azure login prompt** (step 7 requires it)

3. **Complete remaining steps** (7-12) automatically

4. **Review the final HTML report** that opens at the end
