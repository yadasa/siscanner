param(
    [string]$InputFile = ".\words.txt",
    [string]$OutputCsv = ".\si-results.csv",
    [string]$AvailableFile = ".\available.txt",
    [int]$DelayMs = 350,
    [int]$MaxRetries = 5,
    [switch]$SkipCyBuild,
    [switch]$ForceCyRefresh
)

$ErrorActionPreference = "Stop"
$RdapBase = "https://rdap.register.si/domain"
$UsingDefaultInput = $InputFile -eq ".\words.txt"

if ($UsingDefaultInput) {
    $InputFile = Join-Path $PSScriptRoot "words.txt"
}

if (-not $SkipCyBuild -and $UsingDefaultInput) {
    $builder = Join-Path $PSScriptRoot "build-cy-list.ps1"

    if (-not (Test-Path -LiteralPath $builder)) {
        throw "Missing list builder: $builder"
    }

    $buildArgs = @{
        OutputFile = $InputFile
        MappingCsv = (Join-Path $PSScriptRoot "cy-mapping.csv")
        ManualFile = (Join-Path $PSScriptRoot "manual-words.txt")
        CacheFile  = (Join-Path $PSScriptRoot ".cache\words_alpha.txt")
    }

    if ($ForceCyRefresh) {
        $buildArgs.ForceRefresh = $true
    }

    & $builder @buildArgs
}

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

$sourceWordByDomain = @{}
$mappingFile = Join-Path $PSScriptRoot "cy-mapping.csv"

if (Test-Path -LiteralPath $mappingFile) {
    Import-Csv -LiteralPath $mappingFile | ForEach-Object {
        if ($_.Domain -and $_.Word) {
            $sourceWordByDomain[$_.Domain.ToLowerInvariant()] = $_.Word
        }
    }
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

    $sourceWord = ""
    if ($sourceWordByDomain.ContainsKey($domain)) {
        $sourceWord = $sourceWordByDomain[$domain]
    }

    $row = [PSCustomObject]@{
        Word      = $sourceWord
        Domain    = $domain
        Result    = $result
        HTTP      = $status
    }

    $results.Add($row)

    if ($result -eq "LIKELY AVAILABLE") {
        Write-Host ("{0,-35} {1,-18} {2}" -f $domain, $result, $sourceWord) -ForegroundColor Green
    }
    elseif ($result -eq "TAKEN") {
        Write-Host ("{0,-35} {1,-18} {2}" -f $domain, $result, $sourceWord) -ForegroundColor DarkGray
    }
    else {
        Write-Host ("{0,-35} {1,-18} {2}" -f $domain, $result, $sourceWord) -ForegroundColor Yellow
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

$availableRows = @(
    $sorted |
        Where-Object Result -eq "LIKELY AVAILABLE"
)

$availableRows |
    Select-Object -ExpandProperty Domain |
    Set-Content -LiteralPath $AvailableFile

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "LIKELY AVAILABLE .SI DOMAINS" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

if ($availableRows.Count -gt 0) {
    $availableRows | ForEach-Object {
        if ($_.Word) {
            Write-Host ("{0,-35} <- {1}" -f $_.Domain, $_.Word) -ForegroundColor Green
        }
        else {
            Write-Host $_.Domain -ForegroundColor Green
        }
    }
}
else {
    Write-Host "None found in this run." -ForegroundColor Yellow
}

Write-Host ""
Write-Host ("Checked:   {0}" -f $total)
Write-Host ("Available: {0}" -f $availableRows.Count)
Write-Host ("CSV:       {0}" -f $OutputCsv)
Write-Host ("Available: {0}" -f $AvailableFile)
Write-Host ""
Write-Host "Note: Register.si says HTTP 404 usually means the domain is not registered,"
Write-Host "but it does not guarantee the domain can actually be registered."
