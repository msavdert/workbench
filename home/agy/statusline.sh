#!/usr/bin/env bash
# ~/.gemini/antigravity-cli/statusline.sh (home/agy, linked by home/install.sh).
# ==============================================================================
# Antigravity CLI (AGY) Statusline — Tokyo Cyber Minimalist
# ==============================================================================
#
# A high-density, ultra-clean 2-line developer HUD providing at-a-glance visibility
# into Gemini model parameters, agent/subagent state, context window pressure,
# git/PR status, and rate limits.
#
# OUTPUT LAYOUT:
#   Line 1: [VIM] 󰚩 Model · state · 󰚩 subagents ·  tasks  │  ⚡Cache%  │  󰔛 5h% (⏱ reset) · 7d%
#   Line 2: [▓▓░░░░░░] CTX% (tokens)  │   dir  │   branch*+?  │   #PR 󰄬  │  +add -rem · $cost
#
# CORE DESIGN PRINCIPLES:
#   1. Zero Latency (0ms): agy re-renders the statusline on every state event.
#      External git/disk I/O is cached for 5s per session/conversation ID.
#   2. Fail-Safe: Graceful fallbacks for missing/null JSON fields; safe arithmetic
#      guards ensure the script never throws errors and always exits 0.
#   3. Cross-Platform: Fully compatible with both macOS (BSD) and Linux (GNU).
#
# ENVIRONMENT VARIABLES (Optional Knobs):
#   SL_BADGE_CMD   : Shell command whose first line of stdout becomes the project badge.
# ==============================================================================

# Disable filename expansion (globbing) so '*' characters in git dirty flags
# or paths are treated strictly as literal strings.
set -f

# ------------------------------------------------------------------------------
# 1. PATH Setup (macOS Homebrew & Standard Binary Locations)
# ------------------------------------------------------------------------------
for d in /opt/homebrew/bin /usr/local/bin; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH

# ------------------------------------------------------------------------------
# 2. Dependency Verification (jq)
# ------------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  printf 'statusline: jq not found on PATH\n'
  exit 0
fi

# Read entire stdin payload into variable.
input=$(cat)
[ -z "$input" ] && exit 0

# ------------------------------------------------------------------------------
# 3. ANSI Color Palette (Tokyo Night / Catppuccin Inspired)
# ------------------------------------------------------------------------------
ESC=$'\033'
R="${ESC}[0m" # Reset
B="${ESC}[1m" # Bold
D="${ESC}[2m" # Dimmed / Subdued

CY="${ESC}[38;5;117m"   # Soft Cyan / Sky (Model name, PR badges, untracked flags)
BL="${ESC}[38;5;75m"    # Soft Blue (Directory, worktree, agent badges)
MG="${ESC}[38;5;176m"   # Lavender / Magenta (Thinking mode, branch name, cache hit)
GR="${ESC}[38;5;114m"   # Mint Green (Healthy status, staged files, added lines)
YE="${ESC}[38;5;221m"   # Warm Amber / Gold (Medium threshold warning, cost, dirty files)
RD="${ESC}[38;5;203m"   # Coral Red (High threshold alerts, removed lines)
WH="${ESC}[38;5;253m"   # Clean White (Emphasized text, values)
GRAY="${ESC}[38;5;242m" # Slate Gray (Neutral dividers)

SEP=" ${GRAY}│${R} " # Major segment separator
DOT=" ${GRAY}·${R} " # Minor segment separator

# ------------------------------------------------------------------------------
# 4. Helper Functions
# ------------------------------------------------------------------------------

# link <text> <url>
# Formats text as an OSC 8 terminal hyperlink, allowing click-to-open in
# modern terminals (Ghostty, iTerm2, WezTerm, Kitty, etc.).
link() {
  local text="$1" url="$2"
  if [ -n "$url" ]; then
    printf "\033]8;;%s\033\\\\%s\033]8;;\033\\\\" "$url" "$text"
  else
    printf '%s' "$text"
  fi
}

# fmt_tokens <count>
# Converts raw token numbers (e.g. 68420 -> 68k, 1048576 -> 1M) into compact strings.
fmt_tokens() {
  local n=${1:-0}
  if [ "$n" -ge 1000000 ]; then
    printf '%dM' "$((n / 1000000))"
  elif [ "$n" -ge 1000 ]; then
    printf '%dk' "$((n / 1000))"
  else
    printf '%d' "$n"
  fi
}

# int <value> <fallback>
# Sanitizes inputs to safe integers to prevent bash arithmetic syntax errors ($(( ... ))).
int() { case "$1" in '' | *[!0-9-]*) echo "${2:-0}" ;; *) echo "$1" ;; esac }

# ------------------------------------------------------------------------------
# 5. Single-Pass JSON Parsing Engine
# ------------------------------------------------------------------------------
# Handles Antigravity CLI / AGY schema fields (including .quota, .context_window, camelCase and snake_case).
{
  IFS= read -r MODEL
  # shellcheck disable=SC2034 # read to keep the field order, not displayed
  IFS= read -r EFFORT
  IFS= read -r STATE
  IFS= read -r SUBAGENTS
  IFS= read -r TASKS
  IFS= read -r CTX_PCT
  IFS= read -r CTX_SIZE
  IFS= read -r IN_TOK
  IFS= read -r CACHE_R
  IFS= read -r COST
  IFS= read -r L_ADD
  IFS= read -r L_REM
  IFS= read -r FIVE_PCT
  IFS= read -r FIVE_RST
  IFS= read -r SEVEN_PCT
  IFS= read -r WT
  IFS= read -r CWD
  IFS= read -r PR_NUM
  IFS= read -r PR_URL
  IFS= read -r PR_STATE
  IFS= read -r VIM_MODE
  IFS= read -r SID
} < <(
  printf '%s' "$input" | jq -r '
    def is_3p: ((.model.id // .model.display_name // "") | test("claude|gpt|3p"; "i"));
    def q_5h: if is_3p then .quota["3p-5h"] else .quota["gemini-5h"] end // .quota["gemini-5h"] // .quota["3p-5h"] // (.quota | to_entries[0].value?);
    def q_weekly: if is_3p then .quota["3p-weekly"] else .quota["gemini-weekly"] end // .quota["gemini-weekly"] // .quota["3p-weekly"] // (.quota | to_entries[1].value?);
    [
      (.model.display_name // .modelName // .model.name // .model // "?"),
      (.model.effort // ""),
      (.agent_state // .agentState // .state // ""),
      (.activeSubagents // .active_subagents // (.subagents | length? // 0) // 0),
      (.activeTasks // .active_tasks // (.backgroundTasks | length? // (.tasks | length? // 0)) // 0),
      (.context_window.used_percentage // .contextWindow.usedPercentage // 0 | floor),
      (.context_window.context_window_size // .contextWindow.contextWindowSize // 1048576),
      (.context_window.total_input_tokens // .contextWindow.totalInputTokens // 0),
      (.context_window.current_usage.cache_read_input_tokens // .contextWindow.currentUsage.cacheReadInputTokens // 0),
      (.cost.totalCostUsd // .cost.total_cost_usd // 0),
      (.cost.totalLinesAdded // .cost.total_lines_added // 0),
      (.cost.totalLinesRemoved // .cost.total_lines_removed // 0),
      (
        if q_5h.remaining_fraction != null then (q_5h.remaining_fraction * 100 | floor)
        elif .rateLimits.fiveHour.usedPercentage != null then (100 - .rateLimits.fiveHour.usedPercentage | floor)
        elif .rate_limits.five_hour.used_percentage != null then (100 - .rate_limits.five_hour.used_percentage | floor)
        else -1 end
      ),
      (
        q_5h.reset_in_seconds //
        (if .rateLimits.fiveHour.resetsAt then (.rateLimits.fiveHour.resetsAt - (now | floor))
         elif .rate_limits.five_hour.resets_at then (.rate_limits.five_hour.resets_at - (now | floor))
         else 0 end) // 0
      ),
      (
        if q_weekly.remaining_fraction != null then (q_weekly.remaining_fraction * 100 | floor)
        elif .rateLimits.sevenDay.usedPercentage != null then (100 - .rateLimits.sevenDay.usedPercentage | floor)
        elif .rate_limits.seven_day.used_percentage != null then (100 - .rate_limits.seven_day.used_percentage | floor)
        else -1 end
      ),
      (.workspace.gitWorktree // .workspace.git_worktree // ""),
      (.workspacePaths[0] // .workspace.currentDir // .workspace.current_dir // .cwd // "."),
      (.pr.number // ""),
      (.pr.url // ""),
      (.pr.reviewState // .pr.review_state // ""),
      (.vim.mode // ""),
      (.conversationId // .conversation_id // .sessionId // .session_id // "nosess")
    ] | .[] | tostring | gsub("[\r\n\t]"; " ")' 2>/dev/null
)

# Convert all numeric values to safe integers
SUBAGENTS=$(int "$SUBAGENTS" 0)
TASKS=$(int "$TASKS" 0)
CTX_PCT=$(int "$CTX_PCT" 0)
CTX_SIZE=$(int "$CTX_SIZE" 1048576)
IN_TOK=$(int "$IN_TOK" 0)
CACHE_R=$(int "$CACHE_R" 0)
L_ADD=$(int "$L_ADD" 0)
L_REM=$(int "$L_REM" 0)
FIVE_PCT=$(int "$FIVE_PCT" -1)
FIVE_RST=$(int "$FIVE_RST" 0)
SEVEN_PCT=$(int "$SEVEN_PCT" -1)
CWD=${CWD:-.}
SID=${SID:-nosess}

# ------------------------------------------------------------------------------
# 6. Git & Project Badge (5-Second Cache per session_id)
# ------------------------------------------------------------------------------
CACHE="${TMPDIR:-/tmp}/agy-sl-${SID//[^A-Za-z0-9]/_}.cache"
now=$(date +%s 2>/dev/null || echo 0)
mt=$(stat -c %Y "$CACHE" 2>/dev/null || stat -f %m "$CACHE" 2>/dev/null || echo 0)
case "$mt" in '' | *[!0-9]*) mt=0 ;; esac

if [ -s "$CACHE" ] && [ $((now - mt)) -lt 5 ]; then
  # Cache hit (< 5s old)
  IFS=$'\t' read -r BRANCH AHEAD BEHIND STAGED UNSTAGED UNTRACKED GIT_ADD GIT_REM BADGE <"$CACHE"
else
  # Cache miss or expired: query git and workspace state
  BRANCH=$(git -C "$CWD" symbolic-ref --short HEAD 2>/dev/null ||
    git -C "$CWD" rev-parse --short HEAD 2>/dev/null || echo "")
  AHEAD=0
  BEHIND=0
  STAGED=0
  UNSTAGED=0
  UNTRACKED=0
  GIT_ADD=0
  GIT_REM=0

  if [ -n "$BRANCH" ]; then
    # Ahead / Behind remote tracking branch
    counts=$(git -C "$CWD" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || echo "")
    if [ -n "$counts" ]; then
      AHEAD=$(echo "$counts" | cut -f1)
      BEHIND=$(echo "$counts" | cut -f2)
    fi

    # Staged, Unstaged and Untracked file counts
    gs=$(git -C "$CWD" status --porcelain 2>/dev/null)
    if [ -n "$gs" ]; then
      STAGED=$(echo "$gs" | grep -c '^[MADRC]' 2>/dev/null || echo 0)
      UNSTAGED=$(echo "$gs" | grep -c '^.[MADRCU]' 2>/dev/null || echo 0)
      UNTRACKED=$(echo "$gs" | grep -c '^??' 2>/dev/null || echo 0)
    fi

    # Line churn from git diff: uncommitted diff first, then unpushed diff
    numstat=$(git -C "$CWD" diff --numstat HEAD 2>/dev/null)
    if [ -z "$numstat" ] && [ "$AHEAD" -gt 0 ]; then
      numstat=$(git -C "$CWD" diff --numstat '@{upstream}...HEAD' 2>/dev/null)
    fi
    if [ -n "$numstat" ]; then
      read -r GIT_ADD GIT_REM < <(echo "$numstat" | awk '{add+=$1; del+=$2} END {printf "%d\t%d\n", add, del}')
    fi
  fi

  ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
  BADGE=""

  # Custom badge hook (evaluates SL_BADGE_CMD if provided)
  if [ -n "$SL_BADGE_CMD" ]; then
    BADGE=$( (cd "$ROOT" 2>/dev/null && eval "$SL_BADGE_CMD") 2>/dev/null | head -1 | tr -d '\t\n')
  fi

  AHEAD=$(int "$AHEAD" 0)
  BEHIND=$(int "$BEHIND" 0)
  STAGED=$(int "$STAGED" 0)
  UNSTAGED=$(int "$UNSTAGED" 0)
  UNTRACKED=$(int "$UNTRACKED" 0)
  GIT_ADD=$(int "$GIT_ADD" 0)
  GIT_REM=$(int "$GIT_REM" 0)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$BRANCH" "$AHEAD" "$BEHIND" "$STAGED" "$UNSTAGED" "$UNTRACKED" "$GIT_ADD" "$GIT_REM" "$BADGE" >"$CACHE" 2>/dev/null
fi

AHEAD=$(int "$AHEAD" 0)
BEHIND=$(int "$BEHIND" 0)
STAGED=$(int "$STAGED" 0)
UNSTAGED=$(int "$UNSTAGED" 0)
UNTRACKED=$(int "$UNTRACKED" 0)
GIT_ADD=$(int "$GIT_ADD" 0)
GIT_REM=$(int "$GIT_REM" 0)

# Truncate long branch names to avoid line overflow
[ ${#BRANCH} -gt 24 ] && BRANCH="${BRANCH:0:23}…"

# ==============================================================================
# LINE 1 ASSEMBLY: AI Engine, Reasoning & Limits HUD
# ==============================================================================
L1=""

# 1. Vim Editor Mode (when Vim mode is enabled)
if [ -n "$VIM_MODE" ]; then
  case "$VIM_MODE" in
    NORMAL) L1="${L1}${MG}[NOR]${R} " ;;
    INSERT) L1="${L1}${GR}[INS]${R} " ;;
    VISUAL*) L1="${L1}${YE}[VIS]${R} " ;;
    *) L1="${L1}${CY}[${VIM_MODE:0:3}]${R} " ;;
  esac
fi

# 2. Model Name & Execution Modifiers
L1="${L1}${CY}󰚩 ${B}${MODEL}${R}"

# Agent State
if [ -n "$STATE" ]; then
  case "$STATE" in
    thinking | *think*) L1="${L1}${DOT}${MG}think${R}" ;;
    running | working | *run* | *work*) L1="${L1}${DOT}${GR}${STATE}${R}" ;;
    idle) L1="${L1}${DOT}${D}idle${R}" ;;
    *) L1="${L1}${DOT}${WH}${STATE}${R}" ;;
  esac
fi

# Active Subagents & Background Tasks Badges
if [ "$SUBAGENTS" -gt 0 ]; then
  L1="${L1}${DOT}${BL}󰚩 ${SUBAGENTS} agents${R}"
fi
if [ "$TASKS" -gt 0 ]; then
  L1="${L1}${DOT}${YE} ${TASKS} tasks${R}"
fi

# 3. Prompt Caching Efficiency (Cache Hit Ratio)
if [ "$IN_TOK" -gt 0 ] && [ "$CACHE_R" -gt 0 ]; then
  hit_pct=$((CACHE_R * 100 / IN_TOK))
  [ $hit_pct -gt 100 ] && hit_pct=100
  L1="${L1}${SEP}${MG}⚡${hit_pct}% cache${R}"
fi

# 4. Rate Limits & Reset Countdown (5-Hour & 7-Day Windows)
if [ "$FIVE_PCT" -ge 0 ]; then
  five_col="$GR"
  [ "$FIVE_PCT" -lt 50 ] && five_col="$YE"
  [ "$FIVE_PCT" -lt 20 ] && five_col="$RD"

  rst_txt=""
  diff=0
  if [ "$FIVE_RST" -gt 0 ]; then
    if [ "$FIVE_RST" -gt "$now" ]; then
      diff=$((FIVE_RST - now))
    else
      diff="$FIVE_RST"
    fi
  fi

  if [ "$diff" -gt 0 ]; then
    mins=$((diff / 60))
    if [ "$mins" -ge 60 ]; then
      h=$((mins / 60))
      m=$((mins % 60))
      rst_txt=" (${D}⏱ ${h}h${m}m${R})"
    elif [ "$mins" -gt 0 ]; then
      rst_txt=" (${D}⏱ ${mins}m${R})"
    else
      rst_txt=" (${D}⏱ <1m${R})"
    fi
  fi
  L1="${L1}${SEP}󰔛 ${five_col}5h: ${FIVE_PCT}%${R}${rst_txt}"
fi

# 7-day rate limit percentage (if available)
if [ "$SEVEN_PCT" -ge 0 ]; then
  L1="${L1}${DOT}${D}7d: ${SEVEN_PCT}%${R}"
fi

# ==============================================================================
# LINE 2 ASSEMBLY: Context Window, Workspace, Git/PR & Cost
# ==============================================================================
L2=""

# 1. Context Window Usage Bar (8-Character Block Graph)
ctx_col="$GR"
[ "$CTX_PCT" -ge 50 ] && ctx_col="$YE"
[ "$CTX_PCT" -ge 80 ] && ctx_col="$RD"

bw=8
fill=$((CTX_PCT * bw / 100))
[ $fill -gt $bw ] && fill=$bw
[ $fill -lt 0 ] && fill=0
empty=$((bw - fill))

bar=""
for ((i = 0; i < fill; i++)); do bar="${bar}▓"; done
for ((i = 0; i < empty; i++)); do bar="${bar}░"; done

in_tok_fmt=$(fmt_tokens "$IN_TOK")
size_tok_fmt=$(fmt_tokens "$CTX_SIZE")
L2="${ctx_col}[${bar}] ${CTX_PCT}%${R} ${D}(${in_tok_fmt}/${size_tok_fmt})${R}"

# 2. Current Working Directory (CWD) or Active Worktree
dir_disp="${CWD/#$HOME/\~}"
[ ${#dir_disp} -gt 28 ] && dir_disp="…${dir_disp: -27}"

if [ -n "$WT" ]; then
  L2="${L2}${SEP}${BL}⑂ ${WT}${R}"
else
  L2="${L2}${SEP}${BL} ${dir_disp}${R}"
fi

# 3. Git Branch & Detailed Status Indicators (Ahead/Behind & File Counts)
if [ -n "$BRANCH" ]; then
  git_seg="${MG} ${BRANCH}${R}"
  [ "$AHEAD" -gt 0 ] && git_seg="${git_seg} ${BL}⇡${AHEAD}${R}"
  [ "$BEHIND" -gt 0 ] && git_seg="${git_seg} ${RD}⇣${BEHIND}${R}"
  [ "$STAGED" -gt 0 ] && git_seg="${git_seg} ${GR}+${STAGED}${R}"
  [ "$UNSTAGED" -gt 0 ] && git_seg="${git_seg} ${YE}*${UNSTAGED}${R}"
  [ "$UNTRACKED" -gt 0 ] && git_seg="${git_seg} ${CY}?${UNTRACKED}${R}"
  L2="${L2}${SEP}${git_seg}"
fi

# 4. Clickable Pull Request Badge (OSC 8 Hyperlink & Review State)
if [ -n "$PR_NUM" ]; then
  pr_icon=""
  pr_state_icon=""
  pr_col="$CY"
  case "$PR_STATE" in
    approved)
      pr_state_icon=" 󰄬"
      pr_col="$GR"
      ;;
    changes_requested)
      pr_state_icon=" 󰅖"
      pr_col="$RD"
      ;;
    draft)
      pr_state_icon=" ${D}(draft)${R}"
      pr_col="$GRAY"
      ;;
    *)
      pr_state_icon=""
      pr_col="$CY"
      ;;
  esac
  pr_label="${pr_icon} #${PR_NUM}${pr_state_icon}"
  pr_clickable=$(link "${pr_col}${pr_label}${R}" "$PR_URL")
  L2="${L2}${SEP}${pr_clickable}"
fi

# 5. Code Churn (Added/Removed Lines) & Total Session Cost
churn_add=$L_ADD
churn_rem=$L_REM
if [ "$churn_add" -eq 0 ] && [ "$churn_rem" -eq 0 ]; then
  churn_add=$GIT_ADD
  churn_rem=$GIT_REM
fi

churn_cost=""
if [ "$churn_add" -gt 0 ] || [ "$churn_rem" -gt 0 ]; then
  churn_cost="${GR}+${churn_add}${R} ${RD}-${churn_rem}${R}"
fi

cost_val=$(awk "BEGIN {print ($COST + 0)}")
if [ "$(awk "BEGIN {print ($cost_val > 0)}")" = "1" ]; then
  cost_str=$(printf '$%.2f' "$cost_val" 2>/dev/null || echo "\$$cost_val")
  [ -n "$churn_cost" ] && churn_cost="${churn_cost} ${D}·${R} "
  churn_cost="${churn_cost}${YE}${cost_str}${R}"
fi

[ -n "$churn_cost" ] && L2="${L2}${SEP}${churn_cost}"

# 6. Custom Badge (if SL_BADGE_CMD is configured)
if [ -n "$BADGE" ]; then
  case "$BADGE" in
    *:*) L2="${L2}${SEP}${GR}●${R} ${D}${BADGE%%:*}:${R}${WH}${BADGE#*:}${R}" ;;
    *) L2="${L2}${SEP}${GR}●${R} ${WH}${BADGE}${R}" ;;
  esac
fi

# ------------------------------------------------------------------------------
# 7. Final Render
# ------------------------------------------------------------------------------
printf '%s\n%s\n' "$L1" "$L2"
