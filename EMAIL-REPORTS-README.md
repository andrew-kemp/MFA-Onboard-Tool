# Email Reports Feature - README

## Overview
Automated daily or weekly email reports showing MFA rollout progress, sent to administrators.

## What Gets Deployed
- **Logic App**: `logic-mfa-reports-xxxxxx` with Managed Identity
- **Office 365 Connection**: For sending emails
- **Scheduled Trigger**: Daily 9 AM or Weekly Monday 9 AM
- **Graph API Permissions**: Sites.Read.All (for reading SharePoint list)

## Email Report Contents

### Executive Summary Dashboard
- 📊 **Total Users**: Complete count of all users in the rollout
- ✅ **Completed**: Users who have completed MFA enrollment (InGroup = true)
- ⏳ **Pending**: Users who haven't completed enrollment yet
- 📈 **Completion Rate**: Percentage of users completed

### Quick Links
- Direct link to SharePoint list
- Direct link to Upload Portal for detailed analytics

## Deployment Steps

### Automated (Part of Run-Part2-Deploy-Enhanced.ps1)
1. Run `Run-Part2-Deploy-Enhanced.ps1`
2. When prompted, choose "Y" for email reports setup
3. Enter recipient email addresses (comma-separated)
4. Select frequency:
   - Daily (9 AM every day)
   - Weekly (Monday 9 AM)
   - Both
5. After deployment, authorize the Office 365 connection

### Manual (Standalone)
```powershell
.\08-Deploy-Email-Reports.ps1
```

## Post-Deployment Configuration

### Required: Authorize Office 365 Connection
The Office 365 API connection requires one-time authorization:

1. Go to **Azure Portal** > **Resource Groups** > Your Resource Group
2. Find the connection named **office365-reports**
3. Click **Edit API connection**
4. Click **Authorize**
5. Sign in with an account that can send emails
6. Click **Save**

**Important**: Without this step, emails will not be sent!

## Testing

### Manual Test Run
1. Go to **Azure Portal** > **Logic Apps**
2. Select your reports Logic App (`logic-mfa-reports-xxxxxx`)
3. Click **Run Trigger** > **Recurrence**
4. Check your email inbox for the report

### Check Run History
1. Open your Logic App in Azure Portal
2. Click **Overview**
3. View **Run History** for successful/failed runs
4. Click any run to see detailed execution flow

## Configuration

### Stored in mfa-config.ini
```ini
[EmailReports]
LogicAppName=logic-mfa-reports-123456
Recipients=admin1@domain.com,admin2@domain.com
Frequency=Day
```

### Change Recipients
Edit the `Recipients` value in `mfa-config.ini` [EmailReports] section, then:
```powershell
# Redeploy the Logic App to update recipients
.\08-Deploy-Email-Reports.ps1
```

### Change Frequency
Edit the `Frequency` value to `Day` or `Week`, then redeploy.

## Email Report Sample

```
📊 MFA Rollout Report
Thursday, December 14, 2024

Executive Summary
┌─────────────┬──────────────┐
│ 250         │ 180          │
│ Total Users │ Completed    │
├─────────────┼──────────────┤
│ 70          │ 72%          │
│ Pending     │ Completion   │
└─────────────┴──────────────┘

Quick Links
📋 View SharePoint List
📤 Upload Portal

💡 Tip: Log in to the Upload Portal and visit
the Reports tab for detailed analytics and
user-level breakdowns.
```

## Status Calculation Logic

### Completed Count
Users are counted as "Completed" when:
- `InGroup` = `true` (successfully added to MFA group), OR
- `InviteStatus` = `"AddedToGroup"`, OR
- `InviteStatus` = `"Active"`

### Pending Count
All other users are counted as "Pending"

### Completion Rate
`(Completed / Total) * 100`

## Troubleshooting

### Emails Not Sending
1. **Check Office 365 Connection**:
   - Azure Portal > Connections > office365-reports
   - Status should be "Connected"
   - If not, click Edit > Authorize > Save

2. **Check Logic App Run History**:
   - Azure Portal > Logic Apps > Your App
   - Look for failed runs
   - Click failed run to see error details

3. **Check Permissions**:
   - Logic App Managed Identity should have `Sites.Read.All` on Microsoft Graph
   - Run Fix-Graph-Permissions.ps1 to re-grant

### Wrong Data in Report
1. **Verify SharePoint List**:
   - Open SharePoint list directly
   - Confirm data is up to date
   - Check column names match: `InGroup`, `InviteStatus`, `Title`

2. **Check Logic App Query**:
   - Logic App > Logic App Designer
   - Expand "Get_SharePoint_List_Items" action
   - Verify Graph API URL is correct

### Report Not Sending at Scheduled Time
1. **Check Trigger Schedule**:
   - Logic App > Logic App Designer
   - Click on "Recurrence" trigger
   - Verify frequency and time settings

2. **Check Logic App Status**:
   - Logic App > Overview
   - Status should be "Enabled"
   - If disabled, click "Enable"

## Advanced Customization

### Modify Email Template
1. Open **08-Deploy-Email-Reports.ps1**
2. Find the `'Build_Email_Body'` action
3. Modify the HTML content
4. Redeploy: `.\08-Deploy-Email-Reports.ps1`

### Add More Metrics
1. Add new variables after `Initialize_Pending_Count`
2. Add counting logic in the `Count_Statuses` foreach loop
3. Include new metrics in email body template
4. Redeploy

### Change Email Time
1. In `08-Deploy-Email-Reports.ps1`, find:
   ```powershell
   hours = @("9")
   minutes = @(0)
   ```
2. Change to desired time (24-hour format)
3. Redeploy

## Integration with Other Features

### Works With
- ✅ **SharePoint List**: Reads directly from MFA tracking list
- ✅ **Upload Portal**: Links to portal in email
- ✅ **Reports Dashboard**: Complements real-time portal dashboard
- ✅ **Function App**: Shows results of automated user additions

### Does Not Require
- ❌ Users to be logged in (automated background process)
- ❌ Manual intervention (runs automatically on schedule)
- ❌ Additional licenses (uses existing Azure resources)

## Cost Considerations
- **Logic App**: Consumption tier (~$0.000025 per execution)
- **Daily Reports**: ~$0.75/month (30 days × $0.000025)
- **Weekly Reports**: ~$0.13/month (4 weeks)
- **Storage & Graph API**: Negligible for this workload

## Security Notes
- Logic App uses **Managed Identity** (no secrets stored)
- Office 365 connection uses **OAuth 2.0**
- SharePoint data accessed via **Microsoft Graph** with least privilege
- Recipients receive summary only (no sensitive user data in email)

## Support
For issues or questions:
1. Check Logic App run history for errors
2. Review logs in `logs/Part2-Deploy_*.log`
3. Run `Create-TechnicalSummary.ps1` for troubleshooting IDs

---
*Part of MFA Onboarding Automation Suite*
