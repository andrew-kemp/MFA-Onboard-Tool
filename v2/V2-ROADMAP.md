# MFA System V2.0 - Future Enhancements Roadmap

## Overview
This document outlines planned enhancements for the MFA onboarding system, including phishing-resistant authentication, new user onboarding, and self-service recovery options.

---

## 🎯 Feature 1: User Choice - Standard vs Phishing-Resistant MFA

### Description
Allow users to choose their MFA method when clicking the setup link, with support for both standard MFA and phishing-resistant passkeys.

### Architecture

#### Function App Enhancement
**Current**: Immediate redirect to `aka.ms/mfasetup`  
**V2**: Display choice page with two options

**User Flow:**
1. User clicks email link → Function App displays choice page
2. **Option A: Standard MFA**
   - Add to `MFA-Registration` group
   - Update SharePoint: `MFAMethod = "Standard"`
   - Immediate redirect to `aka.ms/mfasetup`
   - User completes standard Authenticator setup

3. **Option B: Phishing-Resistant (Passkey)**
   - Add to `MFA-PhishResistant` group
   - Update SharePoint: `MFAMethod = "Passkey"`, `TAPRequested = true`
   - Show confirmation: "You'll receive an email with setup instructions shortly"

#### Logic App Enhancement
**Existing Logic App** (`MFA-Inviter`) enhanced with passkey flow:

**New Actions:**
1. Query SharePoint: `TAPRequested = true AND TAPIssued = false`
2. For each user:
   - Generate TAP via Graph API (`POST /users/{id}/authentication/temporaryAccessPassAuthenticationMethod`)
   - Send TAP email with passkey setup instructions
   - Update SharePoint: `TAPIssued = true`, `TAPCode = xxx`, `TAPIssuedDate = now()`

### Email Template: TAP for Passkey Setup
```html
Subject: Set Up Phishing-Resistant MFA - Temporary Access Password

Dear [User],

You've chosen to set up phishing-resistant Multi-Factor Authentication using a Passkey!

🔒 Temporary Access Password: [TAP-CODE]
⏰ Valid for: 1 hour from now

Steps to Set Up Your Passkey:
1. Go to: aka.ms/devicelogin
2. Sign in with your username and the temporary password above
3. Follow prompts to register Windows Hello or a FIDO2 security key
4. Your passkey is now active - no more password prompts on trusted devices!

Why Passkeys?
✓ Can't be phished or stolen
✓ More convenient than passwords
✓ Works across devices with Windows Hello, Face ID, or security keys

Questions? Contact [SupportTeam]
```

### SharePoint List Updates
**New Columns for MFA Tracking List:**
- `MFAMethod` (Choice: "Standard" | "Passkey" | "Not Set")
- `TAPRequested` (Yes/No)
- `TAPIssued` (Yes/No)
- `TAPCode` (Single line text) - For audit/support
- `TAPIssuedDate` (Date/Time)
- `TAPExpiresAt` (Date/Time)
- `TAPUsedDate` (Date/Time)

### Required Permissions
**Graph API Permissions:**
- `UserAuthenticationMethod.ReadWrite.All` - Generate TAPs
- `Policy.Read.All` - Read TAP policies

### Conditional Access Policy
**New Policy**: Require MFA for `MFA-PhishResistant` group
- Authentication strength: Phishing-resistant MFA only
- Applies to: Members of `MFA-PhishResistant` group

---

## 🆕 Feature 2: New User Onboarding with TAP

### Description
Automated onboarding for brand new users who have no existing authentication methods. Sends TAP to both work email and personal/alternate email for redundancy.

### Architecture

#### New SharePoint List: "New User Onboarding"
**Columns:**
- `Username` (UPN) - e.g., jsmith@company.com
- `DisplayName` - e.g., John Smith
- `WorkEmail` - Corporate email (same as UPN usually)
- `OtherEmail` - Personal/alternate email for backup
- `Department` (Optional)
- `Manager` (Optional)
- `OnboardingStatus` (Choice: "Pending" | "TAP Sent" | "Completed" | "Failed")
- `TAPIssued` (Yes/No)
- `TAPCode` (Single line text)
- `TAPIssuedDate` (Date/Time)
- `TAPExpiresAt` (Date/Time)
- `TAPUsedDate` (Date/Time)
- `AccountCreatedDate` (Date/Time)
- `FirstLoginDate` (Date/Time)

#### New Logic App: "MFA-NewUser-Onboarding"

**Trigger:** Scheduled (e.g., every 2 hours)

**Flow:**
1. **Get Items** from "New User Onboarding" list
   - Filter: `OnboardingStatus = "Pending" AND TAPIssued = false`

2. **For Each** pending user:
   
   a. **Verify User Exists** (Graph API: GET /users/{id})
      - If not found: Update status to "Failed", skip
   
   b. **Generate TAP** (Graph API: POST /users/{id}/authentication/temporaryAccessPassAuthenticationMethod)
      - Validity: 1 hour
      - One-time use: true
   
   c. **Send Email to Work Address** (Office 365 connector)
      - To: WorkEmail
      - Subject: "Welcome to [Company] - Your Account Setup"
      - Body: Welcome template with TAP
   
   d. **Send Email to Personal Address** (Office 365 connector)
      - To: OtherEmail
      - Subject: "Welcome to [Company] - Account Setup Instructions"
      - Body: Same template (backup delivery)
   
   e. **Update SharePoint** item:
      - `OnboardingStatus = "TAP Sent"`
      - `TAPIssued = true`
      - `TAPCode = [code]`
      - `TAPIssuedDate = utcNow()`
      - `TAPExpiresAt = addHours(utcNow(), 1)`

3. **Monitor TAP Usage** (separate scheduled trigger, runs hourly)
   - Query users with `OnboardingStatus = "TAP Sent"`
   - Check authentication methods (Graph API)
   - If user has registered MFA: Update `OnboardingStatus = "Completed"`, `FirstLoginDate = now()`

### Email Template: New User Welcome
```html
Subject: Welcome to [Company] - Your Account Details

Dear [DisplayName],

Welcome to [Company]! Your account has been created.

🔑 Username: [username@company.com]
🔒 Temporary Password: ABC-DEF-GHI
⏰ Valid for: 1 hour

Next Steps:
1. Go to: aka.ms/devicelogin
2. Sign in with the username and temporary password above
3. Set up Windows Hello or Microsoft Authenticator
4. Create your permanent password
5. You're all set to access company resources!

Important: This temporary password expires in 1 hour. Please complete setup promptly.

Need Help?
Contact [SupportTeam] at [SupportEmail]

---
This email has been sent to both your work email and alternate email address for your convenience.
```

### Upload Portal for Bulk New Users
**Enhancement to existing upload portal:**
- Add "New User Onboarding" upload option
- CSV format: `Username,DisplayName,WorkEmail,OtherEmail,Department`
- Validation: Check OtherEmail format
- Bulk add to "New User Onboarding" list

---

## 📧 Feature 3: Self-Service "Other Email" Registration

### Description
Allow users to register their personal/alternate email address for account recovery and future TAP delivery.

### Architecture

#### New Function App: "register-other-email"

**Endpoint:** `https://func-mfa-enrol-xxx.azurewebsites.net/api/register-other-email`

**Flow:**
1. User visits portal page (hosted on Function App or Storage Account)
2. User enters:
   - Work email (pre-filled if coming from authenticated session)
   - Other email address
3. Verification email sent to OtherEmail with confirmation link
4. User clicks confirmation link
5. Function validates and stores in SharePoint
6. Confirmation shown: "Your alternate email has been registered!"

#### SharePoint List Updates
**MFA Tracking List - New Columns:**
- `OtherEmail` (Single line text)
- `OtherEmailVerified` (Yes/No)
- `OtherEmailRegisteredDate` (Date/Time)
- `OtherEmailVerificationToken` (Single line text, hidden)

#### Self-Service Portal HTML
**Page: "Register Alternate Email"**
- Simple form: Email input + Submit button
- Hosted as static page in Function App or Azure Storage
- Uses Function App API for backend processing
- Linked from email footer: "Register your alternate email for account recovery"

---

## 🔧 Feature 4: Support App for TAP Reset

### Description
Web application for IT support staff to reset user MFA and issue new TAPs, with automatic email delivery to both work and alternate addresses.

### Architecture

#### New Azure Function App: "mfa-support-portal"

**Authentication:** Azure AD with role-based access (IT Support group)

**Features:**
1. **User Search**
   - Search by UPN, display name, or email
   - Show current MFA status, methods registered
   - Show last TAP issued (if any)

2. **TAP Reset Action**
   - Button: "Generate New TAP"
   - Confirmation prompt: "This will revoke existing TAPs. Continue?"
   - Actions:
     - Revoke existing TAPs (Graph API)
     - Generate new TAP (1 hour validity)
     - Send to WorkEmail + OtherEmail (if registered)
     - Log action in audit table

3. **Audit Log**
   - Track all TAP generations
   - Who: Support staff member
   - When: Timestamp
   - For Whom: User UPN
   - Result: Success/Failed

#### SharePoint List: "MFA Support Audit"
**Columns:**
- `SupportStaff` (Person)
- `TargetUser` (Single line text)
- `Action` (Choice: "TAP Generated" | "MFA Reset" | "OtherEmail Updated")
- `Timestamp` (Date/Time)
- `Result` (Choice: "Success" | "Failed")
- `Notes` (Multiple lines)

#### Support Portal UI
**React/HTML Frontend:**
```
┌─────────────────────────────────────┐
│  MFA Support Portal                 │
├─────────────────────────────────────┤
│  Search: [________________] 🔍      │
├─────────────────────────────────────┤
│  User: john.smith@company.com       │
│  Name: John Smith                   │
│  MFA Status: ❌ Not Registered       │
│  Work Email: john.smith@company.com │
│  Other Email: jsmith@gmail.com ✓    │
│                                     │
│  Last TAP: 2026-01-20 (Expired)     │
│                                     │
│  [Generate New TAP]  [Reset MFA]    │
└─────────────────────────────────────┘
```

#### Email Template: TAP Reset by Support
```html
Subject: MFA Reset - New Temporary Access Password

Dear [User],

Your IT Support team has reset your Multi-Factor Authentication at your request.

🔒 New Temporary Password: ABC-DEF-GHI
⏰ Valid for: 1 hour

Steps to Set Up MFA:
1. Go to: aka.ms/mfasetup
2. Sign in with your username and the temporary password above
3. Follow the prompts to set up Microsoft Authenticator or Windows Hello
4. Your access will be restored immediately

This email has been sent to:
✓ Your work email: [WorkEmail]
✓ Your alternate email: [OtherEmail]

If you did not request this reset, please contact IT Security immediately.

Support Ticket Reference: [TicketNumber] (if applicable)
Reset By: [SupportStaffName]
Date: [Timestamp]
```

---

## 📊 Feature 5: Enhanced Reporting Dashboard

### Description
PowerBI or custom dashboard showing MFA adoption metrics and user status.

### Metrics to Track
- **Overall Adoption Rate**: % users with MFA enabled
- **Method Breakdown**: Standard MFA vs Passkey
- **New User Onboarding**: Time from account creation to first login
- **TAP Usage**: How many TAPs issued vs used
- **Support Requests**: TAP resets over time
- **Reminder Effectiveness**: Users who registered after reminder #1, #2, #3
- **At-Risk Users**: Users without MFA after 30 days

### Data Sources
- MFA Tracking SharePoint list
- New User Onboarding list
- Support Audit log
- Azure AD authentication logs

---

## 🔐 Security Considerations

### TAP Security
- **Validity**: 1 hour maximum
- **One-time use**: Automatically revoked after first use
- **Storage**: Encrypted in SharePoint, access restricted
- **Audit**: All TAP generations logged with who/when/why

### Email Security
- **Dual delivery**: Work + Other email reduces single point of failure
- **Verification**: Other email must be verified before use
- **Expiry warnings**: Users notified when TAP about to expire

### Access Control
- **Function Apps**: Managed Identity only
- **Support Portal**: Azure AD authentication + IT Support group membership
- **SharePoint**: Restricted permissions, auditing enabled

---

## 🚀 Implementation Priority

### Phase 1 (High Priority)
1. ✅ User Choice: Standard vs Passkey (Function App + Logic App enhancement)
2. ✅ New User Onboarding Logic App
3. ✅ Self-Service Other Email Registration

### Phase 2 (Medium Priority)
4. Support Portal for TAP Reset
5. Enhanced Reporting Dashboard

### Phase 3 (Future)
6. Mobile app for self-service
7. SMS backup for TAP delivery
8. Integration with HR systems for auto-provisioning

---

## 📋 Prerequisites for V2.0

### Azure AD Configuration
- Enable TAP authentication method in tenant
- Configure TAP policy (validity, lifetime, etc.)
- Create Conditional Access policy for phishing-resistant MFA

### Graph API Permissions (Additional)
- `UserAuthenticationMethod.ReadWrite.All` - Manage TAPs
- `Policy.Read.All` - Read authentication policies
- `AuditLog.Read.All` - Read authentication logs for reporting

### SharePoint Lists (New/Enhanced)
- "New User Onboarding" list (new)
- "MFA Support Audit" list (new)
- "MFA Tracking" list enhancements (new columns)

### Azure Resources (New)
- Function App: `func-mfa-support-portal`
- Logic App: `MFA-NewUser-Onboarding`
- Storage Account: For support portal static site (optional)

---

## 📝 Configuration Changes

### mfa-config.ini Additions
```ini
[V2Features]
EnablePasskeyChoice=true
EnableNewUserOnboarding=true
EnableOtherEmailRegistration=true
TAPValidityHours=1
TAPOneTimeUse=true

[NewUserOnboarding]
OnboardingListTitle=New User Onboarding
CheckIntervalMinutes=120
SendToWorkEmail=true
SendToOtherEmail=true

[SupportPortal]
EnableSupportPortal=true
SupportGroupId=xxx-xxx-xxx-xxx
AuditListTitle=MFA Support Audit
RequireTicketNumber=false
```

---

## 🧪 Testing Plan

### User Acceptance Testing
1. **Standard MFA Path**: User chooses standard, completes setup in <5 minutes
2. **Passkey Path**: User chooses passkey, receives TAP, completes setup
3. **New User**: New user receives TAP at both emails, completes onboarding
4. **Other Email Registration**: User registers alternate email, receives verification
5. **Support Reset**: Support staff generates TAP, user receives at both emails
6. **Expired TAP**: TAP expires after 1 hour, cannot be reused

### Load Testing
- 100 concurrent new user onboardings
- 50 support TAP resets per hour
- Email delivery reliability >99%

---

## 📚 Documentation Updates

### User Documentation
- **"How to Choose Your MFA Method"** - Guide for standard vs passkey
- **"New User Quick Start"** - First-time login with TAP
- **"Register Your Alternate Email"** - Self-service guide
- **"MFA Troubleshooting"** - Common issues and solutions

### IT Support Documentation
- **"Using the Support Portal"** - TAP reset procedures
- **"MFA Support Playbook"** - Common scenarios and resolutions
- **"Audit and Compliance"** - How to access logs and reports

### Admin Documentation
- **"V2.0 Deployment Guide"** - Step-by-step upgrade process
- **"Configuration Reference"** - All V2.0 settings explained
- **"Troubleshooting V2.0"** - Known issues and fixes

---

## 🎯 Success Metrics

### Adoption Goals
- 95%+ MFA adoption within 60 days of V2.0 launch
- 30%+ users choose passkey option
- 90%+ new users complete onboarding within 24 hours
- <5% support tickets for MFA issues

### User Experience
- Average time to complete MFA setup: <3 minutes
- User satisfaction score: >4.5/5
- Support ticket reduction: 40% vs V1.0

---

## 💡 Future Ideas (V3.0+)

### Advanced Features
- **Biometric verification** for high-risk actions
- **Risk-based authentication** - Adaptive MFA based on sign-in risk
- **Self-service account recovery** - Users can unlock themselves
- **Mobile app** - Native iOS/Android app for MFA management
- **Passwordless** - Eliminate passwords entirely, passkeys only
- **Integration with hardware tokens** - YubiKey, etc.
- **Automated compliance reporting** - Export to SOC 2, ISO 27001 formats

---

## 📞 Support & Feedback

### Contact
- **Product Owner**: [Name]
- **Technical Lead**: [Name]
- **Support Channel**: [Team/Email]

### Feedback
Users can provide feedback on V2.0 features via:
- Feedback form in support portal
- Email to [feedback@company.com]
- Monthly user group meetings

---

*Last Updated: January 27, 2026*  
*Version: 2.0 Roadmap (Draft)*  
*Status: Planning Phase*
