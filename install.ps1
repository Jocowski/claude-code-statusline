# install.ps1 - Installer for claude-code-statusline (Windows / PowerShell)
# Run from the repo folder:  powershell -ExecutionPolicy Bypass -File install.ps1
$ErrorActionPreference = 'Stop'

$ClaudeDir = Join-Path $HOME '.claude'
$Dest      = Join-Path $ClaudeDir 'statusline.ps1'
$HooksDest = Join-Path $ClaudeDir 'statusline-hooks.ps1'
$Settings  = Join-Path $ClaudeDir 'settings.json'
$RepoRaw   = 'https://raw.githubusercontent.com/hugohvf/claude-code-statusline/main'

Write-Host ""
Write-Host "Claude Code Statusline - Installer (Windows)"
Write-Host "============================================"
Write-Host ""

# 1. Ensure ~/.claude exists
New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

# 2. Get the scripts - prefer the copies next to this installer, else download
foreach ($pair in @(@('statusline.ps1', $Dest), @('statusline-hooks.ps1', $HooksDest))) {
    $name = $pair[0]; $target = $pair[1]
    $local = Join-Path $PSScriptRoot $name
    if (Test-Path $local) {
        Copy-Item $local $target -Force
        Write-Host "  Copied $name from local repo"
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "$RepoRaw/$name" -OutFile $target
        Write-Host "  Downloaded $name"
    }
}

# 3. Load settings.json (preserve every existing key)
if (Test-Path $Settings) {
    $json = Get-Content $Settings -Raw | ConvertFrom-Json
} else {
    $json = [PSCustomObject]@{}
}

# Use forward slashes: on Windows with Git Bash installed, Claude Code routes
# the statusline command through Git Bash, which eats backslashes in the path.
$DestFwd  = $Dest.Replace('\', '/')
$HooksFwd = $HooksDest.Replace('\', '/')

# 4. Activity tracking (live turn timer + running subagent count) is optional:
#    it registers 5 hooks and re-runs the statusline every second.
Write-Host ""
$answer = Read-Host "Enable live activity tracking (turn timer + subagent count)? [Y/n]"
$enableHooks = ($answer -notmatch '^[nN]')

# refreshInterval 2s: keeps the activity timer live at half the process-spawn cost
# of 1s - that matters when several Claude Code sessions are open at once.
$statusLine = [PSCustomObject]@{ type = 'command'; command = "powershell -NoProfile -ExecutionPolicy Bypass -File $DestFwd" }
if ($enableHooks) {
    $statusLine | Add-Member -NotePropertyName refreshInterval -NotePropertyValue 2
}
$json | Add-Member -NotePropertyName statusLine -NotePropertyValue $statusLine -Force

if ($enableHooks) {
    if (-not ($json.PSObject.Properties.Name -contains 'hooks') -or $null -eq $json.hooks) {
        $json | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $events = @('UserPromptSubmit', 'Stop', 'SubagentStart', 'SubagentStop', 'SessionEnd')
    foreach ($ev in $events) {
        $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File $HooksFwd -Event $ev"
        if (-not ($json.hooks.PSObject.Properties.Name -contains $ev)) {
            $json.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue @() -Force
        }
        $existing = @($json.hooks.$ev)
        $already = $false
        foreach ($entry in $existing) {
            foreach ($h in @($entry.hooks)) {
                if ($h.command -like '*statusline-hooks.ps1*') { $already = $true }
            }
        }
        if (-not $already) {
            $newEntry = [PSCustomObject]@{ hooks = @([PSCustomObject]@{ type = 'command'; command = $cmd }) }
            $json.hooks.$ev = @($existing + $newEntry)
        }
    }
    Write-Host "  Activity hooks registered (refreshInterval: 2s)"
} else {
    Write-Host "  Skipped activity tracking (the 'activity' field will stay empty)"
}

$content = $json | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($Settings, $content)
Write-Host "  settings.json updated"

# 5. Let the user preview and pick fields/layout/theme
& $Dest -Choose

Write-Host ""
Write-Host "Done! Restart Claude Code to activate the statusline."
Write-Host "To change fields/layout/theme later:  powershell -NoProfile -ExecutionPolicy Bypass -File $Dest -Choose"
Write-Host ""
