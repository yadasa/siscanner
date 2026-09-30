param(
    [string]$OutputFile = ".\words.txt",
    [string]$MappingCsv = ".\cy-mapping.csv",
    [string]$ManualFile = ".\manual-words.txt",
    [string]$CacheFile = ".\.cache\words_alpha.txt",
    [switch]$ForceRefresh
)

$ErrorActionPreference = "Stop"
$SourceUrl = "https://raw.githubusercontent.com/dwyl/english-words/master/words_alpha.txt"

$cacheDirectory = Split-Path -Parent $CacheFile
if ($cacheDirectory -and -not (Test-Path -LiteralPath $cacheDirectory)) {
    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
}

if ($ForceRefresh -or -not (Test-Path -LiteralPath $CacheFile)) {
    Write-Host "Downloading English word corpus..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $SourceUrl -OutFile $CacheFile -UseBasicParsing -TimeoutSec 120
}
else {
    Write-Host "Using cached English word corpus: $CacheFile" -ForegroundColor DarkGray
}

$cyRows = @(
    Get-Content -LiteralPath $CacheFile |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object {
            $_ -match '^[a-z]+cy$' -and $_.Length -gt 2
        } |
        Sort-Object -Unique |
        ForEach-Object {
            $word = $_
            $stem = $word.Substring(0, $word.Length - 2)

            if ($stem.Length -gt 0) {
                [PSCustomObject]@{
                    Word   = $word
                    Domain = "$stem.si"
                }
            }
        }
)

if ($cyRows.Count -eq 0) {
    throw "No -cy words were found in the downloaded corpus."
}

$manualDomains = @()

if (Test-Path -LiteralPath $ManualFile) {
    $manualDomains = @(
        Get-Content -LiteralPath $ManualFile |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ -and -not $_.StartsWith("#") } |
            ForEach-Object {
                if ($_ -like "*.si") { $_ } else { "$_.si" }
            }
    )
}

$allDomains = @(
    @($cyRows | Select-Object -ExpandProperty Domain) +
    @($manualDomains)
) | Sort-Object -Unique

$allDomains | Set-Content -LiteralPath $OutputFile
$cyRows | Sort-Object Word | Export-Csv -LiteralPath $MappingCsv -NoTypeInformation

Write-Host ""
Write-Host "Generated .si domain-hack candidates from every *cy entry in the corpus." -ForegroundColor Green
Write-Host ("-cy words:      {0}" -f $cyRows.Count)
Write-Host ("Manual extras:  {0}" -f $manualDomains.Count)
Write-Host ("Unique domains: {0}" -f $allDomains.Count)
Write-Host ("Scan list:      {0}" -f $OutputFile)
Write-Host ("Word mapping:   {0}" -f $MappingCsv)
