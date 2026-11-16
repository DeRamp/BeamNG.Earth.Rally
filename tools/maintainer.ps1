# Start the maintainer: the one Claude session that reviews and merges pull requests into main.
#   powershell -ExecutionPolicy Bypass -File tools/maintainer.ps1      (from the root of any checkout of this repo)
# (scripts are off by default on Windows, hence the bypass). It runs as a background session with no window, always
# in the main checkout, whichever worktree this copy of the script sits in. The owner or, with the owner's approval,
# a sender in /merge-request may run it. Other sessions find it by the name "maintainer". Watch it with
# `claude logs <id>`, talk to it with `claude attach <id>`. A copy of this script on an old branch may pass flags that
# no longer fit main; run the one on main when in doubt.

function Fail($msg) { [Console]::Error.WriteLine("maintainer.ps1: $msg"); exit 1 }

# The main checkout is the parent of the shared .git folder, even when this script runs from a worktree.
$common = git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir
if ($LASTEXITCODE -ne 0 -or -not $common) { Fail "cannot find the repository from $PSScriptRoot" }
function Norm($p) { (Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue).Path -replace '[\\/]+$', '' }
$repo = Norm (Split-Path $common -Parent)
Set-Location -LiteralPath $repo

# Refuse a second maintainer for this repo. Fail closed: if the session list cannot be read, start nothing.
# `claude agents --json` lists live sessions in every project; state "done" means idle between turns, still running.
# Two starts at the same instant can still race; the second sender sees the first within a minute, so that is accepted.
$json = claude agents --json | Out-String
if ($LASTEXITCODE -ne 0) { Fail "claude agents exited $LASTEXITCODE, not starting" }
# This session (a sender) is always live, so a good list is never empty: anything but a JSON array is a failure.
if ($json.Trim() -notmatch '^\[') { Fail "session list is not a JSON array, not starting" }
try { $sessions = $json | ConvertFrom-Json } catch { Fail "cannot parse the session list, not starting" }
# (assigned first: Windows PowerShell 5.1 sends a parsed JSON array down the pipe as one object)
$running = @($sessions | ForEach-Object { $_ } | Where-Object {
    $_.name -eq 'maintainer' -and $_.cwd -and ((Norm $_.cwd) -eq $repo)
})
if ($running.Count -gt 0) {
    Write-Output "maintainer is already running: $($running[0].id). claude attach $($running[0].id)"
    exit 0
}

# A sender runs this from inside its own Claude session: do not hand that session's identity to the new one.
# Every CLAUDE* variable goes, except credentials (an OAuth token or API key set by the owner for auth).
Get-ChildItem Env: | Where-Object { $_.Name -like 'CLAUDE*' -and $_.Name -notmatch 'OAUTH|API_KEY' } |
    ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" -ErrorAction SilentlyContinue }

# auto: it runs unattended, so routine steps must not wait on a permission prompt (ask rules, e.g. git push, still ask).
# No prompt argument: the agent's initialPrompt runs the startup checks (a prompt here would run them twice).
claude --bg --agent maintainer --name maintainer --permission-mode auto --settings "$repo\.claude\maintainer.settings.json"
if ($LASTEXITCODE -ne 0) { Fail "claude --bg exited $LASTEXITCODE" }
