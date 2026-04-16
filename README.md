# MFA Onboarding Automation Tool

A comprehensive PowerShell-based solution for automating Multi-Factor Authentication (MFA) enrollment across Microsoft 365 environments. This tool provides a complete workflow from user upload through automated email invitations, click tracking, group management, MFA verification, manager escalation, and operational reporting.

**Version:** 2.0  
**Author:** Andy Kemp  
**Documentation:** [docs.andykemp.com](https://docs.andykemp.com)

---

## Table of Contents

- [Quick Start](#quick-start)
- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Deployment Scripts](#deployment-scripts)
- [Azure Functions](#azure-functions)
- [Logic App Workflow](#logic-app-workflow)
- [Upload Portal](#upload-portal)
- [Updating an Existing Installation](#updating-an-existing-installation)
- [Infrastructure as Code (Bicep)](#infrastructure-as-code-bicep)
- [SharePoint Schema](#sharepoint-schema)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)
- [Cost Estimation](#cost-estimation)
- [Roadmap](#roadmap)

---

## Quick Start

### One-Line Bootstrap

The fastest way to get started — download and run the bootstrap script in PowerShell 7:

```powershell
irm https://raw.githubusercontent.com/andrew-kemp/MFA-Onboard-Tool/main/v2/Get-MFAOnboarder.ps1 -OutFile Get-MFAOnboarder.ps1; .\Get-MFAOnboarder.ps1
```

This will:

1. Check you're running PowerShell 7+
2. Prompt for an install folder (default: `C:\Scripts`)
3. Download the full repository from GitHub
4. Extract all files and launch `Setup.ps1`
5. `Setup.ps1` detects whether this is a fresh install or existing deployment and presents the appropriate menu

### Alternative: Clone and Run

```powershell
git clone https://github.com/andrew-kemp/MFA-Onboard-Tool.git
cd MFA-Onboard-Tool/v2
.\Setup.ps1
```

### What Setup.ps1 Does

`Setup.ps1` is the single entry point for all operations. It auto-detects your environment:

**New install detected:**
```
[1] New deployment   — Full guided setup (recommended)
[0] Exit
```

**Existing install detected:**
```
[1] Update existing deployment     — Change branding, redeploy code, fix permissions
[2] Pull latest scripts + update   — Download newest code from GitHub, then update
[3] Upgrade to v2                  — Full upgrade: schema, functions, Logic App, permissions
[4] Fresh install (overwrite)      — Full deployment from scratch (backs up config first)
[5] Resume previous install        — Continue where the last install left off
[6] Quick fix (pull + permissions) — Download latest code and fix all permissions
[0] Exit
```

Setup.ps1 preserves your `mfa-config.ini`, certificate files, backups, and logs when pulling latest scripts. It can also detect and migrate configuration from pre-v2 installations in parent directories.

---

## Overview

### The Problem

Rolling out MFA to an organisation is operationally complex:
- Users need clear instructions specific to their environment
- Administrators need to track who has enrolled and who hasn't
- Reminders need to be sent automatically without manual follow-up
- Managers need to be escalated to for persistent non-compliers
- Security groups need to be managed for Conditional Access policies
- The whole process needs to be auditable and reportable

### The Solution

This tool automates the entire MFA onboarding lifecycle:

```
Upload users (CSV/portal) → Automated email invitations → Click tracking
→ Security group management → MFA verification → Automated reminders
→ Manager escalation → Operational reporting → CSV export
```

### User Journey

| Step | What happens | Status |
|------|-------------|--------|
| 1 | Admin uploads CSV or enters users manually in the portal | **Pending** |
| 2 | Logic App sends branded email with enrolment link | **Sent** |
| 3 | Email open is tracked via invisible pixel | *(EmailOpenedDate stamped)* |
| 4 | User clicks the enrolment link | **Clicked** |
| 5 | Azure Function adds user to MFA security group | **AddedToGroup** |
| 6 | User is redirected to https://aka.ms/mfasetup | *(user completes MFA)* |
| 7 | Logic App verifies MFA registration via Graph API | **Active** |
| 8 | If not enrolled after reminders, manager is escalated | *(EscalatedToManager)* |

---

## Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Upload Portal (SPA)                           │
│   Azure Storage Static Website · MSAL.js · 3 tabs                   │
│   CSV Upload (drag-drop) │ Manual Entry │ Reports + CSV Export       │
└─────────────────────────────────┬────────────────────────────────────┘
                                  │ POST /api/upload-users
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     Azure Function App (PowerShell 7.4)              │
│   Managed Identity · Application Insights                            │
│                                                                      │
│   /api/upload-users   — Validate CSV, create/update SharePoint items │
│   /api/enrol          — Track clicks, add to group, branded HTML     │
│   /api/track-open     — 1×1 pixel, stamp EmailOpenedDate             │
│   /api/resend         — Self-service resend form (GET) + reset (POST)│
└──────────────┬──────────────────────────────────────────────────────┘
               │ SharePoint REST + Graph API
               ▼
┌─────────────────────────────┐   ┌────────────────────────────────────┐
│   SharePoint Online List    │   │         Logic App (Consumption)    │
│   24 tracked columns        │   │   Recurrence trigger (configurable)│
│   Per-user status tracking  │◄──│   Process Pending/Sent/Active users│
│   Batch IDs, tokens, dates  │   │   Send emails via shared mailbox  │
│   Manager UPN, escalation   │   │   Check MFA via Graph API         │
└─────────────────────────────┘   │   Automated reminders (7-day)     │
                                  │   Manager escalation (2+ reminders)│
┌─────────────────────────────┐   │   Retry policies (exponential)    │
│   Entra ID / Microsoft 365  │◄──│   Tracking pixels + resend links  │
│   Security Group (CA policy)│   └────────────────────────────────────┘
│   Shared Mailbox (sender)   │
│   User MFA auth methods     │
└─────────────────────────────┘
```

### Azure Resources Created

| Resource | Purpose |
|----------|---------|
| **Resource Group** | Container for all Azure resources |
| **Storage Account** | Hosts the upload portal as a static website |
| **Function App** | PowerShell 7.4, Consumption plan, 4 HTTP endpoints |
| **Application Insights** | Telemetry, logging, request tracing, error monitoring |
| **Logic App** | Orchestrates the email/check/reminder/escalation workflow |
| **API Connections** | Office 365 (email) and SharePoint Online (list access) |
| **System Managed Identity** | Secure auth to Graph API and SharePoint (no stored credentials) |

### Microsoft 365 Resources Created

| Resource | Purpose |
|----------|---------|
| **SharePoint Communication Site** | Hosts the MFA tracking list |
| **SharePoint List** (24 columns) | Per-user tracking with status, dates, tokens, batch IDs |
| **Security Group** | Added to Conditional Access policies to enforce MFA |
| **Shared Mailbox** | Sends branded invitation and reminder emails |
| **App Registration** (SharePoint) | Certificate-based auth for SharePoint operations |
| **App Registration** (Upload Portal) | SPA authentication for the web portal |

---

## Features

### Core Workflow

- **CSV bulk upload** — Upload hundreds of users at once via CSV file
- **Manual entry** — Enter individual email addresses through the portal
- **Automated email invitations** — Branded HTML emails with enrolment links sent from shared mailbox
- **Click tracking** — Records when users click the enrolment link
- **Security group management** — Automatically adds users to MFA security group on click
- **MFA verification** — Checks authentication methods via Microsoft Graph API
- **Status lifecycle** — Full tracking: Pending → Sent → Clicked → AddedToGroup → Active
- **Duplicate handling** — Re-uploading existing users resets them to Pending for re-processing

### Email & Communication

- **Branded HTML emails** — Professional emails with company logo, colours, and formatting
- **Initial invitation** — Step-by-step MFA setup guide with direct enrolment link
- **Automated reminders** — Sent every 7 days for users who haven't completed MFA
- **Manager escalation** — After 2+ reminders, the user's manager receives an escalation email (red header, "Manager Action Required") with employee details and reminder count
- **Email open tracking** — Invisible 1×1 pixel in every email records when the email is opened (`EmailOpenedDate`)
- **Self-service resend** — "Lost your setup link?" footer link lets users request a new invitation without admin intervention
- **Configurable subjects** — Separate subject lines for initial invitations and reminders
- **Configurable sender** — Uses your shared mailbox as the From address
- **App Store links** — Emails include Microsoft Authenticator download links for iOS and Android

### Upload Portal (Web SPA)

- **Azure AD authentication** — MSAL.js popup login with `user.read` + `Sites.Read.All` scopes
- **Three-tab interface:**
  - **CSV Upload** — Drag-and-drop zone, client-side CSV validation, email format checking, preview table (10 rows), progress bar, results summary with error details
  - **Manual Entry** — Textarea for one-per-line or comma-separated email addresses
  - **Reports** — Executive summary dashboard, status breakdown, batch filter, recent activity, high-reminder alerts, CSV export
- **Batch filtering** — Dropdown populated from all `SourceBatchId` values with user counts per batch
- **CSV export** — Export all report data to a date-stamped CSV file
- **Email report** — Send an executive summary email directly from the portal

### Tracking & Reporting

- **24-column SharePoint schema** — Comprehensive per-user tracking (see [SharePoint Schema](#sharepoint-schema))
- **Batch tracking** — Every upload gets a `SourceBatchId` (custom or auto-generated `yyyy-MM-dd-HHmm`)
- **Tracking tokens** — Each user gets a unique GUID token for secure, non-guessable enrolment links
- **Email open tracking** — First-open-only timestamp via invisible tracking pixel
- **Click tracking** — Records exact timestamp when user clicks the enrolment link
- **MFA registration date** — Records when MFA authentication methods are detected
- **Reminder count** — Tracks how many reminders each user has received
- **Escalation tracking** — Records whether and when the user's manager was escalated to
- **Correlation IDs** — Links related operations for audit trails

### Reliability & Resilience

- **Logic App retry policies** — Exponential backoff (3 retries, 10s–1hr interval) on all 16 API actions
- **Duplicate-click protection** — If a user clicks the enrolment link twice, they see a branded "Already Registered" page instead of being re-processed
- **Branded error pages** — Function endpoints return styled HTML pages for: Invalid Link (red), Link Not Recognised (orange), Already Registered (green), MFA Enrolment Started (green), Error (red) — each with auto-redirect countdown
- **Idempotent deployment** — All scripts check for existing resources before creating; safe to re-run
- **Resume capability** — If deployment is interrupted, resume from where it left off with `-Resume`
- **Graceful degradation** — Upload function attempts immediate Logic App trigger but falls back to scheduled processing

### Monitoring & Diagnostics

- **Application Insights** — Full telemetry for all Function App endpoints: request logging, exception tracking, performance metrics, live metrics stream
- **Configurable log levels** — `host.json` controls sampling, log levels, and HTTP throttling
- **Logic App run history** — Detailed per-run flow tracking visible in Azure Portal
- **Deployment reports** — Automated deployment summary with testing instructions and resource URLs

### Operations & Management

- **Operations Group** — Create and manage a mail-enabled security group with mailbox and SharePoint access for your ops team
- **Update tool** — `Update-Deployment.ps1` provides granular update options (function code, Logic App, branding, permissions, schema) without full redeployment
- **Self-updating scripts** — `Setup.ps1` can pull the latest scripts from GitHub while preserving your configuration
- **Tracking token backfill** — Generate tokens for users uploaded before the tracking token feature was added
- **INI-driven configuration** — All settings in `mfa-config.ini`; no hardcoded values in any script

### Infrastructure as Code

- **Bicep template** — `infra/main.bicep` defines all Azure resources (Storage Account, App Insights, App Service Plan, Function App, API Connections) with secure defaults (TLS 1.2, HTTPS-only, FTPS disabled)
- **Parameterised deployment** — `infra/main.parameters.json` for environment-specific values

---

## Requirements

### Software

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| PowerShell | 7.0 | 7.4+ |
| Azure CLI | Latest | Latest |
| OS | Windows 10 / Server 2019 | Windows 11 / Server 2022 |

### PowerShell Modules (auto-installed by Script 01)

| Module | Version | Purpose |
|--------|---------|---------|
| Az | 11.0.0+ | Azure resource management |
| Az.Functions | 4.0.0+ | Function App operations |
| PnP.PowerShell | 2.3.0+ | SharePoint Online management |
| Microsoft.Graph | 2.0.0+ | Microsoft Graph API |
| ExchangeOnlineManagement | 3.2.0+ | Exchange mailbox management |

### Azure & Microsoft 365 Permissions

**Administrator roles required:**
- **Global Administrator** or **Privileged Role Administrator** — For app registrations and admin consent
- **SharePoint Administrator** — For site and list creation
- **Exchange Administrator** — For shared mailbox creation
- **Azure Subscription Owner** or **Contributor** — For Azure resource creation

**Microsoft Graph API permissions granted (to Managed Identity):**
- `User.Read.All` — Look up user details and MFA status
- `Group.ReadWrite.All` — Manage security group membership
- `GroupMember.ReadWrite.All` — Add/remove group members
- `UserAuthenticationMethod.Read.All` — Check MFA registration status

### Licensing

- **Microsoft 365 E3/E5** or **Business Premium**
- **Azure Subscription** (Pay-as-you-go or EA)
- **Entra ID P1** (recommended for Conditional Access policies)
- Shared mailbox is free (no additional licence needed)

---

## Installation

### Full Deployment (New Install)

The guided deployment runs 8 scripts in sequence. Each script reads from `mfa-config.ini` and prompts for any missing values:

| Step | Script | What It Does |
|------|--------|-------------|
| 01 | `01-Install-Prerequisites.ps1` | Installs PowerShell modules, validates connectivity, collects tenant/SharePoint/mailbox configuration, creates security group, saves everything to `mfa-config.ini` |
| 02 | `02-Provision-SharePoint.ps1` | Creates App Registration with certificate auth, generates PFX certificate, creates Communication Site, creates SharePoint List with 24-column schema, indexes key columns, grants admin consent |
| 03 | `03-Create-Shared-Mailbox.ps1` | Creates shared mailbox, grants FullAccess + SendAs to delegate |
| 04 | `04-Create-Azure-Resources.ps1` | Creates Resource Group, Storage Account, Function App (PowerShell 7.4 / Consumption), Application Insights, enables System Managed Identity |
| 05 | `05-Configure-Function-App.ps1` | Packages and deploys function code (4 endpoints), sets environment variables (SharePoint URL, List ID, Group ID, App Insights keys), restarts and tests |
| 06 | `06-Deploy-Logic-App.ps1` | Creates Logic App with managed identity, replaces all template placeholders, creates API connections (Office 365 + SharePoint), configures recurrence trigger |
| 07 | `07-Deploy-Upload-Portal1.ps1` | Enables static website hosting, creates SPA App Registration, injects config into portal HTML, uploads to Storage Account `$web` container |
| 08 | `08-Deploy-Email-Reports.ps1` | Deploys a separate email-reporting Logic App for scheduled executive summary emails |

Post-deployment scripts run automatically:
- `Fix-Graph-Permissions.ps1` — Grants Graph API permissions to Managed Identity
- `Check-LogicApp-Permissions.ps1` — Authorises Logic App API connections

### Resuming a Failed Deployment

If deployment is interrupted:

```powershell
.\Setup.ps1
# Select [5] Resume previous install
```

Or directly:

```powershell
.\Run-Complete-Deployment-Master.ps1 -Resume
# Or start from a specific step:
.\Run-Complete-Deployment-Master.ps1 -StartFromStep 5
```

Deployment state is saved to `logs/deployment-state.json` after each step.

---

## Configuration

All configuration is stored in `mfa-config.ini`. Most values are auto-populated by the deployment scripts — you only need to provide tenant details, naming preferences, and branding.

### INI Sections

#### `[Tenant]`
| Key | Description | Example |
|-----|-------------|---------|
| `TenantId` | Microsoft 365 tenant ID or domain | `contoso.onmicrosoft.com` |
| `SubscriptionId` | Azure subscription ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

#### `[SharePoint]`
| Key | Description | Auto-filled? |
|-----|-------------|--------------|
| `SiteUrl` | Full URL to SharePoint site | User provides |
| `SiteOwner` | Email of site owner | User provides |
| `SiteTitle` | Display title for the site | User provides |
| `ListTitle` | Name of tracking list (default: `MFA Onboarding`) | User provides |
| `AppRegName` | Name for SharePoint app registration | User provides |
| `ClientId` | App Registration client ID | Yes (Script 02) |
| `CertificatePath` | Path to generated PFX certificate | Yes (Script 02) |
| `CertificateThumbprint` | Certificate thumbprint | Yes (Script 02) |
| `ListId` | SharePoint list GUID | Yes (Script 05) |

#### `[Security]`
| Key | Description | Auto-filled? |
|-----|-------------|--------------|
| `MFAGroupName` | Display name for MFA security group | User provides |
| `MFAGroupId` | Security group object ID | Yes (Script 01) |
| `MFAGroupMail` | Group email address | Yes (Script 01) |

#### `[Azure]`
| Key | Description | Auto-filled? |
|-----|-------------|--------------|
| `ResourceGroup` | Azure resource group name | User provides |
| `Region` | Azure region (default: `uksouth`) | User provides |
| `FunctionAppName` | Globally unique Function App name | User provides |
| `StorageAccountName` | Globally unique storage account name | User provides or auto-generated |
| `MFAPrincipalId` | Managed Identity principal ID | Yes (Script 04) |
| `AppInsightsName` | Application Insights resource name | Yes (Script 04) |
| `AppInsightsKey` | Instrumentation key | Yes (Script 04) |
| `AppInsightsConnectionString` | Connection string | Yes (Script 04) |

#### `[Email]`
| Key | Description | Example |
|-----|-------------|---------|
| `MailboxName` | Shared mailbox display name | `MFA Registration` |
| `NoReplyMailbox` | Shared mailbox email address | `mfa-registration@contoso.com` |
| `MailboxDelegate` | User with mailbox access | `admin@contoso.com` |
| `EmailSubject` | Initial invitation subject | `Action Required: Set Up MFA` |
| `ReminderSubject` | Reminder email subject | `Reminder: Set Up MFA` |

#### `[LogicApp]`
| Key | Description | Default |
|-----|-------------|---------|
| `LogicAppName` | Logic App resource name | — |
| `RecurrenceHours` | Hours between Logic App runs | `12` |
| `TriggerUrl` | HTTP trigger URL (auto-filled) | Yes (Script 06) |

#### `[UploadPortal]`
| Key | Description | Auto-filled? |
|-----|-------------|--------------|
| `AppRegName` | SPA app registration name | User provides |
| `ClientId` | SPA client ID | Yes (Script 07) |
| `AppName` | Display name | Yes (Script 07) |

#### `[Branding]`
| Key | Description | Example |
|-----|-------------|---------|
| `LogoUrl` | URL to company logo image | `https://contoso.com/logo.png` |
| `CompanyName` | Company name in emails | `Contoso Ltd` |
| `SupportTeam` | Support team name in email footers | `IT Security Team` |
| `SupportEmail` | Support contact email | `itsupport@contoso.com` |

#### `[OpsGroup]`
| Key | Description | Auto-filled? |
|-----|-------------|--------------|
| `OpsGroupName` | Operations group display name | Via Update-Deployment.ps1 |
| `OpsGroupEmail` | Operations group email | Via Update-Deployment.ps1 |
| `OpsGroupId` | Operations group object ID | Via Update-Deployment.ps1 |

---

## Deployment Scripts

### Core Deployment Scripts

| Script | Purpose |
|--------|---------|
| `Get-MFAOnboarder.ps1` | Bootstrap — downloads repo, launches Setup.ps1 |
| `Setup.ps1` | Single entry point — detects environment, routes to correct action |
| `Run-Complete-Deployment-Master.ps1` | Orchestrates Scripts 01-08 + post-deployment fixes; supports `-Resume` and `-StartFromStep` |
| `01-Install-Prerequisites.ps1` | Installs modules, validates connections, collects config |
| `02-Provision-SharePoint.ps1` | Creates site, list, app registration, certificate |
| `03-Create-Shared-Mailbox.ps1` | Creates shared mailbox with delegate access |
| `04-Create-Azure-Resources.ps1` | Creates RG, Storage, Function App, App Insights, Managed Identity |
| `05-Configure-Function-App.ps1` | Deploys function code, sets env vars, tests endpoints |
| `06-Deploy-Logic-App.ps1` | Deploys Logic App with template placeholder replacement |
| `06b-Redeploy-Logic-App-Only.ps1` | Redeployment script for Logic App only (used by update tool) |
| `07-Deploy-Upload-Portal1.ps1` | Enables static website hosting, creates SPA app reg, uploads portal |
| `08-Deploy-Email-Reports.ps1` | Deploys email reporting Logic App |

### Management & Fix Scripts

| Script | Purpose |
|--------|---------|
| `Update-Deployment.ps1` | Granular update tool — function code, Logic App, branding, schema, permissions |
| `Fix-Function-Auth.ps1` | Configures Function App authentication settings |
| `Fix-Graph-Permissions.ps1` | Grants Graph API permissions to Managed Identity |
| `Check-LogicApp-Permissions.ps1` | Verifies and fixes Logic App API connection permissions |
| `Common-Functions.ps1` | Shared helpers: logging, retry logic, INI parsing, deployment reports |
| `Generate-Deployment-Report.ps1` | Creates a deployment summary document |
| `Create-TechnicalSummary.ps1` | Generates a technical summary of the deployment |

---

## Azure Functions

The Function App hosts four HTTP-triggered PowerShell endpoints, all authenticated via System Managed Identity for Graph API and SharePoint access.

### `POST /api/upload-users` — CSV Upload Processor

Receives user data from the upload portal and creates/updates SharePoint list items.

**Request body (JSON):**
```json
{
  "csv": "UPN\nuser1@contoso.com\nuser2@contoso.com",
  "batchId": "2026-04-Finance"
}
```

**Validation:**
- CSV must not be empty and must parse to at least 1 user
- Must contain a column named `UPN`, `UserPrincipalName`, or `Email` (case-insensitive)
- Per-user email format validation via regex
- Duplicate detection against existing SharePoint items

**Behaviour:**
- **New users:** Creates SharePoint item with `InviteStatus=Pending`, generates unique `TrackingToken` (GUID)
- **Existing users:** Resets to `InviteStatus=Pending`, `MFARegistrationState=Unknown`, updates `SourceBatchId`
- Auto-generates `batchId` as `yyyy-MM-dd-HHmm` if not provided
- Attempts to trigger the Logic App immediately via HTTP trigger; falls back to scheduled processing
- Returns full CORS headers for browser compatibility

**Response:**
```json
{
  "added": 5,
  "updated": 2,
  "skipped": 0,
  "errors": 0,
  "total": 7
}
```

### `GET /api/enrol` — Enrolment Click Tracker

Handles the link users click in their invitation email.

**Query parameters:**
- `token` (preferred) — Unique GUID tracking token
- `user` (legacy fallback) — Raw UPN/email address

**Behaviour:**
1. Looks up user in SharePoint by tracking token (or UPN fallback)
2. **Duplicate-click protection:** If `ClickedLinkDate` is already set, returns a branded "Already Registered" page with 5-second auto-redirect — does NOT re-add to group
3. Looks up user in Entra ID via Graph API
4. Adds user to MFA security group (handles "already a member" gracefully)
5. Updates SharePoint: `ClickedLinkDate`, `InGroup=true`, `AddedToGroupDate`, `InviteStatus=Sent`
6. Returns branded "MFA Enrolment Started" HTML page with auto-redirect to https://aka.ms/mfasetup

**Branded HTML responses** (all with professional styling, auto-redirect countdown):

| Scenario | Colour | Message |
|----------|--------|---------|
| Invalid link (missing parameters) | Red | "Invalid Link" |
| Token/user not found | Orange | "Link Not Recognised" |
| Already clicked | Green | "Already Registered" |
| Success | Green | "MFA Enrolment Started" |
| Error | Red | "Something Went Wrong" |

**API detection:** If request has `Accept: application/json` or no User-Agent, returns JSON instead of HTML (for programmatic callers).

### `GET /api/track-open` — Email Open Tracking Pixel

Invisible tracking pixel embedded in every email. Records when users open the email.

**Query parameter:** `token` — User's tracking token

**Behaviour:**
- **Always** returns a 1×1 transparent GIF (43 bytes) with `Cache-Control: no-store`
- On first open: stamps `EmailOpenedDate` in SharePoint (first-open-only, won't overwrite)
- Fire-and-forget: tracking failures never block the pixel response
- Returns 200 OK even if token is invalid or lookup fails

### `GET/POST /api/resend` — Self-Service Resend

Allows users to request a new invitation email without contacting IT.

**GET:** Returns a branded HTML form with an email input field

**POST:** Accepts `{ "email": "user@contoso.com" }` or form-encoded data
- Looks up user in SharePoint by email
- If status is `Pending` or `Sent`: resets `InviteStatus=Pending`, `ReminderCount=0`, clears `LastReminderDate`
- Logic App picks up the reset user on its next scheduled run
- **Anti-enumeration:** Always returns the same generic success message regardless of whether the user exists: *"If your account is pending MFA setup, you'll receive a new setup email shortly"*

---

## Logic App Workflow

The Logic App (`invite-orchestrator-TEMPLATE.json`) runs on a configurable schedule (default: every 12 hours) and processes all users in the SharePoint list.

### Template Placeholders

The Logic App JSON uses placeholders that are replaced from `mfa-config.ini` at deployment:

| Placeholder | Source |
|-------------|--------|
| `RECURRENCE_HOURS_PLACEHOLDER` | `[LogicApp].RecurrenceHours` |
| `PLACEHOLDER_SHAREPOINT_SITE_URL` | `[SharePoint].SiteUrl` |
| `PLACEHOLDER_LIST_ID` | `[SharePoint].ListId` |
| `PLACEHOLDER_GROUP_ID` | `[Security].MFAGroupId` |
| `PLACEHOLDER_EMAIL` | `[Email].NoReplyMailbox` |
| `PLACEHOLDER_SUBJECT` | `[Email].EmailSubject` |
| `PLACEHOLDER_REMINDER_SUBJECT` | `[Email].ReminderSubject` |
| `PLACEHOLDER_FUNCTION_URL` | Function App hostname |
| `PLACEHOLDER_TRACK_OPEN_URL` | `/api/track-open` endpoint URL |
| `PLACEHOLDER_RESEND_URL` | `/api/resend` endpoint URL |
| `PLACEHOLDER_LOGO_URL` | `[Branding].LogoUrl` |
| `PLACEHOLDER_COMPANY_NAME` | `[Branding].CompanyName` |
| `PLACEHOLDER_SUPPORT_TEAM` | `[Branding].SupportTeam` |
| `PLACEHOLDER_FOOTER` | Generated from branding values |

### Workflow Logic

For each user where `InviteStatus` is `Pending`, `Sent`, or `Active`:

1. **Look up user in Entra ID** — Get display name, department, job title, manager UPN
2. **Check MFA status** — Query `/v1.0/users/{id}/authentication/methods` via Graph API
3. **Check group membership** — Verify if user is in the MFA security group
4. **Update tracking fields** — Stamp `LastChecked`, update `DisplayName`

**If user IS in the group:**
- **MFA registered** (phone/authenticator/OATH methods detected): Set status to `Active`, record `MFARegistrationDate`
- **MFA not registered + status Pending**: Send initial invitation email, set status to `Sent`, `ReminderCount=1`
- **MFA not registered + 7+ days since last reminder**: Send reminder email, increment `ReminderCount`
- **2+ reminders + not escalated**: Look up manager via Graph, send escalation email, set `EscalatedToManager=true`, stamp `EscalationDate`

**If user is NOT in the group:**
- Reset MFA authentication methods (Phone, Authenticator, OATH, FIDO2, Windows Hello)
- Set `MFARegistrationState=Not Registered`, `InGroup=false`
- Follow same email/reminder/escalation logic as above

### Email Types

**Initial Invitation:**
- Professional HTML with company logo and branding
- 4-step MFA setup guide
- Large "Set Up MFA Now" call-to-action button
- Microsoft Authenticator app download links (iOS + Android)
- Tracking pixel + resend link in footer

**Reminder Email:**
- "Reminder #{count}" badge
- Stronger urgency messaging
- Same CTA button and tracking links

**Manager Escalation Email:**
- Red "Manager Action Required" header
- Employee name and reminder count
- Clear escalation messaging
- Sent to the user's manager (from Graph API `manager` endpoint)

### Retry Policies

All 16 API-connected actions in the Logic App have exponential backoff retry policies:
- **Count:** 3 retries
- **Interval:** 10 seconds (minimum)
- **Maximum interval:** 1 hour
- **Type:** Exponential

This covers: SharePoint reads/writes, Office 365 email sends, user lookups, group membership checks, and all Graph API calls.

---

## Upload Portal

The upload portal is a single-page application (`upload-portal.html`) hosted on Azure Storage static website hosting, authenticated via MSAL.js.

### Authentication

- Uses MSAL.js 2.30.0 browser library
- Popup-based login flow
- Scopes: `user.read`, `Sites.Read.All`
- Pre-caches tokens on login to prevent first-upload failures
- Tenant and Client ID injected at deployment time

### Tab 1: CSV Upload

- **Drag-and-drop zone** — Click to browse or drag a `.csv` file
- **Client-side CSV validation:**
  - Parses headers and identifies the email column (`UPN`, `UserPrincipalName`, or `Email`)
  - Validates each email address with regex
  - Shows a preview table (first 10 rows) with valid/invalid indicators
  - Displays summary: total valid, total invalid
- **Batch ID** — Optional text field; auto-generated by the server if left empty
- **Upload** — Sends validated CSV to `/api/upload-users` with progress bar animation
- **Results** — Stat cards showing Total, Added, Updated, Skipped, Errors with detailed error/skip lists

### Tab 2: Manual Entry

- Textarea for entering email addresses (one per line or comma-separated)
- Converts input to CSV format with `UPN` header before submission
- Same progress and results display as CSV Upload

### Tab 3: Reports

- **Refresh Reports** button — Fetches all SharePoint list items via Microsoft Graph API
- **Batch filter dropdown** — Dynamically populated from `SourceBatchId` values, shows user count per batch, filters the entire report view
- **Executive Summary** — Total Users, MFA Active, Pending, Completion Rate (%)
- **High Reminder Alert** — Red warning box for users with 2+ reminders
- **Status Breakdown** — Grid of status cards (Pending, Sent, Clicked, AddedToGroup, Active, Error, Skipped) with counts and percentages
- **Recent Activity** — Last 7 days: Invites sent, Links clicked, Added to group
- **Users Needing Attention** — Lists users requiring follow-up
- **Batch Performance** — Per-batch completion rates and counts
- **Email Report** — Compose and send an executive summary email
- **Export CSV** — Download all report data as a date-stamped CSV file (`mfa-report-YYYY-MM-DD.csv`) with proper escaping

---

## Updating an Existing Installation

### Using Setup.ps1 (Recommended)

```powershell
.\Setup.ps1
# Option [2] Pull latest scripts + update
# or
# Option [3] Upgrade to v2 (full upgrade)
# or
# Option [6] Quick fix (pull latest + fix permissions)
```

### Using Update-Deployment.ps1 Directly

**Interactive menu:**
```powershell
.\Update-Deployment.ps1
```

Presents options:
```
[1] Update All              — Full update (schema + functions + Logic App)
[2] Function Code           — Redeploy Azure Functions only
[3] Logic App               — Redeploy Logic App workflow only
[4] Branding / Emails       — Change logo, company name, email wording
[5] Permissions             — Fix or add user permissions
[6] SharePoint Schema       — Add any missing list fields
[7] Backfill Tokens         — Generate tracking tokens for existing users
[0] Exit
```

**CLI switches for automation:**

```powershell
# Update everything
.\Update-Deployment.ps1 -UpdateAll

# Redeploy just the function code
.\Update-Deployment.ps1 -FunctionCode

# Redeploy just the Logic App
.\Update-Deployment.ps1 -LogicApp

# Update branding (interactive prompts)
.\Update-Deployment.ps1 -Branding

# Fix permissions
.\Update-Deployment.ps1 -Permissions

# Add missing SharePoint columns
.\Update-Deployment.ps1 -SharePointSchema

# Generate tracking tokens for existing users
.\Update-Deployment.ps1 -BackfillTokens

# Full v2 upgrade (schema + backfill + functions + Logic App + permissions)
.\Update-Deployment.ps1 -Upgrade

# Quick fix: pull latest + fix all permissions (non-interactive)
.\Update-Deployment.ps1 -QuickFix
```

### What Each Update Does

| Update | Actions |
|--------|---------|
| **SharePoint Schema** | Compares 24 expected fields against existing list; adds any missing columns; verifies column indexes on `InviteStatus`, `MFARegistrationState`, `TrackingToken` |
| **Function Code** | Packages `function-code/` to ZIP, deploys via `az functionapp deployment source config-zip`, updates all env vars (including App Insights), restarts |
| **Logic App** | Runs `06b-Redeploy-Logic-App-Only.ps1` which re-applies all template placeholders from current INI values |
| **Branding** | Interactive prompts for logo URL, company name, support team, support email, sender mailbox, email subjects, recurrence hours; saves to INI; offers Logic App redeploy |
| **Permissions** | Sub-menu: Fix Function App Graph permissions, Fix Logic App API connections, Add mailbox delegate, Add Upload Portal redirect URI, Manage Operations Group, or all of the above |
| **Backfill Tokens** | Finds users without `TrackingToken`, generates GUID tokens for each |

### Operations Group Management

The Permissions sub-menu includes Operations Group management:

- **Create new group** — Mail-enabled security group with auto-generated alias
- **Add/remove members** — By email address
- **Grant mailbox access** — FullAccess + SendAs on the shared mailbox
- **Grant SharePoint access** — Add group to site Members

---

## Infrastructure as Code (Bicep)

For organisations that prefer declarative infrastructure, a Bicep template is provided at `infra/main.bicep`.

### Resources Defined

| Resource | Type | Configuration |
|----------|------|---------------|
| Storage Account | `Microsoft.Storage/storageAccounts` | Standard_LRS, StorageV2, HTTPS-only, TLS 1.2 |
| Application Insights | `Microsoft.Insights/components` | Web type, 90-day retention |
| App Service Plan | `Microsoft.Web/serverfarms` | Consumption tier (Y1/Dynamic) |
| Function App | `Microsoft.Web/sites` | PowerShell 7.4, Managed Identity, HTTPS-only, FTPS disabled, TLS 1.2 |
| Office 365 Connection | `Microsoft.Web/connections` | API connection for Logic App |
| SharePoint Connection | `Microsoft.Web/connections` | API connection for Logic App |

### Deployment

```powershell
az deployment group create `
  --resource-group rg-mfa-onboarding `
  --template-file infra/main.bicep `
  --parameters infra/main.parameters.json
```

### Outputs

| Output | Description |
|--------|-------------|
| `functionAppPrincipalId` | Managed Identity principal ID (for Graph permission grants) |
| `functionAppHostname` | Function App URL |
| `appInsightsKey` | Instrumentation key |
| `appInsightsConnectionString` | Full connection string |
| `office365ConnectionId` | Office 365 API connection resource ID |
| `sharepointConnectionId` | SharePoint API connection resource ID |

---

## SharePoint Schema

The SharePoint list contains 24 columns tracking every aspect of the user's MFA onboarding journey:

| Column | Type | Description |
|--------|------|-------------|
| `Title` | Text | User's email address (UPN) — the primary identifier |
| `InviteStatus` | Choice | `Pending`, `Sent`, `Clicked`, `AddedToGroup`, `Active`, `Skipped Registered`, `Error` |
| `MFARegistrationState` | Choice | `Unknown`, `Not Registered`, `Registered` |
| `InGroup` | Boolean | Whether user is in the MFA security group |
| `InviteSentDate` | DateTime | When the invitation email was sent |
| `ClickedLinkDate` | DateTime | When the user clicked the enrolment link |
| `AddedToGroupDate` | DateTime | When the user was added to the security group |
| `MFARegistrationDate` | DateTime | When MFA authentication methods were detected |
| `LastChecked` | DateTime | Last time the Logic App checked this user |
| `ReminderCount` | Number | How many reminder emails have been sent |
| `LastReminderDate` | DateTime | When the last reminder was sent |
| `SourceBatchId` | Text | Batch identifier from the upload (custom or auto-generated) |
| `TrackingToken` | Text | Unique GUID for secure, non-guessable enrolment links |
| `CorrelationId` | Text | Links related operations for audit trails |
| `Notes` | Note | Free-text notes (e.g., error messages) |
| `DisplayName` | Text | User's display name from Entra ID |
| `Department` | Text | User's department from Entra ID |
| `JobTitle` | Text | User's job title from Entra ID |
| `ManagerUPN` | Text | User's manager email from Entra ID |
| `ObjectId` | Text | User's Entra ID object ID |
| `UserType` | Text | User type from Entra ID |
| `EmailOpenedDate` | DateTime | When the user first opened the email (tracking pixel) |
| `EscalatedToManager` | Boolean | Whether the user's manager has been notified |
| `EscalationDate` | DateTime | When the manager escalation email was sent |

**Indexed columns** (for Graph API `$filter` performance): `InviteStatus`, `MFARegistrationState`, `TrackingToken`

---

## Security

### Authentication Methods

| Component | Auth Method | Details |
|-----------|------------|---------|
| **Function App → Graph/SharePoint** | System Managed Identity | No credentials stored; Azure manages the identity lifecycle |
| **SharePoint App Reg** | Certificate-based (PFX) | Thumbprint auth; certificates stored locally in `cert-output/` |
| **Upload Portal** | Azure AD (MSAL.js SPA) | Popup login; tokens scoped to `user.read` + `Sites.Read.All` |
| **Logic App → APIs** | OAuth API Connections | Admin-authorised; automatic token refresh |

### Security Design Decisions

- **Tracking tokens** — Enrolment links use random GUIDs, not email addresses, to prevent guessing
- **Anti-enumeration on resend** — Returns identical response regardless of email existence
- **Duplicate-click protection** — Prevents re-processing if a user clicks the link multiple times
- **No stored credentials** — Managed Identity eliminates secrets for Azure Function operations
- **HTTPS-only + TLS 1.2** — Enforced on Storage Account, Function App, and Bicep resources
- **FTPS disabled** — No FTP access to Function App (Bicep template)
- **Certificate auth** — SharePoint operations use certificate thumbprint, not client secrets

### Best Practices

1. **Back up certificates** — Store the `cert-output/` PFX files in a secure location
2. **Limit admin access** — Only grant necessary roles to deployment operators
3. **Review permissions** — Periodically audit Graph permissions and API connections
4. **Monitor Logic App** — Check run history for failures or anomalies
5. **Enable diagnostic logging** — Application Insights captures all function invocations
6. **Secure the INI file** — `mfa-config.ini` contains configuration details; don't commit to public repos

---

## Troubleshooting

### Module Installation Failures

```powershell
# Run as Administrator
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Install-Module -Name Az -Force -AllowClobber
```

### Function App Not Responding

```powershell
# Restart the Function App
az functionapp restart --resource-group <rg-name> --name <func-name>

# Check env vars are set
az functionapp config appsettings list --resource-group <rg-name> --name <func-name> -o table

# Stream live logs
az webapp log tail --resource-group <rg-name> --name <func-name>
```

### Logic App Runs Failing

1. Azure Portal → Logic App → Overview → Runs history
2. Click the failed run to see which action failed
3. Common issues:
   - **API connections need re-authorisation** — Run `.\Check-LogicApp-Permissions.ps1 -AddPermissions`
   - **Managed Identity permissions missing** — Run `.\Fix-Graph-Permissions.ps1`
   - **SharePoint list schema mismatch** — Run `.\Update-Deployment.ps1 -SharePointSchema`

### Upload Portal 403/404 Errors

```powershell
# Verify static website is enabled
az storage blob service-properties show --account-name <storage> --query staticWebsite

# Re-upload portal
.\07-Deploy-Upload-Portal1.ps1
```

### Emails Not Sending

1. Check Logic App run history for errors
2. Verify shared mailbox exists: `Get-Mailbox -Identity <mailbox-email>`
3. Verify API connections are authorised (Azure Portal → Logic App → API connections → Edit → Authorize)
4. Check that `[Email].NoReplyMailbox` in INI matches the actual mailbox address

### Users Stuck in "Pending"

- Verify the Logic App is enabled and running (check last run time)
- Check Logic App recurrence interval in `[LogicApp].RecurrenceHours`
- Manually trigger: Azure Portal → Logic App → Overview → Run Trigger → Recurrence

### Graph Permission Errors

```powershell
# Re-grant all required permissions
.\Fix-Graph-Permissions.ps1

# Verify permissions
az ad app permission list --id <managed-identity-object-id>
```

---

## File Structure

```
MFA-Onboard-Tool/
├── v2/                                    # Active codebase
│   ├── Setup.ps1                          # Single entry point — detects environment, routes actions
│   ├── Get-MFAOnboarder.ps1              # Bootstrap — downloads repo, launches Setup.ps1
│   ├── Run-Complete-Deployment-Master.ps1 # Deployment orchestrator (8 steps + fixes)
│   ├── Update-Deployment.ps1              # Granular update tool (switches + interactive menu)
│   │
│   ├── 01-Install-Prerequisites.ps1       # Module installation & config collection
│   ├── 02-Provision-SharePoint.ps1        # SharePoint site, list, app reg, certificate
│   ├── 03-Create-Shared-Mailbox.ps1       # Shared mailbox creation & delegate
│   ├── 04-Create-Azure-Resources.ps1      # RG, Storage, Function App, App Insights, MI
│   ├── 05-Configure-Function-App.ps1      # Deploy function code, set env vars, test
│   ├── 06-Deploy-Logic-App.ps1            # Logic App + API connections + placeholder replacement
│   ├── 06b-Redeploy-Logic-App-Only.ps1    # Standalone Logic App redeployment
│   ├── 07-Deploy-Upload-Portal1.ps1       # Static website, SPA app reg, portal upload
│   ├── 08-Deploy-Email-Reports.ps1        # Email reporting Logic App
│   │
│   ├── Fix-Function-Auth.ps1              # Function App auth configuration
│   ├── Fix-Graph-Permissions.ps1          # Graph API permission grants
│   ├── Check-LogicApp-Permissions.ps1     # API connection permission verification
│   ├── Common-Functions.ps1               # Shared helpers (logging, retry, INI, reports)
│   ├── Generate-Deployment-Report.ps1     # Deployment summary generator
│   ├── Create-TechnicalSummary.ps1        # Technical summary generator
│   │
│   ├── mfa-config.ini                     # Configuration file (all settings)
│   ├── invite-orchestrator-TEMPLATE.json  # Logic App workflow template
│   ├── Test-Users.csv                     # Sample CSV for testing
│   │
│   ├── function-code/                     # Azure Function source code
│   │   ├── host.json                      # Host config (logging, sampling, throttling)
│   │   ├── profile.ps1                    # PowerShell profile
│   │   ├── requirements.psd1             # Module dependencies
│   │   ├── enrol/                         # /api/enrol — click tracking + group add
│   │   │   ├── function.json
│   │   │   └── run.ps1
│   │   ├── upload-users/                  # /api/upload-users — CSV processing
│   │   │   ├── function.json
│   │   │   └── run.ps1
│   │   ├── track-open/                    # /api/track-open — email open pixel
│   │   │   ├── function.json
│   │   │   └── run.ps1
│   │   └── resend/                        # /api/resend — self-service resend
│   │       ├── function.json
│   │       └── run.ps1
│   │
│   ├── portal/                            # Upload portal SPA
│   │   └── upload-portal.html             # 3-tab portal (upload, manual, reports)
│   │
│   ├── infra/                             # Infrastructure as Code
│   │   ├── main.bicep                     # Bicep template (all Azure resources)
│   │   └── main.parameters.json           # Parameterised values
│   │
│   └── *.md                               # Documentation files
│
└── Archive/                               # Legacy files from pre-v2
```

---

## Cost Estimation

### Azure Resources (Monthly, GBP)

| Resource | Estimated Cost | Notes |
|----------|---------------|-------|
| Function App (Consumption) | £0–15 | First 1M executions free; pay per execution after |
| Storage Account | £1–5 | Static website hosting + Function storage |
| Logic App (Consumption) | £0–10 | Billed per action execution |
| Application Insights | £0–5 | First 5 GB/month free |
| **Total** | **£5–35/month** | Typical small-to-medium organisation |

### Microsoft 365

- No additional licensing costs
- Shared mailbox is free (no licence required)
- Uses existing M365 tenant capabilities

---

## Roadmap

### Planned Features (v2.1+)

- **Passkey / phishing-resistant MFA** — Let users choose between traditional MFA and passkeys
- **New user onboarding with TAP** — Temporary Access Pass for passwordless first login
- **Self-service alternate email** — Users register personal email for account recovery
- **IT support TAP reset portal** — Dedicated portal for helpdesk TAP issuance
- **Power BI reporting** — Advanced dashboards with drill-down analytics
- **Multi-tenant support** — Manage MFA rollout across multiple tenants from one deployment

See [V2-ROADMAP.md](V2-ROADMAP.md) for detailed plans.

---

## Credits

**Developed by:** Andy Kemp  
**Version:** 2.0  
**Documentation:** [docs.andykemp.com](https://docs.andykemp.com)  
**Repository:** [github.com/andrew-kemp/MFA-Onboard-Tool](https://github.com/andrew-kemp/MFA-Onboard-Tool)
