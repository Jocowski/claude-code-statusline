# statusline.ps1 - Claude Code statusline for Windows (PowerShell 5.1+)
#
# Native Windows version: no jq, no Git Bash required.
# Install: copy to %USERPROFILE%\.claude\statusline.ps1 and set in settings.json:
#   { "statusLine": { "type": "command",
#       "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\<you>\\.claude\\statusline.ps1" } }
#
# Customization has 3 independent axes, stored in %USERPROFILE%\.claude\statusline-config.json:
#   fields - which info appears, as lines of field ids (see $FIELD_HELP below)
#   layout - how it is arranged: lines | inline | frame | powerline | powerline-round
#   theme  - colors: ansi | mocha | latte | frappe | macchiato | mono
# Presets bundle the three axes; the -Choose wizard previews and saves any combination.
#
# Usage:
#   statusline.ps1                    normal mode (JSON payload on stdin)
#   statusline.ps1 -Style <preset>    force a preset (still reads stdin)
#   statusline.ps1 -Choose            interactive 3-step wizard with live previews

param(
    [string]$Style,
    [switch]$Choose
)

# Force UTF-8 output so emojis/blocks aren't garbled when stdout is a pipe
# (PowerShell 5.1 defaults to the OEM code page for redirected output).
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Helper: return $default when value is null/empty
function Def($val, $default) {
    if ($null -eq $val -or $val -eq '') { return $default }
    return $val
}

$E     = [char]27
$RESET = "$E[0m"

$ConfigFile      = Join-Path $HOME '.claude\statusline-config.json'
$StyleFileLegacy = Join-Path $HOME '.claude\statusline-style'
$StateDir        = Join-Path $env:TEMP 'claude-statusline'

# ============================== GLYPH SETS ==============================
# emoji (default for text layouts), nerd (powerline layouts), ascii (plain consoles)
function Get-Glyphs($name) {
    $gauge = @([char]0x2581,[char]0x2582,[char]0x2583,[char]0x2584,[char]0x2585,[char]0x2586,[char]0x2587,[char]0x2588)
    switch ($name) {
        'nerd' { return @{
            Dir=[string][char]0xF07B; Git=[string][char]0xE0A0; Clock=[string][char]0xF017
            Warn=[string][char]0x26A0; Bolt=[string][char]0xF0E7; Agents=[string][char]0xF0C0
            Check=[string][char]0xF00C; Cross=[string][char]0xF00D; Pend=[string][char]0xF111
            Brain=[string][char]0xF085; Cycle=[string][char]0x21BB
            Full=[string][char]0x2588; Light=[string][char]0x2591; MOn=[string][char]0x25B0; MOff=[string][char]0x25B1
            Fr1=[string][char]0x256D; FrM=[string][char]0x251C; FrE=[string][char]0x2570; FrH=[string][char]0x2500
            Dot=[string][char]0xB7; Gauge=$gauge
        } }
        'ascii' { return @{
            Dir=''; Git=''; Clock=''; Warn='!'; Bolt='>>'; Agents='agents:'
            Check='ok'; Cross='x'; Pend='o'; Brain='effort:'; Cycle='~'
            Full='#'; Light='-'; MOn='='; MOff='.'
            Fr1='+'; FrM='|'; FrE='`'; FrH='-'
            Dot='|'; Gauge=@('.',':','-','=','+','o','*','#')
        } }
        default { return @{
            Dir=[char]::ConvertFromUtf32(0x1F4C1); Git=[char]::ConvertFromUtf32(0x1F33F); Clock=[string][char]0x23F1
            Warn=[string][char]0x26A0; Bolt=[string][char]0x26A1; Agents=[char]::ConvertFromUtf32(0x1F916)
            Check=[string][char]0x2714; Cross=[string][char]0x2716; Pend=[string][char]0x25CF
            Brain=[char]::ConvertFromUtf32(0x1F9E0); Cycle=[string][char]0x21BB
            Full=[string][char]0x2588; Light=[string][char]0x2591; MOn=[string][char]0x25B0; MOff=[string][char]0x25B1
            Fr1=[string][char]0x256D; FrM=[string][char]0x251C; FrE=[string][char]0x2570; FrH=[string][char]0x2500
            Dot=[string][char]0xB7; Gauge=$gauge
        } }
    }
}

# Glyph + text, skipping the space when the glyph set has no glyph (ascii)
function GT($g, $t) {
    if ("$g" -ne '') { return "$g $t" }
    return $t
}

# ============================== THEMES ==============================
# A theme provides fg colors for text layouts and bg segment colors for powerline.
# Pl segment entry: B = bg escape, S = same color as fg (for separators), T = text fg on it.
function PlSeg($bg, $tx) {
    return @{ B = "$E[48;2;${bg}m"; S = "$E[38;2;${bg}m"; T = "$E[38;2;${tx}m" }
}

function New-CatTheme($p) {
    return @{
        Accent = "$E[38;2;$($p.mauve)m";  Good = "$E[38;2;$($p.green)m"
        Warn   = "$E[38;2;$($p.yellow)m"; Bad  = "$E[38;2;$($p.red)m"
        Money  = "$E[38;2;$($p.peach)m";  Time = "$E[38;2;$($p.teal)m"
        Dim    = "$E[38;2;$($p.overlay)m"; R = $RESET
        Pl = @{
            model   = PlSeg $p.mauve $p.base
            dir     = PlSeg $p.surf0 $p.text
            branch  = PlSeg $p.surf1 $p.text
            good    = PlSeg $p.green $p.base
            warn    = PlSeg $p.yellow $p.base
            bad     = PlSeg $p.red $p.base
            cost    = PlSeg $p.peach $p.base
            time    = PlSeg $p.teal $p.base
            misc    = PlSeg $p.surf0 $p.text
            accent2 = PlSeg $p.blue $p.base
            sky     = PlSeg $p.sky $p.base
        }
    }
}

$THEMES = @{
    ansi = @{
        Accent = "$E[36m"; Good = "$E[32m"; Warn = "$E[33m"; Bad = "$E[31m"
        Money  = "$E[33m"; Time = ''; Dim = "$E[2m"; R = $RESET
        Pl = @{
            model   = @{ B = "$E[46m";  S = "$E[36m"; T = "$E[30m" }
            dir     = @{ B = "$E[44m";  S = "$E[34m"; T = "$E[97m" }
            branch  = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            good    = @{ B = "$E[42m";  S = "$E[32m"; T = "$E[30m" }
            warn    = @{ B = "$E[43m";  S = "$E[33m"; T = "$E[30m" }
            bad     = @{ B = "$E[41m";  S = "$E[31m"; T = "$E[97m" }
            cost    = @{ B = "$E[43m";  S = "$E[33m"; T = "$E[30m" }
            time    = @{ B = "$E[46m";  S = "$E[36m"; T = "$E[30m" }
            misc    = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            accent2 = @{ B = "$E[44m";  S = "$E[34m"; T = "$E[97m" }
            sky     = @{ B = "$E[106m"; S = "$E[96m"; T = "$E[30m" }
        }
    }
    mocha = New-CatTheme @{
        base='30;30;46'; text='205;214;244'; overlay='127;132;156'; mauve='203;166;247'
        green='166;227;161'; yellow='249;226;175'; red='243;139;168'; peach='250;179;135'
        teal='148;226;213'; blue='137;180;250'; sky='137;220;235'; surf0='49;50;68'; surf1='69;71;90'
    }
    latte = New-CatTheme @{
        base='239;241;245'; text='76;79;105'; overlay='124;127;147'; mauve='136;57;239'
        green='64;160;43'; yellow='223;142;29'; red='210;15;57'; peach='254;100;11'
        teal='23;146;153'; blue='30;102;245'; sky='4;165;229'; surf0='204;208;218'; surf1='188;192;204'
    }
    frappe = New-CatTheme @{
        base='48;52;70'; text='198;208;245'; overlay='131;139;167'; mauve='202;158;230'
        green='166;209;137'; yellow='229;200;144'; red='231;130;132'; peach='239;159;118'
        teal='129;200;190'; blue='140;170;238'; sky='153;209;219'; surf0='65;69;89'; surf1='81;87;109'
    }
    macchiato = New-CatTheme @{
        base='36;39;58'; text='202;211;245'; overlay='128;135;162'; mauve='198;160;246'
        green='166;218;149'; yellow='238;212;159'; red='237;135;150'; peach='245;169;127'
        teal='139;213;202'; blue='138;173;244'; sky='145;215;227'; surf0='54;58;79'; surf1='73;77;100'
    }
    mono = @{
        Accent = ''; Good = ''; Warn = ''; Bad = ''; Money = ''; Time = ''
        Dim = "$E[2m"; R = $RESET
        Pl = @{
            model   = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            dir     = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            branch  = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            good    = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            warn    = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            bad     = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            cost    = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            time    = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            misc    = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            accent2 = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
            sky     = @{ B = "$E[100m"; S = "$E[90m"; T = "$E[97m" }
        }
    }
}

$LAYOUTS = @('lines', 'inline', 'frame', 'powerline', 'powerline-round')
$THEME_ORDER = @('ansi', 'mocha', 'latte', 'frappe', 'macchiato', 'mono')

# ============================== PRESETS ==============================
# A preset bundles fields + layout + theme (+ glyphs/adaptive). The wizard lets you
# pick a preset and then override layout and theme independently.
$PRESET_ORDER = @('minimal','compact','classic','dashboard','powerline','rounded','limits','dev','sparkline','adaptive','ascii')
$PRESETS = @{
    minimal   = @{ Layout='inline'; Theme='ansi'; Glyphs='auto'; Adaptive=$false
                   Fields=@(,@('model','ctx-mini','cost','time'))
                   Desc='one line, just the essentials' }
    compact   = @{ Layout='lines'; Theme='ansi'; Glyphs='auto'; Adaptive=$false
                   Fields=@(@('model','dir','branch'),@('ctx','cost','time'))
                   Desc='two lines, no cache line' }
    classic   = @{ Layout='lines'; Theme='ansi'; Glyphs='auto'; Adaptive=$false
                   Fields=@(@('model','dir','branch'),@('ctx','cost','time'),@('cache'))
                   Desc='the original 3-line layout (default)' }
    dashboard = @{ Layout='frame'; Theme='ansi'; Glyphs='auto'; Adaptive=$false
                   Fields=@(@('model','dir','branch','session','version','style'),@('ctx','cost'),@('cache','lines'),@('limits','pr','effort'),@('time','api','activity'))
                   Desc='everything the payload offers, framed' }
    powerline = @{ Layout='powerline'; Theme='mocha'; Glyphs='auto'; Adaptive=$false
                   Fields=@(@('model','dir','branch'),@('ctx-mini','cost','time'))
                   Desc='colored segments, Catppuccin Mocha (Nerd Font)' }
    rounded   = @{ Layout='powerline-round'; Theme='mocha'; Glyphs='auto'; Adaptive=$false
                   Fields=@(@('model','dir','branch'),@('ctx-mini','cost','time'))
                   Desc='powerline with rounded pills (Nerd Font)' }
    limits    = @{ Layout='lines'; Theme='ansi'; Glyphs='auto'; Adaptive=$false
                   Fields=@(@('model','dir','branch'),@('ctx','cost'),@('limits'))
                   Desc='context + rate-limit quotas (Pro/Max plans)' }
    dev       = @{ Layout='lines'; Theme='ansi'; Glyphs='auto'; Adaptive=$false
                   Fields=@(@('repo','branch','pr'),@('ctx','cost','lines'),@('time','activity'))
                   Desc='git/PR focused: repo, PR review state, lines changed' }
    sparkline = @{ Layout='inline'; Theme='ansi'; Glyphs='auto'; Adaptive=$false
                   Fields=@(,@('model','gauges','cost','time'))
                   Desc='one line with tiny gauges for ctx/cache/limits' }
    adaptive  = @{ Layout='lines'; Theme='ansi'; Glyphs='auto'; Adaptive=$true
                   Fields=@(@('model','dir','branch'),@('ctx-mini','cost','time'))
                   Desc='minimal, but expands when something needs attention' }
    ascii     = @{ Layout='lines'; Theme='ansi'; Glyphs='ascii'; Adaptive=$false
                   Fields=@(@('model','dir','branch'),@('ctx','cost','time'),@('cache'))
                   Desc='pure ASCII glyphs, works on any console/font' }
}

$FIELD_HELP = @(
    'model      [Opus 4.8]                    repo     owner/name from origin remote'
    'dir        current folder                branch   git branch (+worktree)'
    'ctx        10-block context bar + %      ctx-mini 5-segment mini bar + %'
    'gauges     1-char gauges ctx/cache/5h    cost     $USD + R$BRL'
    'time       session duration              api      time waiting for the API'
    'cache      cache read + hit %            lines    +added/-removed'
    'limits     5h/7d rate-limit quotas       pr       open PR # + review state'
    'effort     reasoning effort + thinking   session  session name (--name//rename)'
    'version    Claude Code version           style    output style (if not default)'
    'activity   live turn timer + running subagents (needs hooks, see installer)'
)

# ============================== DATA ==============================
function Fmt-Dur($secs) {
    $secs = [int]$secs
    if ($secs -ge 3600) { return "$([math]::Floor($secs / 3600))h $([math]::Floor(($secs % 3600) / 60))m" }
    if ($secs -ge 60)   { return "$([math]::Floor($secs / 60))m $($secs % 60)s" }
    return "${secs}s"
}

# Time remaining until an epoch timestamp, compact ("2h10", "1d4h", "35m")
function Fmt-Until($epoch) {
    try { $rem = [long]$epoch - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() } catch { return '' }
    if ($rem -le 0) { return '' }
    $h = [math]::Floor($rem / 3600); $m = [math]::Floor(($rem % 3600) / 60)
    if ($h -ge 24) { return "$([math]::Floor($h / 24))d$($h % 24)h" }
    if ($h -gt 0)  { return "${h}h$('{0:00}' -f $m)" }
    return "${m}m"
}

# Extract and compute everything the renderers need from the payload
function Get-StatusData($data) {
    $s = @{}

    $s.Model = Def $data.model.display_name 'claude'
    $dir     = Def $data.workspace.current_dir ''
    $s.Pct   = [int][math]::Floor([double](Def $data.context_window.used_percentage 0))
    $s.Cost  = [double](Def $data.cost.total_cost_usd 0)

    # Context window size (200K, or 1M for extended)
    $ctxSize = [double](Def $data.context_window.context_window_size 200000)
    $s.CtxK  = [int][math]::Floor($ctxSize / 1000)

    # Cache - how much we're saving
    $cacheRead   = [double](Def $data.context_window.current_usage.cache_read_input_tokens 0)
    $cacheCreate = [double](Def $data.context_window.current_usage.cache_creation_input_tokens 0)
    $inputTok    = [double](Def $data.context_window.current_usage.input_tokens 0)
    $totalInput  = $inputTok + $cacheRead + $cacheCreate
    $s.TotalInput = $totalInput
    if ($totalInput -gt 0) {
        $s.CachePct = [int][math]::Floor($cacheRead * 100 / $totalInput)
    } else {
        $s.CachePct = 0
    }
    if ($cacheRead -ge 1000) {
        $s.CacheFmt = "$([int][math]::Floor($cacheRead / 1000))K"
    } else {
        $s.CacheFmt = "$([int]$cacheRead)"
    }

    # Exceeds 200K tokens - overspend warning
    $s.Exceeds = [bool](Def $data.exceeds_200k_tokens $false)

    # Durations
    $durMs  = [double](Def $data.cost.total_duration_ms 0)
    $s.Mins = [int][math]::Floor($durMs / 60000)
    $s.Secs = [int][math]::Floor(($durMs % 60000) / 1000)
    $apiMs     = [double](Def $data.cost.total_api_duration_ms 0)
    $s.ApiMins = [int][math]::Floor($apiMs / 60000)
    $s.ApiSecs = [int][math]::Floor(($apiMs % 60000) / 1000)

    # Lines changed this session
    $s.LinesAdded   = [int](Def $data.cost.total_lines_added 0)
    $s.LinesRemoved = [int](Def $data.cost.total_lines_removed 0)

    # Claude Code version + output style + session name
    $s.Version     = Def $data.version ''
    $s.OutStyle    = Def $data.output_style.name ''
    $s.SessionName = Def $data.session_name ''

    # Repo (owner/name from origin remote) + worktree
    $s.Repo = ''
    if ($data.workspace.repo -and $data.workspace.repo.name) {
        $owner = Def $data.workspace.repo.owner ''
        if ($owner) { $s.Repo = "$owner/$($data.workspace.repo.name)" } else { $s.Repo = $data.workspace.repo.name }
    }
    $s.Worktree = Def $data.workspace.git_worktree ''

    # Rate limits (Pro/Max subscriptions only)
    $s.RL5 = $null; $s.RL7 = $null; $s.RL5Reset = ''; $s.RL7Reset = ''
    if ($data.rate_limits) {
        $fh = $data.rate_limits.five_hour
        if ($fh -and $null -ne $fh.used_percentage) {
            $s.RL5 = [int]$fh.used_percentage
            if ($fh.resets_at) { $s.RL5Reset = Fmt-Until $fh.resets_at }
        }
        $sd = $data.rate_limits.seven_day
        if ($sd -and $null -ne $sd.used_percentage) {
            $s.RL7 = [int]$sd.used_percentage
            if ($sd.resets_at) { $s.RL7Reset = Fmt-Until $sd.resets_at }
        }
    }

    # Open PR for current branch
    $s.PrNum = $null; $s.PrState = ''
    if ($data.pr -and $data.pr.number) {
        $s.PrNum = [int]$data.pr.number
        $s.PrState = Def $data.pr.review_state ''
    }

    # Reasoning effort + extended thinking
    $s.Effort = ''
    if ($data.effort) { $s.Effort = Def $data.effort.level '' }
    $s.Thinking = $false
    if ($data.thinking) { $s.Thinking = [bool](Def $data.thinking.enabled $false) }

    # Activity state written by statusline-hooks.ps1 (turn timer + running subagents)
    $s.TurnElapsed = $null; $s.TurnDone = $null; $s.Agents = @()
    $sid = Def $data.session_id ''
    if ($sid) {
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $turnFile = Join-Path $StateDir "turn-$sid.json"
        if (Test-Path $turnFile) {
            try {
                $t = Get-Content $turnFile -Raw | ConvertFrom-Json
                if ($t.start) {
                    if ($t.end) { $s.TurnDone = [int]($t.end - $t.start) }
                    elseif (($now - $t.start) -lt 21600) { $s.TurnElapsed = [int]($now - $t.start) }
                }
            } catch {}
        }
        $agFile = Join-Path $StateDir "agents-$sid.json"
        if (Test-Path $agFile) {
            try {
                $list = @((Get-Content $agFile -Raw | ConvertFrom-Json).agents)
                $s.Agents = @($list | Where-Object { $_.ts -and ($now - $_.ts) -lt 7200 } | ForEach-Object { Def $_.type 'agent' })
            } catch {}
        }
    }

    # ---- USD->BRL rate, cached 24h ----
    # Uses AwesomeAPI (free, no auth). Cache in %TEMP% to fetch once per day.
    $brlCache    = Join-Path $env:TEMP 'statusline-usd-brl'
    $brlMaxAge   = 86400      # 24h - fetch rate once per day
    $brlFallback = 5.70       # offline fallback

    $stale = $true
    if (Test-Path $brlCache) {
        $age = ((Get-Date) - (Get-Item $brlCache).LastWriteTime).TotalSeconds
        if ($age -le $brlMaxAge) { $stale = $false }
    }
    if ($stale) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $resp = Invoke-RestMethod -Uri 'https://economia.awesomeapi.com.br/json/last/USD-BRL' -TimeoutSec 2
            $rate = $resp.USDBRL.bid
            if ($rate) { Set-Content -Path $brlCache -Value $rate -Encoding Ascii -NoNewline }
        } catch {
            if (-not (Test-Path $brlCache)) {
                Set-Content -Path $brlCache -Value $brlFallback -Encoding Ascii -NoNewline
            }
        }
    }
    if (Test-Path $brlCache) {
        try { $usdBrl = [double]((Get-Content $brlCache -Raw).Trim()) } catch { $usdBrl = $brlFallback }
    } else {
        $usdBrl = $brlFallback
    }

    $s.CostUsd = '$' + $s.Cost.ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
    $s.CostBrl = ([math]::Round($s.Cost * $usdBrl, 2)).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')

    # Git branch
    $s.Branch = ''
    if ($dir -and (Test-Path $dir)) {
        try {
            $b = & git -C "$dir" branch --show-current 2>$null
            if ($LASTEXITCODE -eq 0 -and $b) { $s.Branch = $b }
        } catch {}
    }

    # Directory leaf name
    if ($dir) { $s.DirName = Split-Path $dir -Leaf } else { $s.DirName = '' }

    return $s
}

# ============================== FIELD RENDERERS ==============================
# Each field returns @{ X = rich ANSI text; P = plain text (powerline); Role = bg role }
# or $null when there is nothing to show (absent data auto-hides the field).
function Get-PctRole($pct) {
    if ($pct -ge 90) { return 'bad' }
    if ($pct -ge 70) { return 'warn' }
    return 'good'
}
function Get-RoleColor($role, $T) {
    switch ($role) {
        'good' { return $T.Good }
        'warn' { return $T.Warn }
        'bad'  { return $T.Bad }
        default { return '' }
    }
}

function Render-Field($id, $s, $T, $G) {
    switch ($id) {
        'model' {
            return @{ X = "$($T.Accent)[$($s.Model)]$($T.R)"; P = $s.Model; Role = 'model' }
        }
        'dir' {
            if (-not $s.DirName) { return $null }
            # NB: locals here must not be named $t - PowerShell vars are case-insensitive
            # and $t would clobber the $T theme parameter
            $body = GT $G.Dir $s.DirName
            return @{ X = $body; P = $body; Role = 'dir' }
        }
        'branch' {
            if (-not $s.Branch) { return $null }
            $b = $s.Branch
            if ($s.Worktree -and $s.Worktree -ne $s.Branch) { $b = "$b ($($s.Worktree))" }
            $body = GT $G.Git $b
            return @{ X = $body; P = $body; Role = 'branch' }
        }
        'repo' {
            $r = $s.Repo
            if (-not $r) { $r = $s.DirName }
            if (-not $r) { return $null }
            return @{ X = "$($T.Accent)$r$($T.R)"; P = $r; Role = 'dir' }
        }
        'session' {
            if (-not $s.SessionName) { return $null }
            return @{ X = "$($T.Dim)($($s.SessionName))$($T.R)"; P = "($($s.SessionName))"; Role = 'misc' }
        }
        'ctx' {
            $filled = [int][math]::Floor($s.Pct / 10)
            if ($filled -gt 10) { $filled = 10 }; if ($filled -lt 0) { $filled = 0 }
            $bar = ($G.Full * $filled) + ($G.Light * (10 - $filled))
            $role = Get-PctRole $s.Pct
            $col  = Get-RoleColor $role $T
            $wX = ''; $wP = ''
            if ($s.Exceeds) { $wX = " $($T.Bad)$($G.Warn) >200K$($T.R)"; $wP = " $($G.Warn)>200K" }
            return @{ X = "$col$bar$($T.R) $($s.Pct)% of $($s.CtxK)K$wX"; P = "$bar $($s.Pct)%$wP"; Role = $role }
        }
        'ctx-mini' {
            $filled = [int][math]::Floor($s.Pct / 20)
            if ($filled -gt 5) { $filled = 5 }; if ($filled -lt 0) { $filled = 0 }
            $bar = ($G.MOn * $filled) + ($G.MOff * (5 - $filled))
            $role = Get-PctRole $s.Pct
            $col  = Get-RoleColor $role $T
            $wX = ''; $wP = ''
            if ($s.Exceeds) { $wX = " $($T.Bad)$($G.Warn) >200K$($T.R)"; $wP = " $($G.Warn)>200K" }
            return @{ X = "$col$bar$($T.R) $($s.Pct)%$wX"; P = "$bar $($s.Pct)%$wP"; Role = $role }
        }
        'gauges' {
            $partsX = @(); $partsP = @()
            $gi = [int][math]::Floor($s.Pct / 12.5); if ($gi -gt 7) { $gi = 7 }; if ($gi -lt 0) { $gi = 0 }
            $col = Get-RoleColor (Get-PctRole $s.Pct) $T
            $partsX += "$col$($G.Gauge[$gi])ctx$($T.R)"; $partsP += "$($G.Gauge[$gi])ctx"
            $ci = [int][math]::Floor($s.CachePct / 12.5); if ($ci -gt 7) { $ci = 7 }; if ($ci -lt 0) { $ci = 0 }
            if ($s.CachePct -ge 70) { $ccol = $T.Good } elseif ($s.CachePct -ge 30) { $ccol = $T.Warn } else { $ccol = $T.Bad }
            $partsX += "$ccol$($G.Gauge[$ci])cache$($T.R)"; $partsP += "$($G.Gauge[$ci])cache"
            if ($null -ne $s.RL5) {
                $ri = [int][math]::Floor($s.RL5 / 12.5); if ($ri -gt 7) { $ri = 7 }; if ($ri -lt 0) { $ri = 0 }
                $rcol = Get-RoleColor (Get-PctRole $s.RL5) $T
                $partsX += "$rcol$($G.Gauge[$ri])5h$($T.R)"; $partsP += "$($G.Gauge[$ri])5h"
            }
            return @{ X = ($partsX -join ' '); P = ($partsP -join ' '); Role = (Get-PctRole $s.Pct) }
        }
        'cost' {
            return @{ X = "$($T.Money)$($s.CostUsd)$($T.R) $($T.Dim)(R`$$($s.CostBrl))$($T.R)"
                      P = "$($s.CostUsd) (R`$$($s.CostBrl))"; Role = 'cost' }
        }
        'time' {
            $body = GT $G.Clock "$($s.Mins)m $($s.Secs)s"
            return @{ X = "$($T.Time)$body$($T.R)"; P = $body; Role = 'time' }
        }
        'api' {
            return @{ X = "$($T.Dim)$($s.ApiMins)m $($s.ApiSecs)s API$($T.R)"; P = "$($s.ApiMins)m $($s.ApiSecs)s API"; Role = 'time' }
        }
        'cache' {
            if ($s.CachePct -ge 70) { $col = $T.Good; $role = 'good' }
            elseif ($s.CachePct -ge 30) { $col = $T.Warn; $role = 'warn' }
            else { $col = $T.Bad; $role = 'bad' }
            return @{ X = "$($T.Dim)cache:$($T.R) $col$($s.CacheFmt) read ($($s.CachePct)% hit)$($T.R)"
                      P = "cache $($s.CacheFmt) ($($s.CachePct)%)"; Role = $role }
        }
        'lines' {
            if ($s.LinesAdded -eq 0 -and $s.LinesRemoved -eq 0) { return $null }
            return @{ X = "$($T.Good)+$($s.LinesAdded)$($T.R)/$($T.Bad)-$($s.LinesRemoved)$($T.R)"
                      P = "+$($s.LinesAdded)/-$($s.LinesRemoved)"; Role = 'misc' }
        }
        'limits' {
            if ($null -eq $s.RL5 -and $null -eq $s.RL7) { return $null }
            $px = @(); $pp = @(); $worst = 'good'
            if ($null -ne $s.RL5) {
                $r = Get-PctRole $s.RL5; $col = Get-RoleColor $r $T
                $reset = ''; if ($s.RL5Reset) { $reset = " $($G.Cycle)$($s.RL5Reset)" }
                $px += "${col}5h $($s.RL5)%$($T.R)$($T.Dim)$reset$($T.R)"; $pp += "5h $($s.RL5)%$reset"
                if ($r -ne 'good') { $worst = $r }
            }
            if ($null -ne $s.RL7) {
                $r = Get-PctRole $s.RL7; $col = Get-RoleColor $r $T
                $px += "${col}7d $($s.RL7)%$($T.R)"; $pp += "7d $($s.RL7)%"
                if ($r -eq 'bad' -or ($r -eq 'warn' -and $worst -eq 'good')) { $worst = $r }
            }
            return @{ X = ($px -join " $($T.Dim)$($G.Dot)$($T.R) "); P = ($pp -join ' '); Role = $worst }
        }
        'pr' {
            if ($null -eq $s.PrNum) { return $null }
            switch ($s.PrState) {
                'approved'          { $badge = $G.Check; $col = $T.Good; $role = 'good' }
                'changes_requested' { $badge = $G.Cross; $col = $T.Bad;  $role = 'bad' }
                'draft'             { $badge = 'draft';  $col = $T.Dim;  $role = 'misc' }
                default             { $badge = $G.Pend;  $col = $T.Warn; $role = 'warn' }
            }
            return @{ X = "${col}PR #$($s.PrNum) $badge$($T.R)"; P = "PR #$($s.PrNum) $badge"; Role = $role }
        }
        'effort' {
            if (-not $s.Effort -and -not $s.Thinking) { return $null }
            $txt = $s.Effort
            if ($s.Thinking) { if ($txt) { $txt = "$txt+think" } else { $txt = 'think' } }
            $body = GT $G.Brain $txt
            return @{ X = "$($T.Accent)$body$($T.R)"; P = $body; Role = 'accent2' }
        }
        'version' {
            if (-not $s.Version) { return $null }
            return @{ X = "$($T.Dim)v$($s.Version)$($T.R)"; P = "v$($s.Version)"; Role = 'misc' }
        }
        'style' {
            if (-not $s.OutStyle -or $s.OutStyle -eq 'default') { return $null }
            return @{ X = "$($T.Dim)$($s.OutStyle)$($T.R)"; P = $s.OutStyle; Role = 'misc' }
        }
        'activity' {
            if ($null -ne $s.TurnElapsed) {
                $body = GT $G.Bolt (Fmt-Dur $s.TurnElapsed)
                if ($s.Agents.Count -gt 0) {
                    $types = (@($s.Agents | Select-Object -Unique) -join ',')
                    $body = "$body $($G.Dot) $(GT $G.Agents "$($s.Agents.Count) ($types)")"
                }
                return @{ X = "$($T.Warn)$body$($T.R)"; P = $body; Role = 'sky' }
            }
            if ($s.Agents.Count -gt 0) {
                $types = (@($s.Agents | Select-Object -Unique) -join ',')
                $body = GT $G.Agents "$($s.Agents.Count) ($types)"
                return @{ X = "$($T.Warn)$body$($T.R)"; P = $body; Role = 'sky' }
            }
            if ($null -ne $s.TurnDone) {
                $body = GT $G.Check (Fmt-Dur $s.TurnDone)
                return @{ X = "$($T.Dim)$body$($T.R)"; P = $body; Role = 'misc' }
            }
            return $null
        }
        default { return $null }
    }
}

# ============================== LAYOUT ENGINES ==============================
function Render-TextLines($fieldLines, $s, $T, $G, $mode) {
    $rendered = @()
    foreach ($lf in $fieldLines) {
        $segs = @()
        foreach ($id in @($lf)) {
            $f = Render-Field "$id" $s $T $G
            if ($f) { $segs += $f.X }
        }
        if ($segs.Count -gt 0) { $rendered += ,$segs }
    }
    if ($rendered.Count -eq 0) { return }
    if ($mode -eq 'inline') {
        $all = @()
        foreach ($r in $rendered) { $all += $r }
        Write-Output ($all -join " $($T.Dim)$($G.Dot)$($T.R) ")
        return
    }
    for ($i = 0; $i -lt $rendered.Count; $i++) {
        $line = $rendered[$i] -join " $($T.Dim)|$($T.R) "
        if ($mode -eq 'frame') {
            if ($rendered.Count -eq 1) { $p = $G.FrH }
            elseif ($i -eq 0) { $p = $G.Fr1 }
            elseif ($i -eq $rendered.Count - 1) { $p = $G.FrE }
            else { $p = $G.FrM }
            $line = "$($T.Dim)$p$($G.FrH)$($T.R) $line"
        }
        Write-Output $line
    }
}

function Render-PowerLines($fieldLines, $s, $T, $G, $round) {
    if ($round) { $SEP = [string][char]0xE0B4 } else { $SEP = [string][char]0xE0B0 }
    foreach ($lf in $fieldLines) {
        $segs = @()
        foreach ($id in @($lf)) {
            $f = Render-Field "$id" $s $T $G
            if ($f) { $segs += ,$f }
        }
        if ($segs.Count -eq 0) { continue }
        $out = ''
        $prev = $null
        foreach ($f in $segs) {
            $c = $T.Pl[$f.Role]
            if ($null -eq $c) { $c = $T.Pl['misc'] }
            if ($null -eq $prev) { $out += $c.B } else { $out += "$($c.B)$($prev.S)$SEP" }
            $out += "$($c.T) $($f.P) "
            $prev = $c
        }
        $out += "$RESET$($prev.S)$SEP$RESET"
        Write-Output $out
    }
}

# Adaptive: minimal base that grows lines when thresholds are crossed
function Get-AdaptiveFields($s) {
    $lines = @()
    $lines += ,@('model', 'dir', 'branch')
    if ($s.Pct -ge 70) { $lines += ,@('ctx', 'cost', 'time') }
    else { $lines += ,@('ctx-mini', 'cost', 'time') }
    $rlMax = 0
    if ($null -ne $s.RL5 -and $s.RL5 -gt $rlMax) { $rlMax = $s.RL5 }
    if ($null -ne $s.RL7 -and $s.RL7 -gt $rlMax) { $rlMax = $s.RL7 }
    if ($rlMax -ge 70) { $lines += ,@('limits') }
    if ($s.TotalInput -gt 50000 -and $s.CachePct -lt 30) { $lines += ,@('cache') }
    if ($null -ne $s.TurnElapsed -or $s.Agents.Count -gt 0) { $lines += ,@('activity') }
    return ,$lines
}

function Render-Config($cfg, $s) {
    $T = $THEMES[$cfg.Theme]
    if ($null -eq $T) { $T = $THEMES['ansi'] }
    $gname = $cfg.Glyphs
    if (-not $gname -or $gname -eq 'auto') {
        if ($cfg.Layout -like 'powerline*') { $gname = 'nerd' } else { $gname = 'emoji' }
    }
    $G = Get-Glyphs $gname
    $fields = $cfg.Fields
    if ($cfg.Adaptive) { $fields = Get-AdaptiveFields $s }
    switch ($cfg.Layout) {
        'inline'          { Render-TextLines $fields $s $T $G 'inline' }
        'frame'           { Render-TextLines $fields $s $T $G 'frame' }
        'powerline'       { Render-PowerLines $fields $s $T $G $false }
        'powerline-round' { Render-PowerLines $fields $s $T $G $true }
        default           { Render-TextLines $fields $s $T $G 'lines' }
    }
}

# ============================== CONFIG RESOLUTION ==============================
function Resolve-Preset($name) {
    $p = $PRESETS[$name]
    return @{ Preset = $name; Layout = $p.Layout; Theme = $p.Theme; Glyphs = $p.Glyphs
              Adaptive = $p.Adaptive; Fields = $p.Fields }
}

# JSON fields can be ["a","b"] (one line) or [["a","b"],["c"]] (multiple lines)
function Normalize-Fields($raw) {
    $items = @($raw)
    if ($items.Count -eq 0) { return $null }
    $allStrings = $true
    foreach ($el in $items) { if ($el -isnot [string]) { $allStrings = $false } }
    if ($allStrings) { return ,@(,@($items | ForEach-Object { "$_" })) }
    $lines = @()
    foreach ($el in $items) { $lines += ,@(@($el) | ForEach-Object { "$_" }) }
    return ,$lines
}

function Get-ActiveConfig($styleOverride) {
    if ($styleOverride -and $PRESETS.ContainsKey($styleOverride)) { return Resolve-Preset $styleOverride }
    if (Test-Path $ConfigFile) {
        try {
            $j = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            $base = 'classic'
            if ($j.preset -and $PRESETS.ContainsKey([string]$j.preset)) { $base = [string]$j.preset }
            $cfg = Resolve-Preset $base
            if ($j.layout -and $LAYOUTS -contains [string]$j.layout) { $cfg.Layout = [string]$j.layout }
            if ($j.theme -and $THEMES.ContainsKey([string]$j.theme)) { $cfg.Theme = [string]$j.theme }
            if ($j.glyphs) { $cfg.Glyphs = [string]$j.glyphs }
            if ($null -ne $j.adaptive) { $cfg.Adaptive = [bool]$j.adaptive }
            if ($j.fields) {
                $f = Normalize-Fields $j.fields
                if ($f) { $cfg.Fields = $f; $cfg.Adaptive = [bool](Def $j.adaptive $false) }
            }
            return $cfg
        } catch {}
    }
    if (Test-Path $StyleFileLegacy) {
        $n = (Get-Content $StyleFileLegacy -Raw).Trim()
        if ($PRESETS.ContainsKey($n)) { return Resolve-Preset $n }
    }
    return Resolve-Preset 'classic'
}

# ============================== CHOOSER WIZARD (-Choose) ==============================
if ($Choose) {
    # Enable ANSI/VT in plain conhost (Windows Terminal/WezTerm already have it).
    # Only compiled here - never in the statusline hot path.
    try {
        $vt = Add-Type -Namespace Win32 -Name VT -PassThru -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
        $h = $vt::GetStdHandle(-11)
        $m = [uint32]0
        if ($vt::GetConsoleMode($h, [ref]$m)) { [void]$vt::SetConsoleMode($h, $m -bor 4) }
    } catch {}

    # Sample payload with realistic numbers for the previews
    $sampleJson = @'
{
  "model": { "id": "claude-opus-4-8", "display_name": "Opus 4.8" },
  "workspace": { "current_dir": "D:\\dev\\my-project", "project_dir": "D:\\dev\\my-project" },
  "version": "3.0.12",
  "output_style": { "name": "default" },
  "cost": {
    "total_cost_usd": 0.4275,
    "total_duration_ms": 754000,
    "total_api_duration_ms": 482000,
    "total_lines_added": 184,
    "total_lines_removed": 37
  },
  "context_window": {
    "context_window_size": 200000,
    "used_percentage": 47.3,
    "current_usage": {
      "input_tokens": 12480,
      "cache_read_input_tokens": 68200,
      "cache_creation_input_tokens": 8400
    }
  },
  "exceeds_200k_tokens": false
}
'@
    $s = Get-StatusData ($sampleJson | ConvertFrom-Json)
    # Sample dir doesn't exist, so fake the data the payload would carry in a real session
    $s.Branch = 'main'; $s.Repo = 'you/my-project'
    $s.RL5 = 34; $s.RL5Reset = '2h10'; $s.RL7 = 61; $s.RL7Reset = '4d2h'
    $s.PrNum = 42; $s.PrState = 'approved'
    $s.Effort = 'high'; $s.Thinking = $true
    $s.TurnElapsed = 83; $s.Agents = @('Explore', 'Plan')

    function Show-Preview($cfg, $s) {
        Render-Config $cfg $s | ForEach-Object { Write-Host "   $_" }
    }

    # Current saved config (defaults for every step)
    $cur = Get-ActiveConfig $null

    Write-Host ''
    Write-Host 'Claude Code Statusline - Setup wizard'
    Write-Host '====================================='
    Write-Host ''
    Write-Host "Step 1/3 - FIELDS: pick a template (defines what information appears)"
    for ($i = 0; $i -lt $PRESET_ORDER.Count; $i++) {
        $name = $PRESET_ORDER[$i]
        $mark = ''
        if ($name -eq $cur.Preset) { $mark = '  (current)' }
        Write-Host ''
        Write-Host "$('{0,2}' -f ($i + 1))) $name - $($PRESETS[$name].Desc)$mark"
        Show-Preview (Resolve-Preset $name) $s
    }
    Write-Host ''
    $answer = Read-Host "Template [1-$($PRESET_ORDER.Count)] (Enter = keep '$($cur.Preset)')"
    if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $PRESET_ORDER.Count) {
        $cfg = Resolve-Preset $PRESET_ORDER[[int]$answer - 1]
    } else {
        $cfg = $cur
    }

    Write-Host ''
    Write-Host "Step 2/3 - LAYOUT: how the same fields are arranged"
    for ($i = 0; $i -lt $LAYOUTS.Count; $i++) {
        $mark = ''
        if ($LAYOUTS[$i] -eq $cfg.Layout) { $mark = '  (current)' }
        Write-Host ''
        Write-Host "$($i + 1)) $($LAYOUTS[$i])$mark"
        $try = @{ Preset=$cfg.Preset; Layout=$LAYOUTS[$i]; Theme=$cfg.Theme; Glyphs=$cfg.Glyphs; Adaptive=$cfg.Adaptive; Fields=$cfg.Fields }
        Show-Preview $try $s
    }
    Write-Host ''
    $answer = Read-Host "Layout [1-$($LAYOUTS.Count)] (Enter = keep '$($cfg.Layout)')"
    if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $LAYOUTS.Count) {
        $cfg.Layout = $LAYOUTS[[int]$answer - 1]
    }

    Write-Host ''
    Write-Host "Step 3/3 - THEME: colors"
    for ($i = 0; $i -lt $THEME_ORDER.Count; $i++) {
        $mark = ''
        if ($THEME_ORDER[$i] -eq $cfg.Theme) { $mark = '  (current)' }
        Write-Host ''
        Write-Host "$($i + 1)) $($THEME_ORDER[$i])$mark"
        $try = @{ Preset=$cfg.Preset; Layout=$cfg.Layout; Theme=$THEME_ORDER[$i]; Glyphs=$cfg.Glyphs; Adaptive=$cfg.Adaptive; Fields=$cfg.Fields }
        Show-Preview $try $s
    }
    Write-Host ''
    $answer = Read-Host "Theme [1-$($THEME_ORDER.Count)] (Enter = keep '$($cfg.Theme)')"
    if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $THEME_ORDER.Count) {
        $cfg.Theme = $THEME_ORDER[[int]$answer - 1]
    }

    $out = [ordered]@{
        preset   = $cfg.Preset
        layout   = $cfg.Layout
        theme    = $cfg.Theme
        glyphs   = $cfg.Glyphs
        adaptive = [bool]$cfg.Adaptive
        fields   = $cfg.Fields
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $ConfigFile) | Out-Null
    [System.IO.File]::WriteAllText($ConfigFile, ($out | ConvertTo-Json -Depth 5))
    if (Test-Path $StyleFileLegacy) { Remove-Item $StyleFileLegacy -Force }

    Write-Host ''
    Write-Host "Saved: preset '$($cfg.Preset)', layout '$($cfg.Layout)', theme '$($cfg.Theme)'"
    Write-Host "Config file: $ConfigFile (edit 'fields' there to fine-tune what appears)"
    Write-Host ''
    Write-Host 'Available fields:'
    $FIELD_HELP | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
    Write-Host 'Restart Claude Code (or wait for the next update) to see it.'
    exit 0
}

# ============================== NORMAL MODE ==============================
$raw = [Console]::In.ReadToEnd()
if (-not $raw -or -not $raw.Trim()) { exit 0 }
try { $data = ConvertFrom-Json -InputObject $raw -ErrorAction Stop } catch { exit 0 }
if ($null -eq $data) { exit 0 }

Render-Config (Get-ActiveConfig $Style) (Get-StatusData $data)
