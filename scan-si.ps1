param(
    [string]$InputFile = ".\words.txt",
    [string]$OutputCsv = ".\si-results.csv",
    [string]$AvailableFile = ".\available.txt",
    [int]$DelayMs = 350,
    [int]$MaxRetries = 5
)

$ErrorActionPreference = "Stop"
$RdapBase = "https://rdap.register.si/domain"

if (-not (Test-Path -LiteralPath $InputFile)) {
    throw "Input file not found: $InputFile"
}

$domains = Get-Content -LiteralPath $InputFile |
    ForEach-Object { $_.Trim().ToLowerInvariant() } |
    Where-Object { $_ -and -not $_.StartsWith("#") } |
    ForEach-Object {
        if ($_ -like "*.si") { $_ } else { "$_.si" }
    } |
    Sort-Object -Unique

if (-not $domains) {
    throw "No domain candidates found in $InputFile"
}

function Get-RdapStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Domain
    )

    $uri = "$RdapBase/$([uri]::EscapeDataString($Domain))"

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $uri -Method Head -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
            return [int]$response.StatusCode
        }
        catch {
            $response = $_.Exception.Response

            if ($null -ne $response -and $null -ne $response.StatusCode) {
                $status = [int]$response.StatusCode

                if ($status -eq 429 -and $attempt -lt $MaxRetries) {
                    $waitSeconds = [Math]::Min(60, 3 * $attempt)

                    try {
                        $retryAfter = $response.Headers["Retry-After"]
                        $parsedRetryAfter = 0
                        if ($retryAfter -and [int]::TryParse([string]$retryAfter, [ref]$parsedRetryAfter)) {
                            $waitSeconds = [Math]::Max(1, $parsedRetryAfter)
                        }
                    }
                    catch {
                        # Fall back to incremental backoff.
                    }

                    Write-Warning "Rate limited while checking $Domain. Retrying in $waitSeconds second(s)..."
                    Start-Sleep -Seconds $waitSeconds
                    continue
                }

                return $status
            }

            if ($attempt -lt $MaxRetries) {
                $waitSeconds = [Math]::Min(30, 2 * $attempt)
                Write-Warning "Network error while checking $Domain. Retrying in $waitSeconds second(s)..."
                Start-Sleep -Seconds $waitSeconds
                continue
            }

            return 0
        }
    }

    return 0
}

$results = [System.Collections.Generic.List[object]]::new()
$total = $domains.Count
$index = 0

foreach ($domain in $domains) {
    $index++
    Write-Progress -Activity "Checking .si domains" -Status "$index / $total : $domain" -PercentComplete (($index / $total) * 100)

    $status = Get-RdapStatus -Domain $domain

    $result = switch ($status) {
        404 { "LIKELY AVAILABLE" }
        200 { "TAKEN" }
        400 { "INVALID" }
        401 { "TAKEN" }
        429 { "RATE LIMITED" }
        0   { "ERROR" }
        default { "UNKNOWN ($status)" }
    }

    $row = [PSCustomObject]@{
        Domain = $domain
        Result = $result
        HTTP   = $status
    }

    $results.Add($row)

    if ($result -eq "LIKELY AVAILABLE") {
        Write-Host ("{0,-35} {1}" -f $domain, $result) -ForegroundColor Green
    }
    elseif ($result -eq "TAKEN") {
        Write-Host ("{0,-35} {1}" -f $domain, $result) -ForegroundColor DarkGray
    }
    else {
        Write-Host ("{0,-35} {1}" -f $domain, $result) -ForegroundColor Yellow
    }

    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

Write-Progress -Activity "Checking .si domains" -Completed

$sorted = $results | Sort-Object @{
    Expression = {
        switch ($_.Result) {
            "LIKELY AVAILABLE" { 0 }
            "TAKEN"            { 1 }
            default            { 2 }
        }
    }
}, Domain

$sorted | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation

$available = @(
    $sorted |
        Where-Object Result -eq "LIKELY AVAILABLE" |
        Select-Object -ExpandProperty Domain
)

$available | Set-Content -LiteralPath $AvailableFile

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "LIKELY AVAILABLE .SI DOMAINS" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

if ($available.Count -gt 0) {
    $available | ForEach-Object { Write-Host $_ -ForegroundColor Green }
}
else {
    Write-Host "None found in this run." -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("Checked:   {0}" -f $total)
Write-Host ("Available: {0}" -f $available.Count)
Write-Host ("CSV:       {0}" -f $OutputCsv)
Write-Host ("Available: {0}" -f $AvailableFile)
Write-Host ""
Write-Host "Note: Register.si says HTTP 404 usually means the domain is not registered,"
Write-Host "but it does not guarantee the domain can actually be registered."
