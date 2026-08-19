#!/usr/bin/env bash
# Provision the agent VM. Runs INSIDE the VM as root (via sudo). Idempotent:
# re-run it any time to converge the machine on the current repo state.
#
#   sudo ./bootstrap.sh          # everything
#   sudo ./bootstrap.sh docker   # one section
#
# Sections are ordinary functions named step_<name>, executed in the order
# listed in STEPS. `make provision` rsyncs box/ to the VM and calls this.
set -euo pipefail

AGENT_USER="${AGENT_USER:-agent}"
# ai-hub: the operator's agent-behaviour repo (global CLAUDE.md, subagents,
# skills, hooks). It stays a separate repo; this VM only installs it.
AIHUB_REPO="${AIHUB_REPO:-https://github.com/msavdert/ai-hub.git}"
WORKBENCH_REPO="${WORKBENCH_REPO:-https://github.com/msavdert/workbench.git}"
AGENT_HOME="$(getent passwd "$AGENT_USER" | cut -d: -f6)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
files="$here/files"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

log() { printf '\n[bootstrap] == %s\n' "$*" >&2; }
die() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}
# Runs a command as the agent user with the env a real login would have,
# including the user-bus variables systemctl --user needs (linger keeps the
# user manager alive, but sudo does not set XDG_RUNTIME_DIR for us).
as_agent() {
  local uid
  uid="$(id -u "$AGENT_USER")"
  sudo -u "$AGENT_USER" -H env HOME="$AGENT_HOME" \
    XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    PATH="$AGENT_HOME/.local/bin:$AGENT_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin" "$@"
}
# install(1) wrapper that only reports when the file actually changed
put() { # put <mode> <src> <dst>
  local mode=$1 src=$2 dst=$3
  if [[ ! -f $dst ]] || ! cmp -s "$src" "$dst"; then
    install -D -m "$mode" "$src" "$dst"
    echo "  updated $dst"
  fi
}

[[ $EUID -eq 0 ]] || die "run as root (sudo)"
[[ -n $AGENT_HOME ]] || die "user $AGENT_USER does not exist"
. /etc/os-release
[[ $ID == ubuntu && $VERSION_CODENAME == noble ]] || die "expected Ubuntu 24.04 (noble), got $PRETTY_NAME"

# ---------------------------------------------------------------------------
step_system() {
  log "system: apt behaviour, needrestart, sudoers, limits, sysctl, journald, swap"
  # needrestart's interactive "which services to restart?" dialog blocks any
  # agent running apt. Restart automatically.
  install -d /etc/needrestart/conf.d
  put 0644 "$files/needrestart-agent.conf" /etc/needrestart/conf.d/99-agent.conf
  # `sudo apt install` from an agent must never open a debconf dialog.
  put 0440 "$files/sudoers-agent" /etc/sudoers.d/90-agent-env
  visudo -cf /etc/sudoers.d/90-agent-env >/dev/null
  put 0644 "$files/limits-agent.conf" /etc/security/limits.d/90-agent.conf
  put 0644 "$files/sysctl-agent.conf" /etc/sysctl.d/90-agent.conf
  sysctl -q --system >/dev/null
  install -d /etc/systemd/journald.conf.d
  put 0644 "$files/journald-agent.conf" /etc/systemd/journald.conf.d/90-agent.conf
  systemctl restart systemd-journald
  # motd noise (Ubuntu Pro adverts, news) is pure token waste on every login.
  if [[ -f /etc/default/motd-news ]]; then sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news; fi
  if command -v pro >/dev/null; then pro config set apt_news=false >/dev/null 2>&1 || true; fi
  chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true
  # 4 GiB swap: not for capacity (32 GiB RAM) but so a runaway build gets
  # slow instead of getting the agent's tmux session OOM-killed.
  if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
    # guard on "active", not "file exists": a half-finished earlier run must retry
    swapoff /swapfile 2>/dev/null || true
    rm -f /swapfile
    fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    echo "  created /swapfile (4G)"
  fi
  # ssh: keep sessions alive across mobile network hops.
  put 0644 "$files/sshd-agent.conf" /etc/ssh/sshd_config.d/90-agent.conf
  sshd -t && systemctl reload ssh
  timedatectl set-timezone Etc/UTC
}

# ---------------------------------------------------------------------------
step_apt() {
  log "apt: repositories (docker, mise) + base packages"
  install -d -m 0755 /etc/apt/keyrings
  local arch
  arch="$(dpkg --print-architecture)"

  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod 0644 /etc/apt/keyrings/docker.asc
  fi
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    >/etc/apt/sources.list.d/docker.list

  if [[ ! -f /etc/apt/keyrings/mise-archive-keyring.gpg ]]; then
    curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg
    chmod 0644 /etc/apt/keyrings/mise-archive-keyring.gpg
  fi
  echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$arch] https://mise.jdx.dev/deb stable main" \
    >/etc/apt/sources.list.d/mise.list

  apt-get update -qq
  apt-get full-upgrade -y -qq
  # One package per line, grouped; see docs/design.md for the reasoning.
  local pkgs=(
    # build toolchain: native node/python modules, rust crates, go cgo
    build-essential pkg-config cmake autoconf automake libtool
    libssl-dev libffi-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev
    libncurses-dev libxml2-dev libxslt1-dev libpq-dev libyaml-dev
    # vcs
    git git-lfs
    # editors and terminal multiplexer
    vim-nox tmux
    # search / files / text
    ripgrep fd-find jq tree ncdu moreutils bc file gettext-base
    # archives
    unzip zip p7zip-full xz-utils zstd bzip2
    # transfer / sync
    curl wget rsync ca-certificates gnupg openssl
    # network diagnostics
    dnsutils netcat-openbsd iputils-ping traceroute mtr-tiny net-tools
    iproute2 tcpdump nmap socat whois telnet
    # process / system diagnostics
    strace ltrace lsof psmisc procps sysstat iotop htop btop
    # python (uv handles project envs; system python for tooling)
    python3 python3-venv python3-dev python3-pip
    # database clients (servers run in docker)
    postgresql-client mysql-client redis-tools sqlite3
    # shell hygiene; zsh is the interactive hand-off target only (D5)
    shellcheck zsh
    # runtime managers / containers
    mise
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    # virtualization guest
    qemu-guest-agent
  )
  apt-get install -y -qq --no-install-recommends "${pkgs[@]}"
  apt-get autoremove -y -qq
  # Debian renames fd to fdfind; every tool and agent expects `fd`.
  ln -sf /usr/bin/fdfind /usr/local/bin/fd
}

# ---------------------------------------------------------------------------
step_docker() {
  log "docker: daemon config, group membership, cache janitor"
  put 0644 "$files/docker-daemon.json" /etc/docker/daemon.json
  usermod -aG docker "$AGENT_USER"
  systemctl enable --now docker >/dev/null
  systemctl restart docker
  put 0644 "$files/docker-prune.service" /etc/systemd/system/docker-prune.service
  put 0644 "$files/docker-prune.timer" /etc/systemd/system/docker-prune.timer
  systemctl daemon-reload
  systemctl enable --now docker-prune.timer >/dev/null
  docker version --format '  docker {{.Server.Version}}, compose ' | tr -d '\n'
  docker compose version --short
}

# ---------------------------------------------------------------------------
step_user() {
  log "user: shell environment, tmux, helper scripts"
  # lingering: user services (tmux/claude) survive logout and start at boot
  loginctl enable-linger "$AGENT_USER"
  install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0755 \
    "$AGENT_HOME/.local/bin" \
    "$AGENT_HOME/.claude" "$AGENT_HOME/work" "$AGENT_HOME/.config/systemd/user"
  install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 0700 "$AGENT_HOME/.config/op"
  put 0644 "$files/bashrc" "$AGENT_HOME/.bashrc"
  put 0644 "$files/bash_profile" "$AGENT_HOME/.bash_profile"
  put 0644 "$files/tmux.conf" "$AGENT_HOME/.tmux.conf"
  put 0755 "$files/agent-session" "$AGENT_HOME/.local/bin/agent-session"
  # installed but not enabled: needs a one-time interactive `claude auth login`
  put 0644 "$files/claude-remote.service" "$AGENT_HOME/.config/systemd/user/claude-remote.service"
  # per-project servers: claude-remote@<name> -> ~/work/<name>, via remote-add
  put 0644 "$files/claude-remote@.service" "$AGENT_HOME/.config/systemd/user/claude-remote@.service"
  put 0755 "$files/remote-add" "$AGENT_HOME/.local/bin/remote-add"
  put 0755 "$files/remote-rm" "$AGENT_HOME/.local/bin/remote-rm"
  put 0755 "$files/remote-ls" "$AGENT_HOME/.local/bin/remote-ls"
  as_agent systemctl --user daemon-reload 2>/dev/null || true
  # ~/.claude.json holds two one-time consents that otherwise need a TTY and
  # would keep claude-remote.service from starting: workspace trust for
  # ~/work and the "Enable Remote Control? (y/n)" dialog. Merge them in,
  # keeping everything else (oauth account, caches) intact.
  local cj="$AGENT_HOME/.claude.json"
  [[ -f $cj ]] || echo '{}' >"$cj"
  if ! jq -e --arg w "$AGENT_HOME/work" '.projects[$w].hasTrustDialogAccepted == true and .remoteDialogSeen == true and .hasCompletedOnboarding == true' "$cj" >/dev/null 2>&1; then
    jq --arg w "$AGENT_HOME/work" '.projects[$w] = ((.projects[$w] // {}) + {hasTrustDialogAccepted: true}) | .remoteDialogSeen = true | .hasCompletedOnboarding = true' "$cj" >"$cj.tmp" &&
      mv "$cj.tmp" "$cj" && echo "  updated $cj (trust + remote-control consent)"
  fi
  chmod 0600 "$cj"
  chown "$AGENT_USER:$AGENT_USER" "$cj"
  # Machine-level Claude memory: loaded in every session regardless of cwd.
  # Verified on 2026-08-17 that Claude Code reads /etc/claude-code/CLAUDE.md.
  put 0644 "$files/machine-CLAUDE.md" /etc/claude-code/CLAUDE.md
  chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.bashrc" "$AGENT_HOME/.bash_profile" \
    "$AGENT_HOME/.tmux.conf" "$AGENT_HOME/.gitconfig" "$AGENT_HOME/.config" "$AGENT_HOME/.local" "$AGENT_HOME/.claude"
}

# ---------------------------------------------------------------------------
step_home() {
  log "home: clone/update $WORKBENCH_REPO and run home/install.sh box (as $AGENT_USER)"
  # The links must point at a durable checkout, not at the rsync staging dir
  # (~/workbench-box is replaced on every provision), so home/ is installed
  # from the agent's own clone of this repository. Public repo: no token
  # needed; login shell anyway so PATH and MISE_ENV are the agent's own.
  local dir="$AGENT_HOME/work/workbench"
  if [[ -d $dir/.git ]]; then
    as_agent bash -lc "git -C '$dir' pull -q --ff-only" || echo "  WARN: workbench pull failed (local changes?); using existing checkout"
  else
    as_agent bash -lc "git clone -q '$WORKBENCH_REPO' '$dir'"
  fi
  as_agent bash -lc "'$dir/home/install.sh' box" | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
step_tools() {
  log "tools: mise-managed runtimes and CLIs (as $AGENT_USER)"
  # both are symlinks into ~/work/workbench/home/mise (step_home); login
  # shell so MISE_ENV=box (from ~/.config/workbench/env via bashrc) selects
  # config.box.toml - without it only the shared base would be installed
  as_agent mise trust -q "$AGENT_HOME/.config/mise/config.toml"
  as_agent mise trust -q "$AGENT_HOME/.config/mise/config.box.toml"
  # 49 tools resolve "latest" through the GitHub API, which rate-limits
  # anonymous callers to 60/h (seen: 403 mid-install). With the op token in
  # the login shell, `opwith git` injects GITHUB_TOKEN into this one process
  # (home/op-env/git.env); without it, plain mise for a fresh box.
  as_agent bash -lc 'if op whoami >/dev/null 2>&1; then opwith git mise install -y; else mise install -y; fi && mise reshim'
  log "tools: Claude Code (native installer, self-updating)"
  if [[ ! -x $AGENT_HOME/.local/bin/claude ]]; then
    as_agent bash -c 'curl -fsSL https://claude.ai/install.sh | bash' >/dev/null
  fi
  as_agent bash -lc 'mise ls --current' 2>/dev/null | awk '{printf "  %-40s %s\n", $1, $2}'
  printf '  claude %s\n' "$(as_agent "$AGENT_HOME/.local/bin/claude" --version 2>/dev/null || echo '(not installed)')"
}

# ---------------------------------------------------------------------------
step_aihub() {
  log "ai-hub: clone/update $AIHUB_REPO and run its install.sh (as $AGENT_USER)"
  local dir="$AGENT_HOME/work/ai-hub"
  # login shell so ~/.bashrc loads the op token the git credential helper needs
  if [[ -d $dir/.git ]]; then
    as_agent bash -lc "git -C '$dir' pull -q --ff-only" || echo "  WARN: ai-hub pull failed (local changes?); using existing checkout"
  else
    as_agent bash -lc "git clone -q '$AIHUB_REPO' '$dir'"
  fi
  # install.sh links runtime/claude/* into ~/.claude and self-checks the gate;
  # it prints its own OK/WARN lines.
  as_agent bash -lc "cd '$dir' && bash install.sh" | sed 's/^/  /'
}

# ---------------------------------------------------------------------------
step_remotes() {
  log "remotes: Remote Control environments from box/remotes.list (as $AGENT_USER)"
  local list="$here/remotes.list" line
  [[ -f $list ]] || {
    echo "  no remotes.list"
    return 0
  }
  # a fresh VM has ~/work/workbench only if listed here; login shell for the op token
  grep -vE '^\s*(#|$)' "$list" | while read -r line; do
    # shellcheck disable=SC2086
    as_agent bash -lc "remote-add $line" | sed 's/^/  /'
  done
}

# ---------------------------------------------------------------------------
step_verify() {
  log "verify"
  local ok=1
  check() { if "$@" >/dev/null 2>&1; then echo "  ok   $*"; else
    echo "  FAIL $*"
    ok=0
  fi; }
  check systemctl is-active docker
  check systemctl is-active qemu-guest-agent
  check as_agent docker ps
  # one command per check: `command -v a b` succeeds if ANY resolves
  for c in mise node gh op uv go bun omp claude jq rg fd tmux docker; do
    check as_agent bash -lc "command -v $c"
  done
  check as_agent bash -lc 'sudo -n true'
  check bash -c 'swapon --show=NAME --noheadings | grep -qx /swapfile'
  check test -f /etc/needrestart/conf.d/99-agent.conf
  check test -L "$AGENT_HOME/.claude/CLAUDE.md"
  check grep -q boundary-gate.sh "$AGENT_HOME/.claude/settings.json"
  check as_agent bash -lc "'$AGENT_HOME/work/workbench/home/install.sh' --check box"
  # shellcheck disable=SC2016 # MISE_ENV must expand in the agent's login shell
  check as_agent bash -lc 'test "$MISE_ENV" = box'
  check command -v zsh
  check test -f /etc/claude-code/CLAUDE.md
  check test -f /etc/claude-code/CLAUDE.md
  [[ $ok == 1 ]] || die "verification failed"
}

STEPS=(system apt docker user home tools aihub remotes verify)
if [[ $# -gt 0 ]]; then STEPS=("$@"); fi
for s in "${STEPS[@]}"; do
  declare -F "step_$s" >/dev/null || die "unknown step: $s"
  "step_$s"
done
log "done"
