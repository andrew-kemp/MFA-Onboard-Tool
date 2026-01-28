using namespace System.Net

param($Request, $TriggerMetadata)

# Get user email from query string
$userEmail = $Request.Query.user

if (-not $userEmail) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Missing user parameter"
    })
    return
}

Write-Host "TEST MODE: Processing for user: $userEmail"

# Just redirect without doing anything else (test mode)
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::Redirect
    Headers = @{
        Location = "https://aka.ms/mfasetup"
    }
    Body = "Redirecting to MFA setup... (TEST MODE)"
})

Write-Host "TEST MODE: Successfully redirected $userEmail"
