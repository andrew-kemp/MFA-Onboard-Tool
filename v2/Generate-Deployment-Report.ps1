# Generate Deployment Report as HTML with all links and information
param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigFile,
    [Parameter(Mandatory=$false)]
    [hashtable]$StepResults,
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "$PSScriptRoot\logs"
)

function Get-IniContent {
    param([string]$Path)
    $ini = @{}
    $section = ""
    switch -regex -file $Path {
        "^\[(.+)\]$" {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        "(.+?)\s*=\s*(.*)" {
            $name = $matches[1]
            $value = $matches[2]
            $ini[$section][$name] = $value
        }
    }
    return $ini
}

$config = Get-IniContent -Path $ConfigFile

# Extract key values
$tenantId = $config["Tenant"]["TenantId"]
$subscriptionId = $config["Tenant"]["SubscriptionId"]
$siteUrl = $config["SharePoint"]["SiteUrl"]
$listTitle = $config["SharePoint"]["ListTitle"]
$spClientId = $config["SharePoint"]["ClientId"]
$certThumbprint = $config["SharePoint"]["CertificateThumbprint"]
$mfaGroupId = $config["Security"]["MFAGroupId"]
$mfaGroupName = $config["Security"]["MFAGroupName"]
$mfaGroupMail = $config["Security"]["MFAGroupMail"]
$resourceGroup = $config["Azure"]["ResourceGroup"]
$region = $config["Azure"]["Region"]
$functionAppName = $config["Azure"]["FunctionAppName"]
$storageAccountName = $config["Azure"]["StorageAccountName"]
$mfaPrincipalId = $config["Azure"]["MFAPrincipalId"]
$mailboxName = $config["Email"]["MailboxName"]
$noReplyMailbox = $config["Email"]["NoReplyMailbox"]
$mailboxDelegate = $config["Email"]["MailboxDelegate"]
$emailSubject = $config["Email"]["EmailSubject"]
$logicAppName = $config["LogicApp"]["LogicAppName"]
$reportsLogicAppName = $config["EmailReports"]["LogicAppName"]
$uploadPortalClientId = $config["UploadPortal"]["ClientId"]
$uploadPortalAppName = $config["UploadPortal"]["AppName"]
$logoUrl = $config["Branding"]["LogoUrl"]
$companyName = $config["Branding"]["CompanyName"]
$supportTeam = $config["Branding"]["SupportTeam"]
$supportEmail = $config["Branding"]["SupportEmail"]
$portalUrl = "https://$storageAccountName.z33.web.core.windows.net/upload-portal.html"

# Build step statuses in chronological order
$stepsHtml = ""
if ($StepResults) {
    # Define the correct order for steps
    $stepOrder = @(
        "Step 01: Install Prerequisites",
        "Step 02: Provision SharePoint",
        "Step 03: Create Shared Mailbox",
        "Step 04: Azure Resources",
        "Step 05: Function App Configuration",
        "Step 06: Logic App Deployment",
        "Step 07: Upload Portal Deployment",
        "Step 08: Email Reports Setup",
        "Fix: Function Authentication",
        "Fix: Graph Permissions",
        "Fix: Logic App Permissions"
    )
    
    # Display steps in order
    foreach ($stepName in $stepOrder) {
        if ($StepResults.ContainsKey($stepName)) {
            $status = $StepResults[$stepName]
            $statusClass = if ($status) { "success" } else { "failed" }
            $statusText = if ($status) { "✓ Success" } else { "✗ Failed" }
            $stepsHtml += @"
        <tr>
            <td class="step-name">$stepName</td>
            <td class="step-status $statusClass">$statusText</td>
        </tr>
"@
        }
    }
}

$timestamp = Get-Date -Format "dddd, MMMM dd, yyyy @ h:mm tt"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MFA Deployment Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .header p {
            opacity: 0.9;
            font-size: 1.1em;
        }
        .content {
            padding: 40px;
        }
        .section {
            margin-bottom: 40px;
        }
        .section-title {
            font-size: 1.5em;
            color: #333;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #2a5298;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .section-icon {
            font-size: 1.5em;
        }
        .status-table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
        }
        .status-table th {
            background: #f5f5f5;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #333;
            border-bottom: 2px solid #2a5298;
        }
        .status-table td {
            padding: 12px;
            border-bottom: 1px solid #e0e0e0;
        }
        .step-name {
            font-weight: 500;
            color: #333;
        }
        .step-status {
            font-weight: 600;
            text-align: center;
        }
        .step-status.success {
            color: #4caf50;
        }
        .step-status.failed {
            color: #ff5252;
        }
        .link-section {
            background: #f9f9f9;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
        }
        .link-label {
            font-weight: 600;
            color: #2a5298;
            font-size: 0.9em;
            text-transform: uppercase;
            margin-bottom: 8px;
        }
        .link-value {
            padding: 10px 12px;
            background: white;
            border-left: 4px solid #2a5298;
            border-radius: 4px;
            word-break: break-all;
            cursor: pointer;
            transition: all 0.2s;
        }
        .link-value:hover {
            background: #f0f0f0;
        }
        .link-value a {
            color: #2a5298;
            text-decoration: none;
            font-weight: 500;
        }
        .link-value a:hover {
            text-decoration: underline;
        }
        .button-group {
            display: flex;
            gap: 10px;
            margin-top: 10px;
            flex-wrap: wrap;
        }
        .button {
            padding: 10px 16px;
            background: #2a5298;
            color: white;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.9em;
            font-weight: 600;
            text-decoration: none;
            display: inline-block;
            transition: background 0.2s;
        }
        .button:hover {
            background: #1e3c72;
        }
        .button.secondary {
            background: #666;
        }
        .button.secondary:hover {
            background: #555;
        }
        .checklist {
            list-style: none;
            margin-bottom: 20px;
        }
        .checklist li {
            padding: 10px;
            margin-bottom: 8px;
            background: #f9f9f9;
            border-radius: 6px;
            border-left: 4px solid #4caf50;
        }
        .checklist li:before {
            content: "✓ ";
            font-weight: bold;
            color: #4caf50;
        }
        .footer {
            background: #f5f5f5;
            padding: 20px;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }
        .info-box {
            background: #e3f2fd;
            border-left: 4px solid #2196f3;
            padding: 15px;
            border-radius: 6px;
            margin-bottom: 20px;
            color: #1976d2;
        }
        .warning-box {
            background: #fff3e0;
            border-left: 4px solid #ff9800;
            padding: 15px;
            border-radius: 6px;
            margin-bottom: 20px;
            color: #e65100;
        }
        .grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            margin-bottom: 20px;
        }
        @media (max-width: 768px) {
            .grid {
                grid-template-columns: 1fr;
            }
            .header h1 {
                font-size: 2em;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 MFA Onboarding Deployment Report</h1>
            <p>Complete deployment configuration and next steps</p>
            <p style="font-size: 0.9em; margin-top: 10px;">$timestamp</p>
        </div>

        <div class="content">
            <!-- Deployment Status Section -->
            <div class="section">
                <div class="section-title">
                    <span class="section-icon">✓</span>
                    Deployment Status
                </div>
                <table class="status-table">
                    <thead>
                        <tr>
                            <th>Step</th>
                            <th>Status</th>
                        </tr>
                    </thead>
                    <tbody>
                        $stepsHtml
                    </tbody>
                </table>
            </div>

            <!-- Quick Access Links Section -->
            <div class="section">
                <div class="section-title">
                    <span class="section-icon">🔗</span>
                    Quick Access Links
                </div>

                <div class="link-section">
                    <div class="link-label">📤 Upload Portal</div>
                    <div class="link-value">
                        <a href="$portalUrl" target="_blank">$portalUrl</a>
                    </div>
                    <div class="button-group">
                        <button class="button" onclick="window.open('$portalUrl', '_blank')">Open in Browser</button>
                        <button class="button secondary" onclick="copyToClipboard('$portalUrl')">Copy URL</button>
                    </div>
                </div>

                <div class="link-section">
                    <div class="link-label">📋 SharePoint List</div>
                    <div class="link-value">
                        <a href="$siteUrl" target="_blank">$siteUrl</a>
                    </div>
                    <div class="button-group">
                        <button class="button" onclick="window.open('$siteUrl', '_blank')">Open in Browser</button>
                        <button class="button secondary" onclick="copyToClipboard('$siteUrl')">Copy URL</button>
                    </div>
                </div>

                <div class="link-section">
                    <div class="link-label">⚡ Function App</div>
                    <div class="link-value">
                        <a href="https://$functionAppName.azurewebsites.net" target="_blank">https://$functionAppName.azurewebsites.net</a>
                    </div>
                    <div class="button-group">
                        <button class="button" onclick="window.open('https://$functionAppName.azurewebsites.net', '_blank')">Open in Browser</button>
                        <button class="button secondary" onclick="copyToClipboard('https://$functionAppName.azurewebsites.net')">Copy URL</button>
                    </div>
                </div>

                <div class="link-section">
                    <div class="link-label">📧 Invitation Logic App</div>
                    <div class="link-value">
                        <a href="https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName/overview" target="_blank">$logicAppName</a>
                    </div>
                    <div class="button-group">
                        <button class="button" onclick="window.open('https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$logicAppName/overview', '_blank')">View in Portal</button>
                    </div>
                </div>

                <div class="link-section">
                    <div class="link-label">📊 Reports Logic App</div>
                    <div class="link-value">
                        <a href="https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$reportsLogicAppName/overview" target="_blank">$reportsLogicAppName</a>
                    </div>
                    <div class="button-group">
                        <button class="button" onclick="window.open('https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Logic/workflows/$reportsLogicAppName/overview', '_blank')">View in Portal</button>
                    </div>
                </div>

                <div class="link-section">
                    <div class="link-label">🔐 Azure Resource Group</div>
                    <div class="link-value">
                        <a href="https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/overview" target="_blank">$resourceGroup</a>
                    </div>
                    <div class="button-group">
                        <button class="button" onclick="window.open('https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/overview', '_blank')">View in Portal</button>
                    </div>
                </div>
            </div>

            <!-- Important Resources Section -->
            <div class="section">
                <div class="section-title">
                    <span class="section-icon">⚙️</span>
                    Resource Information
                </div>

                <h3 style="margin-bottom: 15px; color: #333;">Tenant Configuration</h3>
                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">Tenant ID</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$tenantId</div>
                        <button class="button secondary" onclick="copyToClipboard('$tenantId')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Subscription ID</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$subscriptionId</div>
                        <button class="button secondary" onclick="copyToClipboard('$subscriptionId')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>
                </div>

                <h3 style="margin: 30px 0 15px 0; color: #333;">Azure Resources</h3>
                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">Resource Group</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$resourceGroup</div>
                        <button class="button secondary" onclick="copyToClipboard('$resourceGroup')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Region</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$region</div>
                        <button class="button secondary" onclick="copyToClipboard('$region')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Function App Name</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$functionAppName</div>
                        <button class="button secondary" onclick="copyToClipboard('$functionAppName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Storage Account</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$storageAccountName</div>
                        <button class="button secondary" onclick="copyToClipboard('$storageAccountName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">MFA Principal ID</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$mfaPrincipalId</div>
                        <button class="button secondary" onclick="copyToClipboard('$mfaPrincipalId')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Invitation Logic App</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$logicAppName</div>
                        <button class="button secondary" onclick="copyToClipboard('$logicAppName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Reports Logic App</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$reportsLogicAppName</div>
                        <button class="button secondary" onclick="copyToClipboard('$reportsLogicAppName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>
                </div>

                <h3 style="margin: 30px 0 15px 0; color: #333;">SharePoint Configuration</h3>
                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">Site URL</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$siteUrl</div>
                        <button class="button secondary" onclick="copyToClipboard('$siteUrl')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">List Title</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$listTitle</div>
                        <button class="button secondary" onclick="copyToClipboard('$listTitle')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">SharePoint Client ID</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$spClientId</div>
                        <button class="button secondary" onclick="copyToClipboard('$spClientId')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Certificate Thumbprint</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$certThumbprint</div>
                        <button class="button secondary" onclick="copyToClipboard('$certThumbprint')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>
                </div>

                <h3 style="margin: 30px 0 15px 0; color: #333;">Security Group</h3>
                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">MFA Group Name</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$mfaGroupName</div>
                        <button class="button secondary" onclick="copyToClipboard('$mfaGroupName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">MFA Group ID</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$mfaGroupId</div>
                        <button class="button secondary" onclick="copyToClipboard('$mfaGroupId')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">MFA Group Email</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$mfaGroupMail</div>
                        <button class="button secondary" onclick="copyToClipboard('$mfaGroupMail')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>
                </div>

                <h3 style="margin: 30px 0 15px 0; color: #333;">Email Configuration</h3>
                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">Mailbox Name</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$mailboxName</div>
                        <button class="button secondary" onclick="copyToClipboard('$mailboxName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">No-Reply Mailbox</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$noReplyMailbox</div>
                        <button class="button secondary" onclick="copyToClipboard('$noReplyMailbox')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Mailbox Delegate</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$mailboxDelegate</div>
                        <button class="button secondary" onclick="copyToClipboard('$mailboxDelegate')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Email Subject</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$emailSubject</div>
                        <button class="button secondary" onclick="copyToClipboard('$emailSubject')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>
                </div>

                <h3 style="margin: 30px 0 15px 0; color: #333;">Upload Portal</h3>
                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">Upload Portal Client ID</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$uploadPortalClientId</div>
                        <button class="button secondary" onclick="copyToClipboard('$uploadPortalClientId')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">App Name</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$uploadPortalAppName</div>
                        <button class="button secondary" onclick="copyToClipboard('$uploadPortalAppName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Portal URL</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$portalUrl</div>
                        <button class="button secondary" onclick="copyToClipboard('$portalUrl')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>
                </div>

                <h3 style="margin: 30px 0 15px 0; color: #333;">Branding</h3>
                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">Company Name</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$companyName</div>
                        <button class="button secondary" onclick="copyToClipboard('$companyName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Logo URL</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$logoUrl</div>
                        <button class="button secondary" onclick="copyToClipboard('$logoUrl')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Support Team</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$supportTeam</div>
                        <button class="button secondary" onclick="copyToClipboard('$supportTeam')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Support Email</div>
                        <div class="link-value" style="border-left-color: #2a5298;">$supportEmail</div>
                        <button class="button secondary" onclick="copyToClipboard('$supportEmail')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>
                </div>
            </div>

            <!-- Next Steps Section -->
            <div class="section">
                <div class="section-title">
                    <span class="section-icon">📋</span>
                    Next Steps
                </div>

                <div class="info-box">
                    <strong>Complete these tasks in order:</strong>
                </div>

                <ul class="checklist">
                    <li><strong>Authorize API Connections:</strong> Go to Azure Portal → Resource Groups → $resourceGroup → Connections and authorize:<br/>
                        • office365-reports (for Logic App emails)<br/>
                        • office365 (for invitation notifications)<br/>
                        • sharepointonline (for SharePoint integration)
                    </li>
                    <li><strong>Test Upload Portal:</strong> Open the Upload Portal URL above and add a test user to verify the workflow</li>
                    <li><strong>Verify Email Delivery:</strong> Check that the test user received an invitation email from the Logic App</li>
                    <li><strong>Monitor Function App:</strong> Check Function App logs in Azure Portal to ensure user additions are working correctly</li>
                    <li><strong>Test Email Reports:</strong> Go to the Reports Logic App and manually trigger a test run to verify email reports send correctly</li>
                    <li><strong>Enable Scheduled Triggers:</strong> Ensure both Logic Apps are enabled and set to run automatically</li>
                    <li><strong>Add Real Users:</strong> Once verified, start uploading your actual user list via the portal</li>
                </ul>
            </div>

            <!-- Troubleshooting Section -->
            <div class="section">
                <div class="section-title">
                    <span class="section-icon">🔧</span>
                    Troubleshooting
                </div>

                <div class="warning-box">
                    <strong>Common Issues:</strong>
                </div>

                <div class="link-section">
                    <div class="link-label">Logic Apps Not Sending Emails</div>
                    <p>→ Check that API connections are authorized (see Next Steps above)</p>
                    <p>→ Review Logic App run history for specific error messages</p>
                    <p>→ Verify managed identity has correct Graph API permissions</p>
                </div>

                <div class="link-section">
                    <div class="link-label">Upload Portal Showing Permission Errors</div>
                    <p>→ Ensure Upload Portal app registration has Sites.Read.All and User.Read permissions</p>
                    <p>→ Check that admin consent has been granted in Azure AD</p>
                    <p>→ Re-run Fix-Graph-Permissions.ps1 if needed</p>
                </div>

                <div class="link-section">
                    <div class="link-label">Function App Not Creating Users</div>
                    <p>→ Check Function App logs in Azure Portal → Function App → Monitor</p>
                    <p>→ Verify managed identity has GroupMember.ReadWrite.All and Sites.ReadWrite.All</p>
                    <p>→ Confirm the target MFA group exists in Microsoft 365</p>
                </div>

                <div class="link-section">
                    <div class="link-label">More Help</div>
                    <p>Review the documentation files:</p>
                    <ul style="margin-top: 10px; margin-left: 20px;">
                        <li>EMAIL-REPORTS-README.md - Email reports configuration</li>
                        <li>EMAIL-REPORTS-PERMISSION-FIX.md - Permission troubleshooting</li>
                        <li>COMPLETE-FEATURE-OVERVIEW.md - Full feature documentation</li>
                    </ul>
                </div>
            </div>
        </div>

        <div class="footer">
            <p>MFA Onboarding Automation Suite | Deployment Report Generated on $timestamp</p>
            <p>For issues or support, check the logs directory and review documentation files</p>
        </div>
    </div>

    <script>
        function copyToClipboard(text) {
            navigator.clipboard.writeText(text).then(() => {
                alert('Copied to clipboard!');
            });
        }
    </script>
</body>
</html>
"@

# Ensure logs directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$reportFile = Join-Path $OutputPath "DEPLOYMENT-REPORT_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').html"
$html | Set-Content $reportFile -Encoding UTF8 -Force

Write-Host "✓ Deployment report generated: $reportFile" -ForegroundColor Green

return $reportFile
