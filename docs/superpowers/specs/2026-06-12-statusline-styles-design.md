# Statusline Styles + Interactive Chooser — Design

Date: 2026-06-12
Status: approved by user

## Goal

Offer multiple visual styles for the Windows statusline (`statusline.ps1`) and let the
user preview and pick one during installation — or switch later without reinstalling.

## Architecture: single script + config file

- `statusline.ps1` contains all styles. Shared parsing/computation of the Claude Code
  JSON payload feeds per-style render functions.
- Active style is read from `~/.claude/statusline-style` (plain text, one word).
  Missing file → `classic` (the current 3-line layout), so existing installs keep working.
- New parameters:
  - `-Style <name>` — force a style (used for previews/testing).
  - `-Choose` — interactive menu: renders every style in the console with embedded
    sample data (real colors/bars), reads a number, writes `~/.claude/statusline-style`.
    Enables VT/ANSI via `SetConsoleMode` so previews work in plain conhost (Win10).

## Styles

| Name | Lines | Content |
|---|---|---|
| `minimal` | 1 | `[Opus] ▰▰▰▱▱ 42% · $0.35 · 12m` |
| `compact` | 2 | model + folder + branch / bar + % + cost USD/BRL + time |
| `classic` | 3 | current layout unchanged (default) |
| `powerline` | 2 | colored background segments, Catppuccin Mocha palette, Nerd Font separators (``) — requires a Nerd Font |
| `dashboard` | 4 | box-drawing frame; everything in the payload: context, cost USD/BRL, cache, lines +/− changed, API vs total time, Claude Code version, output style |

Extra payload fields used by `dashboard`: `cost.total_lines_added`,
`cost.total_lines_removed`, `cost.total_api_duration_ms`, `version`, `output_style.name`.

## Installer / uninstaller

- `install.ps1`: after copying the script and patching `settings.json`, runs
  `& $Dest -Choose` so the user previews and picks a style during install.
- `uninstall.ps1`: also removes `~/.claude/statusline-style`.
- README: new Styles section with the table above and the switch-later command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.claude\statusline.ps1 -Choose`

## Out of scope

- `statusline.sh` (bash) keeps its single current style.

## Error handling

- Invalid/unknown style name in the config file → fall back to `classic`.
- `-Choose` with invalid input → default to `classic` (3).
- Normal statusline path never prompts and never calls `Add-Type` (P/Invoke for VT is
  only compiled in the `-Choose` path, keeping the hot path fast).

## Testing

Pipe a sample payload into the script with each `-Style` value and verify each render
produces the expected number of lines and no errors under PowerShell 5.1.
