# Quick Start

The MFA Onboarding solution uses **`Setup.ps1`** as its single entry point. It automatically detects whether you're running a new install or updating an existing deployment.

## New Installation

1. Open **PowerShell 7** (`pwsh`) — type `pwsh` in the Start menu or terminal.

2. Download and run the bootstrap script:
   ```powershell
   wget https://raw.githubusercontent.com/andrew-kemp/MFA-Onboard-Tool/main/Get-MFAOnboarder.ps1 -OutFile Get-MFAOnboarder.ps1
   .\Get-MFAOnboarder.ps1
   ```

3. Choose an install folder when prompted. The script downloads the latest code and launches `Setup.ps1`.

4. `Setup.ps1` detects **no existing config** and offers:
   ```
   [1] New deployment   - Full guided setup (recommended)
   ```

5. Select **1** and follow the guided deployment (Steps 01–08 run automatically).

## Updating an Existing Installation

If you already have a deployed environment, there are two ways to update:

### Option A — Re-run the bootstrap (easiest)

Re-run `Get-MFAOnboarder.ps1` and point it at your **existing install folder**:

```powershell
.\Get-MFAOnboarder.ps1
# When prompted: enter the path to your existing folder and choose "Use existing folder"
```

The script downloads the latest code into the same folder (your `mfa-config.ini`, certificates, and logs are preserved), then launches `Setup.ps1` which detects the existing deployment:

```
  Existing deployment detected
    Tenant:       yourtenant.onmicrosoft.com
    Function App: func-mfa-yourorg-001

    [1] Update existing deployment    - Change branding, redeploy code, fix permissions
    [2] Pull latest scripts + update  - Download newest code from GitHub, then update
    [3] Fresh install (overwrite)     - Full deployment from scratch
    [4] Resume previous install       - Continue where the last install left off
    [0] Exit
```

Select **1** to launch the update menu.

### Option B — Run Setup.ps1 directly

If you're already in the install folder:

```powershell
cd C:\Scripts\MFA-Onboard-Tool-main\v2
.\Setup.ps1
```

`Setup.ps1` will detect the existing `mfa-config.ini` and show the same menu above. Choose **option 2** to pull the latest scripts from GitHub first, then update — or **option 1** to update with the code you already have.

---

# MFA Onboarding Automation Solution

A comprehensive PowerShell-based solution for automating Multi-Factor Authentication (MFA) enrollment in Microsoft 365 environments. This solution streamlines the process of onboarding users to MFA by providing a complete workflow from user upload to automated tracking and group management.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation & Setup](#installation--setup)
- [Configuration](#configuration)
- [Deployment Scripts](#deployment-scripts)
- [How It Works](#how-it-works)
- [Usage](#usage)
- [Updating an Existing Deployment](#updating-an-existing-deployment)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)

---

## Overview

This solution provides an end-to-end automated workflow for MFA enrollment:

1. **Upload Portal** - Web interface for administrators to upload CSV files with user lists
2. **SharePoint Tracking** - Centralized list to track MFA enrollment status for each user
3. **Azure Function** - Serverless functions to process user data and track enrollment
4. **Logic App** - Automated workflow to send invitation emails and track user progress
5. **Security Group** - Automated group management for conditional access policies

---

## Features

- 🚀 **Fully Automated Deployment** - One-click deployment scripts for entire infrastructure
- 📊 **Real-time Tracking** - SharePoint list tracks each user's MFA enrollment journey
- 📧 **Automated Emails** - Logic App sends invitation emails with tracking links
- 🔐 **Secure Authentication** - Certificate-based authentication for SharePoint, Managed Identity for Azure
- 👥 **Group Management** - Automatic addition to security group upon MFA completion
- 🌐 **Web Portal** - User-friendly upload interface with Azure AD authentication
- 📝 **CSV Import** - Bulk user upload via CSV file
- 🔄 **Status Tracking** - Track: Pending → Sent → Clicked → Added to Group → Active
- ⚙️ **Fully Configurable** - All settings managed via INI configuration file

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      Administrator Workflow                      │
├─────────────────────────────────────────────────────────────────┤
│  1. Upload CSV via Portal (Azure Storage Static Website)        │
│  2. CSV processed by Azure Function (upload-users)              │
│  3. Users added to SharePoint List                              │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│                      Logic App Orchestration                     │
├─────────────────────────────────────────────────────────────────┤
│  1. Recurrence trigger checks SharePoint List                   │
│  2. Finds users with "Pending" status                           │
│  3. Sends email invitation with tracking link                   │
│  4. Updates status to "Sent"                                    │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│                        User Interaction                          │
├─────────────────────────────────────────────────────────────────┤
│  1. User receives email with MFA enrollment instructions        │
│  2. User clicks tracking link                                   │
│  3. Azure Function (enrol) records click → "Clicked"            │
│  4. User is added to MFA Security Group → "AddedToGroup"        │
│  5. User completes MFA enrollment                               │
│  6. Status updated to "Active" (via Microsoft Graph checks)     │
└─────────────────────────────────────────────────────────────────┘
```

### Azure Resources

- **Resource Group** - Contains all Azure resources
- **Storage Account** - Hosts static website (upload portal)
- **Function App** - PowerShell-based serverless functions
  - `enrol` - Tracks user clicks and adds to security group
  - `upload-users` - Processes CSV uploads and adds to SharePoint
- **Logic App** - Orchestrates email sending and status updates
- **Application Insights** - Monitoring and diagnostics
- **Managed Identity** - Secure authentication to Microsoft Graph and SharePoint

### Microsoft 365 Resources

- **SharePoint Site** - Contains MFA tracking list
- **SharePoint List** - Tracks user enrollment status
- **Security Group** - Used for Conditional Access policies
- **Shared Mailbox** - Sends MFA invitation emails
- **App Registrations**
  - SharePoint App (SPO-Automation-MFA) - Certificate-based auth
  - Upload Portal App (MFA-Upload-Portal) - SPA authentication

---

## Requirements

### Software Prerequisites

- **Windows 10/11** or **Windows Server 2019+**
- **PowerShell 7.4+** (recommended) or **PowerShell 5.1+**
- **Azure CLI** - Latest version
- **Internet Connection** - For downloading modules and connecting to cloud services

### PowerShell Modules

The following modules are automatically installed by the setup script:

- **Az** (v11.0.0+) - Azure PowerShell module
- **Az.Functions** (v4.0.0+) - Function App management
- **PnP.PowerShell** (v2.3.0+) - SharePoint Online management
- **Microsoft.Graph** (v2.0.0+) - Microsoft Graph API
- **ExchangeOnlineManagement** (v3.2.0+) - Exchange Online management

### Azure & Microsoft 365 Permissions

**Required Administrator Roles:**
- **Global Administrator** or **Privileged Role Administrator** - For app registrations and consent
- **SharePoint Administrator** - For site and list creation
- **Exchange Administrator** - For shared mailbox creation
- **Azure Subscription Owner** or **Contributor** - For Azure resource creation

**Required Azure Permissions:**
- Create App Registrations
- Create Service Principals
- Grant Admin Consent for API permissions
- Create Azure resources (Function Apps, Storage, Logic Apps)
- Assign Azure RBAC roles

**Required Microsoft 365 Permissions:**
- Create SharePoint sites and lists
- Create Microsoft 365 security groups
- Create and manage shared mailboxes
- Read user information via Microsoft Graph

### License Requirements

- **Microsoft 365 E3/E5** or **Business Premium** license
- **Azure Subscription** - Pay-as-you-go or EA
- **Azure AD P1** (optional but recommended) - For Conditional Access policies

---

## Installation & Setup

### Step 1: Download or Clone Repository

```powershell
# Clone or download all files to a working directory
cd C:\
git clone <repository-url> ANdyKempDev
cd ANdyKempDev
```

### Step 2: Configure Settings

1. **Copy the template INI file:**
   ```powershell
   Copy-Item mfa-config.ini.template mfa-config.ini
   ```

2. **Edit `mfa-config.ini`** with your organization's details:
   ```ini
   [Tenant]
   TenantId=yourtenant.onmicrosoft.com
   SubscriptionId=your-azure-subscription-id
   
   [SharePoint]
   SiteUrl=https://yourtenant.sharepoint.com/sites/MFAOps
   SiteOwner=admin@yourtenant.com
   AppRegName=YourOrg-SPO-Automation-MFA
   SiteTitle=MFA Operations
   
   [Security]
   MFAGroupName=MFA Enabled Users
   
   [Azure]
   ResourceGroup=rg-mfa-onboarding
   Region=uksouth
   FunctionAppName=func-mfa-yourorg-001
   StorageAccountName=stmfayourorg001
   
   [Email]
   MailboxName=MFA Registration
   NoReplyMailbox=MFA-Registration@yourtenant.com
   MailboxDelegate=admin@yourtenant.com
   
   [LogicApp]
   LogicAppName=mfa-invite-orchestrator
   
   [UploadPortal]
   AppRegName=YourOrg-MFA-Upload-Portal
   ```

### Step 3: Run Deployment Scripts

#### Option A: Two-Part Deployment (Recommended)

**Part 1: Initial Setup (Microsoft 365 Resources)**
```powershell
.\Run-Part1-Setup.ps1
```

This runs:
- Script 01: Prerequisites & Configuration
- Script 02: SharePoint Site & List
- Script 03: Shared Mailbox

**Part 2: Azure Deployment (Azure Resources & Configuration)**
```powershell
.\Run-Part2-Deploy.ps1
```

This runs:
- Script 04: Azure Resources
- Script 05: Function App Configuration
- Script 06: Logic App Deployment
- Script 07: Upload Portal Deployment
- Set Function Authentication
- Set Graph Permissions
- Set Logic App Permissions

#### Option B: Individual Script Execution

Run scripts one at a time for troubleshooting:

```powershell
.\01-Install-Prerequisites.ps1
.\02-Provision-SharePoint.ps1
.\03-Create-Shared-Mailbox.ps1
.\04-Create-Azure-Resources.ps1
.\05-Configure-Function-App.ps1
.\06-Deploy-Logic-App.ps1
.\07-Deploy-Upload-Portal1.ps1

# Post-deployment configuration
.\Fix-Function-Auth.ps1
.\Fix-Graph-Permissions.ps1
.\Check-LogicApp-Permissions.ps1 -AddPermissions
```

---

## Configuration

### INI File Sections

#### `[Tenant]`
- **TenantId** - Your Microsoft 365 tenant ID or domain
- **SubscriptionId** - Azure subscription ID

#### `[SharePoint]`
- **SiteUrl** - Full URL to SharePoint site
- **SiteOwner** - Email of site owner
- **AppRegName** - Name for SharePoint app registration (prefix with org name)
- **SiteTitle** - Display title for SharePoint site
- **ListTitle** - Name of tracking list (default: "MFA Onboarding")
- **ClientId** - Auto-filled by deployment
- **CertificatePath** - Auto-filled by deployment
- **CertificateThumbprint** - Auto-filled by deployment

#### `[Security]`
- **MFAGroupId** - Auto-filled by deployment
- **MFAGroupName** - Display name for security group

#### `[Azure]`
- **ResourceGroup** - Name for Azure resource group
- **Region** - Azure region (e.g., uksouth, eastus)
- **FunctionAppName** - Must be globally unique
- **StorageAccountName** - Must be globally unique, lowercase, no dashes
- **MFAPrincipalId** - Auto-filled by deployment

#### `[Email]`
- **MailboxName** - Display name for shared mailbox
- **NoReplyMailbox** - Email address for shared mailbox
- **MailboxDelegate** - User who has access to the mailbox
- **EmailSubject** - Subject line for invitation emails

#### `[LogicApp]`
- **LogicAppName** - Name for Logic App resource

#### `[UploadPortal]`
- **AppRegName** - Name for upload portal app registration
- **ClientId** - Auto-filled by deployment
- **AppName** - Auto-filled by deployment

---

## Deployment Scripts

### Script 01: Install Prerequisites & Configuration
**Purpose:** Installs required PowerShell modules, validates connectivity, and collects configuration.

**What it does:**
- Checks PowerShell version
- Installs/updates required modules (Az, PnP.PowerShell, Microsoft.Graph, ExchangeOnlineManagement)
- Connects to Azure and Microsoft Graph
- Validates tenant connectivity
- Collects configuration details (tenant, SharePoint, mailbox)
- Creates or identifies security group
- Saves all settings to `mfa-config.ini`

**User Interaction:**
- Browser-based authentication prompts
- Configuration value prompts (with defaults from INI)
- Group creation/selection

---

### Script 02: Provision SharePoint Site & List
**Purpose:** Creates SharePoint site and tracking list with proper schema.

**What it does:**
- Creates App Registration with certificate authentication
- Generates PFX certificate for secure authentication
- Creates Communication Site (if doesn't exist)
- Creates SharePoint List with full schema:
  - UPN (Title field) - User's email address
  - Invite Status - Pending/Sent/Clicked/AddedToGroup/Active/Error
  - MFA Registration State - Unknown/Not Registered/Registered
  - In Group - Boolean
  - Date fields (InviteSentDate, ClickedLinkDate, AddedToGroupDate, MFARegistrationDate, LastChecked)
  - Tracking fields (ReminderCount, LastReminderDate, SourceBatchId, CorrelationId, Notes)
  - User attributes (DisplayName, Department, JobTitle, ManagerUPN, ObjectId, UserType)
- Indexes key fields for performance
- Grants admin consent for Microsoft Graph permissions

**Permissions Granted:**
- Microsoft Graph: Sites.ReadWrite.All, Reports.Read.All
- SharePoint: Sites.FullControl.All

---

### Script 03: Create Shared Mailbox
**Purpose:** Creates shared mailbox for sending MFA invitation emails.

**What it does:**
- Connects to Exchange Online
- Creates shared mailbox (if doesn't exist)
- Grants FullAccess and SendAs permissions to delegate
- Configures mailbox for automated sending

**Requirements:**
- Exchange Administrator role
- Mailbox delegate must have valid M365 license

---

### Script 04: Create Azure Resources
**Purpose:** Creates core Azure resources for the solution.

**What it does:**
- Creates Resource Group
- Creates Storage Account (checks INI first, generates unique name if needed)
- Creates Function App with PowerShell 7.4 runtime (checks INI first)
- Enables System Managed Identity
- Configures CORS for Function App
- Handles timeout errors gracefully
- Checks for existing resources before creating

**Resources Created:**
- Resource Group
- Storage Account (StorageV2, Standard_LRS)
- Function App (Windows, PowerShell 7.4)
- App Service Plan (Consumption tier)
- Application Insights (auto-created with Function App)

---

### Script 05: Configure Function App
**Purpose:** Deploys function code and configures environment variables.

**What it does:**
- Gets SharePoint List ID via PnP PowerShell
- Extracts site name from SharePoint URL (fully dynamic from INI)
- Updates function code with configuration values (GroupId, Site, ListId)
- Packages function code into ZIP
- Deploys ZIP to Function App via Azure CLI
- Configures environment variables:
  - SHAREPOINT_SITE_URL
  - SHAREPOINT_LIST_ID
  - SHAREPOINT_SITE_NAME (extracted from URL)
- Restarts Function App to load deployed functions
- Tests endpoint availability

**Functions Deployed:**
- **enrol** - Tracks user clicks, adds to group, redirects to MFA setup
- **upload-users** - Processes CSV uploads, adds users to SharePoint list

---

### Script 06: Deploy Logic App
**Purpose:** Deploys and configures Logic App for email orchestration.

**What it does:**
- Creates Logic App with managed identity
- Loads workflow definition from JSON template
- Replaces placeholders with actual values from INI:
  - SharePoint site URL
  - List ID
  - Function App URL
  - MFA Group ID
  - Shared mailbox email
- Creates API Connections:
  - SharePoint Online
  - Office 365 Outlook
  - Azure AD
- Configures recurrence trigger (checks every 5 minutes)
- Sets up email template with tracking link

**Logic App Workflow:**
1. Recurrence trigger (every 5 minutes)
2. Get items from SharePoint where InviteStatus = "Pending"
3. For each user:
   - Get user details from Azure AD
   - Send email with tracking link
   - Update InviteStatus to "Sent"
   - Record InviteSentDate

---

### Script 07: Deploy Upload Portal
**Purpose:** Deploys web portal for CSV uploads.

**What it does:**
- Gets SharePoint List ID
- Ensures SourceBatchId column exists in list
- Enables static website hosting on Storage Account
- Gets static website URL
- Creates App Registration for portal authentication (SPA)
- Adds Microsoft Graph User.Read permission
- Configures SPA redirect URIs
- Updates portal HTML with:
  - Function App URL
  - Client ID
  - Tenant ID
- Uploads configured HTML to Storage Account ($web container)
- Assigns Storage Blob Data Contributor role to current user
- Handles role propagation delays with retry logic

**Portal Features:**
- Azure AD authentication (MSAL.js)
- CSV file upload
- Optional Batch ID
- Real-time upload progress
- Error handling and validation

---

### Fix Scripts

#### Fix-Function-Auth.ps1
**Purpose:** Configures Function App authentication.

**What it does:**
- Sets authentication level
- Configures App Service authentication
- Enables managed identity authentication

#### Fix-Graph-Permissions.ps1
**Purpose:** Grants Microsoft Graph permissions to Function App managed identity.

**What it does:**
- Gets Function App managed identity
- Assigns Microsoft Graph application permissions:
  - User.Read.All
  - Group.ReadWrite.All
  - GroupMember.ReadWrite.All

#### Check-LogicApp-Permissions.ps1
**Purpose:** Verifies and grants Logic App permissions.

**What it does:**
- Checks API connection permissions
- Grants necessary permissions for:
  - SharePoint Online connection
  - Office 365 Outlook connection
  - Azure AD connection
- Ensures managed identity has required access

---

## How It Works

### User Enrollment Flow

#### 1. Administrator Uploads Users
```
Administrator → Upload Portal (CSV) → Azure Function (upload-users) → SharePoint List
```
- Admin logs into upload portal with Azure AD
- Uploads CSV with UPN/Email column
- Function validates CSV and adds users to SharePoint list
- Initial status: "Pending"

#### 2. Logic App Sends Invitations
```
Logic App (5-minute trigger) → SharePoint List (Get Pending) → Azure AD (Get User Details) → Email
```
- Logic App runs every 5 minutes
- Queries SharePoint for users with status "Pending"
- Gets user details from Azure AD
- Sends personalized email with tracking link
- Updates status to "Sent"

#### 3. User Clicks Link
```
User → Email Link → Azure Function (enrol) → SharePoint Update → Add to Group → Redirect
```
- User clicks link in email
- Function records click timestamp
- Updates status to "Clicked"
- Adds user to MFA security group
- Updates status to "AddedToGroup"
- Redirects user to MFA setup: https://aka.ms/mfasetup

#### 4. User Completes MFA
```
User → MFA Setup → Microsoft Graph (background check) → SharePoint Update
```
- User completes MFA enrollment at Microsoft portal
- Background checks via Microsoft Graph detect MFA registration
- Status updates to "Active"

---

## Usage

### Uploading Users

1. **Navigate to the Upload Portal:**
   - URL is shown at end of Script 07 deployment
   - Format: `https://[storageaccount].z33.web.core.windows.net/upload-portal.html`

2. **Sign in with Azure AD**

3. **Prepare CSV File:**
   ```csv
   UPN
   user1@contoso.com
   user2@contoso.com
   user3@contoso.com
   ```
   
   Alternative column names: `UserPrincipalName`, `Email`

4. **Upload:**
   - Optionally enter Batch ID (e.g., "2026-01-Finance")
   - Select CSV file
   - Click "Upload Users"

5. **Monitor Progress:**
   - View SharePoint list for real-time status updates
   - Check Logic App run history for email sending

### Monitoring

#### SharePoint List
- Navigate to: `[SiteUrl]/Lists/MFA-Onboarding`
- View all user statuses
- Filter by status, batch, department
- Export to Excel for reporting

#### Azure Portal
- **Function App:** Monitor invocations, errors, logs
- **Logic App:** View run history, failed runs
- **Application Insights:** Performance metrics, exceptions

#### Email Tracking
- Check shared mailbox Sent Items for email confirmations
- Review Logic App run details for specific users

---

## Updating an Existing Deployment

The recommended way to update is via `Setup.ps1` (see [Quick Start — Updating](#updating-an-existing-installation) above). Under the hood, it launches `Update-Deployment.ps1` which you can also run directly.

### Interactive Menu

```powershell
.\Update-Deployment.ps1
```

This presents a menu with the following options:

| Option | What it does |
|--------|-------------|
| **1 - Update All** | Schema + backfill tokens + function code + Logic App |
| **2 - Function Code** | Repackages and redeploys Azure Functions (enrol + upload-users) |
| **3 - Logic App** | Redeploys the Logic App workflow with current template and INI settings |
| **4 - Branding / Emails** | Change logo URL, company name, support team, email wording — then optionally redeploy |
| **5 - Permissions** | Fix Graph permissions, API connections, add mailbox delegates |
| **6 - SharePoint Schema** | Adds any missing fields to the SharePoint list (safe to re-run) |
| **7 - Backfill Tokens** | Generates tracking tokens for users that don't have one yet |

### Command-Line Switches

For automation or scripting, use switches directly:

```powershell
# Apply everything
.\Update-Deployment.ps1 -UpdateAll

# Redeploy just the function code
.\Update-Deployment.ps1 -FunctionCode

# Change branding interactively, then redeploy Logic App
.\Update-Deployment.ps1 -Branding

# Add missing SharePoint fields + backfill tokens
.\Update-Deployment.ps1 -SharePointSchema -BackfillTokens
```

### Common Scenarios

**After pulling new code from the repo:**
```powershell
.\Update-Deployment.ps1 -UpdateAll
```

**Changing the company logo or email footer:**
1. Edit `mfa-config.ini` → `[Branding]` section, or run with `-Branding` to be prompted
2. The Logic App will be redeployed with the new branding

**Adding a new delegate to the shared mailbox:**
```powershell
.\Update-Deployment.ps1 -Permissions
# Choose option 3 and enter the delegate's email
```

---

## Troubleshooting

### Common Issues

#### Script 01: Module Installation Fails
**Symptom:** PowerShell module installation errors

**Solution:**
```powershell
# Run PowerShell as Administrator
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
Install-Module -Name Az -Force -AllowClobber
```

#### Script 02: Certificate Password Issues
**Symptom:** Certificate password mismatch

**Solution:**
- Ensure passwords match exactly (case-sensitive)
- Store certificate password securely for future use

#### Script 04: Function App Timeout
**Symptom:** Gateway timeout error but resources are created

**Solution:**
- Script now handles this automatically
- Verifies resources exist despite timeout
- Wait 60 seconds and check Azure Portal

#### Script 05: Function Deployment Fails
**Symptom:** 404 errors when accessing functions

**Solution:**
```powershell
# Re-run script 05
.\05-Configure-Function-App.ps1

# Or manually restart Function App
az functionapp restart --resource-group rg-mfa-onboarding --name [your-function-app]
```

#### Script 07: Upload Portal 404 Error
**Symptom:** Upload fails with 404 Not Found

**Solution:**
1. Verify environment variable `SHAREPOINT_SITE_NAME` is correct:
   ```powershell
   az functionapp config appsettings list --resource-group rg-mfa-onboarding --name [function-app] --query "[?name=='SHAREPOINT_SITE_NAME']"
   ```

2. If incorrect, re-run script 05 (it now auto-extracts from INI)

3. Restart Function App:
   ```powershell
   az functionapp restart --resource-group rg-mfa-onboarding --name [function-app]
   ```

#### Upload Portal: Role Assignment Propagation
**Symptom:** 403 Forbidden when uploading portal HTML

**Solution:**
- Script now waits 60 seconds and retries 3 times
- Azure role assignments can take 2-3 minutes to propagate
- If still fails, wait a few minutes and re-run script 07

#### Logic App: API Connection Not Authorized
**Symptom:** Logic App runs fail with authorization errors

**Solution:**
1. Open Azure Portal → Logic App → API Connections
2. Click each connection (SharePoint, Office 365, Azure AD)
3. Click "Edit API connection"
4. Click "Authorize" and sign in
5. Save connection

Or run:
```powershell
.\Check-LogicApp-Permissions.ps1 -AddPermissions
```

### Permission Issues

#### Admin Consent Required
**Symptom:** "Admin consent required" messages

**Solution:**
1. Navigate to Azure Portal → App Registrations
2. Select your app (e.g., "AKD-SPO-Automation-MFA")
3. Go to "API permissions"
4. Click "Grant admin consent for [Tenant]"

#### Managed Identity Permissions
**Symptom:** Function can't access Microsoft Graph

**Solution:**
```powershell
.\Fix-Graph-Permissions.ps1
```

### Logs and Diagnostics

#### Function App Logs
```powershell
# Stream live logs
az webapp log tail --resource-group rg-mfa-onboarding --name [function-app]

# View in Azure Portal
# Function App → Functions → [function-name] → Monitor
```

#### Logic App Run History
1. Azure Portal → Logic App
2. Click "Overview" → "Runs history"
3. Click specific run to see detailed flow

#### Application Insights
1. Azure Portal → Function App → Application Insights
2. View:
   - Live Metrics
   - Failures
   - Performance
   - Logs (Kusto queries)

---

## File Structure

```
ANdyKempDev/
│
├── README.md                          # This file
├── Setup.ps1                          # Entry point: detects new/existing install
├── Update-Deployment.ps1              # Update tool for existing deployments
├── mfa-config.ini.template            # Configuration template
├── mfa-config.ini                     # Your configuration (git-ignored)
│
├── Run-Complete-Deployment-Master.ps1 # Full deployment with resume support
├── Run-Part1-Setup.ps1                # Master script: Steps 01-03
├── Run-Part2-Deploy.ps1               # Master script: Steps 04-07 + fixes
│
├── 01-Install-Prerequisites.ps1       # Prerequisites & configuration
├── 02-Provision-SharePoint.ps1        # SharePoint site & list
├── 03-Create-Shared-Mailbox.ps1       # Shared mailbox creation
├── 04-Create-Azure-Resources.ps1      # Azure resources
├── 05-Configure-Function-App.ps1      # Function deployment
├── 06-Deploy-Logic-App.ps1            # Logic App deployment
├── 07-Deploy-Upload-Portal1.ps1       # Upload portal deployment
│
├── Fix-Function-Auth.ps1              # Function authentication fix
├── Fix-Graph-Permissions.ps1          # Graph permissions fix
├── Check-LogicApp-Permissions.ps1     # Logic App permissions check/fix
│
├── function-code/                     # Function App source code
│   ├── host.json                      # Function host configuration
│   ├── profile.ps1                    # PowerShell profile
│   ├── requirements.psd1              # PowerShell dependencies
│   ├── enrol/                         # Enrollment tracking function
│   │   ├── function.json              # Function binding config
│   │   └── run.ps1                    # Function code
│   └── upload-users/                  # CSV upload function
│       ├── function.json              # Function binding config
│       └── run.ps1                    # Function code
│
├── portal/                            # Upload portal source
│   └── upload-portal.html             # Portal HTML/JS
│
├── cert-output/                       # Generated certificates (git-ignored)
│   └── [generated-certificates].pfx
│
└── invite-orchestrator-fixed.json     # Logic App workflow template
```

---

## Security Considerations

### Authentication Methods

1. **Certificate-Based (SharePoint):**
   - PFX certificate stored locally
   - Thumbprint-based authentication
   - Certificates should be secured and backed up

2. **Managed Identity (Azure Function):**
   - No credentials in code
   - Azure-managed identity
   - Scoped permissions via RBAC

3. **API Connections (Logic App):**
   - OAuth-based authentication
   - Requires admin authorization
   - Automatic token refresh

### Data Security

- **SharePoint List:** Permissions inherited from site
- **Storage Account:** Role-based access control
- **Function App:** Anonymous auth for enrol (tracking link), managed identity for Graph
- **Upload Portal:** Azure AD authentication required

### Best Practices

1. **Backup certificates** to secure location
2. **Limit admin access** to production resources
3. **Monitor Logic App** run history for anomalies
4. **Review SharePoint permissions** regularly
5. **Enable Azure diagnostic logging** for compliance
6. **Use separate INI files** per environment (dev/test/prod)

---

## Support & Maintenance

### Updating Function Code

```powershell
# Modify function code in function-code/ folder
# Re-run script 05 to redeploy
.\05-Configure-Function-App.ps1
```

### Updating Logic App Workflow

```powershell
# Modify invite-orchestrator-fixed.json
# Re-run script 06 to redeploy
.\06-Deploy-Logic-App.ps1
```

### Updating Upload Portal

```powershell
# Modify portal/upload-portal.html
# Re-run script 07 to redeploy
.\07-Deploy-Upload-Portal1.ps1
```

### Re-running Scripts

All scripts are **idempotent** - they can be safely re-run multiple times:
- Checks for existing resources before creating
- Uses INI values to avoid duplicates
- Updates existing resources where possible

---

## Cost Estimation

### Azure Resources (Monthly)

- **Function App:** ~£0-15 (Consumption plan, depends on usage)
- **Storage Account:** ~£1-5 (static website + Function storage)
- **Logic App:** ~£0-10 (5-minute recurrence)
- **Application Insights:** ~£0-5 (based on data ingestion)

**Estimated Total:** £5-35/month (for typical small-medium organization)

### Microsoft 365

- No additional licensing required (uses existing M365 licenses)
- Shared mailbox is free

---

## Credits

**Developed By:** Andy Kemp  
**Version:** 1.0  
**Last Updated:** January 2026

---

## License

This solution is provided as-is for use within your organization. Modify and adapt as needed for your requirements.
