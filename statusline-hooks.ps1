# statusline-hooks.ps1 - Activity tracker for the Claude Code statusline (Windows)
#
# Registered by install.ps1 as a hook for: UserPromptSubmit, Stop, SubagentStart,
# SubagentStop and SessionEnd. It keeps small per-session state files in
# %TEMP%\claude-statusline that statusline.ps1 reads to render the 'activity' field
# (live "responding for Xm Ys" timer + count of running subagents).
#
# IMPORTANT: this script must never write to stdout - UserPromptSubmit hook output
# is injected into Claude's context. Everything is piped to $null and errors are
# swallowed; a broken hook must never block the session.

param([Parameter(Mandatory = $true)][string]$Event)

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $d = $raw | ConvertFrom-Json
    $sid = $d.session_id
    if (-not $sid) { exit 0 }

    $dir = Join-Path $env:TEMP 'claude-statusline'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $turnFile  = Join-Path $dir "turn-$sid.json"
    $agentFile = Join-Path $dir "agents-$sid.json"
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Parallel subagent spawns fire concurrent hooks; serialize the
    # read-modify-write of the state files with a per-session mutex.
    $acquired = $false
    $mutex = $null
    try {
        $mutex = New-Object System.Threading.Mutex($false, "claude-statusline-$sid")
        $acquired = $mutex.WaitOne(2000)
    } catch {}

    switch ($Event) {
        'UserPromptSubmit' {
            # New turn starts: reset the timer (end stays null while Claude works)
            [System.IO.File]::WriteAllText($turnFile, (@{ start = $now; end = $null } | ConvertTo-Json -Compress))
        }
        'Stop' {
            # Turn finished: stamp the end so the statusline can show the total
            $start = $now
            if (Test-Path $turnFile) {
                try { $t = Get-Content $turnFile -Raw | ConvertFrom-Json; if ($t.start) { $start = $t.start } } catch {}
            }
            [System.IO.File]::WriteAllText($turnFile, (@{ start = $start; end = $now } | ConvertTo-Json -Compress))
            # No subagent survives the end of a turn - clear any leftovers
            if (Test-Path $agentFile) { Remove-Item $agentFile -Force }
        }
        'SubagentStart' {
            # State stored as {"agents":[...]} - a bare array round-trips badly in PS 5.1
            $list = @()
            if (Test-Path $agentFile) {
                try { $list = @((Get-Content $agentFile -Raw | ConvertFrom-Json).agents) } catch { $list = @() }
            }
            $id = $d.agent_id
            if (-not $id) { $id = "agent-$now-$(Get-Random)" }
            $type = $d.agent_type
            if (-not $type) { $type = 'agent' }
            $list += [PSCustomObject]@{ id = $id; type = $type; ts = $now }
            $out = ConvertTo-Json -InputObject @{ agents = @($list) } -Compress -Depth 5
            [System.IO.File]::WriteAllText($agentFile, $out)
        }
        'SubagentStop' {
            if (Test-Path $agentFile) {
                $list = @()
                try { $list = @((Get-Content $agentFile -Raw | ConvertFrom-Json).agents) } catch {}
                $id = $d.agent_id
                if ($id) {
                    $list = @($list | Where-Object { $_.id -ne $id })
                } elseif ($list.Count -gt 0) {
                    # No id available: drop the oldest entry
                    $list = @($list | Sort-Object ts | Select-Object -Skip 1)
                }
                if ($list.Count -gt 0) {
                    $out = ConvertTo-Json -InputObject @{ agents = @($list) } -Compress -Depth 5
                    [System.IO.File]::WriteAllText($agentFile, $out)
                } else {
                    Remove-Item $agentFile -Force
                }
            }
        }
        'SessionEnd' {
            if (Test-Path $turnFile)  { Remove-Item $turnFile -Force }
            if (Test-Path $agentFile) { Remove-Item $agentFile -Force }
            # Opportunistic cleanup of files from sessions dead for over a day
            Get-ChildItem $dir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    if ($acquired) { try { $mutex.ReleaseMutex() } catch {} }
    if ($mutex) { $mutex.Dispose() }
} catch {}
exit 0
