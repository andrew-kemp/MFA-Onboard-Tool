# Email Reports Feature

## Overview

Automated scheduled email reports showing MFA rollout progress, sent to administrators via a separate Logic App (`logic-mfa-reports-{suffix}`).

---

## What Gets Deployed

| Resource | Description |
|----------|-------------|
| Logic App | `logic-mfa-reports-{suffix}` with system-assigned Managed Identity |
| O365 Connection | API connection for sending email (requires one-time authorisation) |
| Graph Permissions | `Sites.Read.All` granted to the Logic App's Managed Identity |

---

## Email Report Contents

### Executive Summary
- **Total Users** — count of all users in the rollout
- **Completed** — users where `InGroup=true`, `InviteStatus=AddedToGroup`, or `InviteStatus=Active`
- **Pending** — all other users
- **Completion Rate** — `(Completed / Total) × 100`

### Quick Links
- Direct link to the SharePoint tracking list
- Direct link to the Upload Portal reports tab

---

## Deployment

### Via Full Deployment
```powershell
.\Setup.ps1          # Option [1] — runs all 8 steps including email reports
```

### Standalone
```powershell
.\08-Deploy-Email-Reports.ps1
```

### Post-Deployment: Authorise the O365 Connection

The Office 365 API connection requires a one-time authorisation:

1. Open **Azure Portal** → **Resource Groups** → your resource group
2. Find the connection named **office365-reports**
3. Click **Edit API connection** → **Authorize**
4. Sign in with an account that can send email from the shared mailbox
5. Click **Save**

> Without this step, report emails will not be sent.

---

## Configuration

Stored in `mfa-config.ini` under `[EmailReports]`:

```ini
[EmailReports]
LogicAppName=logic-mfa-reports-123456
Recipients=admin1@domain.com,admin2@domain.com
Frequency=Day
```

| Key | Values | Description |
|-----|--------|-------------|
| `Recipients` | Comma-separated emails | Who receives the report |
| `Frequency` | `Day` or `Week` | Daily 9 AM, or Weekly Monday 9 AM |

To change recipients or frequency, edit `mfa-config.ini` and redeploy:

```powershell
.\08-Deploy-Email-Reports.ps1
```

---

## Testing

1. **Azure Portal** → **Logic Apps** → select `logic-mfa-reports-{suffix}`
2. Click **Run Trigger** → **Recurrence**
3. Check your inbox for the report
4. View **Run History** for success/failure details

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Emails not sending | Azure Portal → Connections → `office365-reports` → Edit → Authorize → Save |
| Permission errors | Run `Fix-Graph-Permissions.ps1` to re-grant `Sites.Read.All` |
| Logic App disabled | Azure Portal → Logic App → Overview → Enable |
| Wrong data | Open SharePoint list directly and verify column values match |

---

## Integration

The email report complements the Upload Portal's **Reports tab**, which provides real-time interactive reporting with filtering and CSV export. The email report is a scheduled summary delivered to inboxes — no login required.
