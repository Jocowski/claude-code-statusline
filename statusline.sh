#!/bin/bash
# Statusline do Curso 4 — Context Engineering
# Instalar: copie para ~/.claude/statusline.sh e configure em settings.json:
#   { "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" } }
#
# Mostra 3 linhas:
#   1. [Modelo] 📁 diretório | 🌿 branch
#   2. ████░░░░░░ 42% of 200K | $0.35 (R$2,03) | ⏱️ 12m 30s
#   3. cache: 45K read (78% hit)

input=$(cat)

# ── Dados básicos ──
MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# Context window size (200K ou 1M para extended)
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
CTX_K=$((CTX_SIZE / 1000))

# ── Cache — quanto estamos economizando ──
CACHE_READ=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
CACHE_CREATE=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
INPUT_TOK=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')

TOTAL_INPUT=$((INPUT_TOK + CACHE_READ + CACHE_CREATE))
if [ "$TOTAL_INPUT" -gt 0 ]; then
    CACHE_PCT=$((CACHE_READ * 100 / TOTAL_INPUT))
else
    CACHE_PCT=0
fi

# Formatar cache_read em K para legibilidade
if [ "$CACHE_READ" -ge 1000 ]; then
    CACHE_FMT="$((CACHE_READ / 1000))K"
else
    CACHE_FMT="$CACHE_READ"
fi

# Exceeds 200K tokens — alerta de gasto excessivo
EXCEEDS=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')

# ── Cotação USD→BRL com cache de 10 min ──
# Usa AwesomeAPI (gratuita, sem auth). Cache em /tmp por 24h
# para buscar a cotação apenas 1x por dia.
BRL_CACHE="/tmp/statusline-usd-brl"
BRL_CACHE_MAX_AGE=86400  # 24 horas — busca cotação 1x por dia
BRL_FALLBACK="5.70"      # fallback se offline

get_usd_brl() {
    local stale=true
    if [ -f "$BRL_CACHE" ]; then
        local age
        age=$(($(date +%s) - $(stat -c %Y "$BRL_CACHE" 2>/dev/null || stat -f %m "$BRL_CACHE" 2>/dev/null || echo 0)))
        [ "$age" -le "$BRL_CACHE_MAX_AGE" ] && stale=false
    fi

    if $stale; then
        # Tentar AwesomeAPI (timeout 2s para não travar a statusline)
        local rate
        rate=$(curl -sf --max-time 2 "https://economia.awesomeapi.com.br/json/last/USD-BRL" 2>/dev/null \
            | jq -r '.USDBRL.bid // empty' 2>/dev/null)

        if [ -n "$rate" ]; then
            echo "$rate" > "$BRL_CACHE"
        else
            # Se falhou e não tem cache, usar fallback
            [ ! -f "$BRL_CACHE" ] && echo "$BRL_FALLBACK" > "$BRL_CACHE"
        fi
    fi

    cat "$BRL_CACHE"
}

USD_BRL=$(get_usd_brl)

# Calcular custo em BRL
# Usar awk para multiplicação de floats (bash não suporta)
COST_BRL=$(awk "BEGIN { printf \"%.2f\", $COST * $USD_BRL }")

# ── Cores ──
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

# Cor da barra baseada no uso de contexto
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi

# Barra de progresso (10 blocos)
FILLED=$((PCT / 10)); EMPTY=$((10 - FILLED))
printf -v FILL "%${FILLED}s"; printf -v PAD "%${EMPTY}s"
BAR="${FILL// /█}${PAD// /░}"

# Tempo formatado
MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

# Git branch
BRANCH=""
git rev-parse --git-dir > /dev/null 2>&1 && BRANCH=" | 🌿 $(git branch --show-current 2>/dev/null)"

# ── LINHA 1: Modelo + Diretório + Git branch ──
echo -e "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}${BRANCH}"

# ── LINHA 2: Barra de contexto + window size + custo USD (R$) + duração ──
COST_FMT=$(printf '$%.2f' "$COST")
# Formatar BRL com vírgula decimal (padrão brasileiro)
COST_BRL_FMT=$(echo "$COST_BRL" | sed 's/\./,/')
EXCEEDS_WARN=""
if [ "$EXCEEDS" = "true" ]; then
    EXCEEDS_WARN=" ${RED}${BOLD}⚠ >200K${RESET}"
fi
echo -e "${BAR_COLOR}${BAR}${RESET} ${PCT}% of ${CTX_K}K${EXCEEDS_WARN} | ${YELLOW}${COST_FMT}${RESET} ${DIM}(R\$${COST_BRL_FMT})${RESET} | ⏱️ ${MINS}m ${SECS}s"

# ── LINHA 3: Cache savings ──
if [ "$CACHE_PCT" -ge 70 ]; then CACHE_COLOR="$GREEN"
elif [ "$CACHE_PCT" -ge 30 ]; then CACHE_COLOR="$YELLOW"
else CACHE_COLOR="$RED"; fi

echo -e "${DIM}cache:${RESET} ${CACHE_COLOR}${CACHE_FMT} read (${CACHE_PCT}% hit)${RESET}"
