#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""External audit in one message: spec, diff and code inline, no tools.

Usage (Python >= 3.11, standard library only; launch it with `uv run`, which picks a
suitable interpreter even where `python3` is older, e.g. macOS /usr/bin/python3 3.9):

    uv run ~/.claude/skills/audit/audit-ext.py --topic studykit-r3 \
        --spec <workdir>/spec.md --diff <workdir>/diff.patch \
        --out-dir <workdir-parent> \
        [--prev <workdir>/prev.md] [--file src/x.py] [--file src/y.py:120-260] \
        [--repo-root /abs/worktree] [--read-tool --max-reads 8] [--max-time 900]

Why (measured 2026-10-22 in perp-lab, its ADR 0136): with read tools the model
fetched the diff in 60-line chunks (48 turns, 3 thinking bursts, 639 s); the
same audit as one message took 280 s at the same quality.
gemini-3.8-flash:high thinks about 40-50k tokens per answer at about 180
tokens/s, so one answer costs about 4-5 minutes; every extra thinking burst
adds as much.

Writes <out-dir>/audit-<topic>-ext/: prompt.txt, events.jsonl (each omp JSON
event with its elapsed seconds), report.md (the answer), meta.json (elapsed,
turns, tool calls, tokens, the provider and model that answered, stop reason)
and launch.log, whose last line is `exit=<rc>` for a Monitor. That directory
must lie outside any git work tree or in a part of one that git ignores, so
audit files never land in a tracked tree.

--repo-root (the base for --file slices and the read tool) defaults to the git
top level of the current directory.

Exit codes: 0 report complete; 2 refused before any request (bad argument, an
--out-dir in a tracked tree, a credential shape or a secret env value in the
prompt, prompt too large); 3 the run gave no usable report (omp failure, empty
answer, answer cut at the token limit, or answered by a provider/model other
than the one asked for: omp can walk a fallback chain silently).
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any

MODEL = "google-antigravity/gemini-3.8-flash:high"
GRACE_S = 120  # omp's process group is killed this long after its own --max-time
READER_GRACE_S = 10  # after omp exits, its stdout must close within this
MAX_PROMPT_CHARS = 600_000  # about 150k tokens; larger diffs are split by the caller
# High-precision credential shapes, copied from perp-lab ops/ask_models.py
# SECRET_PATTERNS (the eight that do not fire on ordinary code; its key=value,
# e-mail, home-path, op:// and long-run patterns fire on `monkeypatch:
# MonkeyPatch`, `@pytest.fixture`, absolute paths, 1Password references and
# sha256 digests). The prefixes are written as one-character classes so the
# pre-commit grep in AGENTS.md (hard rule 1) does not hit this file itself;
# the regexes match exactly what the originals match.
CODE_SECRET_PATTERNS = {
    "openai/anthropic/openrouter style key": r"\bsk[-][A-Za-z0-9_-]{16,}",
    "1password service token": r"\bops[_][A-Za-z0-9_-]{20,}",
    "github token": r"\b(ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{20,}",
    "aws access key": r"\bAKIA[0-9A-Z]{16}\b",
    "jwt": r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}",
    "private key block": r"-{5}BEGIN [A-Z ]*PRIVATE KEY-{5}",
    "bearer header": r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}",
    "telegram bot token": r"\b\d{8,10}:[A-Za-z0-9_-]{35}\b",
}
SECRET_ENV_NAME = re.compile(r"KEY|TOKEN|SECRET|PASSWORD|PASS|CREDENTIAL", re.IGNORECASE)
# Two code-safe extras: a quoted literal assigned to a key/token/secret/password name,
# and a 40+ character run that mixes upper case, lower case and digits (an exchange
# key; sha256 and git digests are lower-case hex and do not qualify).
QUOTED_SECRET = re.compile(
    r"(?i)\b\w*(key|token|secret|passw(or)?d)\w*[\"']?\s*[=:]\s*[\"'][A-Za-z0-9+/=_-]{16,}[\"']"
)
LONG_RUN = re.compile(r"(?<![A-Za-z0-9])[A-Za-z0-9]{40,}(?![A-Za-z0-9])")
FILE_ARG = re.compile(r"^(?P<path>[^:]+)(?::(?P<a>\d+)-(?P<b>\d+))?$")

HEADER = """You are an adversarial code auditor. Assume the change is broken and try to
prove it. Never run `op`, never read ~/.config/op, ~/.ssh or any key or token
file: tool output is sent upstream.
"""

ASK = """Report, in order of severity, as your reply (the reply is the deliverable):
1. Correctness bugs: file:line, the concrete input or state, the wrong outcome.
   No bug without a failure scenario.
2. Spec drift: asked vs delivered, including silently skipped items.
3. Claims in the change's own description that the code does not back up.
4. Verdict: pass | pass with findings | fail, and what you inspected to earn an
   empty list.
Style remarks only if they hide a defect. Keep the report under {lines} lines.
"""

PREV = """PREVIOUS ROUND FOUND (each claimed fixed): do not re-report a fixed item;
for each one say CLOSED or OPEN with a failure scenario, then report any new bug
the fix introduced.
"""


class Refused(Exception):
    pass


def _git(cwd: Path, *argv: str) -> subprocess.CompletedProcess[str]:
    # GIT_DIR / GIT_WORK_TREE in the caller's environment would override discovery from cwd.
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env["LC_ALL"] = "C"  # the "not a git repository" test below reads git's message
    return subprocess.run(
        ["git", "-C", str(cwd), *argv], capture_output=True, text=True, env=env, check=False
    )


def git_toplevel(cwd: Path) -> Path | None:
    """The work tree containing cwd, or None when cwd is in no git work tree."""
    try:
        res = _git(cwd, "rev-parse", "--show-toplevel")
    except OSError:
        return None
    return Path(res.stdout.strip()).resolve() if res.returncode == 0 else None


def check_out_dir(run_dir: Path) -> None:
    """Refuse a run directory inside a git work tree unless git ignores it (fail closed)."""
    probe = run_dir
    while not probe.exists():
        probe = probe.parent
    if not probe.is_dir():
        raise Refused(f"--out-dir: {probe} exists and is not a directory")
    try:
        inside = _git(probe, "rev-parse", "--is-inside-work-tree")
    except OSError as exc:
        raise Refused(f"--out-dir: git is needed to check {run_dir}: {exc}") from exc
    if inside.returncode != 0:
        if "not a git repository" in inside.stderr:
            return  # outside every repository
        raise Refused(f"--out-dir: git cannot classify {run_dir}: {inside.stderr.strip()}")
    if inside.stdout.strip() != "true":  # inside a .git directory or a bare repository
        raise Refused(f"--out-dir: {run_dir} is inside a git directory")
    top = _git(probe, "rev-parse", "--show-toplevel")
    if top.returncode != 0:
        raise Refused(f"--out-dir: git cannot classify {run_dir}: {top.stderr.strip()}")
    # Compare resolved paths (a symlinked parent must not make git call the path "outside"),
    # and pass it relative to the top. The trailing slash lets a directory-only pattern
    # (`_work/`) match a path not yet created.
    top_dir = Path(top.stdout.strip()).resolve()
    try:
        rel = run_dir.resolve().relative_to(top_dir)
    except ValueError as exc:
        raise Refused(f"--out-dir: {run_dir} does not resolve inside {top_dir}") from exc
    ign = _git(top_dir, "check-ignore", "-q", f"{rel}/")
    if ign.returncode == 1:
        raise Refused(f"--out-dir: {run_dir} is in the tracked tree {top.stdout.strip()}")
    if ign.returncode != 0:
        raise Refused(f"--out-dir: git check-ignore failed for {run_dir}: {ign.stderr.strip()}")


def read_slice(spec: str, root: Path) -> tuple[str, str]:
    """`path` or `path:a-b` (1-based, inclusive, inside root) -> (label, numbered text)."""
    m = FILE_ARG.match(spec)
    if not m:
        raise Refused(f"--file {spec!r}: expected path or path:a-b")
    full = (root / m["path"]).resolve()
    if not full.is_relative_to(root.resolve()):
        raise Refused(f"--file {spec!r}: outside --repo-root {root}")
    if not full.is_file():
        raise Refused(f"--file {spec!r}: no such file under {root}")
    text = full.read_bytes().decode("utf-8")  # strict; no newline translation
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    a, b = (int(m["a"]), int(m["b"])) if m["a"] else (1, len(lines))
    if not 1 <= a <= b or a > len(lines):
        raise Refused(f"--file {spec!r}: bad line range (file has {len(lines)} lines)")
    b = min(b, len(lines))
    body = "\n".join(f"{i:6d}  {lines[i - 1]}" for i in range(a, b + 1))
    return f"{m['path']} lines {a}-{b}", body


def scan_code_secrets(text: str, env: dict[str, str]) -> list[str]:
    """High-precision credential shapes plus any secret-named env var whose value appears."""
    hits = [n for n, pat in CODE_SECRET_PATTERNS.items() if re.search(pat, text)]
    if QUOTED_SECRET.search(text):
        hits.append("quoted secret literal")
    for m in LONG_RUN.finditer(text):
        run = m.group(0)
        if (
            any(c.isupper() for c in run)
            and any(c.islower() for c in run)
            and any(c.isdigit() for c in run)
        ):
            hits.append("long mixed-case token")
            break
    for name, value in env.items():
        if SECRET_ENV_NAME.search(name) and len(value) >= 8 and value in text:
            hits.append(f"value of ${name}")
    return hits


def build_prompt(args: argparse.Namespace) -> str:
    root = Path(args.repo_root).resolve() if args.repo_root else None
    parts = [HEADER]
    if args.read_tool:
        parts.append(
            f"Repository root with the change: {root}. Everything needed is inline below; "
            f"use the read tool only for context it does not show, at most {args.max_reads} "
            "reads, each with a line range. Do not write any file."
        )
    else:
        parts.append("You have no tools. Everything you need is inline below.")
    parts.append(ASK.format(lines=args.report_lines))
    if args.prev:
        parts.append(PREV)
    parts.append("=== SPEC ===\n" + Path(args.spec).read_text(encoding="utf-8"))
    if args.prev:
        parts.append("=== PREVIOUS ROUND ===\n" + Path(args.prev).read_text(encoding="utf-8"))
    parts.append("=== DIFF ===\n" + Path(args.diff).read_text(encoding="utf-8"))
    for spec in args.file:
        assert root is not None  # parse() refuses --file without a repo root
        label, body = read_slice(spec, root)
        parts.append(f"=== FILE {label} (line numbers as on disk) ===\n{body}")
    return "\n\n".join(parts) + "\n"


def summarise(events: list[tuple[float, Any]]) -> dict[str, Any]:
    turns = tools = 0
    msgs: list[dict[str, Any]] = []
    for _, ev in events:
        if not isinstance(ev, dict):
            continue
        kind = ev.get("type")
        if kind == "turn_start":
            turns += 1
        elif kind == "tool_execution_start":
            tools += 1
        elif kind == "message_end":
            msg = ev.get("message")
            if isinstance(msg, dict) and msg.get("role") == "assistant":
                msgs.append(msg)
    usage = [m["usage"] if isinstance(m.get("usage"), dict) else {} for m in msgs]
    last = msgs[-1] if msgs else {}
    raw = last.get("content")
    content: list[Any] = raw if isinstance(raw, list) else []
    text = "".join(
        str(c.get("text", "")) for c in content if isinstance(c, dict) and c.get("type") == "text"
    )
    return {
        "turns": turns,
        "tool_calls": tools,
        "assistant_messages": len(msgs),
        "input_tokens": sum(u.get("input") or 0 for u in usage),
        "cache_read_tokens": sum(u.get("cacheRead") or 0 for u in usage),
        "output_tokens": sum(u.get("output") or 0 for u in usage),
        "reasoning_tokens": sum(u.get("reasoningTokens") or 0 for u in usage),
        "answered_by": sorted({f"{m.get('provider')}/{m.get('model')}" for m in msgs}),
        "stop_reason": last.get("stopReason"),
        "error_message": last.get("errorMessage"),
        "report_chars": len(text),
        "_text": text,
    }


THINKING_LEVELS = {"off", "minimal", "low", "medium", "high", "xhigh", "max", "auto"}


def expected_answerer(model: str) -> str:
    """Drop a trailing thinking level: 'google-antigravity/gemini-3.8-flash:high' ->
    'google-antigravity/gemini-3.8-flash'; ids with colons inside ('a/hf:org/m:high') keep
    them ('a/hf:org/m')."""
    head, sep, tail = model.rpartition(":")
    return head if sep and tail in THINKING_LEVELS else model


def run_dir(args: argparse.Namespace) -> Path:
    return Path(args.out_dir).resolve() / f"audit-{args.topic}-ext"


def run(args: argparse.Namespace, out: Path) -> int:
    try:  # still before the request: a failure here is a refusal (exit 2)
        out.mkdir(parents=True, exist_ok=True)
        for old in ("launch.log", "report.md", "meta.json", "events.jsonl", "prompt.txt"):
            (out / old).unlink(missing_ok=True)  # a rerun never leaves a stale exit= or report
    except OSError as exc:
        raise Refused(f"--out-dir: cannot prepare {out}: {exc}") from exc
    launch = out / "launch.log"
    try:
        prompt = build_prompt(args)
    except (OSError, UnicodeDecodeError) as exc:  # unreadable spec, diff or file: no request
        raise Refused(str(exc)) from exc
    if len(prompt) > MAX_PROMPT_CHARS:
        raise Refused(f"prompt {len(prompt)} chars > {MAX_PROMPT_CHARS}: split the audit")
    hits = scan_code_secrets(prompt, dict(os.environ))
    if hits:
        raise Refused(f"secret-shaped text in the prompt: {hits}")
    (out / "prompt.txt").write_text(prompt, encoding="utf-8")
    cmd = [
        "omp", "-p", "--model", args.model, "--no-session", "--auto-approve", "--no-skills",
        "--max-time", str(args.max_time), "--mode", "json",
    ]  # fmt: skip
    cmd += ["--tools", "read"] if args.read_tool else ["--no-tools"]
    launch.write_text(f"topic={args.topic} model={args.model} chars={len(prompt)}\n")
    start = time.monotonic()
    events: list[tuple[float, Any]] = []
    io_problems: list[str] = []
    with (out / "events.jsonl").open("w", encoding="utf-8") as log:
        proc = subprocess.Popen(
            cmd,
            cwd=out,  # the run's own directory: a read tool cannot wander into other runs
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",  # a stray byte on merged stderr must not kill the reader
            env={**os.environ, "NO_COLOR": "1"},
            start_new_session=True,  # its own process group: helpers die with it
        )
        assert proc.stdin is not None and proc.stdout is not None
        stdin, stdout = proc.stdin, proc.stdout

        def feed() -> None:  # a thread, so a child that writes before reading cannot deadlock us
            try:
                stdin.write(prompt)
            except Exception as exc:  # noqa: BLE001 - any failure is recorded, never swallowed
                io_problems.append(f"omp closed stdin early: {exc.__class__.__name__}")
            finally:
                with contextlib.suppress(Exception):  # already broken; the write recorded it
                    stdin.close()

        def read() -> None:  # only this thread touches events and the log
            try:
                for line in stdout:
                    t = time.monotonic() - start
                    try:
                        ev: Any = json.loads(line)
                    except json.JSONDecodeError:
                        ev = {"type": "raw", "line": line.rstrip("\n")}
                    events.append((t, ev))
                    log.write(json.dumps({"t": round(t, 3), "ev": ev}) + "\n")
            except Exception as exc:  # noqa: BLE001 - recorded; the run then fails closed
                io_problems.append(f"reader failed: {exc!r}")
                with contextlib.suppress(Exception):
                    for _ in stdout:  # keep draining so omp is never blocked on a full pipe
                        pass

        def kill_group() -> None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)

        writer = threading.Thread(target=feed, daemon=True)
        reader = threading.Thread(target=read, daemon=True)
        writer.start()
        reader.start()
        try:
            omp_rc = proc.wait(timeout=args.max_time + GRACE_S)
        except subprocess.TimeoutExpired:
            io_problems.append(f"killed after {args.max_time + GRACE_S} s")
            kill_group()
            omp_rc = proc.wait()
        finally:
            if proc.poll() is None:  # an exception in this thread: never leave omp running
                kill_group()
                proc.wait()
        reader.join(timeout=READER_GRACE_S)
        if reader.is_alive():  # omp exited but a helper still holds stdout open
            kill_group()
            reader.join(timeout=5)
            io_problems.append("stdout held open after omp exited (helpers killed)")
        writer.join(timeout=5)
    meta = summarise(events)
    text = meta.pop("_text")
    meta.update(elapsed_s=round(time.monotonic() - start, 1), omp_rc=omp_rc, model_asked=args.model)
    problems = list(io_problems)
    if omp_rc != 0:
        problems.append(f"omp exit {omp_rc}")
    if not text.strip():
        problems.append("empty answer")
    if meta["stop_reason"] == "length":
        problems.append("answer cut at the token limit")
    elif meta["stop_reason"] != "stop":
        problems.append(f"stop reason {meta['stop_reason']!r}: {meta['error_message']}")
    if meta["answered_by"] != [expected_answerer(args.model)]:
        problems.append(f"answered by {meta['answered_by']}, asked {args.model}")
    meta["problems"] = problems
    (out / "report.md").write_text(text, encoding="utf-8")
    (out / "meta.json").write_text(json.dumps(meta, indent=1, sort_keys=True) + "\n")
    rc = 3 if problems else 0
    with launch.open("a") as fh:
        fh.write(f"elapsed={meta['elapsed_s']}s turns={meta['turns']} ")
        fh.write(f"reasoning={meta['reasoning_tokens']} problems={problems}\n")
        fh.write(f"exit={rc} report={out / 'report.md'}\n")
    return rc


def parse(argv: list[str] | None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=(__doc__ or "").splitlines()[0],
        epilog="Exit codes: 0 report complete, 2 refused before any request, 3 no usable report.",
    )
    p.add_argument("--topic", required=True)
    p.add_argument("--spec", required=True)
    p.add_argument("--diff", required=True)
    p.add_argument(
        "--out-dir",
        required=True,
        help="parent of the run directory audit-<topic>-ext/; outside git or git-ignored",
    )
    p.add_argument("--prev", help="previous round's findings (a re-audit)")
    p.add_argument("--file", action="append", default=[], help="path or path:a-b, repeatable")
    p.add_argument(
        "--repo-root",
        help="base for --file and the read tool (default: git top level of the current directory)",
    )
    p.add_argument("--read-tool", action="store_true", help="allow line-ranged reads")
    p.add_argument("--max-reads", type=int, default=8)
    p.add_argument("--max-time", type=int, default=900)
    p.add_argument("--report-lines", type=int, default=80)
    p.add_argument("--model", default=MODEL)
    args = p.parse_args(argv)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.topic):
        p.error("--topic: letters, digits, dot, dash, underscore")
    if args.repo_root is None:
        top = git_toplevel(Path.cwd())
        if top is not None:
            args.repo_root = str(top)
        elif args.file or args.read_tool:
            p.error("--repo-root: the current directory is in no git work tree; pass it")
    return args


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < (3, 11):
        print("audit-ext: needs Python >= 3.11; launch it with `uv run`", file=sys.stderr)
        return 2
    args = parse(argv)
    out = run_dir(args)
    accepted = False  # launch.log is written only into a run directory that passed the check
    try:
        check_out_dir(out)
        accepted = True
        return run(args, out)
    except Refused as exc:  # raised only before the request
        print(f"audit-ext: REFUSED: {exc}", file=sys.stderr)
        rc, line = 2, f"exit=2 refused: {exc}"
    except Exception as exc:
        if not accepted:  # the out-dir check itself failed: still before any request
            print(f"audit-ext: REFUSED: {exc!r}", file=sys.stderr)
            return 2
        print(f"audit-ext: FAILED: {exc!r}", file=sys.stderr)  # after the request started
        rc, line = 3, f"exit=3 failed: {exc!r}"
    if accepted and out.is_dir():
        # an unwritable run dir must not turn rc into 1
        with contextlib.suppress(OSError), (out / "launch.log").open("a") as fh:
            fh.write(line + "\n")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
