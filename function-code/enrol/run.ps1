using namespace System.Net

param($Request, $TriggerMetadata)

# ── Branded HTML page helper ──────────────────────────────────────
function Get-BrandedHtml {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Icon = "&#9888;",    # ⚠ default
        [string]$Color = "#0078D4",
        [string]$RedirectUrl = ""      # Optional: auto-redirect after 5s
    )

    $redirectScript = ""
    $redirectHtml = ""
    $metaRefresh = ""
    if ($RedirectUrl) {
        $metaRefresh = "<meta http-equiv=`"refresh`" content=`"5;url=$RedirectUrl`">"
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
$metaRefresh
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

# ── Progress page — shows step-by-step status then redirects ──────
function Get-ProgressHtml {
    param(
        [string]$Title = "Setting Up Your MFA",
        [string]$Step1Label = "Adding you to the MFA group",
        [string]$Step2Label = "Redirecting to Microsoft MFA setup",
        [string]$RedirectUrl = "https://aka.ms/mfasetup",
        [int]$RedirectSeconds = 6
    )
    return @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="$RedirectSeconds;url=$RedirectUrl">
<title>$Title</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',Tahoma,Geneva,Verdana,sans-serif;background:linear-gradient(135deg,#1e3c72 0%,#2a5298 100%);min-height:100vh;display:flex;justify-content:center;align-items:center;padding:20px}
.card{background:#fff;border-radius:12px;box-shadow:0 10px 40px rgba(0,0,0,.2);max-width:520px;width:100%;overflow:hidden}
.card-header{background:#0078D4;padding:30px;color:#fff;text-align:center}
.card-header .icon{font-size:48px;margin-bottom:10px}
.card-header h1{font-size:22px;font-weight:600}
.card-body{padding:30px}
.steps{list-style:none;margin:0;padding:0}
.step{display:flex;align-items:center;padding:14px 0;border-bottom:1px solid #eee;font-size:15px;color:#333;transition:opacity .3s}
.step:last-child{border-bottom:none}
.step .status{width:28px;height:28px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;margin-right:14px;flex-shrink:0;font-weight:700;font-size:14px}
.step.pending .status{background:#e0e0e0;color:#999}
.step.pending{opacity:.5}
.step.active .status{background:#0078D4;color:#fff;animation:pulse 1.2s infinite}
.step.done .status{background:#4caf50;color:#fff}
.spinner{display:inline-block;width:14px;height:14px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .8s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes pulse{0%,100%{box-shadow:0 0 0 0 rgba(0,120,212,.5)}50%{box-shadow:0 0 0 8px rgba(0,120,212,0)}}
.footer-note{margin-top:20px;text-align:center;color:#888;font-size:13px}
.footer-note a{color:#0078D4;text-decoration:none}
</style>
</head>
<body>
<div class="card">
<div class="card-header"><div class="icon">&#128274;</div><h1>$Title</h1></div>
<div class="card-body">
<ul class="steps">
<li id="step1" class="step active"><span class="status"><span class="spinner"></span></span><span>$Step1Label</span></li>
<li id="step2" class="step pending"><span class="status">2</span><span>$Step2Label</span></li>
</ul>
<p class="footer-note">Not redirecting automatically? <a href="$RedirectUrl">Click here to continue</a></p>
</div>
</div>
<script>
(function(){
  var step1 = document.getElementById('step1');
  var step2 = document.getElementById('step2');
  // After 1.8s, mark step1 as done and step2 as active
  setTimeout(function(){
    step1.classList.remove('active');
    step1.classList.add('done');
    step1.querySelector('.status').innerHTML = '&#10003;';
    step2.classList.remove('pending');
    step2.classList.add('active');
    step2.querySelector('.status').innerHTML = '<span class="spinner"></span>';
  }, 1800);
  // After $RedirectSeconds seconds, redirect (backup to meta refresh)
  setTimeout(function(){
    window.location.href = '$RedirectUrl';
  }, $RedirectSeconds * 1000);
})();
</script>
</body>
</html>
"@
}

# Accept token parameter (preferred) or legacy user parameter
$trackingToken = $Request.Query.token
$userEmail = $Request.Query.user
$lookupByToken = $false

if (-not $trackingToken -and -not $userEmail) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::BadRequest
        ContentType = "text/html; charset=utf-8"
        Headers     = @{ "Content-Type" = "text/html; charset=utf-8" }
        Body        = (Get-BrandedHtml -Title "Invalid Link" -Message "This link is missing required information. Please use the link from your MFA setup email." -Icon "&#10060;" -Color "#d32f2f")
    })
    return
}

if ($trackingToken) {
    $lookupByToken = $true
    Write-Host "Processing MFA click tracking via token: $($trackingToken.Substring(0, 8))..."
} else {
    Write-Host "Processing MFA click tracking for user: $userEmail (legacy mode)"
}

try {
    # Get access token using Managed Identity
    # Support both new (IDENTITY_ENDPOINT) and legacy (MSI_ENDPOINT) formats
    if ($env:IDENTITY_ENDPOINT) {
        $tokenAuthURI = $env:IDENTITY_ENDPOINT + "?resource=https://graph.microsoft.com&api-version=2019-08-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"X-IDENTITY-HEADER"=$env:IDENTITY_HEADER} -Uri $tokenAuthURI
    } elseif ($env:MSI_ENDPOINT) {
        $tokenAuthURI = $env:MSI_ENDPOINT + "?resource=https://graph.microsoft.com&api-version=2017-09-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"=$env:MSI_SECRET} -Uri $tokenAuthURI
    } else {
        throw "No Managed Identity endpoint found. Ensure System Assigned Managed Identity is enabled."
    }
    $token = $tokenResponse.access_token
    
    Write-Host "Successfully obtained access token via Managed Identity"
    
    # Get configuration from environment variables (set from INI file)
    $groupId = $env:MFA_GROUP_ID
    $siteUrl = $env:SHAREPOINT_SITE_URL
    $listId = $env:SHAREPOINT_LIST_ID
    
    if (-not $groupId) {
        throw "MFA_GROUP_ID environment variable not set"
    }
    if (-not $siteUrl) {
        throw "SHAREPOINT_SITE_URL environment variable not set"
    }
    if (-not $listId) {
        throw "SHAREPOINT_LIST_ID environment variable not set"
    }
    
    Write-Host "Configuration loaded from environment variables"
    Write-Host "  Group ID: $groupId"
    Write-Host "  Site URL: $siteUrl"
    Write-Host "  List ID: $listId"

    # Extract site path from URL for Graph API
    $siteUri = [System.Uri]$siteUrl
    $siteDomain = $siteUri.Host
    $sitePath = $siteUri.AbsolutePath

    # Resolve user from SharePoint (token lookup) or use provided UPN
    $spItemId = $null
    if ($lookupByToken) {
        $listItemsUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$filter=fields/TrackingToken eq '$trackingToken'&`$expand=fields"
        $listItems = Invoke-RestMethod -Uri $listItemsUrl -Headers @{
            Authorization = "Bearer $token"
        } -Method Get

        # Fallback: if the "token" is actually a UPN (happens when the user was
        # imported before TrackingToken existed, so Logic App used Title as the
        # fallback), try looking them up by Title instead.
        if ($listItems.value.Count -eq 0 -and $trackingToken -match '@') {
            Write-Host "Token not found as TrackingToken; it looks like a UPN — retrying lookup by Title"
            $fallbackUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$filter=fields/Title eq '$trackingToken'&`$expand=fields"
            $listItems = Invoke-RestMethod -Uri $fallbackUrl -Headers @{
                Authorization = "Bearer $token"
            } -Method Get
            if ($listItems.value.Count -gt 0) {
                $lookupByToken = $false  # Treat as legacy UPN flow from here on
                $userEmail = $trackingToken
                Write-Host "Resolved UPN-as-token to user: $userEmail"
            }
        }

        if ($listItems.value.Count -eq 0) {
            Write-Host "Warning: Token not found in SharePoint list"
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::NotFound
                ContentType = "text/html; charset=utf-8"
                Headers     = @{ "Content-Type" = "text/html; charset=utf-8" }
                Body        = (Get-BrandedHtml -Title "Link Not Recognised" -Message "We couldn't find a matching record for this link. It may have expired or already been used. Please check your email for the most recent MFA setup invitation." -Icon "&#128269;" -Color "#f57c00")
            })
            return
        }

        $spItem = $listItems.value[0]
        $userEmail = $spItem.fields.Title
        $spItemId = $spItem.id

        # Duplicate click protection
        if ($spItem.fields.ClickedLinkDate) {
            Write-Host "User $userEmail already clicked on $($spItem.fields.ClickedLinkDate) - skipping"
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = "text/html; charset=utf-8"
                Headers     = @{ "Content-Type" = "text/html; charset=utf-8" }
                Body        = (Get-BrandedHtml -Title "Already Registered" -Message "You've already clicked this link and your MFA enrolment is in progress. You'll be redirected to the MFA setup page shortly." -Icon "&#9989;" -Color "#4caf50" -RedirectUrl "https://aka.ms/mfasetup")
            })
            return
        }

        Write-Host "Resolved token to user: $userEmail (Item ID: $spItemId)"
    } else {
        # Legacy UPN mode - look up SharePoint item early for duplicate-click protection
        $listItemsUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items?`$filter=fields/Title eq '$userEmail'&`$expand=fields"
        $listItems = Invoke-RestMethod -Uri $listItemsUrl -Headers @{
            Authorization = "Bearer $token"
        } -Method Get

        if ($listItems.value.Count -gt 0) {
            $spItem = $listItems.value[0]
            $spItemId = $spItem.id

            if ($spItem.fields.ClickedLinkDate) {
                Write-Host "User $userEmail already clicked on $($spItem.fields.ClickedLinkDate) - skipping (legacy mode)"
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode  = [HttpStatusCode]::OK
                    ContentType = "text/html; charset=utf-8"
                    Headers     = @{ "Content-Type" = "text/html; charset=utf-8" }
                    Body        = (Get-BrandedHtml -Title "Already Registered" -Message "You've already clicked this link and your MFA enrolment is in progress. You'll be redirected to the MFA setup page shortly." -Icon "&#9989;" -Color "#4caf50" -RedirectUrl "https://aka.ms/mfasetup")
                })
                return
            }
        } else {
            Write-Host "Warning: User $userEmail not found in SharePoint list (legacy mode)"
        }
    }

    # Get user ID from email
    $userResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$userEmail" -Headers @{
        Authorization = "Bearer $token"
    } -Method Get

    $userId = $userResponse.id
    Write-Host "Found user ID: $userId"

    # Add user to MFA Registration group
    $addedToGroup = $false
    $alreadyInGroup = $false
    try {
        $addMemberBody = @{
            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
        } | ConvertTo-Json

        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" -Headers @{
            Authorization = "Bearer $token"
            "Content-Type" = "application/json"
        } -Method Post -Body $addMemberBody

        Write-Host "Successfully added user to MFA Registration group"
        $addedToGroup = $true
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Host "User already in group (this is fine)"
            $alreadyInGroup = $true
            $addedToGroup = $true
        }
        else {
            Write-Host "Error adding to group: $_"
        }
    }

    # Update SharePoint list with ClickedLinkDate and GroupAdded status
    try {
        Write-Host "Updating SharePoint list..."

        # If we haven't found the SharePoint item yet, it means legacy mode didn't find it earlier
        if (-not $spItemId) {
            Write-Host "Warning: User not found in SharePoint list"
        }

        if ($spItemId) {
            $updateUrl = "https://graph.microsoft.com/v1.0/sites/$($siteDomain):$($sitePath):/lists/$listId/items/$spItemId/fields"
            $currentTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            $updateBody = @{
                ClickedLinkDate = $currentTime
                InGroup = $addedToGroup
                AddedToGroupDate = if ($addedToGroup) { $currentTime } else { $null }
                InviteStatus = "Sent"
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $updateUrl -Headers @{
                Authorization = "Bearer $token"
                "Content-Type" = "application/json"
            } -Method Patch -Body $updateBody

            Write-Host "Successfully updated SharePoint list:"
            Write-Host "  - ClickedLinkDate: $currentTime"
            Write-Host "  - InGroup: $(if ($addedToGroup) { 'True' } else { 'False' })"
            Write-Host "  - InviteStatus: Sent (kept for Logic App monitoring)"
        }
    }
    catch {
        Write-Host "Warning: Could not update SharePoint (non-critical): $_"
        Write-Host "Error details: $($_.Exception.Message)"
    }

    # Check if request is from browser (User-Agent header) or API call (Upload Portal)
    $userAgent = $Request.Headers.'User-Agent'
    $acceptHeader = $Request.Headers.'Accept'
    
    # If Accept header contains "application/json" or no User-Agent, return JSON (Upload Portal)
    $returnJson = ($acceptHeader -like "*application/json*") -or ([string]::IsNullOrEmpty($userAgent))
    
    if ($returnJson) {
        # Return JSON for Upload Portal / API calls
        $jsonResponse = @{
            success = $true
            message = if ($alreadyInGroup) { "User already in group" } else { "User added to group" }
            userEmail = $userEmail
            addedToGroup = $addedToGroup
            alreadyInGroup = $alreadyInGroup
        } | ConvertTo-Json
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Headers = @{
                "Content-Type" = "application/json; charset=utf-8"
            }
            Body = $jsonResponse
        })
        
        Write-Host "Successfully processed API request for $userEmail (JSON response)"
        return
    }
    
    # For browser/email clicks: Branded progress page with auto-redirect to MFA setup
    if ($alreadyInGroup) {
        $progressTitle = "You're Already Set Up"
        $step1 = "Verified you're already in the MFA group"
    } else {
        $progressTitle = "Setting Up Your MFA"
        $step1 = "Added you to the MFA group"
    }
    $step2 = "Redirecting to Microsoft MFA setup"

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::OK
        ContentType = "text/html; charset=utf-8"
        Headers     = @{ "Content-Type" = "text/html; charset=utf-8" }
        Body        = (Get-ProgressHtml -Title $progressTitle -Step1Label $step1 -Step2Label $step2 -RedirectUrl "https://aka.ms/mfasetup" -RedirectSeconds 6)
    })

    Write-Host "Successfully processed click tracking for $userEmail (progress landing page)"
}
catch {
    $errorDetail = $_.Exception.Message
    if ($_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errorBody = $reader.ReadToEnd()
            $errorDetail += " | Response: $errorBody"
        } catch {}
    }
    Write-Host "ERROR: $errorDetail"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::InternalServerError
        ContentType = "text/html; charset=utf-8"
        Headers     = @{ "Content-Type" = "text/html; charset=utf-8" }
        Body        = (Get-BrandedHtml -Title "Something Went Wrong" -Message "We encountered an unexpected error while processing your request. Please try again in a few minutes, or contact your IT support team if the problem persists." -Icon "&#9888;" -Color "#d32f2f")
    })
}







