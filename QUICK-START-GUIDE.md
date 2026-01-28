# Quick Start Guide - MFA Onboarding with Email Reports

## 🚀 5-Minute Setup

### Step 1: Prerequisites (One-Time)
```powershell
.\01-Install-Prerequisites.ps1
```
Installs required PowerShell modules and Azure CLI.

### Step 2: Configure
1. Copy `mfa-config.ini.template` to `mfa-config.ini`
2. Fill in your tenant details

### Step 3: Deploy M365 Resources
```powershell
.\Run-Part1-Setup-Enhanced.ps1
```
Creates app registrations, security group, SharePoint list.

### Step 4: Deploy Azure Resources
```powershell
.\Run-Part2-Deploy-Enhanced.ps1
```
Creates Function App, Logic Apps, Storage, Upload Portal.

**When prompted**: Choose "Y" to set up email reports!

### Step 5: Authorize Connections
1. Go to Azure Portal > Resource Groups > Your RG > Connections
2. Authorize `office365` connection (for invitations)
3. Authorize `office365-reports` connection (for email reports)

### Step 6: Test
1. Open Upload Portal URL (shown at end of deployment)
2. Upload test CSV or enter user manually
3. Check email report arrives at scheduled time

---

## 📧 Email Reports - Quick Reference

### What You Get
- **Daily Reports**: Every day at 9:00 AM
- **Weekly Reports**: Every Monday at 9:00 AM
- **Content**: Total users, completed, pending, completion rate

### How to Configure

#### During Deployment
When `Run-Part2-Deploy-Enhanced.ps1` asks about email reports:
```
Would you like to set up automated daily/weekly email reports? (Y/N)
Choice: Y

Enter email addresses to receive reports (comma-separated):
Recipients: admin1@domain.com,admin2@domain.com

Select report frequency:
  1) Daily (9 AM)
  2) Weekly (Monday 9 AM)  
  3) Both Daily and Weekly
Choice (1-3): 1
```

#### After Deployment
Run standalone script:
```powershell
.\08-Deploy-Email-Reports.ps1
```

### Sample Email Report

```
┌────────────────────────────────────────┐
│   📊 MFA Rollout Report                │
│   Thursday, December 14, 2024          │
└────────────────────────────────────────┘

Executive Summary
┌───────────────┬──────────────┐
│ 250           │ 180          │
│ Total Users   │ Completed    │
├───────────────┼──────────────┤
│ 70            │ 72%          │
│ Pending       │ Completion   │
└───────────────┴──────────────┘

Quick Links
• 📋 View SharePoint List
• 📤 Upload Portal (with Reports Tab)

💡 Visit the Reports tab in Upload Portal
   for detailed user-level analytics.
```

---

## 📊 Upload Portal Reports Tab

### What You See
1. **Executive Summary**
   - Total Users
   - Completed (InGroup = true)
   - Pending
   - Completion Rate %

2. **Status Breakdown**
   - Sent: Invitations sent
   - Clicked: Users clicked link
   - AddedToGroup: Successfully added
   - Pending: No action yet

3. **Recent Activity** (Last 7 Days)
   - Users who recently completed
   - Timeline view

4. **Users Needing Attention**
   - Pending 3+ days
   - Clicked but not in group

5. **Batch Performance**
   - Completion rate by batch ID
   - Batch upload date

### How to Access
1. Open Upload Portal
2. Click **Reports** tab
3. Click **Load Reports**

---

## 🎯 Complete Reporting Suite

| Feature | Type | Frequency | Access |
|---------|------|-----------|--------|
| **Email Reports** | Automated | Daily/Weekly | Email inbox |
| **Portal Dashboard** | Real-Time | On-demand | Upload Portal > Reports |
| **SharePoint List** | Manual | Always | Direct link |
| **Deployment Logs** | Static | After deploy | logs/ folder |
| **Technical Summary** | Static | After deploy | logs/ folder |

---

## 🔍 Monitoring Workflow

### Daily
1. **Check Email Report** (9 AM)
   - See overnight progress
   - Review completion rate
   - Check total counts

2. **Upload New Users** (As Needed)
   - Via Upload Portal > CSV Upload
   - Or Manual Entry tab

3. **Monitor Real-Time** (Throughout Day)
   - Upload Portal > Reports tab
   - Check "Users Needing Attention"

### Weekly
1. **Review Weekly Email Report** (Monday 9 AM)
   - Compare to previous week
   - Identify trends
   - Plan follow-ups

2. **Follow Up on Pending Users**
   - Check "Pending 3+ Days" list
   - Send reminder emails
   - Troubleshoot issues

3. **Batch Performance Review**
   - Check completion rates by batch
   - Identify problematic batches
   - Optimize future uploads

---

## 🛠️ Troubleshooting

### Email Reports Not Arriving
**Problem**: No email received at scheduled time

**Solution**:
1. Check Logic App status:
   ```
   Azure Portal > Logic Apps > logic-mfa-reports-XXXXXX
   Status: Should be "Enabled"
   ```

2. Check run history:
   ```
   Overview > Run History
   Look for failed runs
   ```

3. Authorize Office 365 connection:
   ```
   Resource Groups > Your RG > Connections > office365-reports
   Click "Edit API connection" > "Authorize" > Sign in > "Save"
   ```

### Reports Tab Shows No Data
**Problem**: Portal Reports tab is empty

**Solution**:
1. Grant Sites.Read.All permission:
   ```powershell
   .\Fix-Graph-Permissions.ps1
   ```

2. Clear browser cache and reload portal

3. Check SharePoint list has data:
   - Open SharePoint list directly
   - Verify users exist with data

### Wrong Recipients for Email Reports
**Problem**: Reports going to wrong people

**Solution**:
1. Edit `mfa-config.ini`:
   ```ini
   [EmailReports]
   Recipients=newadmin1@domain.com,newadmin2@domain.com
   ```

2. Redeploy email reports:
   ```powershell
   .\08-Deploy-Email-Reports.ps1
   ```

---

## 📁 Key Files

### Configuration
- `mfa-config.ini` - All settings (edit this!)
- `mfa-config.ini.template` - Template to copy

### Deployment Scripts
- `Run-Part1-Setup-Enhanced.ps1` - M365 setup
- `Run-Part2-Deploy-Enhanced.ps1` - Azure deployment
- `08-Deploy-Email-Reports.ps1` - Email reports (standalone)

### Documentation
- `COMPLETE-FEATURE-OVERVIEW.md` - Full feature list
- `EMAIL-REPORTS-README.md` - Email reports guide
- `WHATS-NEW.md` - Latest enhancements
- `ENHANCED-SCRIPTS-README.md` - Deployment guide

### Generated Logs (After Deployment)
```
logs/
├── Part1-Setup_2024-12-14_093045.log
├── Part2-Deploy_2024-12-14_095122.log
├── DEPLOYMENT-COMPLETE-SUMMARY_2024-12-14_095122.txt
├── TECHNICAL-SUMMARY_2024-12-14_095122.txt
└── LogicApp-Deployed_2024-12-14_095122.json
```

---

## ⚡ Pro Tips

### For Administrators
- ✅ Set up **both** daily and weekly reports for comprehensive tracking
- ✅ Check Portal Reports tab before big uploads to verify system health
- ✅ Keep `TECHNICAL-SUMMARY` file handy for troubleshooting
- ✅ Archive old deployment logs monthly

### For Large Rollouts (1000+ Users)
- ✅ Upload in batches of 100-200 users
- ✅ Monitor batch performance via Reports tab
- ✅ Space batches 1-2 hours apart
- ✅ Check email reports daily during rollout

### For Multi-Tenant Deployments
- ✅ Use separate `mfa-config.ini` per tenant
- ✅ Compare `TECHNICAL-SUMMARY` files across tenants
- ✅ Deploy email reports to different recipient lists per tenant
- ✅ Use consistent naming conventions

---

## 📞 Quick Command Reference

```powershell
# Full deployment
.\Run-Part2-Deploy-Enhanced.ps1

# Email reports only
.\08-Deploy-Email-Reports.ps1

# Fix permissions (if reports not working)
.\Fix-Graph-Permissions.ps1

# Generate technical summary anytime
.\Create-TechnicalSummary.ps1

# View logs
Get-Content .\logs\Part2-Deploy_*.log -Tail 50

# Check Logic App status
az logic workflow show --name logic-mfa-reports-XXXXXX --resource-group rg-mfa-onboarding
```

---

## 🎓 Next Steps

1. ✅ Complete deployment (Parts 1 & 2)
2. ✅ Set up email reports
3. ✅ Test with sample users
4. ✅ Review first email report
5. ✅ Check Portal Reports tab
6. ✅ Begin production rollout
7. ✅ Monitor daily progress
8. ✅ Review weekly trends

---

**Need Help?**
- Check deployment logs in `logs/` folder
- Review `TECHNICAL-SUMMARY` for all IDs
- See `EMAIL-REPORTS-README.md` for troubleshooting
- Check Logic App run history in Azure Portal

---

*MFA Onboarding System - Quick Start Guide*
*With Automated Email Reports & Real-Time Dashboard*
