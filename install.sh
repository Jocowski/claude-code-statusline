#!/bin/bash
# install.sh — Quick installer for claude-code-statusline
set -e

SCRIPT_URL="https://raw.githubusercontent.com/hugohvf/claude-code-statusline/main/statusline.sh"
DEST="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

echo ""
echo "Claude Code Statusline — Installer"
echo "===================================="
echo ""

# ── 1. Check dependencies ──────────────────────────────────────────────────────
echo "Checking dependencies..."

if ! command -v jq &> /dev/null; then
    echo ""
    echo "  jq is required but not installed."
    echo "  macOS:  brew install jq"
    echo "  Linux:  sudo apt install jq  (or your distro's package manager)"
    echo ""
    exit 1
fi

echo "  ✓ jq found"
echo "  ✓ bash found"
echo ""

# ── 2. Download script ─────────────────────────────────────────────────────────
echo "Downloading statusline.sh to $DEST ..."
mkdir -p "$HOME/.claude"
curl -fsSL "$SCRIPT_URL" -o "$DEST"
chmod +x "$DEST"
echo "  ✓ Downloaded and made executable"
echo ""

# ── 3. Patch settings.json ─────────────────────────────────────────────────────
echo "Configuring ~/.claude/settings.json ..."

if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

# Use jq to merge statusLine key, preserving all existing settings
UPDATED=$(jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' "$SETTINGS")
echo "$UPDATED" > "$SETTINGS"
echo "  ✓ settings.json updated"
echo ""

# ── 4. Done ────────────────────────────────────────────────────────────────────
echo "Done! Restart Claude Code to activate the statusline."
echo ""
echo "You should see 3 lines at the bottom of your session:"
echo "  [model] 📁 dir | 🌿 branch"
echo "  ████████░░ 78% of 200K | \$0.42 (R\$2,39) | ⏱️ 8m 15s"
echo "  cache: 62K read (81% hit) — input cacheado custa 90% menos"
echo ""
echo "To customize, edit: $DEST"
echo ""
