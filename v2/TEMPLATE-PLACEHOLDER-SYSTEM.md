# Template Placeholder System

## Overview

The Logic App workflow is defined in `invite-orchestrator-TEMPLATE.json` using a placeholder-based approach. No values are hardcoded — all environment-specific values come from `mfa-config.ini` and are replaced at deployment time.

This makes the template fully portable across tenants and environments.

---

## Placeholders

| Placeholder | INI Source | Description |
|-------------|-----------|-------------|
| `RECURRENCE_HOURS_PLACEHOLDER` | `[LogicApp].RecurrenceHours` | Hours between Logic App runs (default: 12) |
| `PLACEHOLDER_SHAREPOINT_SITE_URL` | `[SharePoint].SiteUrl` | Full SharePoint site URL |
| `PLACEHOLDER_LIST_ID` | `[SharePoint].ListId` | SharePoint list GUID |
| `PLACEHOLDER_GROUP_ID` | `[Security].MFAGroupId` | MFA security group object ID |
| `PLACEHOLDER_EMAIL` | `[Email].NoReplyMailbox` | Shared mailbox email address |
| `PLACEHOLDER_SUBJECT` | `[Email].EmailSubject` | Initial invitation email subject |
| `PLACEHOLDER_REMINDER_SUBJECT` | `[Email].ReminderSubject` | Reminder email subject |
| `PLACEHOLDER_FUNCTION_URL` | Computed | Function App hostname (from Azure) |
| `PLACEHOLDER_TRACK_OPEN_URL` | Computed | Full `/api/track-open` endpoint URL |
| `PLACEHOLDER_RESEND_URL` | Computed | Full `/api/resend` endpoint URL |
| `PLACEHOLDER_LOGO_URL` | `[Branding].LogoUrl` | Company logo image URL |
| `PLACEHOLDER_COMPANY_NAME` | `[Branding].CompanyName` | Company name for email branding |
| `PLACEHOLDER_SUPPORT_TEAM` | `[Branding].SupportTeam` | Support team name |
| `PLACEHOLDER_FOOTER` | Computed | Generated footer from branding values |

---

## How Replacement Works

### At Deployment (Script 06)

`06-Deploy-Logic-App.ps1` reads the template, performs string replacements, and deploys the result:

```powershell
$template = Get-Content "invite-orchestrator-TEMPLATE.json" -Raw
$template = $template -replace "PLACEHOLDER_SHAREPOINT_SITE_URL", $config.SharePoint.SiteUrl
$template = $template -replace "PLACEHOLDER_LIST_ID", $config.SharePoint.ListId
# ... all 14 placeholders replaced
```

### At Redeployment

`06b-Redeploy-Logic-App-Only.ps1` performs the same replacement from current `mfa-config.ini` values. This script is called by:
- `Update-Deployment.ps1 -LogicApp`
- `Update-Deployment.ps1 -Branding` (after updating branding values in INI)
- `Update-Deployment.ps1 -UpdateAll`

---

## Adding New Placeholders

To add a new placeholder:

1. Add the placeholder text to `invite-orchestrator-TEMPLATE.json` where needed
2. Add the corresponding key to `mfa-config.ini` under the appropriate section
3. Add the replacement line to both `06-Deploy-Logic-App.ps1` and `06b-Redeploy-Logic-App-Only.ps1`
4. Update this documentation

---

## Template Location

The template file is always at: `invite-orchestrator-TEMPLATE.json` in the v2 directory.

A deployed copy of the Logic App JSON is saved to `logs/LogicApp-Deployed_TIMESTAMP.json` after each deployment for audit purposes.
