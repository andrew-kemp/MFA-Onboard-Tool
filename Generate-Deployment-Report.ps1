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
$resourceGroup = $config["Azure"]["ResourceGroup"]
$functionAppName = $config["Azure"]["FunctionAppName"]
$subscriptionId = $config["Tenant"]["SubscriptionId"]
$siteUrl = $config["SharePoint"]["SiteUrl"]
$logicAppName = $config["LogicApp"]["LogicAppName"]
$reportsLogicAppName = $config["EmailReports"]["LogicAppName"]
$uploadPortalClientId = $config["UploadPortal"]["ClientId"]
$storageAccountName = $config["Azure"]["StorageAccountName"]
$portalUrl = "https://$storageAccountName.z33.web.core.windows.net/upload-portal.html"

# Build step statuses
$stepsHtml = ""
if ($StepResults) {
    foreach ($step in $StepResults.Keys) {
        $status = $StepResults[$step]
        $statusClass = if ($status) { "success" } else { "failed" }
        $statusText = if ($status) { "✓ Success" } else { "✗ Failed" }
        $stepsHtml += @"
        <tr>
            <td class="step-name">$step</td>
            <td class="step-status $statusClass">$statusText</td>
        </tr>
"@
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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
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
            border-bottom: 3px solid #667eea;
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
            border-bottom: 2px solid #667eea;
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
            color: #667eea;
            font-size: 0.9em;
            text-transform: uppercase;
            margin-bottom: 8px;
        }
        .link-value {
            padding: 10px 12px;
            background: white;
            border-left: 4px solid #667eea;
            border-radius: 4px;
            word-break: break-all;
            cursor: pointer;
            transition: all 0.2s;
        }
        .link-value:hover {
            background: #f0f0f0;
        }
        .link-value a {
            color: #667eea;
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
            background: #667eea;
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
            background: #764ba2;
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

                <div class="grid">
                    <div class="link-section">
                        <div class="link-label">Subscription ID</div>
                        <div class="link-value" style="border-left-color: #ff9800;">$subscriptionId</div>
                        <button class="button secondary" onclick="copyToClipboard('$subscriptionId')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Resource Group</div>
                        <div class="link-value" style="border-left-color: #ff9800;">$resourceGroup</div>
                        <button class="button secondary" onclick="copyToClipboard('$resourceGroup')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Storage Account</div>
                        <div class="link-value" style="border-left-color: #ff9800;">$storageAccountName</div>
                        <button class="button secondary" onclick="copyToClipboard('$storageAccountName')" style="margin-top: 8px; width: 100%;">Copy</button>
                    </div>

                    <div class="link-section">
                        <div class="link-label">Upload Portal Client ID</div>
                        <div class="link-value" style="border-left-color: #ff9800;">$uploadPortalClientId</div>
                        <button class="button secondary" onclick="copyToClipboard('$uploadPortalClientId')" style="margin-top: 8px; width: 100%;">Copy</button>
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
