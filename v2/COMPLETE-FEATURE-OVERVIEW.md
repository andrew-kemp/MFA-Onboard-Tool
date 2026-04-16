# Complete Feature Overview

Detailed breakdown of every feature in the MFA Onboarding Automation Tool v2.

---

## 1. User Upload & Management

### CSV Bulk Upload
- Upload CSV files via the web portal's drag-and-drop interface
- Supports columns named `UPN`, `UserPrincipalName`, or `Email` (case-insensitive)
- Client-side validation: email format checking with preview table (first 10 rows)
- Server-side validation: regex email validation, duplicate detection against existing SharePoint items
- Optional Batch ID: custom or auto-generated as `yyyy-MM-dd-HHmm`
- **New users**: Created with `InviteStatus=Pending`, unique `TrackingToken` GUID
- **Existing users**: Reset to `InviteStatus=Pending`, `MFARegistrationState=Unknown`, re-processed
- Progress bar and results summary with stat cards (Total, Added, Updated, Skipped, Errors)

### Manual Entry
- Textarea input for one-per-line or comma-separated email addresses
- Converted to CSV format with `UPN` header before submission
- Same server-side processing as CSV upload

### Immediate Logic App Trigger
- After upload, the function attempts to trigger the Logic App immediately via HTTP
- If the Logic App trigger URL is unavailable, falls back to the next scheduled run
- No user impact if trigger fails — graceful degradation

---

## 2. Automated Email Workflow

### Initial Invitation
- Professional HTML email with:
  - Company logo and branding (configurable)
  - 4-step MFA setup guide
  - Large "Set Up MFA Now" call-to-action button linking to `/api/enrol?token={TrackingToken}`
  - Microsoft Authenticator app download links (iOS and Android App Store)
  - Invisible tracking pixel (`/api/track-open?token={TrackingToken}`)
  - "Lost your setup link?" footer link to `/api/resend`
- Sent from the configured shared mailbox
- Configurable subject line via `[Email].EmailSubject`

### Automated Reminders
- Sent 7+ days after previous email if MFA is not yet registered
- Includes "Reminder #{count}" badge with stronger urgency messaging
- Same tracking pixel and resend link as initial invitation
- Configurable subject line via `[Email].ReminderSubject`
- `ReminderCount` incremented in SharePoint after each reminder

### Manager Escalation
- Triggered after 2+ reminders without MFA completion
- Looks up user's manager via Microsoft Graph API (`/users/{id}/manager`)
- Escalation email features:
  - Red "Manager Action Required" header
  - Employee name and department
  - Number of reminders sent
  - Clear action instructions
- Records `EscalatedToManager=true` and `EscalationDate` in SharePoint
- Only escalates once per user (checks before sending)

### Email Open Tracking
- Invisible 1×1 transparent GIF pixel in every email
- `/api/track-open` endpoint records `EmailOpenedDate` on first open only
- Fire-and-forget: tracking failures never block the pixel response
- Always returns valid GIF with `Cache-Control: no-store` (43 bytes)

### Self-Service Resend
- Footer link in every email: "Lost your setup link?"
- `/api/resend` endpoint:
  - GET: Returns branded HTML form
  - POST: Resets user to `InviteStatus=Pending`, clears `ReminderCount` and `LastReminderDate`
- **Anti-enumeration**: Always returns the same generic success message regardless of whether the email exists in the system
- Logic App picks up reset users on next scheduled run

---

## 3. Enrolment Click Tracking

### `/api/enrol` Endpoint
- Handles the link users click in their invitation email
- **Token-based lookup** (preferred): Uses `TrackingToken` GUID for secure, non-guessable links
- **Legacy fallback**: Falls back to raw UPN for pre-v2 users

### Duplicate-Click Protection
- If `ClickedLinkDate` is already set, returns branded "Already Registered" page
- Does NOT re-add user to the security group
- 5-second auto-redirect to https://aka.ms/mfasetup

### Security Group Management
- Looks up user in Entra ID via Graph API
- Adds user to MFA security group (handles "already a member" gracefully)
- Updates SharePoint: `ClickedLinkDate`, `InGroup=true`, `AddedToGroupDate`, `InviteStatus=Sent`

### Branded HTML Responses
All responses are professionally styled HTML pages with auto-redirect countdown:

| Scenario | Colour | Message | Redirect |
|----------|--------|---------|----------|
| Missing parameters | Red | "Invalid Link" | Portal URL |
| Token/user not found | Orange | "Link Not Recognised" | Portal URL |
| Already clicked | Green | "Already Registered" | aka.ms/mfasetup |
| Success | Green | "MFA Enrolment Started" | aka.ms/mfasetup |
| Internal error | Red | "Something Went Wrong" | Portal URL |

### API Mode
- Detects programmatic callers (no User-Agent or `Accept: application/json`)
- Returns JSON instead of HTML for integrations and testing

---

## 4. MFA Verification

### Graph API Integration
- Logic App queries `/v1.0/users/{id}/authentication/methods` via Managed Identity
- Checks for: Phone, Microsoft Authenticator, OATH software/hardware tokens, FIDO2 security keys, Windows Hello for Business
- If any method detected: Sets `InviteStatus=Active`, `MFARegistrationState=Registered`, records `MFARegistrationDate`

### Status Lifecycle
```
Pending → Sent → Clicked → AddedToGroup → Active
                                         ↗
                            (MFA verified via Graph)
```

- **Pending**: User uploaded, awaiting first email
- **Sent**: Initial invitation email sent
- **Clicked**: User clicked enrolment link
- **AddedToGroup**: User added to MFA security group
- **Active**: MFA authentication methods detected and verified
- **Skipped Registered**: Users already registered when uploaded
- **Error**: Processing error (details in Notes column)

---

## 5. Upload Portal (Web SPA)

### Authentication
- MSAL.js 2.30.0 with Entra ID popup login
- Scopes: `user.read`, `Sites.Read.All`
- Pre-caches tokens on login to prevent first-upload authentication failures
- Tenant and Client ID injected at deployment time from `mfa-config.ini`

### Tab 1: CSV Upload
- Drag-and-drop zone (click or drag `.csv` file)
- Client-side CSV parsing and email validation
- Preview table showing first 10 rows with valid/invalid indicators
- Summary of total valid/invalid before upload
- Optional Batch ID text field
- Progress bar during upload
- Results: stat cards with expandable error/skip details

### Tab 2: Manual Entry
- Textarea for email addresses (one per line or comma-separated)
- Converts to CSV format internally
- Same progress and results display

### Tab 3: Reports
- **Refresh Reports**: Fetches all SharePoint items via Microsoft Graph
- **Batch filter dropdown**: Populated from `SourceBatchId` values with per-batch counts
- **Executive summary**: Total Users, MFA Active, Pending, Completion Rate %
- **High reminder alerts**: Red warning for users with 2+ reminders
- **Status breakdown**: Grid of status cards with counts and percentages
- **Recent activity**: Last 7 days — invites sent, links clicked, added to group
- **Users needing attention**: Follow-up required list
- **Batch performance**: Per-batch completion rates
- **Email report**: Compose and send executive summary email
- **CSV export**: Download as `mfa-report-YYYY-MM-DD.csv` with proper escaping

---

## 6. Logic App Workflow

### Scheduled Processing
- Configurable recurrence (default: every 12 hours via `[LogicApp].RecurrenceHours`)
- Processes all users where `InviteStatus` is `Pending`, `Sent`, or `Active`
- For each user: look up in Entra ID, check MFA status, check group membership, update tracking fields

### Retry Policies
- **Exponential backoff** on all 16 API-connected actions
- 3 retries, 10-second minimum interval, 1-hour maximum interval
- Covers: SharePoint reads/writes, email sends, user lookups, group checks

### Template Placeholder System
- Logic App JSON (`invite-orchestrator-TEMPLATE.json`) uses 14 placeholders
- All replaced from `mfa-config.ini` values at deployment
- Re-applied when Logic App is redeployed via `Update-Deployment.ps1 -LogicApp`
- Placeholders cover: recurrence, SharePoint URL/ListID, group ID, email addresses, branding

---

## 7. Application Insights

### Telemetry
- Full request and exception logging for all 4 Function App endpoints
- Performance metrics and dependency tracking
- Live Metrics Stream for real-time monitoring during rollouts
- Automatic correlation of related operations

### Configuration
- Auto-provisioned by Script 04 (`04-Create-Azure-Resources.ps1`)
- Instrumentation key and connection string stored in `mfa-config.ini`
- Set as Function App environment variables
- `host.json` controls: sampling rates (Request excluded), log levels, HTTP throttling (20 concurrent)

---

## 8. Infrastructure as Code (Bicep)

### `infra/main.bicep`
- Declarative definition of all Azure resources
- Secure defaults: TLS 1.2, HTTPS-only, FTPS disabled
- Resources: Storage Account, App Insights, App Service Plan (Consumption), Function App (with MI), O365 + SP API connections
- Parameterised via `infra/main.parameters.json`

### Outputs
- Managed Identity principal ID, Function App hostname, App Insights keys, API connection IDs

---

## 9. SharePoint Tracking

### 24-Column Schema
Comprehensive per-user tracking covering:
- **Identity**: Title (UPN), ObjectId, DisplayName, Department, JobTitle, ManagerUPN, UserType
- **Status**: InviteStatus (7 values), MFARegistrationState (3 values), InGroup (boolean)
- **Dates**: InviteSentDate, ClickedLinkDate, AddedToGroupDate, MFARegistrationDate, LastChecked, LastReminderDate, EmailOpenedDate, EscalationDate
- **Tracking**: TrackingToken (GUID, indexed), CorrelationId, ReminderCount, SourceBatchId
- **Escalation**: EscalatedToManager (boolean), EscalationDate
- **Notes**: Free-text notes column

### Column Indexing
Three columns are indexed for Graph API `$filter` performance:
- `InviteStatus`
- `MFARegistrationState`
- `TrackingToken`

---

## 10. Update & Operations

### Update-Deployment.ps1
- 8 CLI switches: `-UpdateAll`, `-FunctionCode`, `-LogicApp`, `-Branding`, `-Permissions`, `-SharePointSchema`, `-BackfillTokens`, `-Upgrade`, `-QuickFix`
- Interactive 7-option menu when run without switches
- Each operation reads from `mfa-config.ini` for current configuration

### Operations Group
- Mail-enabled security group for ops team
- Automatically granted: mailbox FullAccess + SendAs, SharePoint site Members
- Managed via Permissions sub-menu

### Self-Updating Scripts
- `Setup.ps1` option [2]: Pull latest from GitHub, replace scripts, preserve config/certs/logs
- Detects and migrates config from pre-v2 parent directories

### Tracking Token Backfill
- Generates `TrackingToken` GUIDs for users uploaded before v2
- Run via `Update-Deployment.ps1 -BackfillTokens`

---

## 11. Security Features

- **Managed Identity**: No stored credentials for Function App operations
- **Certificate auth**: PFX certificate for SharePoint App Registration
- **Tracking tokens**: Random GUIDs prevent link guessing
- **Anti-enumeration**: Resend endpoint returns identical response regardless of email existence
- **Duplicate-click protection**: Prevents re-processing on repeated clicks
- **HTTPS-only + TLS 1.2**: Enforced across all Azure resources
- **FTPS disabled**: No FTP access to Function App

---

## 12. Deployment & Recovery

- **8-step guided deployment** with automatic module installation and config collection
- **Resume capability**: State saved after each step; resume from interruption point
- **Idempotent scripts**: Safe to re-run without creating duplicates
- **Deployment reports**: Automatic summary generation with testing instructions and resource URLs
- **Technical summary**: All IDs, URLs, and troubleshooting commands captured
