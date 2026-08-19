#!/usr/bin/env python3
"""Programmatic grader for omp-fleet evals. Usage: grade.py <iteration-dir>
Writes grading.json per run dir (fields text/passed/evidence) and prints a table."""
import json, re, sys, pathlib

def slurp(d, pats):
    out = {}
    for p in d.rglob('*'):
        if p.is_file() and any(re.search(x, p.name) for x in pats):
            try: out[str(p.relative_to(d))] = p.read_text(errors='replace')
            except: pass
    return out

def has(texts, rx):
    for name, t in texts.items():
        t = re.sub(r'\\\n\s*', ' ', t)  # join shell line continuations
        m = re.search(rx, t, re.I | re.S | re.M)
        if m: return name + ': ' + t[max(0,m.start()-40):m.end()+40].replace('\n',' ')
    return None

def grade_run(run):
    task = run / 'outputs' / 'task'
    reply = (run / 'outputs' / 'reply.md')
    reply_t = {'reply.md': reply.read_text()} if reply.exists() else {}
    prompts = slurp(task, [r'prompt.*\.(txt|md)$'])
    launch = slurp(task, [r'^LAUNCH\.sh$'])
    # A prompt embedded in LAUNCH.sh via heredoc is the skill's own documented pattern.
    if not prompts and launch and any(re.search(r"<<\s*'?\w+'?", t) for t in launch.values()):
        prompts = {k + ' (heredoc)': v for k, v in launch.items()}
    allf = slurp(task, [r'.'])
    ev = run.parent.parent.name  # eval-N-name
    A = []
    def add(text, ev_ok, ev_str): A.append({'text': text, 'passed': bool(ev_ok), 'evidence': ev_str or 'not found'})
    if ev.startswith('eval-1') or ev.startswith('eval-2') or ev.startswith('eval-3'):
        add('prompt file written', bool(prompts), ', '.join(prompts) or None)
        e=has(prompts, r'web_search'); add('prompt names web_search tool', e, e)
        e=has(prompts, r'(do not|don.t|never|no)[^.\n]{0,40}(scraper|playwright|write.{0,20}python)'); add('prompt forbids scrapers', e, e)
        e=has(prompts, r'(do not|don.t|never|no)[^.\n]{0,40}(subagent|task tool|spawn)'); add('prompt forbids subagents/task tool', e, e)
        e=has(prompts, r'source url|url for every|every (number|claim|quote)[^.\n]{0,40}(source|url)'); add('prompt demands per-claim sources', e, e)
        e=has(prompts, r'(write|save)[^\n]{0,80}\.md'); add('prompt directs full output to a file', e, e)
        e=has(prompts, r'(at most|no more than|max(imum)?)\s*(5|five)\s*lines'); add('prompt caps the reply at 5 lines', e, e)
        e=has(launch, r'omp-run\.sh|\$OMP_RUN'); add('LAUNCH.sh uses the wrapper', e, e)
        e=has(launch, r'(^|[;&|\s])omp\s+-p'); add('LAUNCH.sh does NOT call raw omp -p', not e, e or 'no raw omp -p')
        e=has(launch, r'(\$OMP_RUN|omp-run\.sh)"?\s+"?\S+"?\s+"?(/|\$\{?(REPO|TASKDIR|[A-Z_]*ROOT|PWD|WORKDIR|WORK_DIR)|\$\(pwd\))') or has(launch, r'PROMPT[A-Z_]*=["\']?(/|\$\(pwd\)|\$\{?(REPO|TASKDIR|[A-Z_]*ROOT|PWD|WORKDIR|WORK_DIR))'); add('LAUNCH.sh passes absolute (or root-anchored) prompt path', e, e)
        e=has(dict(launch, **reply_t), r'run_in_background|background|nohup|&\s*$'); add('launch is backgrounded / background noted', e, e)
        want = r'gemini-3\.7-flash'
        e=has({k: '\n'.join(l for l in v.splitlines() if not l.strip().startswith('#')) for k, v in launch.items()}, want); add('launched model = the policy default (gemini-3.7-flash)', e, e)
        e=has(allf, r'STATE\.md|log/handoff\.md|strategy/'); leak = e and not ev.startswith('eval-3'); add('no project-specific path leakage (STATE.md, log/handoff.md)', not leak, e or 'none')
    if ev.startswith('eval-2') or ev.startswith('eval-3'):
        e=has(prompts, r'(vendor|marketing|landing page|case stud)'); add('source rules: vendor/marketing content banned', e, e)
        e=has(prompts, r'(reddit|hacker news|forum|blind|stack overflow|mailing list)'); add('source rules: first-person forum sources named', e, e)
        e=has(prompts, r'who is speaking|who (posted|wrote)|why they posted|state.{0,20}(who|author)'); add('source rules: who-is-speaking clause', e, e)
        e=has(prompts, r'second.person|"you can|addressed (at|to) a reader'); add('source rules: second-person copy discarded', e, e)
        e=has(prompts, r'under.deliver|fewer.{0,20}(quotes|is fine)|do not pad|padding'); add('source rules: under-delivering preferred to padding', e, e)
    if ev.startswith('eval-3'):
        dec = slurp(task / 'strategy', [r'DECISION']) if (task/'strategy').exists() else {}
        add('DECISION.md written in-session', bool(dec), ', '.join(dec) or None)
        e=has(prompts, r'(decide|recommend|which segment)[^.\n]{0,40}(target|first)'); add('decision NOT delegated to omp', not e, e or 'prompt does not ask delegate to decide')
        e=has(dec, r'(unverified|claim|not (yet )?verified|spot.check|self.rated|self.reported)'); add('DECISION treats delegate output as claim / spot-checks', e, e)
        e=has(dec, r'53\.7|53\.8|recomput|miscalcul|does not (add up|multiply|compute)|(wrong|incorrect|overstat)[^.\n]{0,30}(figure|number|revenue|math|by \$)'); add('DECISION catches the planted revenue arithmetic error (73.8 should be 53.8)', e, e)
        e=has(dec, r'n\s*=\s*6|n=6|six respondents|small sample|thin'); add('DECISION flags n=6 WTP sample as thin despite HIGH confidence', e, e)
    if ev.startswith('eval-4'):
        e=has(reply_t, r'\bwait\b'); k=has(reply_t, r'\bkill\b[^.\n]{0,30}(now|it|and relaunch)'); add('verdict: wait', e and not has(reply_t, r'(recommend|should)[^.\n]{0,20}kill'), e)
        e=has(reply_t, r'cpu'); add('basis: CPU signal', e, e)
        e=has(reply_t, r'run\.log[^.\n]{0,80}(not|meaningless|worthless|exit|buffer)|(buffer|written at exit)'); add('run.log dismissed as liveness signal', e, e)
        e=has(reply_t, r'quota[^.\n]{0,80}(not|regenerat|meaningless|worthless)|regenerat'); add('quota bar dismissed as liveness signal', e, e)
        e=has(reply_t, r'(100|700)\s*s|timeout|backstop|max.time'); add('mentions expected window / wrapper timeout backstop', e, e)
    p_ = sum(a['passed'] for a in A)
    tm = json.loads((run/'timing.json').read_text()) if (run/'timing.json').exists() else {}
    if 'duration_ms' in tm: tm['total_duration_seconds'] = round(tm['duration_ms']/1000, 1)
    (run/'grading.json').write_text(json.dumps({'expectations': A, 'summary': {'passed': p_, 'failed': len(A)-p_, 'total': len(A), 'pass_rate': p_/len(A) if A else 0}}, indent=1))
    return A

it = pathlib.Path(sys.argv[1])
rows=[]
for run in sorted(it.glob('eval-*/*/run-*')):
    A = grade_run(run)
    p = sum(a['passed'] for a in A)
    rows.append((run.parent.parent.name, run.parent.name, run.name, p, len(A)))
    print(f"{run.parent.parent.name:38s} {run.parent.name:10s} {run.name}: {p}/{len(A)}")
    for a in A:
        if not a['passed']: print('    FAIL', a['text'])
