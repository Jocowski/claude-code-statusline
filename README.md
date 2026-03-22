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
