# SI Scanner

Fast, free bulk availability checking for `.si` domains using the official **Register.si RDAP server**.

The default mode now automatically builds a scan list from **every English-word entry ending in `-cy`** in the DWYL English Words corpus, converts each one into a `.si` domain hack, and then checks it.

Examples:

| English word | Domain checked |
| --- | --- |
| `privacy` | `priva.si` |
| `latency` | `laten.si` |
| `agency` | `agen.si` |
| `accuracy` | `accura.si` |
| `efficiency` | `efficien.si` |

In other words, the final `cy` is replaced by `.si`.

## Word source

The automatic list builder downloads `words_alpha.txt` from **dwyl/english-words**, a 466k+ English-word corpus, and selects every alphabetic entry that ends in `cy`.

Source: https://github.com/dwyl/english-words

The phrase "every -cy word" in this repo therefore means **every matching entry in that corpus**, not a claim that any finite dictionary contains every English word ever used.

The corpus is cached locally under `.cache/`, so it is not downloaded again on every scan. Use `-ForceCyRefresh` when you want to refresh it.

## How availability checking works

Register.si supports anonymous RDAP `HEAD` requests specifically for checking whether a `.si` domain is already registered:

```text
https://rdap.register.si/domain/example.si
```

The scanner interprets the registry's documented HTTP responses as:

| HTTP | Scanner result | Meaning |
| --- | --- | --- |
| `404` | `LIKELY AVAILABLE` | Domain was not found. Usually unregistered, but not guaranteed registrable. |
| `200` | `TAKEN` | Registered and/or currently cannot be registered. |
| `401` | `TAKEN` | Registered; anonymous access cannot return further data. |
| `400` | `INVALID` | Invalid request/name. |
| `429` | `RATE LIMITED` | Too many requests; scanner retries with backoff. |

Official Register.si documentation: https://www.register.si/en/rdap/

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- Internet connection

No API key or paid service is required.

## Run the full -cy scan

```powershell
.\scan-si.ps1
```

On the first run the scanner will:

1. Download the English-word corpus.
2. Find every entry ending in `cy`.
3. Replace the final `cy` with `.si`.
4. Write the complete domain list to `words.txt`.
5. Write the word-to-domain mapping to `cy-mapping.csv`.
6. Check every generated domain against Register.si.
7. Save all results to `si-results.csv`.
8. Save likely available domains to `available.txt`.

If PowerShell blocks local scripts for the current process:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scan-si.ps1
```

## Refresh the source corpus

```powershell
.\scan-si.ps1 -ForceCyRefresh
```

## Build the -cy list without scanning

```powershell
.\build-cy-list.ps1
```

That regenerates `words.txt` and `cy-mapping.csv` without making RDAP availability requests.

## Add custom candidates

Put custom stems or full domains in `manual-words.txt`. They are merged into the generated list automatically.

Examples:

```text
mybrand
custom.si
```

## Scan your own file instead

When you provide a custom input file, automatic `-cy` list generation is skipped:

```powershell
.\scan-si.ps1 -InputFile .\my-list.txt
```

## Other options

Slow the request rate if Register.si starts rate limiting:

```powershell
.\scan-si.ps1 -DelayMs 1000
```

Skip rebuilding the `-cy` list and scan the existing `words.txt`:

```powershell
.\scan-si.ps1 -SkipCyBuild
```

The default delay is 350 ms between requests. HTTP 429 responses are retried automatically with backoff.

## Output

- `words.txt` — complete generated scan list
- `cy-mapping.csv` — original `-cy` word → `.si` domain mapping
- `si-results.csv` — every domain, source word, HTTP code, and availability result
- `available.txt` — only domains returned as `LIKELY AVAILABLE`
- `.cache/words_alpha.txt` — cached source corpus

Generated corpus/results files are ignored by Git where appropriate.

## Important

A Register.si `404` means the domain was not found and **usually** means it is not registered. The registry explicitly notes that this does **not** guarantee the domain is eligible to be registered.

Treat `LIKELY AVAILABLE` as the shortlist, then confirm the final name with your registrar before purchasing.
