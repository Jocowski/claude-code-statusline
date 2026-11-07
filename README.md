# Claude Code Statusline

A custom statusline script for [Claude Code](https://claude.ai/code) that shows real-time session information directly in your terminal — context window usage, session cost in USD and BRL, prompt cache efficiency, model name, and git branch.

## Preview

```
[claude-sonnet-4-6] 📁 my-project | 🌿 main
████████░░ 78% of 200K | $0.42 (R$2,39) | ⏱️ 8m 15s
cache: 62K read (81% hit)
```

Three lines of information at a glance:
1. **Model** + working directory + git branch
2. **Context window** progress bar + percentage + window size + cost (USD and BRL) + session duration
3. **Prompt cache** hit rate and tokens read from cache

## Customization (Windows / PowerShell version)

The Windows script (`statusline.ps1`) separates customization into **3 independent axes**,
so you can mix the information of one template with the look of another:

1. **Fields** — *what* appears: `model`, `dir`, `branch`, `repo`, `ctx`, `ctx-mini`,
   `gauges`, `cost`, `time`, `api`, `cache`, `lines`, `limits`, `pr`, `effort`,
   `session`, `version`, `style`, `activity`
2. **Layout** — *how* it is arranged: `lines`, `inline` (single line), `frame` (boxed),
   `powerline`, `powerline-round` (the last two need a [Nerd Font](https://www.nerdfonts.com/))
3. **Theme** — *colors*: `ansi`, Catppuccin `mocha` / `latte` / `frappe` / `macchiato`, `mono`

The installer runs a 3-step wizard that previews every option with sample data.
To change anything later (no reinstall needed):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.claude\statusline.ps1 -Choose
```

### Templates

Templates bundle the three axes as a starting point:

| Template | What it shows |
|---|---|
| `minimal` | 1 line: model, mini context bar, cost, time |
| `compact` | 2 lines: model + folder + branch / bar + cost (USD/BRL) + time |
| `classic` | the original 3-line layout (default) |
| `dashboard` | everything: context, cost, cache, lines ±, rate limits, PR, effort, API time, version |
| `powerline` | colored background segments, Catppuccin Mocha |
| `rounded` | powerline with rounded pill separators |
| `limits` | context + 5h/7d rate-limit quotas with reset countdown (Pro/Max plans) |
| `dev` | git/PR focused: repo owner/name, PR review state, lines changed |
| `sparkline` | 1 line with tiny 1-char gauges for context/cache/limits |
| `adaptive` | minimal by default, auto-expands lines when context ≥70%, limits ≥70%, cache hit <30% or agents are running |
| `ascii` | pure ASCII glyphs — works on any console or font |

Everything is stored in `%USERPROFILE%\.claude\statusline-config.json`. Edit the
`fields` array there (lines of field ids) to fine-tune exactly what appears, e.g.:

```json
{
  "layout": "powerline",
  "theme": "mocha",
  "fields": [["model", "dir", "branch"], ["ctx", "cost", "limits", "activity"]]
}
```

### Live activity tracking (optional)

The `activity` field shows a live **"how long has Claude been working on my request"**
timer (⚡ 1m 23s) and the **number/type of subagents running** (🤖 2 (Explore, Plan)),
turning into ✔ + total duration when the turn finishes. Claude Code doesn't expose
this in the statusline payload, so the installer (optionally) registers
`statusline-hooks.ps1` for the `UserPromptSubmit`, `Stop`, `SubagentStart`,
`SubagentStop` and `SessionEnd` hook events — it keeps tiny per-session state files in
`%TEMP%\claude-statusline` — and sets `statusLine.refreshInterval: 2` so the timer
stays live. Each refresh spawns a PowerShell process (~0.5s wall time on a typical
machine), so if you keep many sessions open at once you can raise the interval in
`settings.json`; if you remove it, the statusline still updates after every message,
the timer just won't tick in between. State files are keyed by `session_id` and hook
writes are mutex-serialized, so concurrent sessions and parallel subagents don't clash.

## Features

- Context window usage bar (green → yellow → red as you approach the limit)
- Session cost in USD with live BRL conversion (fetched from [AwesomeAPI](https://economia.awesomeapi.com.br), cached 24h, with offline fallback)
- Prompt cache hit rate — highlights when you're saving money via caching (90% cheaper than regular input tokens)
- Warning indicator when context exceeds 200K tokens
- Git branch display when inside a git repository
- Supports both 200K and 1M (extended) context windows

## Installation

### Quick install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/hugohvf/claude-code-statusline/main/install.sh | bash
```

This will:
1. Check that `jq` is installed
2. Download `statusline.sh` to `~/.claude/statusline.sh`
3. Patch `~/.claude/settings.json` to enable the statusline
4. Print confirmation — just restart Claude Code

> **Requires:** `jq` — install with `brew install jq` (macOS) or `sudo apt install jq` (Linux)

### Windows (PowerShell)

Clone the repo and double-click `install.bat`, or run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

This copies `statusline.ps1` and `statusline-hooks.ps1` to `%USERPROFILE%\.claude\`,
patches `settings.json`, asks whether to enable live activity tracking, then runs a
3-step wizard (fields → layout → theme) with live previews of every option.
No jq or Git Bash required. To remove everything, run `uninstall.bat`.

---

### Let Claude set it up for you

Already inside a Claude Code session? Paste this prompt and Claude will handle the entire setup:

```
Please install the statusline from https://github.com/hugohvf/claude-code-statusline for me.

Steps:
1. Download https://raw.githubusercontent.com/hugohvf/claude-code-statusline/main/statusline.sh to ~/.claude/statusline.sh and make it executable
2. Open ~/.claude/settings.json and add (or merge) this key:
   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
3. Confirm what you changed and tell me to restart Claude Code to activate it
```

---

### Manual installation

#### 1. Download the script

```bash
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/hugohvf/claude-code-statusline/main/statusline.sh
chmod +x ~/.claude/statusline.sh
```

#### 2. Configure Claude Code

Add the following to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

> **Tip:** You can open `settings.json` quickly with `/config` inside Claude Code.

#### 3. Restart Claude Code

The statusline will appear at the bottom of your terminal session.

## Compatibility

This statusline is exclusive to **Claude Code** (the official Anthropic CLI). Other AI coding tools do not support custom statusline commands:

| Tool | Statusline support |
|---|---|
| Claude Code | ✅ Supported |
| Cursor | ❌ Not supported |
| OpenAI Codex CLI | ❌ Not supported |
| GitHub Copilot | ❌ Not supported |

---

## Requirements

- **bash** — available by default on macOS and Linux
- **jq** — for JSON parsing. Install with `brew install jq` (macOS) or `apt install jq` (Linux)
- **curl** — for BRL exchange rate fetching (optional — falls back to a hardcoded rate if unavailable)
- **git** — for branch display (optional — silently skipped if not in a git repo)

## How it works

Claude Code passes a JSON payload to the statusline command via stdin on every update. The script reads it using `jq`, extracts the relevant fields, formats them, and prints up to 3 lines to stdout.

The USD→BRL exchange rate is fetched once per day from [AwesomeAPI](https://economia.awesomeapi.com.br/json/last/USD-BRL) and cached at `/tmp/statusline-usd-brl`. If the request fails or you're offline, it falls back to `5.70`.

For more details on how the statusline feature works, see the [official Claude Code statusline docs](https://code.claude.com/docs/en/statusline).

## Customization

You can edit `statusline.sh` to:

- Change the BRL fallback rate (`BRL_FALLBACK`)
- Adjust the cache TTL (`BRL_CACHE_MAX_AGE`, default 24h)
- Change color thresholds for the context bar (currently yellow at 70%, red at 90%)
- Change cache hit thresholds (green at ≥70%, yellow at ≥30%, red below)
- Add or remove lines

## License

MIT
