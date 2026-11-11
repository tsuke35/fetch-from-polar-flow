[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"
$workFolder = "C:\Temp\PolarData\"
$saveFolder = Join-Path $workFolder "daily-log"
$TokenFile = Join-Path $workFolder "polar-token.xml"   # never share or commit this file

If (!(Test-Path $saveFolder)){
    New-Item -Path $saveFolder -ItemType Directory | Out-Null
}

if (Test-Path $TokenFile) {
    # Normal weekly run: reuse the saved token (Polar's docs say it does not expire unless revoked).
    # Import-Clixml decrypts it with Windows DPAPI, so only your Windows user on this PC can read it.
    $SecureToken = Import-Clixml -Path $TokenFile
    $AccessToken = [System.Net.NetworkCredential]::new("", $SecureToken).Password
}
else {
    throw "missing token file, run update-token.ps1"
}

# Register the user once; data endpoints refuse requests until this has been done.
$ApiHeader = @{
    Authorization = "Bearer $AccessToken"   # user token authentication for /v3/users/...
    Accept        = "application/json"
}

# Get days to fetch based on the newest file + 1 extra day
$daysFromToFetch = 28 # Default, Polar won't support fetches further away
$files = (Get-ChildItem $saveFolder -File -Filter "*.json").Name | Sort-Object -Descending
If ($files) {
    $mostRecent = $files[0].Split(".")[0]
} else {
    $mostRecent = Get-Date -Date (Get-Date).AddDays(-30) -Format "yyyy-MM-dd" # force logic to default value when no files found
}

$timeSpan = New-TimeSpan -Start $mostRecent -End (Get-Date)
If ($timeSpan.Days -eq 0) {
    Write-Warning "Already up to date"
    Start-Sleep -Seconds 5
    break
}
Elseif ($timeSpan.Days -lt 28){
    $daysFromToFetch = $timeSpan.Days + 1
}

$dateFrom = Get-Date -Format "yyyy-MM-dd" -Date (Get-Date).AddDays(-$daysFromToFetch)


try {
    Write-Host "Starting REST fetches" -ForegroundColor Green
    $physicalInfo = Invoke-RestMethod -Method Get -Uri "https://www.polaraccesslink.com/v3/users/physical-info" -Headers $ApiHeader -ContentType "application/json"
    $activities = Invoke-RestMethod -Method Get -Uri "https://www.polaraccesslink.com/v3/users/activities?steps=true&activity_zones=true&from=$dateFrom" -Headers $ApiHeader -ContentType "application/json"
    $cardioHash = @{}
    $cardioLoads = Invoke-RestMethod -Method Get -Uri "https://www.polaraccesslink.com/v3/users/cardio-load" -Headers $ApiHeader -ContentType "application/json"
    $cardioLoads | % {
        $cardioHash.Add($_.date,$_)
    }
    $sleepHash = @{}
    $sleeps = Invoke-RestMethod -Method Get -Uri "https://www.polaraccesslink.com/v3/users/sleep" -Headers $ApiHeader -ContentType "application/json"
    $sleeps.nights | % {
        $sleepHash.Add($_.date,$_)
    }
    $nightlyRechargeHash = @{}
    $nigthlyRecharges = Invoke-RestMethod -Method Get -Uri "https://www.polaraccesslink.com/v3/users/nightly-recharge" -Headers $ApiHeader -ContentType "application/json"
    $nigthlyRecharges.recharges | % {
        $nightlyRechargeHash.Add($_.date,$_)
    }
    
    $continuousHRHash = @{}
    $continuousHR = Invoke-RestMethod -Method Get -Uri "https://www.polaraccesslink.com/v3/users/continuous-heart-rate?from=$dateFrom" -Headers $ApiHeader -ContentType "application/json"
    $continuousHR.heart_rates | % {
        $continuousHRHash.Add($_.date,$_)
    }

    $exercises = Invoke-RestMethod -Method Get -Uri "https://www.polaraccesslink.com/v3/exercises?samples=true&zones=true&route=true" -Headers $ApiHeader -ContentType "application/json"

    Write-Host "Fetches done, saving daily data to files" -ForegroundColor Green
    $i = 1
    foreach ($activity in $activities) {
        $day = ($activity.start_time -split "T")[0]   # "2026-11-04T00:00" -> "2026-11-04"
        Write-Progress -Activity $day -PercentComplete ($i / $activities.Count * 100);$i++

        $dailyExcercises = $exercises | Where-Object {$_.start_time -like "$day*"}
        # One object with named fields instead of a positional array. A missing item
        # (for example no sleep recorded) becomes null, so the file is always valid JSON.
        $record = [pscustomobject]@{
            date            = $day
            physicalInfo    = $physicalInfo
            activity        = $activity
            continuousHR    = $continuousHRHash[$day]
            cardioLoad      = $cardioHash[$day]
            sleep           = $sleepHash[$day]
            nightlyRecharge = $nightlyRechargeHash[$day]
            exercises       = $dailyExcercises
        }

        # -Depth 10: the default depth of 2 turns the nested step/zone samples into blank strings.
        $json = $record | ConvertTo-Json -Depth 10

        # -Encoding UTF8 keeps the files readable by any tool (Windows PowerShell 5.1 defaults to ANSI).
        Set-Content -Value $json -Path (Join-Path $saveFolder "$day.json") -Encoding UTF8
    }
}
catch {
    # HTTP 409 means this user is already registered for the client, which is fine.
    Write-Host "Register response: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host $_.ErrorDetails.Message
}


