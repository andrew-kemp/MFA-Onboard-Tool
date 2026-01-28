# Progressive INI Configuration - How It Works

## ✅ NEW: Scripts Create INI File Dynamically!

**You no longer need to run `01-Install-Prerequisites.ps1` first!**

Each script now:
1. ✅ Checks if `mfa-config.ini` exists
2. ✅ Creates it if missing
3. ✅ Checks for required values
4. ✅ Prompts you if values are missing
5. ✅ Saves your answers to the INI file
6. ✅ Continues with deployment

---

## 🚀 Flexible Deployment Options

### Option 1: Run Scripts Individually (NEW!)
```powershell
# Start anywhere - INI file builds as you go!
.\02-Provision-SharePoint.ps1
# Prompts for: TenantId, SiteUrl, SiteOwner, ListTitle, AppRegName
# Saves to mfa-config.ini

.\04-Create-Azure-Resources.ps1
# Prompts for: SubscriptionId, ResourceGroup, Region
# Adds to existing mfa-config.ini

.\08-Deploy-Email-Reports.ps1
# Prompts for: Any missing values
# Completes mfa-config.ini
```

### Option 2: Use Prerequisites Script (Original Method)
```powershell
# Gather all values upfront
.\01-Install-Prerequisites.ps1
# Interactive Q&A creates complete mfa-config.ini

# Then run deployment scripts
.\Run-Part1-Setup-Enhanced.ps1
.\Run-Part2-Deploy-Enhanced.ps1
```

### Option 3: Pre-Create INI File
```powershell
# Copy template and fill in manually
Copy-Item "mfa-config.ini.template" "mfa-config.ini"
notepad mfa-config.ini

# Then run any script - it uses existing values
.\02-Provision-SharePoint.ps1
```

---

## 📋 How Each Script Works Now

### 02-Provision-SharePoint.ps1
**Checks for:**
- `[SharePoint] SiteUrl`
- `[SharePoint] ListTitle`
- `[SharePoint] SiteOwner`
- `[SharePoint] AppRegName`
- `[Tenant] TenantId`

**Prompts if missing, saves to INI, continues**

### 04-Create-Azure-Resources.ps1
**Checks for:**
- `[Tenant] TenantId`
- `[Tenant] SubscriptionId`
- `[Azure] ResourceGroup`
- `[Azure] Region`

**Prompts if missing, saves to INI, continues**

### 08-Deploy-Email-Reports.ps1
**Checks for:**
- `[Azure] ResourceGroup`
- `[Azure] Region`
- `[SharePoint] SiteUrl`
- `[SharePoint] ListId`
- `[Tenant] TenantId`

**Prompts if missing, saves to INI, continues**

### Other Scripts
Follow the same pattern - check, prompt, save, continue.

---

## 🎯 Example Workflow

### Scenario: Start Fresh with No INI File

```powershell
# Step 1: Run SharePoint provisioning
PS C:\ANdyKempDev> .\02-Provision-SharePoint.ps1

Creating new configuration file: mfa-config.ini
Checking configuration...
SharePoint Site URL (e.g., https://yourtenant.sharepoint.com/sites/MFAOps):
> https://contoso.sharepoint.com/sites/MFAOps

SharePoint List Title [MFA Enrollment Tracking]:
> [Enter] (uses default)

Site Owner Email:
> admin@contoso.com

SharePoint App Registration Name [SPO-MFA-Automation]:
> [Enter] (uses default)

Tenant ID (e.g., contoso.onmicrosoft.com or guid):
> contoso.onmicrosoft.com

✓ Configuration loaded
[continues with SharePoint provisioning]
```

**Result:** `mfa-config.ini` now contains:
```ini
[SharePoint]
SiteUrl=https://contoso.sharepoint.com/sites/MFAOps
ListTitle=MFA Enrollment Tracking
SiteOwner=admin@contoso.com
AppRegName=SPO-MFA-Automation

[Tenant]
TenantId=contoso.onmicrosoft.com
```

```powershell
# Step 2: Create Azure resources
PS C:\ANdyKempDev> .\04-Create-Azure-Resources.ps1

Checking configuration...
Azure Subscription ID:
> 12345678-1234-1234-1234-123456789012

Resource Group name [rg-mfa-onboarding]:
> [Enter] (uses default)

Azure region [uksouth]:
> [Enter] (uses default)

✓ Configuration loaded
[continues with Azure resources]
```

**Result:** `mfa-config.ini` now also has:
```ini
[Tenant]
SubscriptionId=12345678-1234-1234-1234-123456789012

[Azure]
ResourceGroup=rg-mfa-onboarding
Region=uksouth
```

---

## 💡 Key Benefits

### ✅ No Prerequisites Required
- Start with any script
- Build configuration progressively
- No need to know everything upfront

### ✅ Smart Prompting
- Only asks for missing values
- Shows defaults in brackets `[default]`
- Press Enter to accept defaults

### ✅ Persistent Configuration
- Values saved immediately
- Rerun script = uses saved values
- No re-prompting for existing values

### ✅ Safe & Idempotent
- Can run scripts multiple times
- Existing values preserved
- Only missing values prompted

---

## 🔍 How It Works Under the Hood

### New Helper Function: `Get-IniValueOrPrompt`

```powershell
function Get-IniValueOrPrompt {
    param(
        [string]$Path,        # mfa-config.ini path
        [string]$Section,     # e.g., "SharePoint"
        [string]$Key,         # e.g., "SiteUrl"
        [string]$Prompt,      # What to ask user
        [string]$Default = "" # Optional default value
    )
    
    # Check if value exists in INI
    if (Test-Path $Path) {
        $config = Get-IniContent -Path $Path
        $value = $config[$Section][$Key]
    }
    
    # If missing, prompt user
    if ([string]::IsNullOrWhiteSpace($value)) {
        if ($Default) {
            $input = Read-Host "$Prompt [$Default]"
            $value = if ($input) { $input } else { $Default }
        } else {
            $value = Read-Host $Prompt
        }
        
        # Save to INI for next time
        Set-IniValue -Path $Path -Section $Section -Key $Key -Value $value
    }
    
    return $value
}
```

### Usage in Scripts

```powershell
# Old way (throws error if missing)
$siteUrl = $config["SharePoint"]["SiteUrl"]
if ([string]::IsNullOrWhiteSpace($siteUrl)) {
    throw "Please run Step 01 first!"
}

# New way (prompts if missing)
$siteUrl = Get-IniValueOrPrompt -Path $configFile `
    -Section "SharePoint" `
    -Key "SiteUrl" `
    -Prompt "SharePoint Site URL" `
    -Default "https://yourtenant.sharepoint.com/sites/MFAOps"
```

### Enhanced `Set-IniValue`

Now creates:
- ✅ INI file if doesn't exist
- ✅ Section if doesn't exist
- ✅ Key if doesn't exist

```powershell
# Creates everything automatically
Set-IniValue -Path "mfa-config.ini" `
    -Section "NewSection" `
    -Key "NewKey" `
    -Value "NewValue"

# Result: Section and key added to file
```

---

## 📊 Progressive Configuration Example

### Starting State
```
C:\ANdyKempDev\
├── 02-Provision-SharePoint.ps1
├── 04-Create-Azure-Resources.ps1
├── 08-Deploy-Email-Reports.ps1
└── (no mfa-config.ini)
```

### After Script 02
```ini
# mfa-config.ini

[Tenant]
TenantId=contoso.onmicrosoft.com

[SharePoint]
SiteUrl=https://contoso.sharepoint.com/sites/MFAOps
SiteOwner=admin@contoso.com
ListTitle=MFA Enrollment Tracking
AppRegName=SPO-MFA-Automation
ClientId=<auto-populated-by-script>
CertificateThumbprint=<auto-populated-by-script>
```

### After Script 04
```ini
# mfa-config.ini (adds Azure section)

[Tenant]
TenantId=contoso.onmicrosoft.com
SubscriptionId=12345678-1234-1234-1234-123456789012

[SharePoint]
SiteUrl=https://contoso.sharepoint.com/sites/MFAOps
SiteOwner=admin@contoso.com
ListTitle=MFA Enrollment Tracking
AppRegName=SPO-MFA-Automation
ClientId=<guid>
CertificateThumbprint=<thumbprint>

[Azure]
ResourceGroup=rg-mfa-onboarding
Region=uksouth
FunctionAppName=<auto-generated>
StorageAccountName=<auto-generated>
MFAPrincipalId=<auto-populated>
```

### After Script 08
```ini
# mfa-config.ini (adds EmailReports section)

[Tenant]
TenantId=contoso.onmicrosoft.com
SubscriptionId=12345678-1234-1234-1234-123456789012

[SharePoint]
SiteUrl=https://contoso.sharepoint.com/sites/MFAOps
SiteOwner=admin@contoso.com
ListTitle=MFA Enrollment Tracking
AppRegName=SPO-MFA-Automation
ClientId=<guid>
CertificateThumbprint=<thumbprint>
ListId=<auto-populated>

[Azure]
ResourceGroup=rg-mfa-onboarding
Region=uksouth
FunctionAppName=func-mfa-123456
StorageAccountName=stmfa123456
MFAPrincipalId=<guid>

[EmailReports]
LogicAppName=logic-mfa-reports-789012
Recipients=admin@contoso.com
Frequency=Daily
```

---

## 🎯 Best Practices

### ✅ DO
- Let scripts prompt you for values
- Press Enter to accept sensible defaults
- Review generated INI file periodically
- Backup INI file after successful deployment

### ❌ DON'T
- Don't manually edit INI while scripts running
- Don't delete INI mid-deployment (scripts add to it)
- Don't skip required prompts (press Ctrl+C to abort instead)

---

## 🔄 Multi-Tenant Workflows

### Approach 1: Separate INI Files Per Customer
```powershell
# Customer 1
Copy-Item "mfa-config.ini" "mfa-config-customer1.ini"

# Customer 2
Copy-Item "mfa-config.ini.template" "mfa-config.ini"
.\02-Provision-SharePoint.ps1  # Builds new config
Rename-Item "mfa-config.ini" "mfa-config-customer2.ini"

# Switch between customers
Copy-Item "mfa-config-customer1.ini" "mfa-config.ini"
```

### Approach 2: Directory Per Customer
```
C:\Deployments\
├── Customer1\
│   ├── mfa-config.ini
│   └── [scripts]
└── Customer2\
    ├── mfa-config.ini
    └── [scripts]
```

---

## ✅ Summary

**Progressive INI configuration means:**
1. No prerequisite script needed
2. Start deployment anywhere
3. Scripts prompt for missing values
4. Configuration builds automatically
5. Rerun scripts = no re-prompting
6. Complete flexibility in workflow

**The INI file grows with your deployment!**

---

*MFA Onboarding System - Progressive Configuration*
*Scripts Updated: January 26, 2026*
