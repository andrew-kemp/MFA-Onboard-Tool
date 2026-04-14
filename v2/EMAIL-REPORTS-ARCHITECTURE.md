# MFA Onboarding - Email Reports Architecture

## System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     MFA ONBOARDING SYSTEM                       │
│                    with Email Reports                            │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐
│   ADMIN      │
│   UPLOADS    │
│   USERS      │
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────────┐
│  UPLOAD PORTAL (Static Web App)                                  │
│  ┌────────────┬──────────────┬───────────────┐                  │
│  │ CSV Upload │ Manual Entry │ Reports Tab   │                  │
│  │            │              │ (Live Data)   │                  │
│  └────────────┴──────────────┴───────────────┘                  │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│  FUNCTION APP - upload-users                                     │
│  • Validates CSV data                                            │
│  • Writes to SharePoint list                                     │
│  • Returns batch ID                                              │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│  SHAREPOINT LIST (Central Data Store)                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ • Title (UPN)                • InviteSentDate            │   │
│  │ • InviteStatus               • SourceBatchId             │   │
│  │ • InGroup (boolean)          • ClickedLinkDate           │   │
│  │ • AddedToGroupDate                                       │   │
│  └──────────────────────────────────────────────────────────┘   │
└──┬──────────────┬────────────────┬──────────────────────────────┘
   │              │                │
   │              │                │
   ▼              ▼                ▼
┌──────────┐  ┌──────────┐  ┌────────────────────┐
│ LOGIC    │  │ FUNCTION │  │ LOGIC APP          │
│ APP      │  │ APP      │  │ EMAIL REPORTS      │
│ INVITES  │  │ enrol    │  │ (NEW!)             │
└────┬─────┘  └────┬─────┘  └─────┬──────────────┘
     │             │               │
     │             │               │
     ▼             ▼               ▼
┌─────────┐  ┌─────────┐  ┌──────────────┐
│ USER    │  │ USER    │  │ ADMIN        │
│ RECEIVES│  │ ADDED   │  │ RECEIVES     │
│ EMAIL   │  │ TO GROUP│  │ REPORT EMAIL │
└─────────┘  └─────────┘  └──────────────┘
```

---

## Email Reports Logic App - Detailed Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    TRIGGER (Recurrence)                       │
│  • Daily at 9:00 AM OR Weekly Monday 9:00 AM                │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│             ACTION: Get SharePoint List Items                 │
│  • Graph API: GET /sites/{siteId}/lists/{listId}/items      │
│  • Authentication: Managed Identity                          │
│  • Returns: All user enrollment records                      │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                   ACTION: Parse JSON                          │
│  • Extract 'value' array from Graph response                 │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│            ACTIONS: Initialize Variables                      │
│  • totalCount = length of items array                        │
│  • completedCount = 0                                        │
│  • pendingCount = 0                                          │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│              ACTION: For Each Item (Loop)                     │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  IF: InGroup = true OR InviteStatus = "AddedToGroup"  │  │
│  │      THEN: Increment completedCount                    │  │
│  │      ELSE: Increment pendingCount                      │  │
│  └────────────────────────────────────────────────────────┘  │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│          ACTION: Calculate Completion Rate                    │
│  • Formula: (completedCount / totalCount) * 100              │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                ACTION: Build Email Body (HTML)                │
│  • Executive summary with counts                             │
│  • Completion rate percentage                                │
│  • Quick links to SharePoint & Portal                        │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────┐
│             ACTION: Send Email (Office 365)                   │
│  • To: Configured recipients                                 │
│  • Subject: "MFA Rollout Report - DATE - XX% Complete"      │
│  • Body: HTML email with metrics                            │
└──────────────────────────────────────────────────────────────┘
```

---

## Data Flow - Status Calculation

```
┌────────────────────────────────────────────────────────────────┐
│                   SharePoint List Record                       │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Title: user@domain.com                                  │ │
│  │  InviteStatus: "AddedToGroup"                           │ │
│  │  InGroup: true                                           │ │
│  │  ClickedLinkDate: 2024-12-14 10:30:00                  │ │
│  │  AddedToGroupDate: 2024-12-14 10:30:05                 │ │
│  │  InviteSentDate: 2024-12-13 09:00:00                   │ │
│  │  SourceBatchId: batch-20241213-001                      │ │
│  └──────────────────────────────────────────────────────────┘ │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│                   Logic App Evaluation                          │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  CHECK: Is InGroup = true?          → YES               │ │
│  │  OR:    Is InviteStatus = "AddedToGroup"? → YES         │ │
│  │  OR:    Is InviteStatus = "Active"? → NO                │ │
│  │                                                          │ │
│  │  RESULT: User counts as COMPLETED                       │ │
│  │  ACTION: Increment completedCount                       │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                    Email Report Output                          │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Total Users: 250                                        │ │
│  │  Completed: 180  (this user contributes to this count)  │ │
│  │  Pending: 70                                             │ │
│  │  Completion Rate: 72%                                    │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

---

## Permission Flow

```
┌────────────────────────────────────────────────────────────────┐
│               LOGIC APP (Managed Identity)                      │
│  Principal ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx           │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ Granted by Fix-Graph-Permissions.ps1
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│              MICROSOFT GRAPH API                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Application Permission: Sites.Read.All                  │ │
│  │  Scope: Organization-wide                                │ │
│  │  Consent: Admin granted                                  │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ Allows access to
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│              SHAREPOINT ONLINE SITE                             │
│  Site: https://tenant.sharepoint.com/sites/MFAOnboarding      │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  List: MFA Enrollment Tracking                           │ │
│  │  List ID: {guid}                                         │ │
│  │                                                          │ │
│  │  Logic App can READ all items                           │ │
│  │  (Uses Graph API endpoint)                              │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

---

## Office 365 Connection Flow

```
┌────────────────────────────────────────────────────────────────┐
│            LOGIC APP (Office 365 Connection)                    │
│  Connection Name: office365-reports                            │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ Requires authorization
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│              AZURE API CONNECTION                               │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Type: Office 365 Outlook                                │ │
│  │  API: /v2/Mail (Send Email)                              │ │
│  │  Auth: OAuth 2.0 Delegated                               │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ Admin authorizes once
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│              OFFICE 365 ACCOUNT                                 │
│  Email: admin@domain.com                                       │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │  Permission: Mail.Send (delegated)                       │ │
│  │  Allows: Logic App to send email AS this user            │ │
│  └──────────────────────────────────────────────────────────┘ │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ Sends to
                         │
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                   REPORT RECIPIENTS                             │
│  • admin1@domain.com                                           │
│  • admin2@domain.com                                           │
│  • admin3@domain.com                                           │
└────────────────────────────────────────────────────────────────┘
```

---

## Complete Reporting Ecosystem

```
┌──────────────────────────────────────────────────────────────────┐
│                  REPORTING SUITE OVERVIEW                        │
└──────────────────────────────────────────────────────────────────┘

┌─────────────────────┐     ┌─────────────────────┐
│  EMAIL REPORTS      │     │  PORTAL DASHBOARD   │
│  (Logic App)        │     │  (Real-Time)        │
├─────────────────────┤     ├─────────────────────┤
│ • Daily/Weekly      │     │ • Executive Summary │
│ • Automated         │     │ • Status Breakdown  │
│ • HTML formatted    │     │ • Recent Activity   │
│ • Quick Links       │     │ • Needing Attention │
│                     │     │ • Batch Performance │
└──────────┬──────────┘     └──────────┬──────────┘
           │                           │
           │                           │
           └────────┬──────────────────┘
                    │
                    │ Both read from
                    │
                    ▼
┌──────────────────────────────────────────────────────────────────┐
│              SHAREPOINT LIST (Single Source of Truth)            │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  • Real-time updates from Function App                     │ │
│  │  • Single data store for all reporting                     │ │
│  │  • Graph API access for both Logic App and Portal         │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘

     ┌─────────────────────────────────────────────────────┐
     │           ALSO AVAILABLE                            │
     ├─────────────────────────────────────────────────────┤
     │  • Deployment Logs (logs/*.log)                     │
     │  • Technical Summary (logs/TECHNICAL-SUMMARY*.txt)  │
     │  • Logic App JSON (logs/LogicApp-Deployed*.json)   │
     └─────────────────────────────────────────────────────┘
```

---

## Timeline View - User Journey with Reports

```
TIME │ EVENT                              │ VISIBILITY
─────┼────────────────────────────────────┼─────────────────────────
Day 0│ Admin uploads CSV                  │ Portal: CSV Upload tab
     │ ↓                                  │
     │ Function creates SharePoint items │ Portal: Manual list view
     │ ↓                                  │
     │ Logic App sends invitation emails │ SharePoint: InviteStatus=Sent
─────┼────────────────────────────────────┼─────────────────────────
Day 1│ 9:00 AM - Daily email report sent │ Admin inbox: First report
     │   Shows: 250 total, 0 completed   │ "0% Complete"
     │ ↓                                  │
     │ User clicks enrollment link       │ Portal Reports: Recent Activity
     │ ↓                                  │
     │ Function adds to MFA group        │ SharePoint: InGroup=true
     │ ↓                                  │
     │ Function updates SharePoint       │ Portal Reports: Updated
─────┼────────────────────────────────────┼─────────────────────────
Day 2│ 9:00 AM - Daily email report sent │ Admin inbox: Second report
     │   Shows: 250 total, 45 completed  │ "18% Complete"
     │ ↓                                  │
     │ Admin checks Portal Reports tab   │ Portal: Real-time dashboard
     │   Sees: Users needing attention   │ 205 pending 1+ days
─────┼────────────────────────────────────┼─────────────────────────
Day 5│ 9:00 AM - Daily email report sent │ Admin inbox: Progress report
     │   Shows: 250 total, 180 completed │ "72% Complete"
     │ ↓                                  │
     │ Admin reviews pending users       │ Portal: Needing Attention
     │   Sees: 70 pending 3+ days        │ Follow-up needed
─────┼────────────────────────────────────┼─────────────────────────
Week │ Monday 9:00 AM - Weekly report    │ Admin inbox: Weekly summary
  1  │   Shows: 250 total, 235 completed │ "94% Complete"
     │   Progress: +94% since start      │
─────┴────────────────────────────────────┴─────────────────────────
```

---

*MFA Onboarding System - Email Reports Architecture*
*Visual Reference Guide*
