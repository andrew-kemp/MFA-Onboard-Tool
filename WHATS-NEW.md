# What's New in v2

A complete summary of every feature, improvement, and change in v2 of the MFA Onboarding Automation Tool.

---

## New Entry Points

### Single Entry Point: `Setup.ps1`
- Replaces the old `Run-Part1-Setup.ps1` / `Run-Part2-Deploy.ps1` flow with a single script
- Auto-detects new install vs existing deployment
- Self-updating: can pull latest scripts from GitHub while preserving your config
- 6-option menu for existing installs (update, upgrade, fresh install, resume, quick fix)
- Detects and migrates configuration from pre-v2 parent directories

### Bootstrap Script: `Get-MFAOnboarder.ps1`
- One-line download-and-run installation
- Checks PowerShell 7+ prerequisite
- Downloads full repository, extracts, and launches `Setup.ps1`

### Update Tool: `Update-Deployment.ps1`
- Granular update operations via 8 CLI switches or interactive 7-option menu
- Update function code, Logic App, branding, permissions, schema independently
- Operations Group management (create, add/remove members, grant access)
- Backfill tracking tokens for pre-v2 users
- Full v2 upgrade path with `-Upgrade` switch
- Quick fix mode with `-QuickFix` (pull latest + fix permissions)

---

## New Azure Function Endpoints

### `/api/track-open` — Email Open Tracking
- Invisible 1×1 transparent GIF pixel embedded in every email
- Records `EmailOpenedDate` in SharePoint on first open only
- Fire-and-forget: tracking failures never block the pixel response
- Always returns 200 OK with valid GIF bytes

### `/api/resend` — Self-Service Resend
- GET returns a branded HTML form where users enter their email
- POST resets `InviteStatus` to Pending and clears `ReminderCount`
- **Anti-enumeration**: returns identical success message regardless of whether the user exists
- Logic App picks up reset users on its next run
- Linked in the footer of every email: "Lost your setup link?"

### Enhancements to `/api/enrol`
- **Duplicate-click protection**: If `ClickedLinkDate` is already set, returns a branded "Already Registered" page instead of re-adding to group
- **Branded HTML responses** with auto-redirect countdown for all outcomes:
  - Invalid Link (red) — missing parameters
  - Link Not Recognised (orange) — token/user not found
  - Already Registered (green) — previously clicked
  - MFA Enrolment Started (green) — success, redirects to aka.ms/mfasetup
  - Error (red) — unexpected failure
- **API detection**: Returns JSON instead of HTML for programmatic callers (based on `Accept` header / User-Agent)
- **Token-based lookup**: Uses `TrackingToken` GUID for secure, non-guessable links (falls back to UPN for legacy users)

### Enhancements to `/api/upload-users`
- **Immediate Logic App trigger**: After uploading users, attempts to trigger the Logic App immediately via HTTP; falls back to scheduled processing
- **Tracking token generation**: Each new user gets a unique GUID `TrackingToken`

---

## Upload Portal Improvements

### Drag-and-Drop CSV Upload
- Visual drag-and-drop zone (click or drag a `.csv` file)
- **Client-side validation**: Parses headers, identifies email column (`UPN`, `UserPrincipalName`, or `Email`), validates email format with regex
- **Preview table**: Shows first 10 rows with valid/invalid indicators
- **Summary**: Total valid and invalid counts before upload
- **Progress bar**: Animated upload progress
- **Results**: Stat cards (Total, Added, Updated, Skipped, Errors) with expandable error/skip details

### Reports Tab
- **Executive summary dashboard**: Total Users, MFA Active, Pending, Completion Rate (%)
- **Batch filter dropdown**: Dynamically populated from `SourceBatchId` values with per-batch user counts; filters all report sections
- **Status breakdown**: Grid cards for each status (Pending, Sent, Clicked, AddedToGroup, Active, Error, Skipped) with counts and percentages
- **Recent activity**: Last 7 days — invites sent, links clicked, added to group
- **High reminder alerts**: Red warning box highlighting users with 2+ reminders
- **Users needing attention**: List of users requiring follow-up
- **Batch performance**: Per-batch completion rates and user counts
- **CSV export**: Download all report data as `mfa-report-YYYY-MM-DD.csv` with proper escaping
- **Email report**: Compose and send an executive summary email directly from the portal

### Branded Success Landing Page
- After successful CSV upload, users see a styled success page
- Auto-redirects to the reports tab after countdown

---

## Logic App Enhancements

### Retry Policies on All Actions
- **Exponential backoff** on all 16 API-connected actions
- 3 retries with 10-second minimum interval and 1-hour maximum
- Covers: SharePoint reads/writes, Office 365 email sends, user lookups, group membership checks, Graph API calls
- Eliminates transient failures causing stuck users

### Manager Escalation
- After 2+ reminder emails without MFA completion, the user's **manager is automatically escalated**
- Manager is looked up via Microsoft Graph (`/users/{id}/manager`)
- Escalation email has a **red "Manager Action Required" header**, includes employee name, reminder count, and clear action instructions
- Records `EscalatedToManager=true` and `EscalationDate` in SharePoint
- Only escalates once per user (checks `EscalatedToManager` before sending)

### Email Open Tracking Pixel
- Every outgoing email includes an invisible `<img>` tag pointing to `/api/track-open?token={TrackingToken}`
- Stamps `EmailOpenedDate` in SharePoint on first open
- Works alongside click tracking to give full engagement visibility

### Self-Service Resend Link
- Every email footer includes a "Lost your setup link?" link pointing to `/api/resend`
- Users can request a re-send without contacting IT

### Configurable Email Subjects
- Separate `EmailSubject` and `ReminderSubject` fields in `mfa-config.ini`
- Replaced at deployment via template placeholders `PLACEHOLDER_SUBJECT` and `PLACEHOLDER_REMINDER_SUBJECT`

---

## Application Insights Integration

- **Full telemetry** for all Function App endpoints: request logging, exception tracking, performance metrics
- **Live Metrics Stream** for real-time monitoring during rollouts
- Auto-provisioned by Script 04 (`04-Create-Azure-Resources.ps1`)
- Instrumentation key and connection string saved to `mfa-config.ini`
- Set as environment variables on the Function App (`APPINSIGHTS_INSTRUMENTATIONKEY`, `APPLICATIONINSIGHTS_CONNECTION_STRING`)
- Configurable in `host.json`: sampling rates, log levels, HTTP throttling
- Request telemetry excluded from sampling for complete audit trail

---

## Infrastructure as Code (Bicep)

- New `infra/main.bicep` template defining all Azure resources:
  - Storage Account (Standard_LRS, HTTPS-only, TLS 1.2)
  - Application Insights (Web type, 90-day retention)
  - App Service Plan (Consumption Y1/Dynamic)
  - Function App (PowerShell 7.4, Managed Identity, HTTPS-only, FTPS disabled, TLS 1.2)
  - Office 365 API Connection
  - SharePoint API Connection
- `infra/main.parameters.json` for environment-specific values
- Outputs: `functionAppPrincipalId`, `functionAppHostname`, `appInsightsKey`, `appInsightsConnectionString`, connection IDs

---

## New SharePoint Columns

v2 adds these columns to the tracking list (auto-added by `Update-Deployment.ps1 -SharePointSchema`):

| Column | Type | Purpose |
|--------|------|---------|
| `TrackingToken` | Text (indexed) | Unique GUID for secure enrolment links |
| `EmailOpenedDate` | DateTime | First email open timestamp (tracking pixel) |
| `EscalatedToManager` | Boolean | Whether manager has been escalated |
| `EscalationDate` | DateTime | When the escalation email was sent |
| `ManagerUPN` | Text | Manager's email from Entra ID |
| `MFARegistrationDate` | DateTime | When MFA auth methods were first detected |
| `SourceBatchId` | Text | Batch identifier from upload |

---

## Operations Group Support

- Create a **mail-enabled security group** for your operations team
- Automatically grant the group:
  - **FullAccess + SendAs** on the shared mailbox
  - **Member access** on the SharePoint site
- Add/remove members by email
- Managed via `Update-Deployment.ps1 -Permissions` → Manage Operations Group
- Configuration stored in `[OpsGroup]` section of `mfa-config.ini`

---

## Deployment & Scripting Improvements

### Common-Functions.ps1
- `Initialize-Logging` — Creates timestamped log files
- `Write-Log` — Consistent logging with timestamps and severity levels
- `Invoke-WithRetry` — Generic retry wrapper with configurable attempts
- `Get-IniContent` — Parses `mfa-config.ini` into a nested hashtable
- `New-DeploymentSummary` — Generates post-deployment summary with testing instructions

### Deployment Reports
- Automatic deployment summary generation after completing all scripts
- Technical summary with all IDs, URLs, and troubleshooting commands
- Logic App JSON capture for audit and redeployment

### Resume Capability
- Deployment state saved to `logs/deployment-state.json` after each step
- Resume from last completed step with `.\Run-Complete-Deployment-Master.ps1 -Resume`
- Start from a specific step with `-StartFromStep 5`

### Idempotent Scripts
- All deployment scripts check for existing resources before creating
- Safe to re-run any script without duplicating resources
- Handles "already exists" errors gracefully

---

## Upgrade Path from v1

Existing v1 installations can upgrade to v2:

```powershell
.\Setup.ps1
# Select [3] Upgrade to v2
```

Or directly:

```powershell
.\Update-Deployment.ps1 -Upgrade
```

The upgrade process:
1. Updates SharePoint schema (adds new columns)
2. Backfills tracking tokens for existing users
3. Redeploys function code (4 endpoints)
4. Redeploys Logic App (with retry policies, escalation, tracking pixel, resend link)
5. Fixes all Graph API permissions

Your `mfa-config.ini` and existing SharePoint data are preserved throughout the upgrade.
