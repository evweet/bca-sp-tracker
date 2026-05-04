# ============================================================
# sync.ps1 — Detect PG procedure changes and commit/push to Git
# ============================================================

[CmdletBinding()]
param(
    [string]$RepoDir     = (Resolve-Path "$PSScriptRoot\..\..").Path,
    [string]$ScriptDir   = $PSScriptRoot,
    [string]$PgHost      = "127.0.0.1",
    [int]   $Port        = 21521,
    [string]$Database    = "bca_dev",
    [string]$Username    = "polaruser1",
    [string]$Schema      = "tsadba",
    [string]$Branch      = "main",
    [string]$Remote      = "origin",
    [string]$CommitUser  = "sp-tracker-bot",
    [string]$CommitEmail = "sp-tracker@localhost",
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"

Set-Location $RepoDir

# --- Logging ------------------------------------------------------------
$logDir = Join-Path $RepoDir "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("sync-{0}.log" -f (Get-Date -Format "yyyyMMdd"))
Start-Transcript -Path $logFile -Append | Out-Null

try {
    $startedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
    Write-Host "=== sp-tracker sync @ $startedAt ==="

    # --- Load PGPASSWORD from secret.pgpass if not already set ----------
    if (-not $env:PGPASSWORD) {
        $secretFile = Join-Path $RepoDir "secret.pgpass"
        if (Test-Path $secretFile) {
            $env:PGPASSWORD = (Get-Content -Raw -Path $secretFile).Trim()
            Write-Host "Loaded PGPASSWORD from secret.pgpass"
        } else {
            Write-Error "PGPASSWORD not set and secret.pgpass not found. Aborting."
            exit 2
        }
    }

    # --- Step 1: extract -----------------------------------------------
    Write-Host "Extracting procedures from $Schema..."
    & "$ScriptDir\extract.ps1" `
        -PgHost $PgHost -Port $Port -Database $Database `
        -Username $Username -Schema $Schema `
        -OutputDir (Join-Path $RepoDir "procedures")
    if ($LASTEXITCODE -ne 0) {
        Write-Error "extract.ps1 failed with exit $LASTEXITCODE"
        exit $LASTEXITCODE
    }

    # --- Step 2: detect changes ----------------------------------------
    $status = git status --porcelain -- procedures/
    if (-not $status) {
        Write-Host "No changes detected. Nothing to commit."
        exit 0
    }
    Write-Host "Changes detected:"
    Write-Host $status

    # --- Step 3: commit -------------------------------------------------
    git config user.name  $CommitUser
    git config user.email $CommitEmail

    git add procedures/ 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' } | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { Write-Error "git add failed"; exit 1 }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $msgFile = New-TemporaryFile
    @(
        "chore(sp): snapshot $Schema @ $timestamp",
        "",
        "Changed files:",
        $status
    ) | Set-Content -Path $msgFile -Encoding UTF8

    git commit -F $msgFile.FullName
    $commitExit = $LASTEXITCODE
    Remove-Item $msgFile -Force -ErrorAction SilentlyContinue
    if ($commitExit -ne 0) { Write-Error "git commit failed"; exit 1 }

    # --- Step 4: push ---------------------------------------------------
    if ($NoPush) {
        Write-Host "Skipping push (-NoPush set)."
        exit 0
    }

    $remoteUrl = git remote get-url $Remote 2>$null
    if (-not $remoteUrl) {
        Write-Warning "Remote '$Remote' not configured. Commit kept locally."
        exit 0
    }

    git push $Remote $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git push failed with exit $LASTEXITCODE"
        exit 1
    }

    Write-Host "Pushed changes to $Remote/$Branch"
    exit 0
}
finally {
    Stop-Transcript | Out-Null
}
