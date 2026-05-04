# ============================================================
# register-task.ps1 — Register the daily sync as a Scheduled Task
# Run from an elevated PowerShell.
# ============================================================
# NOTE on PGPASSWORD:
#   Scheduled tasks do NOT inherit your interactive shell's env vars.
#   Either:
#     (a) place a `secret.pgpass` file at the repo root (gitignored), or
#     (b) set PGPASSWORD as a User/Machine env var:
#         [Environment]::SetEnvironmentVariable('PGPASSWORD','...', 'User')
# ============================================================

[CmdletBinding()]
param(
    [string]$TaskName  = "SP-Tracker-Sync",
    [string]$ScriptDir = $PSScriptRoot,
    [string]$RunTime   = "08:00AM"
)

$syncScript = Join-Path $ScriptDir "sync.ps1"
if (-not (Test-Path $syncScript)) {
    Write-Error "sync.ps1 not found at $syncScript"
    exit 1
}

$workingDir = (Resolve-Path "$ScriptDir\..\..").Path

$action = New-ScheduledTaskAction `
    -Execute  "powershell.exe" `
    -Argument ("-NonInteractive -ExecutionPolicy Bypass -File `"{0}`"" -f $syncScript) `
    -WorkingDirectory $workingDir

$trigger = New-ScheduledTaskTrigger -Daily -At $RunTime

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action   $action `
    -Trigger  $trigger `
    -Settings $settings `
    -RunLevel Highest `
    -Force | Out-Null

Write-Host "Scheduled task '$TaskName' registered (daily at $RunTime)."
Write-Host "Test it with: Start-ScheduledTask -TaskName '$TaskName'"
