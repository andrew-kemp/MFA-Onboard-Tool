# Resume Deployment Guide

## Overview

The deployment process supports full **resume functionality**. Progress is tracked after each step in `logs/deployment-state.json`, so if a step fails or the script is interrupted, you can pick up exactly where you left off.

---

## Step Numbers

| Step | Script | Description |
|------|--------|-------------|
| 1 | `01-Install-Prerequisites.ps1` | Install required PowerShell modules |
| 2 | `02-Provision-SharePoint.ps1` | Create SharePoint site, list, and columns |
| 3 | `03-Create-Shared-Mailbox.ps1` | Create shared mailbox and app registration |
| 4 | `04-Create-Azure-Resources.ps1` | Create Azure resources (Function App, etc.) |
| 5 | `05-Configure-Function-App.ps1` | Deploy function code and configure settings |
| 6 | `06-Deploy-Logic-App.ps1` | Deploy invitation Logic App workflow |
| 7 | `07-Deploy-Upload-Portal1.ps1` | Register and deploy the upload portal |
| 8 | `08-Deploy-Email-Reports.ps1` | Deploy email reports Logic App |

---

## How to Resume

### Option A: Via Setup.ps1 (Recommended)

```powershell
.\Setup.ps1
# Choose option [1] Run Full Deployment
# The script automatically detects the last completed step and resumes
```

### Option B: Via Run-Complete-Deployment-Master.ps1

```powershell
.\Run-Complete-Deployment-Master.ps1
# Enter the step number to resume from when prompted
```

### Option C: Run Individual Scripts

```powershell
# Run just the specific step that failed
.\05-Configure-Function-App.ps1
```

Each script reads its configuration from `mfa-config.ini` and is idempotent — safe to re-run without creating duplicate resources.

---

## State File

Progress is tracked in `logs/deployment-state.json`:

```json
{
  "LastCompletedStep": 5,
  "LastRunTimestamp": "2025-01-15T14:30:00",
  "DeploymentId": "abc123"
}
```

Delete this file to force a full re-deployment from step 1.

---

## Common Resume Scenarios

### Script failed mid-step
Re-run the same script. All scripts check for existing resources before creating new ones.

### Need to change configuration
Edit `mfa-config.ini`, then re-run from the step that uses that configuration. See the [README](README.md) for which INI sections each script reads.

### Azure session expired
Re-authenticate with `Connect-AzAccount`, then re-run the failed step.

### Need to start completely fresh
Delete `logs/deployment-state.json` and `mfa-config.ini`, then run `Setup.ps1`.
