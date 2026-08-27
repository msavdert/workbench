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
# Same idea for an arbitrary user: step_hermes runs commands as the isolated
# family-gateway user too. No mise shims on purpose - only the agent user is
# mise-managed.
as_user() { # as_user <user> <cmd...>
  local user=$1 uid uhome
  shift
  uid="$(id -u "$user")"
  uhome="$(getent passwd "$user" | cut -d: -f6)"
  # --chdir: never inherit bootstrap's cwd (the rsync staging dir lives in
  # the agent home, which other users cannot read - uv's project discovery
  # walks up from cwd and dies on the permission boundary)
  sudo -u "$user" -H env --chdir="$uhome" HOME="$uhome" \
    XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    PATH="$uhome/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
}
# install(1) wrapper that only reports when the file actually changed.
# Mode is converged even when content matches: a hand chmod on sudoers or
# sshd drop-ins must not survive a re-run.
put() { # put <mode> <src> <dst>
  local mode=$1 src=$2 dst=$3
  if [[ ! -f $dst ]] || ! cmp -s "$src" "$dst"; then
    install -D -m "$mode" "$src" "$dst"
    echo "  updated $dst"
  elif ((8#$(stat -c %a "$dst") != 8#$mode)); then
    chmod "$mode" "$dst"
    echo "  mode $mode $dst"
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
  # Images without openssh-server (OrbStack reaches the machine its own way)
  # get it in step_apt; the config above is then read on first start.
  # sshd -t wants the privsep dir, which a socket-activated (idle) sshd has not
  # created yet; try-reload only touches a running service.
  if command -v sshd >/dev/null; then
    mkdir -p /run/sshd
    sshd -t
    systemctl try-reload-or-restart ssh
  fi
  # Terminals newer than the image's ncurses (Ghostty) have no terminfo entry
  # here; without one zle redraws the whole line and every keystroke shows
  # twice over ssh. tic overwrites in place, so re-runs are harmless.
  tic -x -o /etc/terminfo "$files/xterm-ghostty.terminfo"
  # The owner works on New York time (D15); the RTC stays in UTC and
  # systemd-timesyncd (the 24.04 default, ntp.ubuntu.com) keeps the clock.
  timedatectl set-timezone America/New_York
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
    # ssh on port 22 everywhere, even where the image relies on another path
    openssh-server
    # virtualization guest; the unit only starts where the virtio port exists
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
  # Restart only on a real daemon.json change: live-restore keeps containers
  # up, but an unconditional restart still kills in-flight builds on every
  # provision run.
  local before
  before=$(md5sum /etc/docker/daemon.json 2>/dev/null || true)
  put 0644 "$files/docker-daemon.json" /etc/docker/daemon.json
  usermod -aG docker "$AGENT_USER"
  systemctl enable --now docker >/dev/null
  if [[ $before != "$(md5sum /etc/docker/daemon.json)" ]]; then
    systemctl restart docker
  fi
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
  # Only what exists: .gitconfig and .claude appear in step_home, which runs later.
  local p
  for p in .bashrc .bash_profile .tmux.conf .gitconfig .config .local .claude; do
    if [[ -e "$AGENT_HOME/$p" ]]; then chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/$p"; fi
  done
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
  # the human shell's caches (home/zsh): completion files and init snippets
  # for the tools just installed, and the two zsh plugins. Same two scripts
  # mac/setup.sh runs; the login shell gives them the mise PATH.
  log "tools: zsh completion cache and plugins (as $AGENT_USER)"
  as_agent bash -lc 'zsh ~/.config/zsh/regen-completions.zsh && ~/.config/zsh/install-plugins.sh' | sed 's/^/  /'
  log "tools: Claude Code (native installer, self-updating)"
  if [[ ! -x $AGENT_HOME/.local/bin/claude ]]; then
    as_agent bash -c 'curl -fsSL https://claude.ai/install.sh | bash' >/dev/null
  fi
  # herdr's hooks are NOT part of `mise install`: each harness needs its own
  # `herdr integration install`, and until 2026-08-19 that lived only in a
  # manual `mise run herdr:integrations` that nobody ran after a rebuild - the
  # box rebuilt that morning had none of the three. Nothing complained: the
  # Claude hook is registered behind an `[ -x ]` guard, so its absence fails
  # silently, and `install.sh --check` cannot see it either because those files
  # belong to herdr rather than to this repository. Calling the repo's own task
  # keeps one definition of the step; it re-runs home/install.sh last, which is
  # how settings.json is taken back from herdr's edit.
  log "tools: herdr integrations for claude, omp and agy (as $AGENT_USER)"
  as_agent bash -lc 'mise run herdr:integrations' | sed 's/^/  /'
  as_agent bash -lc 'mise ls --current' 2>/dev/null | awk '{printf "  %-40s %s\n", $1, $2}'
  printf '  claude %s\n' "$(as_agent "$AGENT_HOME/.local/bin/claude" --version 2>/dev/null || echo '(not installed)')"
}

# ---------------------------------------------------------------------------
step_remotes() {
  log "remotes: repositories under ~/work from box/remotes.list (as $AGENT_USER)"
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
step_hermes() {
  log "hermes: two isolated Telegram gateways (agent: personal+vault, savdert: family)"
  # The family gateway runs as its own OS user: no sudo, no 1Password token,
  # and /home/agent (0750) is unreadable to it - the personal vault stays
  # filesystem-isolated from the shared family bot (docs/reference/hermes.md).
  if ! id savdert &>/dev/null; then
    useradd -m -s /bin/bash savdert
    echo "  created user savdert"
  fi
  chmod 0750 /home/savdert
  # user services survive logout and start at boot
  loginctl enable-linger savdert

  local user uhome
  for user in agent savdert; do
    uhome="$(getent passwd "$user" | cut -d: -f6)"

    # `hermes --version` exercises the venv, so a half-finished install (a
    # launcher without working deps) triggers a repair run, not a skip.
    # Plain `bash -c` everywhere in this step, never a login shell: the
    # agent's login env puts mise's uv (0.12.x, newer) ahead of hermes'
    # bundled uv, and hermes' uv.lock (relative exclude-newer-span) makes
    # the newer uv re-resolve and refuse `uv sync --locked`. as_user's PATH
    # is mise-free on purpose.
    if ! as_user "$user" bash -c 'hermes --version' >/dev/null 2>&1; then
      log "hermes: installing for $user (this downloads node, python, deps)"
      if [[ $user == savdert ]]; then
        # browserless: the family bot needs no Playwright/Chromium, and the
        # savdert user has no sudo for the system libraries anyway
        as_user "$user" bash -c \
          'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-browser' \
          </dev/null >/dev/null
      else
        as_user "$user" bash -c \
          'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash' \
          </dev/null >/dev/null
      fi
    fi
    install -d -o "$user" -g "$user" -m 0700 "$uhome/.hermes"

    # Chromium system libraries for the agent gateway's browser stack (the
    # savdert install is browserless). Cheap guard: libnss3 is the canonical
    # first missing dependency.
    if [[ $user == agent ]] && ! dpkg -s libnss3 >/dev/null 2>&1; then
      # shellcheck disable=SC2016 # $HOME must expand in the target user's shell
      as_user "$user" bash -c \
        'cd ~/.hermes/hermes-agent && sudo env PATH="$HOME/.hermes/node/bin:$PATH" npx playwright install-deps chromium' >/dev/null
      echo "  installed chromium system libraries"
    fi

    # .env: rendered from the tracked op:// template on EVERY provision
    # (secret rotation = rotate in 1Password, re-provision). op runs as the
    # agent user - its login shell has the service-account token - and the
    # result is installed root-side, so savdert itself never touches op.
    local tmp
    install -d -o "$AGENT_USER" -g "$AGENT_USER" "$AGENT_HOME/.cache"
    tmp="$AGENT_HOME/.cache/hermes-env.$user.$$"
    as_agent bash -lc "op inject -f -i '$files/hermes/env.$user.tpl' -o '$tmp'" >/dev/null ||
      die "op inject failed for hermes env.$user.tpl"
    install -o "$user" -g "$user" -m 0600 "$tmp" "$uhome/.hermes/.env"
    rm -f "$tmp"

    # config.yaml and SOUL.md are seeded ONCE (the installer writes its own
    # defaults; the running agent owns them afterwards). The marker file is
    # the memory of that first seeding.
    if [[ ! -f "$uhome/.hermes/.workbench-seeded" ]]; then
      install -o "$user" -g "$user" -m 0644 "$files/hermes/config.$user.yaml" "$uhome/.hermes/config.yaml"
      install -o "$user" -g "$user" -m 0644 "$files/hermes/SOUL.$user.md" "$uhome/.hermes/SOUL.md"
      as_user "$user" touch "$uhome/.hermes/.workbench-seeded"
      echo "  seeded config.yaml + SOUL.md for $user"
    fi
    # fill schema defaults / migrate after an update; harmless when current.
    # </dev/null everywhere below: `make provision` runs bootstrap under a
    # tty, so a hermes subcommand that decides to ask something would block
    # forever with its prompt swallowed by the >/dev/null.
    as_user "$user" bash -c 'hermes doctor --fix' </dev/null >/dev/null 2>&1 || true

    # Skills Hub: `skills list` creates ~/.hermes/skills/.hub on its first
    # run. Without it doctor warns and hub-installed skills have nowhere to
    # land; the guard keeps this a first-install action only.
    [[ -d "$uhome/.hermes/skills/.hub" ]] ||
      as_user "$user" bash -c 'hermes skills list' </dev/null >/dev/null 2>&1 || true

    # hermes writes ~/.config/systemd/user/hermes-gateway.service itself.
    # Both install questions (start now? start on login?) must be answered on
    # the command line - without them the prompts come before the "already
    # installed" check, so even a converged box hangs. The unit is enabled
    # and started below, which is why --no-start-now is the right answer.
    as_user "$user" bash -c \
      'hermes gateway install --no-start-now --start-on-login' </dev/null >/dev/null 2>&1 || true
    as_user "$user" systemctl --user daemon-reload
    as_user "$user" systemctl --user enable --now hermes-gateway >/dev/null 2>&1 ||
      echo "  WARN: hermes-gateway not active for $user yet (check journalctl --user -u hermes-gateway)"
  done
}

# ---------------------------------------------------------------------------
step_vault() {
  log "vault: nightly sessions digest + compile timers against ~/work/vault"
  if [[ -d $AGENT_HOME/work/vault/.git ]]; then
    # the vault's gitleaks pre-commit gate is a tracked .githooks dir; the
    # hooksPath setting is per-clone and must be converged here
    as_agent git -C "$AGENT_HOME/work/vault" config core.hooksPath .githooks
  else
    echo "  WARN: ~/work/vault missing; step_remotes should have cloned it"
  fi
  local unit
  for unit in vault-compile.service vault-compile.timer \
    vault-sessions.service vault-sessions.timer; do
    put 0644 "$files/$unit" "$AGENT_HOME/.config/systemd/user/$unit"
    chown "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.config/systemd/user/$unit"
  done
  as_agent systemctl --user daemon-reload
  # sessions digest first (02:50), compiler second (03:00): the digest must be
  # in yesterday's daily log before the compiler distills it
  for unit in vault-sessions.timer vault-compile.timer; do
    as_agent systemctl --user enable --now "$unit" >/dev/null 2>&1 ||
      echo "  WARN: $unit not active"
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
  # Ubuntu 24.04 socket-activates sshd: the service is dead until the first client
  check bash -c 'systemctl is-active ssh || systemctl is-active ssh.socket'
  # qemu-guest-agent's unit is conditioned on this port; OrbStack has none
  check bash -c 'test ! -e /dev/virtio-ports/org.qemu.guest_agent.0 || systemctl is-active qemu-guest-agent'
  check as_agent docker ps
  # one command per check: `command -v a b` succeeds if ANY resolves
  for c in mise node gh op uv go bun omp agy herdr claude jq rg fd tmux docker; do
    check as_agent bash -lc "command -v $c"
  done
  check as_agent bash -lc 'sudo -n true'
  check bash -c 'swapon --show=NAME --noheadings | grep -qx /swapfile'
  check test -f /etc/needrestart/conf.d/99-agent.conf
  check test -L "$AGENT_HOME/.claude/CLAUDE.md"
  check grep -q boundary-gate.sh "$AGENT_HOME/.claude/settings.json"
  # the three herdr integration hooks; each fails open on its own, so without
  # a check here their absence after a rebuild is invisible (it was, once)
  check test -x "$AGENT_HOME/.claude/hooks/herdr-agent-state.sh"
  check test -d "$AGENT_HOME/.omp/agent/extensions"
  check test -f "$AGENT_HOME/.gemini/config/hooks.json"
  check as_agent bash -lc "'$AGENT_HOME/work/workbench/home/install.sh' --check box"
  # shellcheck disable=SC2016 # MISE_ENV must expand in the agent's login shell
  check as_agent bash -lc 'test "$MISE_ENV" = box'
  check command -v zsh
  check test -f /etc/claude-code/CLAUDE.md
  # hermes gateways: one per user, isolated (docs/reference/hermes.md)
  check as_agent bash -lc 'systemctl --user is-active hermes-gateway'
  check as_user savdert bash -lc 'systemctl --user is-active hermes-gateway'
  check as_user savdert bash -lc 'command -v hermes'
  # the family user must NOT see the agent home (vault isolation)
  check sudo -u savdert bash -c '! test -r /home/agent/work'
  # vault: clone present, nightly compile armed
  check test -d "$AGENT_HOME/work/vault/.git"
  check as_agent bash -lc 'systemctl --user is-active vault-compile.timer'
  [[ $ok == 1 ]] || die "verification failed"
}

STEPS=(system apt docker user home tools remotes hermes vault verify)
if [[ $# -gt 0 ]]; then STEPS=("$@"); fi
for s in "${STEPS[@]}"; do
  declare -F "step_$s" >/dev/null || die "unknown step: $s"
  "step_$s"
done
log "done"
