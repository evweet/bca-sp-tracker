# ============================================================
# setup.ps1 — One-time repo initialization for sp-tracker
# ============================================================

[CmdletBinding()]
param(
    [string]$RepoDir   = (Resolve-Path "$PSScriptRoot\..\..").Path,
    [string]$RemoteUrl = ""
)

$ErrorActionPreference = "Stop"

Set-Location $RepoDir

# --- Folders --------------------------------------------------------------
foreach ($d in @("procedures", "logs")) {
    $p = Join-Path $RepoDir $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

# --- git init -------------------------------------------------------------
if (-not (Test-Path (Join-Path $RepoDir ".git"))) {
    git init -b main | Out-Null
    Write-Host "Initialized git repository."
} else {
    Write-Host "Git repository already initialized."
}

# Keep diffs clean across machines
git config core.autocrlf false

# --- .gitignore -----------------------------------------------------------
$giPath = Join-Path $RepoDir ".gitignore"
$gi = @(
    "# sp-tracker"
    "logs/"
    "*.log"
    "secret.pgpass"
    "*.bak"
) -join "`n"
[System.IO.File]::WriteAllText($giPath, $gi + "`n", [System.Text.UTF8Encoding]::new($false))

# --- .gitattributes -------------------------------------------------------
$gaPath = Join-Path $RepoDir ".gitattributes"
$ga = @(
    "* text=auto eol=lf"
    "*.sql text eol=lf"
    "*.ps1 text eol=lf"
    "*.sh  text eol=lf"
) -join "`n"
[System.IO.File]::WriteAllText($gaPath, $ga + "`n", [System.Text.UTF8Encoding]::new($false))

# --- Initial commit -------------------------------------------------------
git add .gitignore .gitattributes src/ LICENSE 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' } | ForEach-Object { Write-Host $_ }
$pending = git status --porcelain
if ($pending) {
    git commit -m "chore: initial sp-tracker setup" 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' } | ForEach-Object { Write-Host $_ }
    Write-Host "Created initial commit."
} else {
    Write-Host "Nothing new to commit."
}

# --- Optional remote ------------------------------------------------------
if ($RemoteUrl) {
    $existing = git remote get-url origin 2>$null
    if ($existing) {
        git remote set-url origin $RemoteUrl
        Write-Host "Updated origin -> $RemoteUrl"
    } else {
        git remote add origin $RemoteUrl
        Write-Host "Added origin -> $RemoteUrl"
    }
    Write-Host "Push with: git push -u origin main"
}

Write-Host ""
Write-Host "Next steps (run from repo root '$RepoDir'):"
Write-Host "  1. Create .\secret.pgpass containing the DB password (one line)."
Write-Host "  2. `$env:PGPASSWORD = (Get-Content .\secret.pgpass -Raw).Trim()"
Write-Host "  3. .\src\windows\extract.ps1   # validate"
Write-Host "  4. .\src\windows\sync.ps1      # full cycle"
Write-Host "  5. Run .\src\windows\register-task.ps1 from an elevated PowerShell to schedule daily."
