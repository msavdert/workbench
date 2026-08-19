# Skill authoring conventions

Applies to every skill in this directory, not injected per-skill. When
writing a new skill, check this file first.

## Content placement: system prompt vs. skill

If a piece of information is needed regardless of the task, it belongs in
`CLAUDE.md` or the agent's system prompt. If it is only needed for some
tasks, it belongs in a skill — skills are pulled into context on demand,
not paid for on every turn. A skill whose content is actually needed on
every task is misplaced; move it up.

## Self-documenting on blocker

When a skill's procedure hits a blocker its current instructions do not
cover, update the skill file itself before moving on — not just a
one-off workaround in the session. The next run (your own, or someone
else's) should not hit the same blocker again. This is how
`youtube-whisper-transcriber` and `oss-project-eval` are meant to be
maintained: the skill file is the accumulated fix history, not a static
spec written once.

**Extract the principle, not the instance.** When updating a skill in
response to a specific failure, write down the general rule the failure
revealed — not a literal patch for that one case. "Never mention pricing
in the first line" is an instance; "if the user is venting, don't pitch"
is the principle. A skill file that only accumulates literal patches
turns into a brittle if/then list that fights itself; one line for the
wrong case doesn't compose with the next fix. Ask, before writing the
edit: would this line still be correct for a case that looks nothing
like the one that triggered it?

## Structure: current truth in SKILL.md, history in references/

`SKILL.md` is loaded whole every time the skill triggers, so it states only
what is true today: when to use, the rules with a one-line reason each, the
procedure, the templates. Corrections ("this skill previously said..."),
benchmark tables, incident narratives and troubleshooting go under
`references/` with a pointer from SKILL.md; the model reads them only when
that situation arises. The fix history the section above asks for still
accumulates - in the skill directory, not in the part paid on every trigger.

Acceptance, checked before a skill is linked anywhere:

| Check | Why |
|---|---|
| `description` says what it does, when to use it, and names the trigger words or thresholds; under 1024 characters | Triggering is decided from the description alone; the body is not read until after |
| SKILL.md under ~200 lines, no duplicated instruction, no "correction" or dated changelog prose | Every line is paid on every trigger; a correction makes the model read the wrong claim first |
| No project-specific paths or file names in a globally linked skill | The model will write to files that do not exist, or skip the rule |
| One unambiguous decision table for anything the model must choose (model, tool, mode) | Experiment 009: three ways of stating the model policy produced three different choices |
| Deterministic checks are scripts, not prose | "Spot-check the numbers" did not make a reader recompute a product; a rule that says "recompute derived numbers" did |
| `evals/evals.json` with 3-4 realistic prompts and a programmatic grader | A skill tested with one prompt is untested |

## Procedure: changing a skill

Measured in `lab/experiments/009-skill-creator/`; the loop is Anthropic's
`skill-creator`, fetched when needed rather than kept resident:

```bash
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/anthropics/skills "$SCRATCH/anthropic-skills"
git -C "$SCRATCH/anthropic-skills" sparse-checkout set skills/skill-creator
```

1. Snapshot the skill directory before editing (`cp -r`).
2. Run every prompt in `evals/evals.json` twice against the snapshot with a
   fresh subagent each; save `timing.json` from the task notification (it is
   not persisted anywhere else) and grade with the skill's `evals/grade.py`.
   Read every assertion that passes on the baseline and surprises you: it is
   more likely a grader bug than a strength.
3. Edit. Re-run the same prompts against the new version. Aggregate:
   `python -m scripts.aggregate_benchmark <workspace>/iteration-N --skill-name <name>`
   from the skill-creator directory.
4. Land the change only if pass rate did not drop and tokens per run did not
   rise without a reason you can name. Record the numbers in the commit.

---
Source: Anthropic Applied AI talk "Tool, skill, or subagent: Decomposing
an agent", Claude Code team talk "Stop babysitting your agents" (both
analyzed 2026-08-06), and Warp's "Teaching agents to learn from your
team" (analyzed 2026-08-06). Full findings:
`journal/2026-08-06-transkript-bulgulari.md` and
`journal/2026-08-06-transkript-bulgulari-2.md`. Structure and
procedure sections: `lab/experiments/009-skill-creator/EXPERIMENT.md`
(2026-08-16).
