# shellcheck shell=bash
# ~/.config/bash/interactive.sh - the interactive half of the box's bashrc
# (home/bash, linked by home/install.sh). box/files/bashrc sources this file
# only after its `case $- in *i*)` guard, so nothing here can reach an
# agent-spawned shell: Claude Code's Bash tool, `ssh host cmd`, cron and
# systemd units all return at the guard (D5, P3).

# Hand off to zsh (home/zsh/) when a human is at a real terminal. Any one of
# these keeps plain bash: no TTY on stdin (captured output, tools that drive
# an interactive shell), TERM=dumb (editor subshells), a `bash -ic cmd`
# invocation (BASH_EXECUTION_STRING is set; exec would drop the command), or
# WORKBENCH_PLAIN set (the operator opting out). `exec` keeps the process
# tree flat; $SHELL stays /bin/bash because nothing sets it. The agent-safe
# defaults from bashrc's non-interactive part (NO_COLOR, PAGER=cat) are
# lifted first: they were for tool output, and this is a human's terminal.
if [ -t 0 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${BASH_EXECUTION_STRING:-}" ] &&
  [ -z "${WORKBENCH_PLAIN:-}" ] && command -v zsh >/dev/null 2>&1; then
  unset NO_COLOR PAGER GIT_PAGER
  export CLICOLOR=1
  exec zsh
fi

# --- plain interactive bash from here on -----------------------------------

# full mise activation (PATH updates on `cd`, per-project .mise.toml)
command -v mise >/dev/null && eval "$(mise activate bash)"

# badge in the Claude Code statusline (see home/claude/statusline.sh's SL_BADGE_CMD
# knob), so a session started here is identifiable if this repo is ever
# reused to stand up another VM.
export SL_BADGE_CMD='hostname -s'

# colour for human eyes only (see guard above); still single line, no git
# status in the prompt itself - keep this cheap, it runs on every prompt.
unset NO_COLOR
export CLICOLOR=1
PS1='\[\033[38;5;71m\]\u@\h\[\033[0m\]:\[\033[38;5;74m\]\w\[\033[0m\]\$ '
alias ls='ls --color=auto'
alias grep='grep --color=auto'

HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoredups
HISTTIMEFORMAT='%F %T '
shopt -s histappend checkwinsize
PROMPT_COMMAND='history -a'

alias ll='ls -la'
alias la='ls -A'
alias dc='docker compose'

# bash completion is useful for humans, harmless for agents
if ! shopt -oq posix && [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi
