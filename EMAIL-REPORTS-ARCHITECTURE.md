# Email Reports — Architecture

## System Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    MFA ONBOARDING SYSTEM                         │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────────────┐     ┌──────────────┐
│ Upload Portal│────▶│  Function App         │────▶│  SharePoint  │
│ (HTML SPA)   │     │  upload-users         │     │  List        │
└──────────────┘     └──────────────────────┘     └──────┬───────┘
                                                         │
                     ┌───────────────────────────────────┤
                     │                                   │
                     ▼                                   ▼
              ┌──────────────┐                   ┌──────────────────┐
              │ Logic App    │                   │ Logic App        │
              │ Invitations  │                   │ Email Reports    │
              │              │                   │                  │
              │ • Send email │                   │ • Read all items │
              │ • Check MFA  │                   │ • Count statuses │
              │ • Escalate   │                   │ • Build summary  │
              └──────┬───────┘                   └────────┬─────────┘
                     │                                    │
                     ▼                                    ▼
              ┌──────────────┐                   ┌──────────────────┐
              │ User receives│                   │ Admin receives   │
              │ MFA invite   │                   │ report email     │
              └──────────────┘                   └──────────────────┘
```

---

## Email Reports Logic App — Detailed Flow

```
┌──────────────────────────────────────────────────────────┐
│  TRIGGER: Recurrence                                      │
│  Daily 9 AM  or  Weekly Monday 9 AM                       │
└──────────────────────┬───────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────┐
│  GET SharePoint List Items                                │
│  Graph API: GET /sites/{siteId}/lists/{listId}/items     │
│  Auth: Managed Identity                                   │
└──────────────────────┬───────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────┐
│  INITIALISE COUNTERS                                      │
│  TotalCount = 0, CompletedCount = 0, PendingCount = 0   │
└──────────────────────┬───────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────┐
│  FOR EACH item in SharePoint results                      │
│  ├─ Increment TotalCount                                 │
│  ├─ If InGroup=true OR InviteStatus in                   │
│  │     (AddedToGroup, Active):  Increment CompletedCount │
│  └─ Else: Increment PendingCount                         │
└──────────────────────┬───────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────┐
│  BUILD EMAIL BODY                                         │
│  HTML template with:                                      │
│  • Executive summary (Total, Completed, Pending, Rate)   │
│  • Quick links to SharePoint + Portal                    │
│  • Date and branding                                      │
└──────────────────────┬───────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────┐
│  SEND EMAIL                                               │
│  Via O365 API connection                                  │
│  To: [EmailReports].Recipients                            │
│  From: Shared mailbox                                     │
└──────────────────────────────────────────────────────────┘
```

---

## Authentication Model

| Component | Auth Method |
|-----------|------------|
| SharePoint read | Managed Identity with `Sites.Read.All` |
| Email send | O365 API connection (one-time authorisation) |
| Logic App trigger | Azure-managed recurrence (no external trigger) |

---

## Permissions Required

| Permission | Type | Purpose |
|------------|------|---------|
| `Sites.Read.All` | Application | Read SharePoint list items via Graph |

Granted automatically by `Fix-Graph-Permissions.ps1` or during step 8 deployment.
