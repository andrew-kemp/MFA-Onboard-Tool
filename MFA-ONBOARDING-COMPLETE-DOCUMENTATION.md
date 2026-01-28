# MFA Onboarding System - Complete Documentation

## Table of Contents
1. [System Overview](#system-overview)
2. [Architecture Components](#architecture-components)
3. [Deployment Guide](#deployment-guide)
4. [User Workflow](#user-workflow)
5. [Technical Flow](#technical-flow)
6. [SharePoint List Schema](#sharepoint-list-schema)
7. [Function App Endpoints](#function-app-endpoints)
8. [Logic App Workflows](#logic-app-workflows)
9. [Status Lifecycle](#status-lifecycle)
10. [Troubleshooting](#troubleshooting)

---

## System Overview

The MFA Onboarding System is an automated solution for enrolling users into Multi-Factor Authentication (MFA) in Microsoft 365. It provides:

- **Web-based Upload Portal** for bulk CSV uploads or manual user entry
- **Automated Email Invitations** sent immediately after upload
- **Click Tracking** to monitor user engagement
- **Automatic Group Management** when users click enrollment links
- **MFA Status Monitoring** to track completion
- **Scheduled Email Reports** for administrators

### Key Features
- ✅ Immediate email delivery (no waiting for scheduled runs)
- ✅ Automatic user addition to MFA security group
- ✅ Real-time status tracking in SharePoint
- ✅ Comprehensive reporting capabilities
- ✅ Self-service enrollment for end users
- ✅ Fallback scheduled processing (every 12 hours)

---

## Architecture Components

### 1. **SharePoint Online**
- **Site**: Dedicated SharePoint site for MFA operations
- **List**: "MFA Registration" list tracking all users
- **App Registration**: Certificate-based authentication for PowerShell access

**Columns:**
- Title (User Email)
- DisplayName
- InviteStatus (Pending/Sent/Active/Completed)
- InviteSentDate
- ClickedLinkDate
- InGroup (Boolean)
- AddedToGroupDate
- BatchId (for tracking uploads)

### 2. **Azure Function App**
- **Runtime**: PowerShell 7.4
- **Hosting**: Consumption Plan (serverless)
- **Authentication**: System-assigned Managed Identity

**Functions:**
- `enrol` - Processes enrollment link clicks
- `upload-users` - Handles CSV/manual user uploads

**Environment Variables:**
- SHAREPOINT_SITE_URL
- SHAREPOINT_LIST_ID
- SHAREPOINT_SITE_NAME
- MFA_GROUP_ID
- LOGIC_APP_TRIGGER_URL

### 3. **Logic Apps**

#### **Invitation Logic App**
- **Triggers**: 
  - HTTP Request (immediate, triggered by user uploads)
  - Recurrence (every 12 hours as backup)
- **Actions**: Sends invitation emails to users with status "Pending" or "Sent"
- **Permissions**: Directory.Read.All, User.Read.All, GroupMember.ReadWrite.All

#### **Email Reports Logic App** (Optional)
- **Trigger**: Recurrence (daily/weekly at 9:00 AM)
- **Actions**: Generates and emails MFA rollout statistics
- **Permissions**: Sites.Read.All

### 4. **Azure AD (Entra ID)**
- **MFA Security Group**: Users automatically added when clicking enrollment link
- **App Registrations**: 
  - SharePoint Access (certificate auth)
  - Upload Portal (delegated auth)

### 5. **Upload Portal**
- **Type**: Single-page HTML application
- **Location**: Deployed to user's temp folder
- **Features**: CSV upload, manual entry, reporting dashboard
- **Authentication**: Azure AD (user delegation)

### 6. **Shared Mailbox** (Optional)
- **Purpose**: No-reply sender address for invitation emails
- **Format**: mfa-noreply@yourdomain.com

---

## Deployment Guide

### Prerequisites
- Global Administrator or equivalent privileges
- Azure subscription with Owner/Contributor role
- PowerShell 7.4 or higher
- Azure CLI installed

### Deployment Steps

#### **Quick Deploy - All Steps**
```powershell
# Run complete deployment (Steps 01-08 + Fixes)
.\Run-Complete-Deployment.ps1
```

#### **Manual Step-by-Step Deployment**

**PART 1 - FOUNDATION (15-20 minutes)**

**Step 01: Install Prerequisites**
```powershell
.\01-Install-Prerequisites.ps1
```
- Installs required PowerShell modules
- Installs Azure CLI (if missing)
- Validates PnP PowerShell version

**Step 02: Provision SharePoint**
```powershell
.\02-Provision-SharePoint.ps1
```
- Creates SharePoint site: `/sites/MFAOps`
- Creates "MFA Registration" list with required columns
- Creates app registration with certificate
- Saves certificate to `cert-output/` folder
- Updates `mfa-config.ini` with site URL, List ID, Client ID, Certificate Thumbprint

**Step 03: Create Shared Mailbox** (Optional)
```powershell
.\03-Create-Shared-Mailbox.ps1
```
- Creates Exchange Online shared mailbox
- Configures no-reply address for invitation emails
- Updates `mfa-config.ini` with mailbox address

**PART 2 - AZURE DEPLOYMENT (20-30 minutes)**

**Step 04: Create Azure Resources**
```powershell
.\04-Create-Azure-Resources.ps1
```
- Creates Resource Group: `Multi-Factor-Auth-RG` (or custom name)
- Creates Storage Account for Function App
- Creates Function App with System-assigned Managed Identity
- Configures PowerShell 7.4 runtime
- Updates `mfa-config.ini` with Azure resource names

**Step 05: Configure Function App**
```powershell
.\05-Configure-Function-App.ps1
```
- Deploys function code (`enrol` and `upload-users`)
- Configures environment variables from INI file
- Sets up application settings:
  - SHAREPOINT_SITE_URL
  - SHAREPOINT_LIST_ID
  - MFA_GROUP_ID
  - LOGIC_APP_TRIGGER_URL (placeholder, updated by Step 06)
- Enables Application Insights (optional)

**Step 06: Deploy Invitation Logic App**
```powershell
.\06-Deploy-Logic-App.ps1
```
- Creates Logic App with System-assigned Managed Identity
- Grants Graph API permissions (Directory.Read.All, User.Read.All, etc.)
- Creates API connections (SharePoint, Office 365, Azure AD)
- Deploys workflow with dual triggers:
  - HTTP trigger (for immediate email sending)
  - Recurrence trigger (every 12 hours backup)
- Retrieves HTTP trigger URL
- Updates Function App with trigger URL
- Saves `ListId` to INI file
- **MANUAL STEP REQUIRED**: Authorize API connections in Azure Portal

**Step 07: Deploy Upload Portal**
```powershell
.\07-Deploy-Upload-Portal1.ps1
```
- Creates Azure AD app registration for portal
- Grants delegated permissions (User.Read, Sites.Read.All)
- Configures single-page application settings
- Deploys HTML portal to `$env:TEMP\upload-portal-deployed.html`
- Portal includes 3 tabs:
  - CSV Upload
  - Manual Entry
  - Reporting Dashboard

**Step 08: Setup Email Reports** (Optional)
```powershell
.\08-Deploy-Email-Reports.ps1
```
- Prompts for report recipients
- Prompts for frequency (Daily/Weekly)
- Creates Reports Logic App with Managed Identity
- Deploys scheduled workflow (runs at 9:00 AM)
- Grants Sites.Read.All permission
- Creates Office 365 API connection
- **MANUAL STEP REQUIRED**: Authorize Office 365 connection

**PART 3 - FIXES & PERMISSIONS (10-15 minutes)**

**Fix 1: Function Authentication**
```powershell
.\Fix-Function-Auth.ps1
```
- Enables System-assigned Managed Identity on Function App
- Configures authentication settings
- Validates identity configuration

**Fix 2: Graph API Permissions**
```powershell
.\Fix-Graph-Permissions.ps1
```
- Grants permissions to Function App Managed Identity:
  - User.Read.All
  - GroupMember.ReadWrite.All
  - Sites.ReadWrite.All
- Grants permissions to Invitation Logic App:
  - Directory.Read.All
  - User.Read.All
  - UserAuthenticationMethod.Read.All
  - GroupMember.ReadWrite.All
  - Group.Read.All
- Grants permissions to Reports Logic App:
  - Sites.Read.All
- Grants admin consent to Upload Portal:
  - User.Read (delegated)
  - Sites.Read.All (delegated)

**Fix 3: Logic App Permissions Check**
```powershell
.\Check-LogicApp-Permissions.ps1
```
- Validates all Logic App permissions
- Checks API connection status
- Reports any missing permissions

### Post-Deployment Manual Steps

**1. Authorize API Connections**
- Navigate to: Azure Portal → Resource Groups → Your Resource Group → Connections
- For each connection (`sharepointonline`, `office365`, `azuread`, `office365-reports`):
  - Click the connection name
  - Click "Edit API connection"
  - Click "Authorize"
  - Sign in with admin account
  - Click "Save"

**2. Verify Permissions**
- Azure Portal → Azure AD → Enterprise Applications
- Find each managed identity (Function App, Logic Apps)
- Verify API permissions are granted

**3. Test End-to-End**
- Open Upload Portal
- Upload test user
- Verify invitation email sent
- Click enrollment link
- Verify user added to MFA group
- Complete MFA setup
- Check SharePoint list for status updates

---

## User Workflow

### Administrator Experience

**1. Access Upload Portal**
- Open `upload-portal-deployed.html` in browser
- Sign in with Azure AD credentials

**2. Upload Users**
- **CSV Upload**: Upload file with columns: `Email,DisplayName`
- **Manual Entry**: Enter individual user details

**3. Monitor Progress**
- View real-time status in "Reporting" tab
- Check SharePoint list for detailed tracking
- Receive scheduled email reports (if configured)

### End User Experience

**1. Receive Email Invitation**
- Email subject: "Action Required: Enable Multi-Factor Authentication"
- Email from: `mfa-noreply@yourdomain.com` (or configured mailbox)
- Email contains:
  - Explanation of MFA requirement
  - Enrollment link
  - Support contact information

**2. Click Enrollment Link**
- Link format: `https://func-mfa-enrol-XXXXXX.azurewebsites.net/api/enrol?user=user@domain.com`
- Redirects to Microsoft MFA setup page: `https://aka.ms/mfasetup`

**3. Complete MFA Setup**
- Choose authentication method (Authenticator app, phone, etc.)
- Follow Microsoft's setup wizard
- Verify MFA working

**4. Automatic Processing**
- User automatically added to MFA security group
- Status updated to "Active" in tracking system
- No further action required

---

## Technical Flow

### Upload Flow (Immediate Processing)

```
┌─────────────────┐
│  Upload Portal  │ User uploads CSV or enters user manually
└────────┬────────┘
         │ POST /api/upload-users
         ▼
┌─────────────────────────┐
│  Function: upload-users │
├─────────────────────────┤
│ 1. Authenticate user    │
│ 2. Validate input       │
│ 3. Add users to SPO     │
│ 4. Set Status=Pending   │
│ 5. Trigger Logic App ◄──┼── HTTP POST to trigger URL
└────────┬────────────────┘
         │
         ▼
┌──────────────────────────┐
│  Logic App: Invitations  │
├──────────────────────────┤
│ 1. Query SPO list        │
│ 2. Filter Status=Pending │
│ 3. Get user details      │
│ 4. Send email invite     │
│ 5. Update Status=Sent    │
└──────────────────────────┘
         │
         ▼
    User receives email within 1-2 minutes
```

### Enrollment Flow (User Click)

```
┌──────────────┐
│  User Email  │ User clicks enrollment link
└──────┬───────┘
       │ GET /api/enrol?user=email@domain.com
       ▼
┌─────────────────────┐
│  Function: enrol    │
├─────────────────────┤
│ 1. Get user ID      │
│ 2. Add to MFA group │◄── Managed Identity with GroupMember.ReadWrite.All
│ 3. Update SPO:      │
│    - ClickedLinkDate│
│    - InGroup=true   │
│    - Status=Sent    │◄── Kept as "Sent" for Logic App monitoring
│ 4. Redirect user    │
└─────────┬───────────┘
          │ 302 Redirect
          ▼
┌──────────────────────┐
│ https://aka.ms/      │
│      mfasetup        │ Microsoft MFA setup wizard
└──────────────────────┘
```

### Monitoring Flow (Scheduled)

```
┌────────────────────────┐
│  Logic App: Invitation │
├────────────────────────┤
│ Trigger: Every 12 hours│
└────────┬───────────────┘
         │
         ▼
┌────────────────────────────┐
│ 1. Query SPO list          │
│    Status = Sent           │
├────────────────────────────┤
│ For each user:             │
│ 2. Check MFA methods       │◄── UserAuthenticationMethod.Read.All
│ 3. Check group membership  │◄── GroupMember.ReadWrite.All
│ 4. Update status:          │
│    - If MFA configured     │
│      → Status = Active     │
│    - If not yet configured │
│      → Resend email (once) │
└────────────────────────────┘
```

### Reporting Flow (Optional)

```
┌────────────────────────┐
│  Logic App: Reports    │
├────────────────────────┤
│ Trigger: Daily @ 9:00  │
└────────┬───────────────┘
         │
         ▼
┌────────────────────────────┐
│ 1. Query SPO list (all)    │◄── Sites.Read.All via Graph API
│ 2. Calculate statistics:   │
│    - Total users           │
│    - Pending count         │
│    - Sent count            │
│    - Active count          │
│    - Completed count       │
│    - Completion %          │
│ 3. Format HTML email       │
│ 4. Send to recipients      │◄── Office 365 Outlook connector
└────────────────────────────┘
```

---

## SharePoint List Schema

### List: "MFA Registration"

| Column Name        | Type            | Description                                    |
|--------------------|-----------------|------------------------------------------------|
| **Title**          | Single line text| User's email address (primary key)             |
| **DisplayName**    | Single line text| User's full name (from Azure AD)               |
| **InviteStatus**   | Choice          | Pending, Sent, Active, Completed               |
| **InviteSentDate** | Date/Time       | When invitation email was sent                 |
| **ClickedLinkDate**| Date/Time       | When user clicked enrollment link              |
| **InGroup**        | Yes/No          | True if user added to MFA group                |
| **AddedToGroupDate**| Date/Time      | When user was added to group                   |
| **BatchId**        | Single line text| Upload batch identifier (GUID)                 |
| **Created**        | Date/Time       | (System) When record created                   |
| **Modified**       | Date/Time       | (System) Last modification time                |

### Status Values

| Status      | Description                                                |
|-------------|------------------------------------------------------------|
| **Pending** | User uploaded, waiting for invitation email                |
| **Sent**    | Invitation sent, waiting for user action                   |
| **Active**  | User clicked link, added to group, MFA confirmed           |
| **Completed**| (Future use) Full onboarding completed                    |

---

## Function App Endpoints

### 1. **POST /api/upload-users**

**Purpose**: Accepts CSV or manual user uploads from portal

**Authentication**: Azure AD (delegated, user context)

**Request Body**:
```json
{
  "users": [
    {
      "email": "user1@domain.com",
      "displayName": "User One"
    },
    {
      "email": "user2@domain.com",
      "displayName": "User Two"
    }
  ]
}
```

**Response**:
```json
{
  "success": true,
  "batchId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "added": [
    {"email": "user1@domain.com", "status": "Added"},
    {"email": "user2@domain.com", "status": "Added"}
  ],
  "skipped": [],
  "errors": [],
  "logicAppTriggered": true
}
```

**Process**:
1. Validates user has access to SharePoint list
2. Validates email format
3. Checks for duplicates
4. Adds users to SharePoint with Status=Pending
5. Generates batch ID
6. Triggers Logic App via HTTP POST
7. Returns results

**Environment Variables Used**:
- SHAREPOINT_SITE_URL
- SHAREPOINT_LIST_ID
- LOGIC_APP_TRIGGER_URL

### 2. **GET /api/enrol**

**Purpose**: Processes enrollment link clicks

**Authentication**: Anonymous (public endpoint)

**Query Parameters**:
- `user` (required): User's email address

**Example**: `https://func-mfa-enrol-XXXXXX.azurewebsites.net/api/enrol?user=user@domain.com`

**Response**: HTTP 302 Redirect to `https://aka.ms/mfasetup`

**Process**:
1. Validates user email
2. Gets user ID from Azure AD
3. Adds user to MFA security group
4. Updates SharePoint:
   - ClickedLinkDate = current timestamp
   - InGroup = true
   - AddedToGroupDate = current timestamp
   - InviteStatus = "Sent" (unchanged, for Logic App monitoring)
5. Redirects to Microsoft MFA setup page

**Environment Variables Used**:
- MFA_GROUP_ID
- SHAREPOINT_SITE_URL
- SHAREPOINT_LIST_ID

**Error Handling**:
- If user already in group: Continue (non-fatal)
- If SharePoint update fails: Log warning, continue
- If Graph API fails: Return 500 error

---

## Logic App Workflows

### Invitation Logic App

**Resource Name**: `logic-mfa-invite-XXXXXX`

**Triggers**:
1. **HTTP Trigger** (Primary)
   - Triggered immediately by upload-users function
   - Receives: batchId, usersAdded, triggerTime
   
2. **Recurrence Trigger** (Backup)
   - Runs every 12 hours
   - Catches any missed users

**Workflow Steps**:

```
1. Trigger (HTTP or Recurrence)
   ↓
2. Get SharePoint List Items
   Filter: InviteStatus = 'Pending' OR InviteStatus = 'Sent'
   ↓
3. For Each User:
   ↓
   3a. Get User Details (Azure AD)
       - Display Name
       - User Principal Name
   ↓
   3b. Update Display Name in SharePoint
   ↓
   3c. Check MFA Status (Graph API)
       GET /users/{id}/authentication/methods
   ↓
   3d. Check Group Membership (Graph API)
       GET /groups/{mfaGroupId}/members/{userId}
   ↓
   3e. Parse MFA Methods
       Count non-default methods
   ↓
   3f. Condition: Has MFA?
       ├─ YES → Update Status to 'Active'
       └─ NO  → Continue
   ↓
   3g. Condition: In Group Already?
       ├─ YES → Skip email
       └─ NO  → Continue
   ↓
   3h. Condition: Already Sent Today?
       ├─ YES → Skip
       └─ NO  → Send Email
   ↓
   3i. Send Invitation Email (Office 365)
       To: User email
       From: No-reply mailbox
       Subject: "Action Required: Enable Multi-Factor Authentication"
       Body: HTML with enrollment link
   ↓
   3j. Update SharePoint
       - InviteSentDate = now
       - InviteStatus = 'Sent'
```

**Email Template**:
```html
<p>Hello,</p>
<p>As part of our ongoing security improvements, you are required to enable Multi-Factor Authentication (MFA) on your account.</p>
<p><strong>Action Required:</strong></p>
<p>Click the link below to enroll in MFA:</p>
<p><a href="https://func-mfa-enrol-XXXXXX.azurewebsites.net/api/enrol?user={email}">Enroll in MFA</a></p>
<p>This will redirect you to the Microsoft MFA setup page where you can choose your preferred authentication method.</p>
<p>If you have any questions, please contact IT Support.</p>
```

**Graph API Permissions Required**:
- Directory.Read.All
- User.Read.All
- UserAuthenticationMethod.Read.All
- GroupMember.ReadWrite.All
- Group.Read.All

**API Connections**:
- SharePoint Online (delegated)
- Office 365 Outlook (delegated)
- Azure AD (delegated)

### Email Reports Logic App

**Resource Name**: `logic-mfa-reports-XXXXXX`

**Trigger**:
- **Recurrence**: Daily or Weekly at 9:00 AM

**Workflow Steps**:

```
1. Trigger (Recurrence)
   ↓
2. Get SharePoint List Items (via Graph API)
   GET /sites/{site}/lists/{listId}/items?$expand=fields
   ↓
3. Parse Items Response
   ↓
4. Initialize Variables:
   - totalCount = length(items)
   - completedCount = 0
   - pendingCount = 0
   - sentCount = 0
   - activeCount = 0
   ↓
5. For Each Item:
   Count by InviteStatus
   ↓
6. Calculate Completion Percentage
   completedCount / totalCount * 100
   ↓
7. Format HTML Email Report
   ↓
8. Send Email (Office 365)
   To: Configured recipients
   Subject: "MFA Rollout Status Report - {date}"
```

**Email Report Format**:
```html
<h2>MFA Rollout Status Report</h2>
<p>Report Date: {currentDate}</p>

<table>
  <tr><th>Metric</th><th>Count</th></tr>
  <tr><td>Total Users</td><td>{totalCount}</td></tr>
  <tr><td>Pending</td><td>{pendingCount}</td></tr>
  <tr><td>Invitations Sent</td><td>{sentCount}</td></tr>
  <tr><td>MFA Active</td><td>{activeCount}</td></tr>
  <tr><td>Completion Rate</td><td>{percentage}%</td></tr>
</table>

<h3>Recent Activity</h3>
<ul>
  <li>Users added this week: {weeklyCount}</li>
  <li>Users activated this week: {weeklyActiveCount}</li>
</ul>
```

**Graph API Permissions Required**:
- Sites.Read.All

**API Connections**:
- Office 365 Outlook (delegated)

---

## Status Lifecycle

### Status Transition Diagram

```
┌─────────┐
│ Upload  │
│ Portal  │
└────┬────┘
     │
     ▼
┌──────────────┐     Logic App      ┌──────────────┐
│   PENDING    │────sends email────►│     SENT     │
└──────────────┘                    └──────┬───────┘
                                           │
                              User clicks  │
                              enrollment   │
                              link         │
                                           ▼
                    ┌──────────────────────────────┐
                    │      SENT                    │
                    │  (InGroup=true,              │
                    │   ClickedLinkDate set)       │
                    └──────────┬───────────────────┘
                               │
                  Logic App    │
                  checks MFA   │
                  status       │
                               ▼
                    ┌──────────────────┐
                    │     ACTIVE       │
                    │  (MFA confirmed) │
                    └──────────────────┘
```

### Status Details

**PENDING**
- **Set By**: upload-users function
- **When**: User first added to system
- **SharePoint Fields**:
  - InviteStatus = "Pending"
  - InviteSentDate = null
  - ClickedLinkDate = null
  - InGroup = false
- **Next Action**: Logic App will send invitation email

**SENT**
- **Set By**: Invitation Logic App
- **When**: Invitation email successfully sent
- **SharePoint Fields**:
  - InviteStatus = "Sent"
  - InviteSentDate = timestamp
  - ClickedLinkDate = null (or set if user clicked)
  - InGroup = false (or true if user clicked)
- **Next Action**: Wait for user to click link or Logic App to detect MFA setup

**ACTIVE**
- **Set By**: Invitation Logic App
- **When**: MFA authentication methods detected for user
- **SharePoint Fields**:
  - InviteStatus = "Active"
  - InviteSentDate = timestamp
  - ClickedLinkDate = timestamp (if link was clicked)
  - InGroup = true
- **Next Action**: No further automated actions

### Field Update Matrix

| Action | Status | InviteSentDate | ClickedLinkDate | InGroup | AddedToGroupDate |
|--------|--------|----------------|-----------------|---------|------------------|
| **Upload** | Pending | null | null | false | null |
| **Send Email** | Sent | now | null | false | null |
| **Click Link** | Sent | (kept) | now | true | now |
| **MFA Confirmed** | Active | (kept) | (kept) | true | (kept) |

---

## Troubleshooting

### Common Issues

#### Issue: Invitation emails not being sent

**Symptoms**: Users uploaded but InviteStatus stays "Pending"

**Possible Causes**:
1. Logic App not triggered
2. API connections not authorized
3. Logic App permissions missing

**Solutions**:
```powershell
# Check Logic App trigger URL is set
az functionapp config appsettings list --name func-mfa-enrol-XXXXXX --resource-group Multi-Factor-Auth-RG --query "[?name=='LOGIC_APP_TRIGGER_URL'].value"

# Manually trigger Logic App
# Azure Portal → Logic Apps → Your Logic App → Run Trigger → Manual

# Check API connections
# Azure Portal → Resource Group → Connections → Authorize each connection

# Re-grant permissions
.\Fix-Graph-Permissions.ps1
```

#### Issue: User not added to MFA group

**Symptoms**: ClickedLinkDate set but InGroup = false

**Possible Causes**:
1. Function App managed identity not configured
2. Missing GroupMember.ReadWrite.All permission
3. MFA Group ID incorrect

**Solutions**:
```powershell
# Check Function App has managed identity
az functionapp identity show --name func-mfa-enrol-XXXXXX --resource-group Multi-Factor-Auth-RG

# Re-grant permissions
.\Fix-Graph-Permissions.ps1

# Verify MFA Group ID
$config = Get-Content mfa-config.ini
# Check [Security] section, MFAGroupId value
```

#### Issue: "WorkflowManagedIdentityNotSpecified" error

**Symptoms**: Logic App fails with managed identity error

**Possible Causes**:
1. Managed identity not enabled
2. Permissions not granted yet

**Solutions**:
```powershell
# Enable managed identity
az logicapp identity assign --resource-group Multi-Factor-Auth-RG --name logic-mfa-invite-XXXXXX

# Grant permissions
.\Fix-Graph-Permissions.ps1

# Wait 5 minutes for propagation
Start-Sleep -Seconds 300
```

#### Issue: Upload portal authentication fails

**Symptoms**: "AADSTS50011: Reply URL mismatch"

**Possible Causes**:
1. Redirect URI not configured
2. Wrong tenant ID

**Solutions**:
```powershell
# Check app registration redirect URIs
az ad app show --id <ClientId> --query "web.redirectUris"

# Should include: http://localhost
# Add if missing:
az ad app update --id <ClientId> --web-redirect-uris "http://localhost"
```

#### Issue: SharePoint updates failing

**Symptoms**: Users added but SharePoint list not updating

**Possible Causes**:
1. Certificate authentication failed
2. List ID incorrect
3. Sites.ReadWrite.All permission missing

**Solutions**:
```powershell
# Test SharePoint connection
Connect-PnPOnline -Url "https://yourtenant.sharepoint.com/sites/MFAOps" `
    -ClientId <ClientId> `
    -Thumbprint <Thumbprint> `
    -Tenant <TenantId>

Get-PnPList | Where-Object {$_.Title -eq "MFA Registration"}

# Re-deploy if needed
.\02-Provision-SharePoint.ps1
```

### Monitoring & Diagnostics

#### Check Function App Logs
```powershell
# Stream logs in real-time
func azure functionapp logstream func-mfa-enrol-XXXXXX

# Or via Azure Portal
# Function App → Monitoring → Log Stream
```

#### Check Logic App Run History
```
Azure Portal → Logic Apps → Your Logic App → Overview → Runs history
Click on any run to see:
- Trigger status
- Each action's inputs/outputs
- Error messages
```

#### Query SharePoint List
```powershell
# Count users by status
Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantId
$list = Get-PnPList -Identity "MFA Registration"
$items = Get-PnPListItem -List $list -PageSize 1000

$items | Group-Object {$_.FieldValues.InviteStatus} | Select-Object Name, Count
```

#### Check Application Insights
```
Azure Portal → Function App → Application Insights
Analyze:
- Request rates
- Failure rates
- Response times
- Custom traces
```

---

## Configuration Reference

### mfa-config.ini Structure

```ini
[Tenant]
TenantId = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SubscriptionId = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

[Azure]
ResourceGroup = Multi-Factor-Auth-RG
Region = uksouth
FunctionAppName = func-mfa-enrol-XXXXXX
StorageAccountName = stmfaenrolXXXXXX

[SharePoint]
SiteUrl = https://yourtenant.sharepoint.com/sites/MFAOps
SiteName = MFAOps
SiteOwner = admin@yourtenant.onmicrosoft.com
ListTitle = MFA Registration
ListId = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ClientId = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
CertificateThumbprint = XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

[Email]
NoReplyMailbox = mfa-noreply@yourdomain.com

[Security]
MFAGroupName = MFA-Registration-Required
MFAGroupId = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

[LogicApp]
LogicAppName = logic-mfa-invite-XXXXXX
TriggerUrl = https://prod-XX.region.logic.azure.com:443/workflows/...

[UploadPortal]
ClientId = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
TenantId = xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

[EmailReports]
LogicAppName = logic-mfa-reports-XXXXXX
Recipients = admin@yourdomain.com
Frequency = Day
```

---

## Security Considerations

### Authentication & Authorization

**Function App**:
- Uses System-assigned Managed Identity
- No credentials stored in code or configuration
- Minimal permissions (least privilege principle)

**Logic Apps**:
- Use System-assigned Managed Identities
- API connections use delegated authentication
- Require manual authorization for sensitive operations

**Upload Portal**:
- Azure AD authentication required
- Users must have access to SharePoint list
- Single-page app (no server-side secrets)

**SharePoint Access**:
- Certificate-based authentication for PowerShell
- Certificate stored securely in user profile
- Limited to specific app registration

### Data Privacy

**PII Handling**:
- Email addresses stored in SharePoint (business necessity)
- Display names retrieved from Azure AD (not stored redundantly)
- No sensitive authentication data stored

**Data Retention**:
- SharePoint list can be archived after onboarding complete
- No data stored in Function App beyond logs
- Application Insights: 90-day retention by default

**Access Control**:
- SharePoint list permissions control who can view tracking data
- Function App logs accessible only to Azure administrators
- Logic App run history contains user emails (limit access)

### Compliance

**GDPR Considerations**:
- User email addresses are processed for legitimate business purpose
- Users can request deletion from SharePoint list
- Automated processing with human oversight (admin reports)

**Audit Trail**:
- All SharePoint changes logged (Modified By, Modified Date)
- Function App logs in Application Insights
- Logic App run history shows all actions taken

---

## Maintenance & Operations

### Regular Maintenance Tasks

**Daily**:
- Review email reports (if configured)
- Check for users stuck in "Pending" or "Sent" status
- Monitor Function App errors in Application Insights

**Weekly**:
- Review Logic App run history for failures
- Check API connection status (may expire)
- Verify certificate hasn't expired (SharePoint access)

**Monthly**:
- Archive completed users from SharePoint list
- Review and update invitation email template if needed
- Check for Azure cost anomalies

**Quarterly**:
- Review security group membership vs. SharePoint list
- Audit Function App permissions
- Update PowerShell modules if security updates available

### Scaling Considerations

**Small Deployments** (< 500 users):
- Default Consumption Plan sufficient
- No changes needed

**Medium Deployments** (500-5000 users):
- Consider App Service Plan for Function App (more predictable performance)
- Increase SharePoint list view threshold awareness
- Monitor Logic App throttling limits

**Large Deployments** (> 5000 users):
- Use batching for SharePoint queries (1000 items per batch)
- Consider splitting into multiple lists by department
- Implement rate limiting in Function App
- Use Premium Logic Apps for higher throughput

### Backup & Disaster Recovery

**SharePoint List**:
- Backed up automatically by Microsoft 365
- Can export to CSV from portal
- Consider scheduled exports via PowerShell

**Azure Resources**:
- Function App code stored in Git (version control recommended)
- Logic App definitions exported to JSON (saved in logs/ folder)
- Configuration in mfa-config.ini (store in secure repository)

**Recovery Procedures**:
1. Restore SharePoint list from backup
2. Redeploy Azure resources using Run-Complete-Deployment.ps1
3. Restore mfa-config.ini from backup
4. Re-authorize API connections
5. Test with single user

---

## Appendices

### Appendix A: PowerShell Modules Required

| Module | Version | Purpose |
|--------|---------|---------|
| Az.Accounts | Latest | Azure authentication |
| Az.Resources | Latest | Azure resource management |
| Az.Functions | Latest | Function App deployment |
| PnP.PowerShell | 2.x | SharePoint operations |
| Microsoft.Graph.Authentication | Latest | Graph API permissions |
| ExchangeOnlineManagement | Latest | Shared mailbox creation |

### Appendix B: Azure Resources Created

| Resource Type | Name Pattern | Purpose |
|---------------|--------------|---------|
| Resource Group | Multi-Factor-Auth-RG | Container for all resources |
| Storage Account | stmfaenrolXXXXXX | Function App storage |
| Function App | func-mfa-enrol-XXXXXX | Hosts enrollment functions |
| Logic App | logic-mfa-invite-XXXXXX | Sends invitation emails |
| Logic App | logic-mfa-reports-XXXXXX | Sends status reports |
| API Connection | sharepointonline | SharePoint connector |
| API Connection | office365 | Outlook email connector |
| API Connection | azuread | Azure AD connector |
| API Connection | office365-reports | Reports email connector |

### Appendix C: Useful Commands

**Check deployment status**:
```powershell
# Get Function App status
az functionapp show --name func-mfa-enrol-XXXXXX --resource-group Multi-Factor-Auth-RG --query "state"

# Get Logic App status
az logicapp show --name logic-mfa-invite-XXXXXX --resource-group Multi-Factor-Auth-RG --query "state"

# List all resources in group
az resource list --resource-group Multi-Factor-Auth-RG --output table
```

**Manual trigger Logic App**:
```powershell
# Get trigger URL
$config = Get-Content mfa-config.ini | ConvertFrom-StringData
$triggerUrl = $config.TriggerUrl

# Trigger with curl
$body = @{
    batchId = "manual-trigger"
    usersAdded = 0
    triggerTime = (Get-Date).ToString("o")
} | ConvertTo-Json

Invoke-RestMethod -Uri $triggerUrl -Method Post -Body $body -ContentType "application/json"
```

**Export SharePoint list**:
```powershell
Connect-PnPOnline -Url $siteUrl -ClientId $clientId -Thumbprint $thumbprint -Tenant $tenantId
$items = Get-PnPListItem -List "MFA Registration" -PageSize 1000
$items | ForEach-Object {
    [PSCustomObject]@{
        Email = $_.FieldValues.Title
        DisplayName = $_.FieldValues.DisplayName
        Status = $_.FieldValues.InviteStatus
        InviteSent = $_.FieldValues.InviteSentDate
        ClickedLink = $_.FieldValues.ClickedLinkDate
        InGroup = $_.FieldValues.InGroup
    }
} | Export-Csv -Path "MFA-Export-$(Get-Date -Format 'yyyy-MM-dd').csv" -NoTypeInformation
```

---

## Support & Contact

### Getting Help

**Documentation**: This document (keep updated version)

**Azure Resources**:
- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
- [Logic Apps Documentation](https://docs.microsoft.com/azure/logic-apps/)
- [Microsoft Graph API](https://docs.microsoft.com/graph/)

**Community Support**:
- Azure Functions: Stack Overflow tag `azure-functions`
- Logic Apps: Microsoft Q&A
- SharePoint PnP: GitHub issues

### Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-26 | Initial documentation |

---

**Document End**
