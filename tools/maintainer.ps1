# Start the maintainer: the one Claude session that reviews and merges pull requests into main.
# From the repo root (scripts are off by default on Windows, hence the bypass):
#   powershell -ExecutionPolicy Bypass -File tools\maintainer.ps1
# Other sessions find it by the name "maintainer" and send it merge requests (/merge-request).
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo
claude --agent maintainer --name maintainer --settings "$repo\.claude\maintainer.settings.json"
