---
name: add-secret
description: Use when a command needs a new credential, token or API key - covers storing it in the dotfiles 1Password vault, adding an op:// reference to home/op-env/*.env, wrapping the consumer with opwith, auditing that no value was committed, and the rotate-first recovery path after a leak.
---

# Adding a secret

The rule (AGENTS.md hard rule 1): **no secret is ever exported into the shell
environment.** Values live in one process and die with it. Files in
`home/op-env/` contain `op://` references only, which is why they are safe to
commit (`CLAUDE.md` invariant 2).

## Procedure

### 1. Store the value in 1Password

Put it in the **`dotfiles`** vault. Nothing else in this setup reads any other
vault, and the box's service account is scoped read-only to that vault alone.

Note the reference path shape: `op://<vault>/<item>/<field>`, e.g.
`op://dotfiles/OpenRouter/generaltoken`.

### 2. Add a reference line to the right env file

Existing files:

| File | Purpose | Consumers |
|---|---|---|
| `home/op-env/ai.env` | AI tooling credentials | `claude()`, `kilocode()` wrappers in `home/zsh/.zshrc` |
| `home/op-env/git.env` | GitHub tokens for non-interactive `git`/`gh` | `opwith git <cmd>` |

Add to whichever file the consuming command already uses, or create a new
`home/op-env/<name>.env` - `opwith <name>` picks up any file in
`~/.config/op-env/`. Match the existing header-comment style.

`omp` is deliberately NOT wrapped in `opwith` — see the `omp-tuning` skill. Its
one file-shaped secret is materialised by the `omp:auth` mise task instead, so
its reference lives in `home/mise/config.box.toml`, not here:

```ini
op://dotfiles/Synthetic/credential
```

Non-secret settings (base URLs, model names) may sit in the same file as literal
values; `ai.env` already does this with `ANTHROPIC_BASE_URL`.

The directory is `op-env`, never `op`: `~/.config/op` is the 1Password CLI's own
state directory (`config`, `op-daemon.sock`) and symlinking over it breaks `op`
entirely.

### 3. Wire the consumer

Either call it directly:

```bash
opwith ai mytool --flag
```

or, if the command is used interactively every day, add a thin wrapper next to
the existing ones in `home/zsh/.zshrc`, inside the
`(( $+commands[op] )) && [[ -d $OP_ENV_DIR ]]` guard:

```zsh
mytool() { opwith ai mytool "$@"; }
```

These cannot recurse: `op run` execs the binary directly via PATH lookup without
going through a shell, so the zsh function never applies to the child.

`opwith` itself resolves `$OP_ENV_DIR/<name>.env` and runs
`op run --no-masking --env-file=<file> -- "$@"`. `--no-masking` is deliberate:
masking corrupts interactive TUI redraws. Drop the flag for CI-style scripts.

**Never** add `export MYTOOL_TOKEN=...` or an eager `op read` to `.zshrc`. That
is invariant 2, and it costs a network round trip on every zellij pane, every
`ssh dev` and every `exec zsh`.

### 4. When the secret must become a file

Some tools cannot take an env var. The accepted pattern is an on-demand mise
task, like `kube:homelab` in `home/mise/config.box.toml`:

```toml
[tasks."kube:homelab"]
run = """
mkdir -p ~/.kube ~/.talos
op read "op://dotfiles/texts/homelab-kubeconfig"  > ~/.kube/config
chmod 600 ~/.kube/config
"""
```

Materialize on demand, write into a persisted volume path (`~/.kube` is one of
the three named volumes), `chmod 600`, never into the repo.

### 5. Commit - reference, not value

```bash
git diff --cached -- home/op-env/
```

Every added line must carry the `op://` prefix. This is the last cheap moment to
catch a mistake.

## Authentication behind it

- **the box:** `OP_SERVICE_ACCOUNT_TOKEN`, pushed to `~/.config/op/env` by
  `make secrets`. It is the one secret that exists as plaintext somewhere,
  and the only one the box's shells depend on.
- **macOS:** the 1Password desktop app over its local socket, unlocked with
  Touch ID. No token on disk. `op signin` once per session if prompted.

Verify resolution:

```bash
op whoami
opwith ai env | grep -c OPENROUTER_API_KEY   # 1 inside the wrapped process
```

## Auditing

On the box or the mac:

```bash
env | grep -iE 'token|key|secret'                                 # must print nothing
git log -p -- home/op-env/ | grep -E '(sk)-|(ghp)_|github_pat_'   # must print nothing (grouped so this line itself never trips a secret grep)
```

The second one is worth running every few months (it is also part of the routine
health check in `docs/06-maintenance.md`). This repo's history is clean; a single
careless commit changes that permanently, and rewriting published git history is
far more painful than rotating a token.

## If a secret leaks

Order matters.

1. **Rotate it first.** In 1Password, revoke and reissue. A rotated secret in a
   public commit is harmless; a scrubbed history containing a live secret is not,
   because clones and forks keep the old objects.
2. Update the vault item. The `op://` reference does not change, so no repo edit
   is needed unless the field name changed.
3. Only then consider git history. Usually the answer is "leave it" - the value
   is already dead.
4. If the leaked value was `OP_SERVICE_ACCOUNT_TOKEN`, it invalidates everything.
   Follow `docs/06-maintenance.md`:

   ```bash
   # 1Password -> Developer -> Service Accounts -> rotate
   make secrets                  # re-reads the vault, pushes the new
                                  # OP_SERVICE_ACCOUNT_TOKEN to ~/.config/op/env
   ssh agent-vm-ssh op whoami     # verify
   ```

   Do this also if the box is ever compromised or the token is older than a
   year. It is cheap.

## Not applicable

- **git push/pull needs no secret in the environment.** `home/git/config`
  ships a credential helper that resolves op://dotfiles/GitHub/admintoken
  itself on demand, so the box authenticates without an SSH key and
  without depending on gh auth login's machine-local OAuth session.
- **SSH keys** live in 1Password. On the Mac its native SSH agent serves them
  (`mac/ssh/config.macos`); no private key file exists there. On the box
  `mise run ssh:sync` (home/mise/config.box.toml) loads the keys tagged
  `ssh-host` into the running ssh-agent and writes only public keys and
  host stanzas to `~/.ssh/`.
