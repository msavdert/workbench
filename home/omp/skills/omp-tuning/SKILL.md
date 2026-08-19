---
name: omp-tuning
description: Use when changing this OMP setup itself - editing home/omp/config.yml, models.yml, keybindings.yml, adding or overriding a subagent under home/omp/agents/, writing a new skill, or deciding whether guidance belongs in AGENTS.md, RULES.md, WATCHDOG.md or APPEND_SYSTEM.md, plus how to verify the change took effect.
---

# Tuning this OMP setup

OMP's user agent directory is its **default**, `~/.omp/agent/`. There is no
`PI_CODING_AGENT_DIR` anywhere in this repo, and there must not be: the variable
relocates the whole agent base (config, auth store, sessions), and pointing it at
a repo checkout would break the container, which never clones this repo.

The tracked source of truth is `home/omp/`, copied into the image at
`/home/dev/.omp/agent/` by the config layer of the `Dockerfile`. So: **edit the
repo, rebuild the image, pull on the VPS** (`skill://devbox-image`,
`skill://vps-deploy`). Editing `~/.omp/agent/*` inside a running container works
for a quick experiment and is destroyed by the next image pull - that directory
is not one of the three persisted volumes.

## Which file owns what

| Path in repo | Lands at | Owns |
|---|---|---|
| `home/omp/config.yml` | `~/.omp/agent/config.yml` | every setting: `modelRoles`, `task.agentModelOverrides`, `tools.approvalMode`, `memory`, `theme`, ... |
| `home/omp/models.yml` | `~/.omp/agent/models.yml` | custom providers/models, aliases, per-model overrides. Not settings. |
| `home/omp/keybindings.yml` | `~/.omp/agent/keybindings.yml` | key remaps only. Flat mapping of action id -> chord; there is **no** `keybindings` block in `config.yml`. |
| `home/omp/agents/<name>.md` | `~/.omp/agent/agents/<name>.md` | one subagent definition per file (frontmatter `name` + `description` required, body = its system prompt). |
| `home/omp/skills/<name>/SKILL.md` | `~/.omp/agent/skills/<name>/SKILL.md` | procedures like this one. |

### The four prompt files - they are not interchangeable

| File | Loaded as | Use it for |
|---|---|---|
| `AGENTS.md` | user-level **context file**, injected once into the opening `<context>` block | durable background: what this repo is, conventions, where things live. Costs context budget once. |
| `RULES.md` | **always-apply sticky rule**, re-attached near the current turn | the handful of hard requirements that must survive a long conversation ("never commit unless asked"). Keep it short. Frontmatter cannot make it non-sticky. |
| `WATCHDOG.md` | appended to the **advisor** system prompt only | review priorities for the second-opinion model. Never reaches the primary agent. |
| `APPEND_SYSTEM.md` | extra **system prompt block** after the defaults | instructions that must be part of the system prompt itself. |

Deliberately absent: `SYSTEM.md`. It *replaces* the default system-prompt block,
which is where the discovered skills list, the rulebook summary and the tool
guidance are generated. Using it would silently make every skill in
`home/omp/skills/` invisible to the model. Always prefer `APPEND_SYSTEM.md`.

## Changing a model assignment

Roles first, in `config.yml`:

```yaml
modelRoles:
  default: anthropic/claude-opus-5
  smol: google-antigravity/gemini-3.7-flash:high
```

Per-subagent model, also in `config.yml`:

```yaml
task:
  agentModelOverrides:
    scout: google-antigravity/gemini-3.7-flash:high
    librarian: synthetic/hf:moonshotai/Kimi-K3
```

Precedence at spawn time is `task.agentModelOverrides[name]` > agent frontmatter
`model` > the parent session's model. The override wins, which is exactly why it
is the right lever.

**Synthetic concurrency rule.** The Synthetic provider allows one concurrent
request *per model*; a second request to the same model queues behind the first,
while different models run fully in parallel. Never point two roles that can run
concurrently (say `audit` and `librarian`) at the same Synthetic model, or the
fan-out serializes.

## The bundled-agent trap

Bundled agents are `scout`, `sonic`, `task`, `reviewer`, `librarian`, `designer`.
Discovery merges project `.omp/agents`, then `~/.omp/agent/agents`, then bundled
definitions, **first-wins by exact name**.

Creating `home/omp/agents/scout.md` therefore does not tweak `scout` - it
**replaces** the bundled definition entirely, throwing away its tuned prompt and
its `blocking: true` / `read-summarize: false` behavior. A file named after a
bundled agent that only sets `model:` is a strict downgrade.

- Want a different model for a bundled agent -> `task.agentModelOverrides` in
  `config.yml`. Nothing else.
- Want different behavior -> add a **new** name (`audit.md`), do not shadow a
  bundled one.
- Name matching is case-sensitive, so `Scout` and `scout` are different agents,
  which is a confusing bug, not a workaround.

## Adding a skill

Layout is exactly one level deep:

```
home/omp/skills/<skill-name>/SKILL.md
```

`home/omp/skills/group/<skill>/SKILL.md` is **not discovered**. Frontmatter
must include `name` and `description`; the native `.omp` provider requires a
description and silently drops a skill without one. The description is the only
thing the model matches against, so write it as a trigger sentence ("Use
when ..."), not a title. Keep companion files inside the same directory and
reference them as `skill://<name>/<relative-path>`.

## Arrays replace, they do not merge

Every array-typed setting (`disabledProviders`, `enabledModels`, `cycleOrder`,
`extensions`, ...) is replaced wholesale by the higher-precedence layer. Objects
deep-merge; scalars and arrays do not. If a project `.omp/config.yml` sets
`disabledProviders: [github]`, the global list is gone inside that project - not
extended. Always write the complete desired array in the layer that sets it.

Settings layer order, lowest to highest: global `~/.omp/agent/config.yml`, then
project `<cwd>/.omp/config.yml`, then `--config` overlays. Only the global file
is written by `omp config set` and `/settings`.

## Runtime state is not configuration

OMP creates these in the same directory and none of them belong in git:
`agent.db*`, `history.db*`, `models.db*`, `sessions/`, `terminal-sessions/`,
`last-changelog-version`. They must stay covered by `.gitignore`.

Credentials live in `agent.db` (anthropic OAuth, google-antigravity OAuth, the
synthetic API key) and are deliberately **not** baked into the image and not
persisted by a volume. Auth is disposable and recoverable, exactly like `gh`
auth: re-run the login after a rebuild. Never try to bake a token into
`home/omp/` - that would violate the no-secrets-in-the-repo invariant
(`skill://add-secret`).

## Verify a change took effect

```bash
omp config path                       # active agent directory - must be ~/.omp/agent
omp config get modelRoles              # whole record; sub-keys are NOT addressable
omp config list --json                # everything, machine-readable
omp models                            # provider-grouped tables of concrete models
```

Unknown keys make `omp config get` exit non-zero, which is the fastest way to
catch an invented setting name. It is also a trap: **record-typed settings are
not addressable by sub-key**. `omp config get modelRoles.default` does not print
the default role, it exits non-zero with `Unknown setting`, which reads exactly
like a config that failed to load. The same applies to
`task.agentModelOverrides.<name>` and `retry.fallbackChains.<role>`. Ask for the
whole record and read the JSON. Inside a session:

- `/agents` - the resolved agent roster, including which model each one uses
- `/settings` - the same merged settings the CLI prints

Note that `omp` is invoked directly, with no `opwith` wrapper: `ai.env` sets
`ANTHROPIC_BASE_URL` to OpenRouter, which would reroute OMP's own Anthropic
OAuth and break the architect role. Its only file-shaped secret comes from
`mise run omp:auth`.

A YAML mistake is not always loud: a bad `models.yml` keeps the registry running
on built-in models and only surfaces the error in the UI, so verify with
`omp models` rather than assuming a clean start means a clean config.

## Ship it

`home/omp/` is inside the image, so a change is not real until:

```bash
docker build -t devbox-test .    # local check
git commit -am "feat(omp): ..." && git push
ssh vps 'cd ~/devbox && docker compose pull && docker compose up -d'
```

And per `CLAUDE.md` invariant 7, update the doc that describes the behaviour in
the same commit.
