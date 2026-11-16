# Start the maintainer: the one Claude session that reviews and merges pull requests into main.
#   powershell -ExecutionPolicy Bypass -File tools/maintainer.ps1
# (scripts are off by default on Windows, hence the bypass). It runs as a background session with no window, always
# in the main checkout, whichever worktree this copy of the script sits in. Other sessions find it by the name
# "maintainer" (/merge-request). Watch it with `claude logs <id>`, talk to it with `claude attach <id>`.
$ErrorActionPreference = 'Stop'

# The main checkout is the parent of the shared .git folder, even when this script runs from a worktree.
$common = git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir
if ($LASTEXITCODE -ne 0 -or -not $common) { Write-Error "maintainer.ps1: cannot find the repository from $PSScriptRoot"; exit 1 }
$repo = Split-Path $common -Parent
Set-Location $repo

# Refuse a second maintainer. Fail closed: if the session list cannot be read, start nothing.
# `claude agents --json` lists live sessions only; state "done" means idle between turns, still running.
# Two launches at the same instant can still race; only the owner launches it, so that is accepted.
try {
    $json = claude agents --json | Out-String
    if ($LASTEXITCODE -ne 0) { throw "claude agents exited $LASTEXITCODE" }
    # (assign first: Windows PowerShell 5.1 sends a parsed JSON array down the pipe as one object)
    $sessions = $json | ConvertFrom-Json
} catch {
    Write-Error "maintainer.ps1: cannot read the session list, not starting: $_"
    exit 1
}
$running = @($sessions | ForEach-Object { $_ } | Where-Object { $_.name -eq 'maintainer' })
if ($running.Count -gt 0) {
    Write-Output "maintainer is already running: $($running[0].id). claude attach $($running[0].id)"
    exit 0
}

# auto: it runs unattended, so routine steps must not wait on a permission prompt (ask rules, e.g. git push, still ask).
# No prompt argument: the agent's initialPrompt runs the startup checks (a prompt here would run them twice).
claude --bg --agent maintainer --name maintainer --permission-mode auto --settings "$repo\.claude\maintainer.settings.json"
