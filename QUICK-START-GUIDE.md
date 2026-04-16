# Quick Start Guide

Get up and running with the MFA Onboarding Tool in minutes.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **PowerShell 7+** | [Download PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows) |
| **Azure CLI** | [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows) |
| **Admin roles** | Global Admin (or Privileged Role Admin), SharePoint Admin, Exchange Admin, Azure Subscription Owner/Contributor |
| **Licensing** | Microsoft 365 E3/E5 or Business Premium, Azure subscription |

---

## Option A: One-Line Bootstrap (Recommended)

Open PowerShell 7 and run:

```powershell
irm https://raw.githubusercontent.com/andrew-kemp/MFA-Onboard-Tool/main/v2/Get-MFAOnboarder.ps1 -OutFile Get-MFAOnboarder.ps1; .\Get-MFAOnboarder.ps1
```

This downloads the tool, asks for an install folder, and launches `Setup.ps1`.

## Option B: Clone from GitHub

```powershell
git clone https://github.com/andrew-kemp/MFA-Onboard-Tool.git
cd MFA-Onboard-Tool/v2
.\Setup.ps1
```

---

## First-Time Deployment

When `Setup.ps1` detects a new install, select **[1] New deployment**. This runs 8 scripts in sequence:

| Step | Script | What Happens |
|------|--------|-------------|
| 01 | Install Prerequisites | Installs PowerShell modules, connects to Azure/M365, collects configuration |
| 02 | Provision SharePoint | Creates site, list (24 columns), app registration with certificate |
| 03 | Create Shared Mailbox | Creates mailbox, grants delegate access |
| 04 | Create Azure Resources | Resource Group, Storage, Function App, App Insights, Managed Identity |
| 05 | Configure Function App | Deploys 4 function endpoints, sets environment variables |
| 06 | Deploy Logic App | Creates workflow with email automation, reminders, escalation |
| 07 | Deploy Upload Portal | Static website with CSV upload, manual entry, and reporting |
| 08 | Deploy Email Reports | Scheduled email reporting Logic App |

Each script reads from `mfa-config.ini` and prompts for any missing values. Post-deployment scripts automatically fix Graph API permissions and Logic App API connections.

**Have these ready before starting:**
- Your tenant domain (e.g., `contoso.onmicrosoft.com`)
- Azure subscription ID
- Desired names for: SharePoint site, shared mailbox, Function App, resource group
- Company branding: logo URL, company name, support team name/email

---

## After Deployment

### Test the Setup

1. **Upload a test user:**
   - Open the portal URL (shown after Script 07 completes)
   - Log in with your admin account
   - Go to the **CSV Upload** tab
   - Upload the included `Test-Users.csv` or enter a test email in **Manual Entry**

2. **Verify the Logic App:**
   - Azure Portal → Logic App → Overview → **Run Trigger** → Recurrence
   - Wait for the run to complete — check run history for success
   - The test user should receive a branded invitation email

3. **Click the enrolment link:**
   - Click the "Set Up MFA Now" button in the email
   - You should see a branded "MFA Enrolment Started" page
   - Check the SharePoint list — `ClickedLinkDate` and `InGroup` should be updated

4. **Check reports:**
   - Go to the **Reports** tab in the upload portal
   - Click **Refresh Reports**
   - You should see the test user in the dashboard

### Key URLs After Deployment

All URLs are saved in `mfa-config.ini` and displayed after deployment:

| Resource | Where to Find |
|----------|--------------|
| Upload Portal | Storage Account → Static website → Primary endpoint |
| Function App | `https://<func-name>.azurewebsites.net` |
| Logic App | Azure Portal → Logic App → Overview |
| SharePoint List | `[SharePoint].SiteUrl` → Lists → MFA Onboarding |

---

## Day-to-Day Operations

### Uploading Users

**CSV Upload** (bulk):
1. Prepare a CSV with a column named `UPN`, `UserPrincipalName`, or `Email`
2. Open the portal → CSV Upload tab → Drag/drop or browse for the file
3. Review the preview, optionally enter a Batch ID
4. Click Upload → Review results

**Manual Entry** (individual):
1. Open the portal → Manual Entry tab
2. Enter email addresses (one per line or comma-separated)
3. Click Submit

### Monitoring Progress

- **Portal Reports tab**: Real-time dashboards, batch filtering, CSV export
- **Logic App run history**: Azure Portal → Logic App → Runs history
- **Application Insights**: Full telemetry for function calls
- **SharePoint list**: Direct view of all user statuses and dates

### Updating the Tool

```powershell
.\Setup.ps1
# Select [2] Pull latest scripts + update
```

Or for specific updates:
```powershell
.\Update-Deployment.ps1 -FunctionCode    # Redeploy functions only
.\Update-Deployment.ps1 -LogicApp         # Redeploy Logic App only
.\Update-Deployment.ps1 -Branding         # Change branding / email settings
.\Update-Deployment.ps1 -SharePointSchema # Add any missing columns
```

---

## Resuming a Failed Deployment

If deployment is interrupted, just run `Setup.ps1` again and select **[5] Resume previous install**. It picks up from the last completed step.

Or directly:
```powershell
.\Run-Complete-Deployment-Master.ps1 -Resume
```

---

## Next Steps

- [README.md](README.md) — Full documentation with architecture, configuration, and security details
- [WHATS-NEW.md](WHATS-NEW.md) — Complete list of v2 features
- [V2-ROADMAP.md](V2-ROADMAP.md) — Planned future features
- [docs.andykemp.com](https://docs.andykemp.com) — Online documentation
