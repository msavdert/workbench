# omp-fleet - operations: liveness, wrapper internals, failure modes

Read this before killing a run, when a launch misbehaves, or when a result looks wrong.

## Is the run alive? Read this before killing anything

Two obvious progress signals are worthless, and both have already caused a
healthy run to be misdiagnosed as hung.

**`run.log` is written at exit, not during the run.** `omp -p` buffers. The file
sits at 11 bytes containing `Working...` for the entire run, whether that run is
10 seconds or 10 minutes from finishing. An unchanging `run.log` is the normal
state of a working delegate and means nothing.

**The Synthetic quota bars are dominated by regeneration, not consumption.**
Requests regenerate 5% of 500 per tick while a single agentic run spends only a
handful, so the bar can sit still or even fall *while work is happening* - across
one 629s run it went 25 -> 24. Credits are the honest meter but only move on
tick boundaries, so between ticks they look frozen too. Over that same run
credits moved $12.89 -> $13.15, about $0.26. Do not read either bar as liveness.

What actually tells you a run is alive:

```bash
ps -o pid,etime,pcpu,args -p "$(pgrep -f 'bun .*omp -p' | head -1)"
```

Non-zero `%CPU` and a growing `etime` mean it is working. Sustained 0.0% CPU
with no output file for several minutes is a real hang. Expect 100-700s for a
research job; the wrapper's `timeout` is the backstop, so waiting is nearly
always correct.


## Known failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Run produces scrapers and `.html` debris | `web_search` not mentioned in prompt | Rule 3 |
| Report reads as sourced research but the URLs do not support it, or carries no URLs at all | The delegate's search failed and it answered from its own knowledge instead of reporting the failure. Cost a whole discarded agentshard research run, 2026-08-27. | Rule 0 (check search first) and the "do NOT answer from your own knowledge" block in the prompt template |
| Foreground call killed at 10 min | Bash timeout cap | Rule 1 |
| Empty output file, `exit=1`, `run.log` says `No such file or directory` | Relative prompt path; the wrapper `cd`s before reading it. Fixed 2026-08-14 | Nothing to do; the wrapper now absolutises the path. No quota is spent when this happens |
| `prompt file not found`, exit 2, workdir never created | The shell's cwd was not the repo root, and `$REPO` is derived from cwd. The Bash tool keeps cwd across calls, so an earlier `cd` into a work directory silently poisons the next launch | **Always pass the prompt as an absolute path**, and `cd` to the repo root in the same command as the launch |
| A launch "succeeded" with exit 0 but nothing ran | `$OMP_RUN ... \| tail -3` reports the exit status of `tail`, not the wrapper | Do not pipe the launch. If you must, append `; echo "exit=$?"` before the pipe or check `$pipestatus[1]` |
| Empty output file, run consumed real time and quota | Model genuinely failed | Check `run.log`; re-run on the other pool |
| `run.log` stuck at 11 bytes for minutes | Normal. `omp -p` buffers and writes at exit | Check process CPU, not the log. See "Is the run alive?" |
| Synthetic quota bar not moving during a run | Normal. Regeneration outpaces a single run's consumption | Credits move ~$0.26 per research run and only on tick boundaries. Not a liveness signal |
| Findings land in your context, not a file | Prompt did not restrict the reply | Rule 2 |
| Delegate claims "high confidence" on thin data | Self-assessment is unreliable | Rule 8 |
| Quotes are real, sourced, and all agree with the hypothesis | Delegate quoted vendor marketing pages, which are written to match the query | Rule 9. Check the host of every source before believing any of it |
| Quota drains long after a run "died" | Delegate used `task` to fan out; children outlive the parent and are owned by the worker daemon | Rule 6. Confirm with `$OMP_RUN status`, not with the parent's PID file - the parent showed as a reaped zombie while nine children were still burning quota |
| 429 `RESOURCE_EXHAUSTED` in `run.log` | Pool was already empty at launch | Rule 7 |

## Wrapper internals

What the wrapper does and why the raw command is banned:

| Defence | Prevents |
|---|---|
| `--tools read,write,web_search` | The `task` tool fanning out parallel subagents (the 2026-08-14 quota drain), and `bash`/`python`/`browser` being used to write scrapers |
| Orphan reaping around the run | Subagents surviving the parent's death; they are spawned by omp's worker daemon, so they are **not** in the parent's process group and a normal kill does not reach them |
| Quota gate at 90% | Spending a request to discover the pool is empty |
| `timeout --kill-after` | A hung run holding the slot open |

The underlying flags, for reference: `-p` non-interactive; `--no-session`
ephemeral; `--config .claude/omp-delegate.yml` disables the advisor runtime;
`--auto-approve` guards against a change to the operator's `yolo` approval
mode; `--no-skills` keeps the operator's interactive skill set out;
`--max-time` is a hard stop; `NO_COLOR=1` keeps the log parseable. The prompt
goes in **on stdin** - passed as a positional argument with stdin not a TTY,
`omp` hangs forever in `readPipedInput`.

Flags and why:
- `-p` non-interactive; `--no-session` ephemeral, nothing to garbage-collect
- `--config .claude/omp-delegate.yml` disables the advisor runtime, which the
  operator has enabled globally and which adds latency and tokens for no
  benefit in a headless one-shot
- `--auto-approve` - the operator's `tools.approvalMode` is already `yolo`, so
  this is belt-and-braces against a config change
- `--no-skills` - do not load the operator's interactive skill set
- `--max-time` - hard stop; set it below the `timeout` you wrap it in
- `NO_COLOR=1` - output is parsed, and ANSI escapes make logs unreadable

