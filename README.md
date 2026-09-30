# SI Scanner

Fast, free bulk availability checking for `.si` domains using the official **Register.si RDAP server**.

No Porkbun account, API key, or paid service is required.

## How it works

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

No dependencies need to be installed.

## Usage

1. Put candidate names in `words.txt`, one per line.

You can enter stems:

```text
priva
agen
laten
accura
```

or complete domains:

```text
priva.si
agen.si
laten.si
accura.si
```

2. Run:

```powershell
.\scan-si.ps1
```

If PowerShell blocks local scripts for the current process:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scan-si.ps1
```

## Output

The scanner writes:

- `si-results.csv` — every candidate and its HTTP/result status
- `available.txt` — only names returned as `LIKELY AVAILABLE`

Generated result files are ignored by Git.

## Options

```powershell
.\scan-si.ps1 -InputFile .\my-list.txt
```

Use a different output location:

```powershell
.\scan-si.ps1 -OutputCsv .\results.csv -AvailableFile .\free.txt
```

Slow the request rate if Register.si starts rate limiting:

```powershell
.\scan-si.ps1 -DelayMs 1000
```

The default delay is 350 ms between requests. HTTP 429 responses are retried automatically with backoff.

## Important

A Register.si `404` means the domain was not found and **usually** means it is not registered. The registry explicitly notes that this does **not** guarantee the domain is eligible to be registered.

Treat `LIKELY AVAILABLE` as the shortlist, then confirm the final name with your registrar before purchasing.
