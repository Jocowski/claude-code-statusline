# uninstall.ps1 - Remove claude-code-statusline (Windows / PowerShell)
# Run:  powershell -ExecutionPolicy Bypass -File uninstall.ps1
$ErrorActionPreference = 'Stop'

$ClaudeDir = Join-Path $HOME '.claude'
$Dest      = Join-Path $ClaudeDir 'statusline.ps1'
$HooksDest = Join-Path $ClaudeDir 'statusline-hooks.ps1'
$Settings  = Join-Path $ClaudeDir 'settings.json'
$Cache     = Join-Path $env:TEMP 'statusline-usd-brl'
$StateDir  = Join-Path $env:TEMP 'claude-statusline'
$ConfigOld = Join-Path $ClaudeDir 'statusline-style'
$Config    = Join-Path $ClaudeDir 'statusline-config.json'

Write-Host ""
Write-Host "Claude Code Statusline - Uninstaller (Windows)"
Write-Host "=============================================="
Write-Host ""

# 1. Clean settings.json: statusLine key + our hook entries (keep everything else)
if (Test-Path $Settings) {
    $json = Get-Content $Settings -Raw | ConvertFrom-Json
    $dirty = $false
    if ($json.PSObject.Properties.Name -contains 'statusLine') {
        $json.PSObject.Properties.Remove('statusLine')
        $dirty = $true
        Write-Host "  Removed statusLine from settings.json"
    }
    if ($json.PSObject.Properties.Name -contains 'hooks' -and $null -ne $json.hooks) {
        foreach ($prop in @($json.hooks.PSObject.Properties)) {
            $kept = @()
            foreach ($entry in @($prop.Value)) {
                $ours = $false
                foreach ($h in @($entry.hooks)) {
                    if ($h.command -like '*statusline-hooks.ps1*') { $ours = $true }
                }
                if (-not $ours) { $kept += $entry }
            }
            if ($kept.Count -lt @($prop.Value).Count) {
                $dirty = $true
                if ($kept.Count -gt 0) {
                    $json.hooks.($prop.Name) = $kept
                } else {
                    $json.hooks.PSObject.Properties.Remove($prop.Name)
                }
            }
        }
        if (@($json.hooks.PSObject.Properties).Count -eq 0) {
            $json.PSObject.Properties.Remove('hooks')
            $dirty = $true
        }
        Write-Host "  Removed statusline hooks from settings.json"
    }
    if ($dirty) {
        $content = $json | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($Settings, $content)
    } else {
        Write-Host "  Nothing to remove from settings.json"
    }
} else {
    Write-Host "  settings.json not found (nothing to remove)"
}

# 2. Delete scripts and config
foreach ($f in @($Dest, $HooksDest, $Config, $ConfigOld)) {
    if (Test-Path $f) {
        Remove-Item $f -Force
        Write-Host "  Deleted $f"
    }
}

# 3. Delete caches and activity state
if (Test-Path $Cache) {
    Remove-Item $Cache -Force
    Write-Host "  Deleted exchange-rate cache"
}
if (Test-Path $StateDir) {
    Remove-Item $StateDir -Recurse -Force
    Write-Host "  Deleted activity state files"
}

Write-Host ""
Write-Host "Done! Restart Claude Code."
Write-Host ""
