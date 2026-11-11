# update-token.ps1  -  exchange the authorization code for an access token, then register the user

# Older Windows PowerShell (5.1) may default to outdated TLS versions; Polar requires modern TLS.
# This line is harmless on PowerShell 7.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

<###
Instructions on usage https://www.polar.com/accesslink-api/#polar-accesslink-api

1. Create account on Polar Flow
2. Fill your application information at https://admin.polaraccesslink.com, 
3. Obtain your application ClientId and replace it below in the variables. Write down secret somewhere as well for later use.
4. RedirectUri is mandatory, but you can use any e.g the one below. Remember to match the one you input on your application with the script variable
5. Use your browser to go to: https://auth.polar.com/oauth/authorize?client_id=<your_clientId>&response_type=code&redirect_uri=<callback_uri>
    Example: https://auth.polar.com/oauth/authorize?client_id=12122b0a-a32a-4f7b-a56f-5339b51348e7&response_type=code&redirect_uri=http://localhost:8080/callback
6  Log in with your Polar Flow account on your browser when prompted
7. Browser should point to your callback url with "code=<your_code>", save it for script use or set to variable $Code
8. Run the script, it asks for Secret (from when you filled the application information) and the code that you got from the browser's URL box

###>

$workFolder = "C:\Temp\PolarData\"
$memberName = "template-member-name"
$ClientId    = "12122b0a-a32a-4f7b-a56f-5339b51348e7"   # public identifier of your API client
$RedirectUri = "http://localhost:8080/callback"          # must be identical to the one used in the browser URL

# Ask for the secret and code at runtime so they never end up in the script file or in your history.
# -AsSecureString hides what you type; the second line converts it back to plain text for the request.
$SecretSecure = Read-Host "Client secret" -AsSecureString
$ClientSecret = [System.Net.NetworkCredential]::new("", $SecretSecure).Password
$Code         = Read-Host "Authorization code (copied from the browser address bar)"

# The token endpoint wants "Authorization: Basic base64(clientId:clientSecret)".
# Building the header by hand makes sure it is sent on the first request (Basic auth via -Credential
# is only sent after a 401 challenge on Windows PowerShell 5.1, which this endpoint may not issue).
$Pair      = "{0}:{1}" -f $ClientId, $ClientSecret
$Base64    = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Pair))
$AuthHeader = @{
    Authorization = "Basic $Base64"
    Accept        = "application/json"
}

If (!(Test-Path $workFolder)){
    New-Item -Path $workFolder -ItemType Directory | Out-Null
}

# A hashtable body combined with this content type is sent form-encoded
# (application/x-www-form-urlencoded), which is what the token endpoint requires.

$TokenBody = @{
    grant_type   = "authorization_code"   # the only supported value
    code         = $Code                  # one-time code, valid 10 minutes, usable only once
    redirect_uri = $RedirectUri           # required because it was also given to the authorize endpoint
}

try {
    $Token = Invoke-RestMethod -Method Post `
        -Uri "https://polarremote.com/v2/oauth2/token" `
        -Headers $AuthHeader `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $TokenBody
}
catch {
    # ErrorDetails.Message usually contains Polar's JSON error (e.g. invalid_grant = code used/expired)
    Write-Host "Token request failed: $($_.ErrorDetails.Message)" -ForegroundColor Red
    return
}

# After $Token has been received, save it encrypted for next time:
$TokenFile = Join-Path $workFolder "polar-token.xml"   # never share or commit this file
$Token.access_token | ConvertTo-SecureString -AsPlainText -Force | Export-Clixml -Path $TokenFile
Write-Host "TokenFile saved to $TokenFile" 

# Per the docs this does not expire unless revoked
$AccessToken = $Token.access_token   

Write-Host "Token received. Polar user id: $($Token.x_user_id)" -ForegroundColor Green
# Treat the token like a password. Store it in a password manager, not in this script.

# Register the user once; data endpoints refuse requests until this has been done.
$ApiHeader = @{
    Authorization = "Bearer $AccessToken"   # user token authentication for /v3/users/...
    Accept        = "application/json"
}

try {
    $User = Invoke-RestMethod -Method Post `
        -Uri "https://www.polaraccesslink.com/v3/users" `
        -Headers $ApiHeader `
        -ContentType "application/json" `
        -Body (@{ "member-id" = $memberName } | ConvertTo-Json)   # any unique string you choose
    Write-Host "Registered: polar-user-id $($User.'polar-user-id')" -ForegroundColor Green
}
catch {
    # HTTP 409 means this user is already registered for the client, which is fine.
    Write-Host "Register response: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host $_.ErrorDetails.Message
}