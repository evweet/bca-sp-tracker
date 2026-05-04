# ============================================================
# extract.ps1 — Pull procedure definitions from PostgreSQL
# ============================================================
# Requires: psql.exe on PATH (PostgreSQL 14+ client)
# Auth:     password supplied via $env:PGPASSWORD (never logged)
# ============================================================

[CmdletBinding()]
param(
    [string]$PgHost    = "127.0.0.1",
    [int]   $Port      = 21521,
    [string]$Database  = "bca_dev",
    [string]$Username  = "polaruser1",
    [string]$Schema    = "tsadba",
    [string]$OutputDir = (Join-Path (Resolve-Path "$PSScriptRoot\..\..").Path "procedures"),
    [string]$PsqlPath  = "C:\Self Installed\pgsql\bin\psql.exe"
)

$ErrorActionPreference = "Stop"

# List of procedures to track (schema-qualified by -Schema)
$procedures = @(
    "tsa_sp_school_weight_cal",
    "tsa_sp_school_weight_cav_cal",
    "tsa_sp_student_weight_cal"
)

# --- Pre-flight ----------------------------------------------------------
if (-not $env:PGPASSWORD) {
    Write-Error "PGPASSWORD environment variable is not set. Aborting."
    exit 2
}

if (-not (Get-Command $PsqlPath -ErrorAction SilentlyContinue)) {
    Write-Error "psql client not found (looked for '$PsqlPath'). Add PostgreSQL bin to PATH or pass -PsqlPath."
    exit 2
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# UTF-8 without BOM for deterministic, clean diffs
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# Common psql args: no rc file, no password prompt, stop on first error
$psqlBase = @(
    "--host=$PgHost"
    "--port=$Port"
    "--dbname=$Database"
    "--username=$Username"
    "--no-psqlrc"
    "--no-password"
    "-v", "ON_ERROR_STOP=1"
)

# --- Connectivity check --------------------------------------------------
try {
    $null = & $PsqlPath @psqlBase -A -t -c "SELECT 1" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "psql connectivity check failed (exit $LASTEXITCODE)" }
} catch {
    Write-Error "Cannot connect to $PgHost`:$Port/$Database as $Username. $_"
    exit 3
}

# --- Helpers -------------------------------------------------------------
function Sanitize-ForFilename {
    param([string]$s)
    $clean = ($s -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
    if ([string]::IsNullOrEmpty($clean)) { return "noargs" }
    return $clean
}

function Invoke-Psql-Tuples {
    param(
        [string]$Sql,
        [string]$RecordSep = [char]0x1E,
        [string]$FieldSep  = [char]0x1F
    )
    $psqlArgs = $psqlBase + @(
        "-A", "-t",
        "-F", $FieldSep,
        "-R", $RecordSep,
        "-c", $Sql
    )
    $output = & $PsqlPath @psqlArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "psql query failed (exit $LASTEXITCODE): $output"
    }
    return [string]::Join("`n", $output)
}

# --- Main loop -----------------------------------------------------------
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
$failures  = 0

foreach ($sp in $procedures) {
    try {
        $listSql = @"
SELECT p.oid::text,
       pg_get_function_identity_arguments(p.oid),
       p.prokind
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = '$Schema'
  AND p.proname = '$sp'
ORDER BY p.oid
"@
        $listOut = Invoke-Psql-Tuples -Sql $listSql
        $rows = $listOut -split [char]0x1E | Where-Object { $_ -and $_.Trim() }

        if (-not $rows -or $rows.Count -eq 0) {
            Write-Warning "Not found: $Schema.$sp"
            continue
        }

        $multiOverload = $rows.Count -gt 1

        foreach ($row in $rows) {
            $parts  = $row -split [char]0x1F
            $oid    = $parts[0].Trim()
            $argSig = if ($parts.Count -ge 2) { $parts[1] } else { "" }
            $kind   = if ($parts.Count -ge 3) { $parts[2].Trim() } else { "" }

            $defSql = "SELECT pg_get_functiondef($oid)"
            $def = Invoke-Psql-Tuples -Sql $defSql

            $def = $def -replace [char]0x1E, ""
            $def = $def -replace "`r`n", "`n" -replace "`r", "`n"
            $def = $def.TrimEnd("`n", " ", "`t") + "`n"

            $kindLabel = switch ($kind) {
                'p' { 'PROCEDURE' }
                'f' { 'FUNCTION' }
                'a' { 'AGGREGATE' }
                'w' { 'WINDOW' }
                default { 'ROUTINE' }
            }

            $header = @(
                "-- ============================================================",
                "-- source : $Schema.$sp($argSig)",
                "-- kind   : $kindLabel",
                "-- ============================================================",
                ""
            ) -join "`n"

            $content = $header + $def

            $fileName = if ($multiOverload) {
                "{0}.{1}({2}).sql" -f $Schema, $sp, (Sanitize-ForFilename $argSig)
            } else {
                "{0}.{1}.sql" -f $Schema, $sp
            }
            $filePath = Join-Path $OutputDir $fileName

            [System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
            Write-Host "Extracted: $fileName"
        }
    } catch {
        $failures++
        Write-Error "Failed to extract $Schema.$sp : $($_.Exception.Message)"
    }
}

if ($failures -gt 0) {
    Write-Error "$failures procedure(s) failed to extract at $timestamp"
    exit 1
}

Write-Host "Done at $timestamp"
exit 0
