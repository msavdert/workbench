# =============================================================================
# .zshrc - interactive shells only
# =============================================================================
# Shared by the mac (thin client) and the box, where it is reached through
# bash's interactive hand-off (D5). Every block is guarded so a missing tool
# is a no-op rather than an error.
#
# Design rules (shell start-up budget):
#   1. No network calls at start-up.  Secrets are fetched per-command via `op
#      run`, never eagerly - see the "Secrets" section below.
#   2. No `source <(tool completion zsh)`.  Completions are pre-generated into
#      $ZSH_COMPLETIONS by `mise run completions:regen`.  Sourcing them at
#      start-up costs one fork per tool.
#   3. `compinit` uses its cache and only does the security scan once a day.
# =============================================================================

# --- Locale / terminal -------------------------------------------------------
# NOTE: TERM is deliberately NOT set here. The terminal emulator knows what it
# is; overriding it to xterm-256color loses undercurl, truecolor detection and
# correct keys inside zellij. If a terminal reports something the remote host
# has no terminfo entry for, fix it with `infocmp -x | ssh host tic -x -`.

# --- History -----------------------------------------------------------------
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=100000
SAVEHIST=100000

setopt EXTENDED_HISTORY          # record timestamps
setopt SHARE_HISTORY             # sync between running shells
setopt HIST_IGNORE_ALL_DUPS      # keep only the most recent copy of a command
setopt HIST_IGNORE_SPACE         # leading space keeps it out of history
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY               # expand !! but let me confirm before running

setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP

# --- Completion --------------------------------------------------------------
export ZSH_COMPLETIONS="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions"
[[ -d $ZSH_COMPLETIONS ]] && fpath=("$ZSH_COMPLETIONS" $fpath)

autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
[[ -d ${_zcompdump:h} ]] || mkdir -p "${_zcompdump:h}"
# Run the (slow) security scan at most once every 24h, use the cache otherwise.
# The glob qualifier must be expanded in an array assignment - inside [[ ]] zsh
# does no filename generation, so the common `[[ -n file(#qN.mh+24) ]]` idiom
# silently always takes the slow branch.
_zcompstale=( ${_zcompdump}(N.mh+24) )
if (( ${#_zcompstale} )) || [[ ! -f $_zcompdump ]]; then
    compinit -d "$_zcompdump"
    touch "$_zcompdump"
else
    compinit -C -d "$_zcompdump"
fi
unset _zcompdump _zcompstale

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu select
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/compcache"

# `ssh <TAB>` normally falls back to zsh's generic host completion (`_hosts`,
# which lists /etc/hosts) before it ever tries parsing ~/.ssh/config itself -
# `_ssh_hosts`'s `_combination` call returns as soon as that generic list is
# non-empty, which it always is, so aliases from ~/.ssh/config.local (written
# by `mise run ssh:sync`) never get a chance to show.
# Feed them in directly via the `hosts` style instead, which `_hosts` reads
# ahead of its own /etc/hosts fallback.
if [[ -r $HOME/.ssh/config.local ]]; then
    _1p_ssh_hosts=(${(f)"$(command awk '
        tolower($1) == "host" {
            for (i = 2; i <= NF; i++) if ($i !~ /[*?]/) print $i
        }' $HOME/.ssh/config.local)"})
    (( ${#_1p_ssh_hosts} )) && zstyle ':completion:*:hosts' hosts $_1p_ssh_hosts
    unset _1p_ssh_hosts
fi

# `ssh <TAB>` also always offers every local system account (root, www-data,
# uucp, ...) alongside hosts - stock behaviour, so you can start typing
# `user@host` too (`_ssh`'s `userhost` state runs `_ssh_users`, which falls
# back to /etc/passwd same as `_users` does absent an override). Silence that
# half for ssh/scp/sftp specifically; other commands using `_users`
# (chown, passwd, ...) are untouched.
zstyle ':completion:*:*:(ssh|slogin|scp|sftp):*:users' users

# --- Tool integration --------------------------------------------------------
# `mise activate` replaces the shims from .zshenv with direct paths and keeps
# them in sync on every directory change.
if (( $+commands[mise] )); then
    eval "$(mise activate zsh)"
fi

(( $+commands[zoxide] ))   && eval "$(zoxide init zsh)"

# Everything below this point talks to the prompt or to zle, and neither exists
# under a dumb terminal. `zsh -c`, editor subshells and any tool that captures
# command output run with TERM=dumb, where starship prints
#   [ERROR] - (starship::print): Under a 'dumb' terminal
# and fzf's keybindings abort with
#   (eval):1: can't change option: zle
# straight into the captured stream. `mise activate` and `zoxide` above are
# deliberately NOT guarded: captured shells still need a correct PATH and
# working directory resolution.
if [[ ${TERM:-} != dumb ]]; then
    # Force standard Emacs editing mode (disables Vi mode in Zsh Line Editor)
    bindkey -e

    # Navigation & editing keybindings across Ghostty, Terminal.app, xterm
    bindkey "^[[H"    beginning-of-line          # Home / fn + Left
    bindkey "^[OH"    beginning-of-line
    bindkey "^[[1~"   beginning-of-line
    bindkey "^[[7~"   beginning-of-line
    bindkey "^A"      beginning-of-line          # Ctrl-A / Cmd-Left

    bindkey "^[[F"    end-of-line                # End / fn + Right
    bindkey "^[OF"    end-of-line
    bindkey "^[[4~"   end-of-line
    bindkey "^[[8~"   end-of-line
    bindkey "^E"      end-of-line                # Ctrl-E / Cmd-Right

    bindkey "^[[3~"   delete-char                # Delete / fn + Backspace
    bindkey "^?"      backward-delete-char       # Backspace

    # Word navigation (Option + Left / Right)
    bindkey "^[b"     backward-word              # Alt-b / Option-Left
    bindkey "^[f"     forward-word               # Alt-f / Option-Right
    bindkey "^[[1;3D" backward-word              # Option-Left
    bindkey "^[[1;3C" forward-word               # Option-Right
    bindkey "^[[1;5D" backward-word              # Ctrl-Left
    bindkey "^[[1;5C" forward-word               # Ctrl-Right
    bindkey "^[^[[D"  backward-word
    bindkey "^[^[[C"  forward-word

    (( $+commands[starship] )) && eval "$(starship init zsh)"

    # fzf ships its own keybindings (Ctrl-R history, Ctrl-T files). The
    # snippet is pre-generated by regen-completions.zsh (same rule as
    # completions: no subprocess per tool at start-up). Missing file means
    # fzf was added after the last `mise run completions:regen`.
    [[ -r "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/init/fzf.zsh" ]] \
        && source "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/init/fzf.zsh"
fi

# --- Secrets -----------------------------------------------------------------
# Secrets are NEVER exported into the shell environment. Each wrapper below
# resolves its op:// references in a single `op run` call, injects them into
# that one process, and they disappear when it exits.
#
# Why not export at start-up: N secrets meant N network round-trips on every
# new terminal, and anything in the environment leaks into every child process
# and into /proc/<pid>/environ (D10).
#
# NOTE: this is ~/.config/op-env, NOT ~/.config/op. The latter is the 1Password
# CLI's own state directory (its config file and daemon socket live there);
# putting our files on top of it breaks `op` completely.
# Exported, unlike the secrets themselves: this is a PATH, not a credential, so
# it leaks nothing into child processes. It has to be exported because agents
# and other non-interactive shells inherit the environment but not this file.
export OP_ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/op-env"

# `opwith <env> <cmd...>` itself is a script, home/bin/opwith on PATH, so it
# works the same in bash, zsh and non-interactive shells. Only its completion
# and the wrappers live here.
if (( $+commands[op] )) && [[ -d $OP_ENV_DIR ]]; then
    # Autocompletion for opwith: 1st arg completes env files, remaining args use standard command completion
    function _opwith {
        local -a envs
        envs=(${OP_ENV_DIR}/*.env(N:t:r))
        _arguments -C \
            "1:env file:($envs)" \
            "*::command:_normal"
    }
    compdef _opwith opwith

    # `op run` execs the binary directly (PATH lookup, no shell), so these
    # functions cannot recurse into themselves.
    # Note: claude is intentionally not wrapped with opwith so it can use native claude.ai OAuth login & Connectors.
    unalias kilocode gh 2>/dev/null
    function kilocode { opwith ai kilocode "$@"; }

    # `gh` reads GH_TOKEN from the environment, so wrapping it here removes the
    # need for `gh auth login` and keeps the token out of ~/.config/gh/hosts.yml.
    # git itself is NOT wrapped - home/git/config resolves its credential
    # from 1Password per invocation and needs nothing in the environment.
    function gh { opwith git gh "$@"; }

    # WORKBENCH_PROFILE comes from ~/.config/workbench/env (home/install.sh).
    # The box is a disposable single-tenant VM with no other workloads, so
    # skipping the permission-prompt loop there is an acceptable trade - it
    # is NOT safe on the mac, where `claude` runs against the real filesystem.
    if [[ ${WORKBENCH_PROFILE:-} == box ]]; then
        unalias claude agy 2>/dev/null
        function claude { command claude --dangerously-skip-permissions "$@"; }
        function agy    { command agy --dangerously-skip-permissions "$@"; }
    fi

    # NOTE: no `omp` wrapper here, on purpose. OMP needs nothing from op-env:
    # it resolves its credentials from ~/.omp/agent/agent.db and its Synthetic
    # key from ~/.omp/agent/.env (`mise run omp:auth`). Wrapping it would put
    # every variable in ai.env into its environment, and any ANTHROPIC_* value
    # added there later would silently reroute OMP's own Anthropic OAuth.
fi

# --- OMP ---------------------------------------------------------------------
# OMP uses its DEFAULT agent directory, ~/.omp/agent. PI_CODING_AGENT_DIR is
# deliberately NOT set; the declarative config reaches that directory by
# per-file symlinks from home/install.sh (home/omp/).

# --- Aliases -----------------------------------------------------------------
# Editors (Guarded: Fallback to system vim/vi on macOS if nvim is not installed)
if (( $+commands[nvim] )); then
    alias vim='nvim'           # Full Neovim (all plugins & config loaded)
    alias vi='nvim --clean'    # Super light Vi mode (0 plugins, instant startup)
    alias v='nvim --clean'     # Super light Vi mode shortcut
elif (( $+commands[vim] )); then
    alias vi='vim -u NONE'     # Clean Vim without config/plugins
    alias v='vim'              # Standard Vim
else
    alias v='vi'
fi
alias ..='cd ..'
alias ...='cd ../..'

# Modern tools get their OWN names. Shadowing grep/find/cat with rg/fd/bat
# breaks every script and pasted command that relies on POSIX flags - and it
# silently rewrites these very functions, because zsh expands aliases inside
# function bodies at definition time. This applies to `ls` too: agents run
# their commands with stdin attached to a pipe, and eza then waits for a
# path list on stdin instead of listing the directory - a bare `ls` under
# Claude Code's Bash tool blocked until timeout (measured 2026-08-16). The
# aliases below are captured into the agent shell snapshot regardless of
# any interactive guard, so the only fix is not to take the name.
(( $+commands[eza] )) && {
    alias l='eza --icons --group-directories-first'
    alias ll='eza -l --icons --group-directories-first --git'
    alias la='eza -la --icons --group-directories-first --git'
    alias lt='eza --tree --level=2 --icons'
}
(( $+commands[bat] ))  && alias bcat='bat --style=plain'
(( $+commands[dust] )) && alias duh='dust'
(( $+commands[gping] )) && alias pingg='gping'

# Kubernetes
alias k='kubectl'
alias kg='kubectl get'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deploy'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectl config use-context'
(( $+functions[__start_kubectl] )) && compdef __start_kubectl k

# --- Functions ---------------------------------------------------------------
# `command` prefixes below are load-bearing: they bypass any alias or function
# of the same name.

# ssh with no arguments -> fuzzy host picker built from the ssh config files.
unalias ssh zs 2>/dev/null
function ssh {
    if (( $# > 0 )); then
        command ssh "$@"
        return
    fi
    local host
    host=$(command awk '/^[Hh]ost / { for (i=2; i<=NF; i++) if ($i !~ /[*?]/) print $i }' \
              ~/.ssh/config ~/.ssh/config.local 2>/dev/null \
           | command sort -u \
           | fzf --height 40% --reverse --border --prompt='ssh > ')
    [[ -n $host ]] && command ssh "$host"
}

# herdr restores the tty and sends its mode resets (CSI ?1003l, CSI <u)
# correctly on prefix+q detach, but over ssh those resets reach Ghostty a few
# tens of milliseconds later. In that window the release of the "q" key
# (kitty protocol: ESC[113;1:3u) and any mouse motion still arrive as raw
# bytes at a tty nobody reads, get echoed, and land on the next command line
# as "3;1:3u" / "35;64;25M". Drain the tty until it has been quiet for 0.2s
# (capped at 2s) before zle takes over. Local terminals and zellij do not
# show this, and on macOS `read -k` can block on a pending partial line, so
# the drain runs only on the remote path.
function herdr {
    command herdr "$@"
    local rc=$? junk end=$((SECONDS + 2))
    [[ -n ${SSH_CONNECTION:-} ]] || return $rc
    while (( SECONDS < end )) && read -s -t 0.2 -k 1 junk; do :; done
    return $rc
}

# zs -> pick a directory from zoxide's frecency list, attach/create a zellij
# session named after it. This is the "resume where I left off" entry point.
function zs {
    (( $+commands[zellij] && $+commands[zoxide] && $+commands[fzf] )) || {
        print -u2 "zs: needs zellij, zoxide and fzf"; return 1
    }
    local dir
    dir=$(zoxide query -l | fzf --height 40% --reverse --border --prompt='session > ')
    [[ -n $dir ]] || return 0
    local name="${${dir:t}//[^a-zA-Z0-9_-]/_}"
    zellij attach "$name" 2>/dev/null \
        || (cd "$dir" && zellij --session "$name")
}

# --- SSH agent ---------------------------------------------------------------
# On macOS, point SSH_AUTH_SOCK at the 1Password agent socket if it is live.
# On the box (Linux) or on systems without 1Password, manage a fallback
# agent socket. If an agent is already forwarded into the session, leave it alone.
if [[ "$(uname -s)" == "Darwin" ]]; then
    _1p_sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    if [[ -S "$_1p_sock" ]]; then
        export SSH_AUTH_SOCK="$_1p_sock"
    fi
    unset _1p_sock
elif [[ -z ${SSH_AUTH_SOCK:-} || $SSH_AUTH_SOCK == "${XDG_RUNTIME_DIR:-$HOME/.ssh}/ssh-agent.sock" ]] \
    && (( $+commands[ssh-agent] && $+commands[ssh-add] )); then
    _agent_sock="${XDG_RUNTIME_DIR:-$HOME/.ssh}/ssh-agent.sock"
    SSH_AUTH_SOCK="$_agent_sock" command ssh-add -l &>/dev/null
    if (( $? == 2 )); then
        rm -f "$_agent_sock"
        eval "$(ssh-agent -s -a "$_agent_sock")" >/dev/null
    fi
    export SSH_AUTH_SOCK="$_agent_sock"
    unset _agent_sock
fi

# --- Plugins -----------------------------------------------------------------
# Order matters: zsh-syntax-highlighting wraps every widget that exists when it
# is sourced, so it must come last. Both are zle widgets, hence the same dumb
# terminal guard as the prompt integrations above.
ZSH_PLUGINS="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-plugins"
if [[ -d $ZSH_PLUGINS && ${TERM:-} != dumb ]]; then
    source "$ZSH_PLUGINS/zsh-autosuggestions/zsh-autosuggestions.zsh" 2>/dev/null
    source "$ZSH_PLUGINS/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" 2>/dev/null
fi

# --- Local overrides ---------------------------------------------------------
# Machine-specific, never committed.
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
