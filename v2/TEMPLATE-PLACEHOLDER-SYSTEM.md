# Template & Placeholder System

## Overview
The deployment system now uses a **template-based approach with placeholders** instead of regex-based replacements. This ensures the system is portable and can be deployed to any new environment by simply updating the `mfa-config.ini` file.

## Key Changes

### Template File
- **File**: `invite-orchestrator-TEMPLATE.json`
- **Purpose**: Contains the Logic App workflow definition with placeholders
- **Status**: Contains NO hardcoded values, only placeholders

### Placeholders Used
All placeholders follow the format `PLACEHOLDER_XXXX` for easy identification:

1. **PLACEHOLDER_FUNCTION_URL** - Azure Function tracking URL
2. **PLACEHOLDER_SHAREPOINT_SITE_URL** - SharePoint site URL
3. **PLACEHOLDER_LIST_ID** - SharePoint list GUID
4. **PLACEHOLDER_GROUP_ID** - Azure AD MFA group GUID
5. **PLACEHOLDER_EMAIL** - No-reply mailbox address
6. **PLACEHOLDER_LOGO_URL** - Company logo URL
7. **PLACEHOLDER_COMPANY_NAME** - Company name for branding
8. **PLACEHOLDER_SUPPORT_TEAM** - Support team name
9. **PLACEHOLDER_FOOTER** - Email footer with contact info

### Configuration Source
All values come from `mfa-config.ini`:

```ini
[Azure]
SubscriptionId = ...
ResourceGroup = ...
FunctionAppName = func-mfa-enrol-748713

[SharePoint]
SiteUrl = https://kempy.sharepoint.com/sites/MFA-Operations
ListId = ... (generated during deployment)

[Email]
NoReplyMailbox = MFA@andykemp.com

[Security]
MFAGroupId = ...

[Branding]
LogoUrl = https://...
CompanyName = Cygnet Group
SupportTeam = IT Security Team
SupportEmail = MFA@andykemp.com
```

### Deployment Scripts Updated
Both deployment scripts now use the template system:

#### 06-Deploy-Logic-App.ps1
- Reads from `invite-orchestrator-TEMPLATE.json`
- Uses simple `.Replace()` method for all placeholders
- No regex patterns (more reliable)
- Creates all connections from scratch

#### 06b-Redeploy-Logic-App-Only.ps1
- Reads from `invite-orchestrator-TEMPLATE.json`
- Uses simple `.Replace()` method for all placeholders
- No regex patterns (more reliable)
- Preserves existing connections

## Advantages

### Portability
✓ Template file works on ANY environment
✓ No hardcoded tenant-specific values
✓ Simple INI file configuration

### Reliability
✓ No regex complexity or escaping issues
✓ Predictable string replacement
✓ No JSON parsing errors from complex patterns

### Maintainability
✓ Clear placeholder naming convention
✓ Easy to identify what needs replacing
✓ Single source of truth (INI file)

### Redeployability
✓ Can redeploy to new tenants easily
✓ Just update INI file values
✓ Template stays unchanged

## Email Footer Features
The footer now includes:
- Support team name from INI config
- **Clickable email link** with pre-filled subject
- Subject: "MFA Setup Query" (URL encoded)
- No © character (removed)
- Professional styling

Example footer:
```
This is an automated message from IT Security Team.
For questions or assistance, please contact MFA@andykemp.com.

Please do not reply to this email as this is an unmonitored mailbox.
```

## App Store Badges
Updated to use **Microsoft official badge URLs**:
- iOS: `https://mysignins.microsoft.com/images/ios-app-store-button.svg`
- Android: `https://mysignins.microsoft.com/images/google-play-button.svg`

## Testing
To verify the system works:

1. **Check template has placeholders**:
   ```powershell
   Get-Content .\invite-orchestrator-TEMPLATE.json | Select-String "PLACEHOLDER_"
   ```

2. **Run deployment**:
   ```powershell
   .\06b-Redeploy-Logic-App-Only.ps1
   ```

3. **Verify JSON is valid** (script does this automatically):
   - After all replacements, JSON is parsed with `ConvertFrom-Json`
   - Deployment will fail if JSON is invalid

## Migration Notes
- **Old system**: Used regex to find hardcoded values in JSON
- **New system**: Uses simple string replacement of placeholders
- **Benefit**: More reliable, portable, and maintainable

## Deployment Workflow
1. Update `mfa-config.ini` with your environment values
2. Run deployment script (06 or 06b)
3. Script reads TEMPLATE file
4. Script reads INI values
5. Script replaces all placeholders
6. Script validates JSON
7. Script deploys to Azure

## Future Deployments
To deploy to a **new tenant**:
1. Create new `mfa-config.ini` with tenant values
2. Run `.\06-Deploy-Logic-App.ps1`
3. **No need to modify JSON template**

The template file (`invite-orchestrator-TEMPLATE.json`) remains unchanged and portable across all deployments.
