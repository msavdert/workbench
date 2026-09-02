# NNN — <project name>

**Source:** <repo URL> @ `<commit sha>`
**Evaluated:** <YYYY-MM-DD>
**Verdict:** adopt | reject | retry later

## 1. What it claims

**Mechanism in one sentence:** <marketing removed; if this cannot be written, stop here>

| Claim | Testable | Source |
|---|---|---|
| | yes / no | README line, docs page, benchmark |

## 2. Which invariant

| Question | Answer |
|---|---|
| Serves which invariant | context economy / verification / isolation / recovery / cost-speed / **none** |
| Replaces or sits next to | replaces `<what>` / next to `<what>` |
| If next to, defence | |

If the invariant is "none", stop here, set the verdict to reject, and delete the
remaining sections. A dated one-page rejection is a complete result.

## 3. Provenance and blast radius

| Check | Finding |
|---|---|
| First / last commit, contributors | |
| Release and versioning | |
| Install method | |
| Runs at install or import | |
| Access requested (shell, network, credentials, filesystem) | |
| Sandbox used for this evaluation | container / throwaway dir / none - why |

## 4. Measurement

**Hypothesis:** <X does Y to metric Z by amount N>
**Metric:** <countable unit>
**Baseline:** <the current way, measured here, not remembered>
**Workload:** <own task, own data>

| Environment | Value |
|---|---|
| Host / container image | |
| Versions (tool, runtime, model) | |
| Date of run | |

| Run | Condition | Metric | Notes |
|---|---|---|---|
| 1 | baseline | | |
| 2 | candidate | | |
| 3 | candidate | | |

**Spread:** <min-max, not just the mean>
**Raw output:** `raw/`

### Trivial-explanation check

A surprisingly good result is a bug hypothesis first.

| Candidate explanation | Ruled out how |
|---|---|
| Warm cache / repeated work | |
| Baseline mismeasured or not comparable | |
| Work silently skipped | |
| Output never validated for correctness | |

## 5. Decision

**Verdict:** adopt | reject | retry later
**Reason:** <one sentence tied to the invariant and the number>
**Replaced:** <file deleted, or "nothing">
**Landed in:** `agents/<path>` (workbench) — <what changed>
**Revisit when:** <condition that would change this verdict, or "not applicable">
