using namespace System.Net

param($Request, $TriggerMetadata)

# ── Branded HTML page helper (shared with enrol function) ─────────
function Get-BrandedHtml {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Icon = "&#9888;",
        [string]$Color = "#0078D4",
        [string]$RedirectUrl = ""
    )
    $redirectScript = ""
    $redirectHtml = ""
    if ($RedirectUrl) {
        $redirectHtml = @"
<div class="countdown">Redirecting in <strong id="timer">5</strong> seconds...</div>
<a href="$RedirectUrl" style="display:inline-block;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);color:#fff;text-decoration:none;padding:12px 30px;border-radius:25px;font-size:15px;font-weight:600;margin-bottom:15px">Continue Now</a>
"@
        $redirectScript = @"
<script>let s=5;const t=document.getElementById('timer');const i=setInterval(()=>{s--;t.textContent=s;if(s<=0){clearInterval(i);window.location.href='$RedirectUrl';}},1000);</script>
"@
    }
    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$Title</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);min-height:100vh;display:flex;justify-content:center;align-items:center;padding:20px}
.card{background:#fff;border-radius:12px;box-shadow:0 10px 40px rgba(0,0,0,.2);max-width:520px;width:100%;text-align:center;overflow:hidden}
.card-header{background:$Color;padding:30px;color:#fff}
.card-header .icon{font-size:48px;margin-bottom:10px}
.card-header h1{font-size:22px;font-weight:600}
.card-body{padding:30px}
.card-body p{color:#333;font-size:15px;line-height:1.6;margin-bottom:15px}
.card-body .help{color:#666;font-size:13px}
.countdown{color:#888;font-size:13px;margin-bottom:15px}
.countdown strong{color:#2a5298}
</style>
</head>
<body>
<div class="card">
<div class="card-header"><div class="icon">$Icon</div><h1>$Title</h1></div>
<div class="card-body"><p>$Message</p>$redirectHtml<p class="help">If you need assistance, please contact your IT support team.</p></div>
</div>
$redirectScript
</body>
</html>
"@
}

# ── Self-service resend form HTML ─────────────────────────────────
function Get-ResendFormHtml {
    param([string]$Message = "", [string]$MessageColor = "#333")
    $msgBlock = ""
    if ($Message) {
        $msgBlock = "<div style='margin:15px 0;padding:12px;border-radius:8px;background:#f5f5f5;color:$MessageColor;font-size:14px'>$Message</div>"
    }
    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Resend MFA Setup Link</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);min-height:100vh;display:flex;justify-content:center;align-items:center;padding:20px}
.card{background:#fff;border-radius:12px;box-shadow:0 10px 40px rgba(0,0,0,.2);max-width:480px;width:100%;overflow:hidden}
.card-header{background:#0078D4;padding:30px;color:#fff;text-align:center}
.card-header .icon{font-size:48px;margin-bottom:10px}
.card-header h1{font-size:22px;font-weight:600}
.card-body{padding:30px}
.card-body p{color:#555;font-size:14px;line-height:1.6;margin-bottom:15px}
input[type=email]{width:100%;padding:12px 15px;border:2px solid #ddd;border-radius:8px;font-size:15px;margin-bottom:15px;outline:none;transition:border-color .2s}
input[type=email]:focus{border-color:#0078D4}
button{width:100%;padding:14px;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);color:#fff;border:none;border-radius:25px;font-size:16px;font-weight:600;cursor:pointer;box-shadow:0 4px 15px rgba(30,60,114,.4);transition:all .3s}
button:hover{box-shadow:0 6px 20px rgba(30,60,114,.6);transform:translateY(-2px)}
.help{color:#888;font-size:12px;text-align:center;margin-top:10px}
</style>
</head>
<body>
<div class="card">
<div class="card-header"><div class="icon">&#128231;</div><h1>Resend MFA Setup Link</h1></div>
<div class="card-body">
<p>Lost your MFA setup email? Enter your work email address below and we'll send you a new setup link.</p>
$msgBlock
<form method="POST" action="">
<input type="email" name="email" placeholder="your.name@company.com" required autocomplete="email" />
<button type="submit">Send Me a New Link</button>
</form>
<p class="help">You'll only receive a link if your account is pending MFA setup.</p>
</div>
</div>
</body>
</html>
"@
}

# ── Main logic ────────────────────────────────────────────────────

# GET request: show the form
if ($Request.Method -eq "GET") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers = @{ "Content-Type" = "text/html; charset=utf-8" }
        Body = (Get-ResendFormHtml)
    })
    return
}

# POST request: process resend
$email = $null
if ($Request.Body -and $Request.Body.email) {
    $email = $Request.Body.email
} elseif ($Request.Body -is [string]) {
    # Handle form-encoded data
    $parts = $Request.Body -split '&'
    foreach ($part in $parts) {
        $kv = $part -split '=', 2
        if ($kv[0] -eq 'email' -and $kv.Count -eq 2) {
            $email = [System.Web.HttpUtility]::UrlDecode($kv[1])
        }
    }
}

if ([string]::IsNullOrWhiteSpace($email)) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers = @{ "Content-Type" = "text/html; charset=utf-8" }
        Body = (Get-ResendFormHtml -Message "Please enter a valid email address." -MessageColor "#c00")
    })
    return
}

# Normalize email
$email = $email.Trim().ToLower()

# Always show same response regardless of whether user exists (prevent enumeration)
$genericSuccess = "If your account is pending MFA setup, you'll receive a new setup email shortly. Please check your inbox (and spam folder) in the next few minutes."

try {
    # Get Managed Identity token
    if ($env:IDENTITY_ENDPOINT) {
        $tokenAuthURI = $env:IDENTITY_ENDPOINT + "?resource=https://graph.microsoft.com&api-version=2019-08-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER"=$env:IDENTITY_HEADER} -Uri $tokenAuthURI
    } elseif ($env:MSI_ENDPOINT) {
        $tokenAuthURI = $env:MSI_ENDPOINT + "?resource=https://graph.microsoft.com&api-version=2017-09-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"=$env:MSI_SECRET} -Uri $tokenAuthURI
    } else {
        throw "No Managed Identity endpoint found"
    }
    $token = $tokenResponse.access_token
    
    $siteUrl = $env:SHAREPOINT_SITE_URL
    $listId  = $env:SHAREPOINT_LIST_ID
    
    if (-not $siteUrl -or -not $listId) {
        throw "SharePoint configuration missing"
    }
    
    $siteUri = [System.Uri]$siteUrl
    $siteDomain = $siteUri.Host
    $sitePath = $siteUri.AbsolutePath
    
    # Look up user in SharePoint by email (Title column)
    $safeEmail = $email -replace "'", "''"
    $filter = "fields/Title eq '$safeEmail'"
    $listItemsUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$filter=$filter&`$expand=fields"
    $listItems = Invoke-RestMethod -Uri $listItemsUrl -Headers @{ Authorization = "Bearer $token" } -Method Get
    
    if ($listItems.value.Count -gt 0) {
        $spItem = $listItems.value[0]
        $status = $spItem.fields.InviteStatus
        
        # Only resend for Pending or Sent statuses
        if ($status -in @("Pending", "Sent")) {
            # Reset status to Pending so the Logic App picks it up on next run
            $patchUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items/$($spItem.id)/fields"
            $patchBody = @{
                InviteStatus = @{ Value = "Pending" }
                ReminderCount = 0
                LastReminderDate = $null
            } | ConvertTo-Json -Depth 3
            
            Invoke-RestMethod -Uri $patchUrl -Headers @{
                Authorization  = "Bearer $token"
                "Content-Type" = "application/json"
            } -Method Patch -Body $patchBody | Out-Null
            
            Write-Host "Resend requested for $email - reset to Pending"
        } else {
            Write-Host "Resend requested for $email but status is '$status' - no action taken"
        }
    } else {
        Write-Host "Resend requested for $email but not found in list - no action taken"
    }
} catch {
    Write-Host "Resend error (non-blocking): $($_.Exception.Message)"
}

# Always show the same success message (prevent user enumeration)
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Headers = @{ "Content-Type" = "text/html; charset=utf-8" }
    Body = (Get-BrandedHtml -Title "Request Received" -Message $genericSuccess -Icon "&#9993;" -Color "#4caf50")
})
