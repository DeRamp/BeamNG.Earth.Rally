# Start the maintainer: the one Claude session that reviews and merges pull requests into main.
# From the repo root (scripts are off by default on Windows, hence the bypass):
#   powershell -ExecutionPolicy Bypass -File tools\maintainer.ps1
# It runs as a background session (no window). Other sessions find it by the name "maintainer" and send it merge
# requests (/merge-request). Watch it with `claude logs maintainer`, talk to it with `claude attach <id>`.
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo

# (assign first: Windows PowerShell 5.1 sends a parsed JSON array down the pipe as one object)
$sessions = claude agents --json | Out-String | ConvertFrom-Json
# `claude agents --json` lists live sessions only; state "done" means idle between turns, still running
$running = @($sessions | ForEach-Object { $_ } | Where-Object { $_.name -eq 'maintainer' })
if ($running.Count -gt 0) {
    Write-Output "maintainer is already running: $($running[0].id) ($($running[0].state)). claude attach $($running[0].id)"
    exit 0
}

# auto: it runs unattended, so routine steps must not wait on a permission prompt (ask rules, e.g. git push, still ask)
claude --bg --agent maintainer --name maintainer --permission-mode auto `
    --settings "$repo\.claude\maintainer.settings.json" `
    "Start up as the maintainer. Run the startup checks and report that you are ready, then wait for merge requests."
