# omp-fleet - model benchmarks and policy history

Measured delegated runs, cumulative. SKILL.md states the current policy; this file keeps the evidence and the corrections that produced it, so a future change can be argued from numbers.

## Policy history and measurements

| Role | Model string | When |
|---|---|---|
| Deep research / analysis | `google-antigravity/gemini-3.1-pro:high` | Multi-source research, anything needing citations or synthesis |
| Bulk / parallel / simple | `google-antigravity/gemini-3.7-flash:high` | Single-page extraction, reformatting, fan-out across many URLs |
| Second pool | `synthetic/syn:large:text:high` | Research and extraction both. Slow but works - see below. |

**Correction, 2026-08-15: Synthetic does work for research.** This skill
previously said it had "failed every research task given to it" and must not be
used for research. That was over-generalised from two failures, and it is
wrong. On a segment-research task `syn:large:text:high` ran 629s and produced a
15 KB report with a source URL on every one of 24 quotes - **better** per-claim
sourcing discipline than `gemini-3.1-pro:high` managed on a comparable job the
same night, and it reported its own search failures honestly and specifically.

The likeliest cause of the two earlier zero-byte runs is the one this skill
already documents in its own failure table: **both left scraper debris behind,
which means the model ran and spent its time writing fetchers instead of
searching.** That is the symptom of rule 3 being missing from the prompt, not of
a broken provider. The successful run used the explicit `web_search` and
no-scraper block. This is an inference from the debris, not a confirmed
post-mortem - the original prompts were not kept.

Note that debris also rules the path bug out for those two: when the prompt path
fails to resolve, `omp` never starts, leaves nothing, and spends no quota.

Benchmarks, cumulative:

| Model | Task | Time | Output | Result |
|---|---|---|---|---|
| `gemini-3.1-pro` | DBRE comp | 590s | 6.0 KB | 22 sourced figures, self-rated "med" |
| `claude-opus-4-6` | DBRE comp | 543s | 8.9 KB | 25 sourced figures, self-rated "high" |
| `synthetic/GLM-5.2` | DBRE comp | - | 0 B | produced nothing |
| `gemini-3.1-pro` | competitors | 112s | 9.2 KB | facts held, but zero per-claim URLs and one fabricated matrix row |
| `syn:large:text` | segment | 629s | 15 KB | URL on every quote, honest about gaps, but 10 of 24 quotes lifted from vendor marketing pages |
| `Kimi-K3` | hybrid-DBA comp | ~240s | 20 KB | 26 URLs, no debris, best self-criticism seen so far: reported its own n=6 shortfall unprompted, refused to pad, and flagged its own headline delta as sector-confounded. But its one unsourceable claim was still wrong - see below |
| `Kimi-K3` | employer map | ~240s | 21 KB | 32 employers across three groups, mostly primary sources (ATS postings, levels.fyi, H1B filings), some filler aggregators mixed in |

**`synthetic/hf:moonshotai/Kimi-K3:high` is now the first-choice research
model**: roughly 2.5x faster than `gemini-3.1-pro`, larger output, and the only
model in this table that has volunteered its own sampling weakness without
being caught at it. It is not more trustworthy - it is more honest about where
it is untrustworthy, which is a different and more useful property.

**Its failure mode is the paraphrased statistic.** On 2026-08-15 it reported
"BLS: database administrators -1%, 2024-34" with a correct URL attached. The
page it cited actually says the occupation is projected to grow **4%**. The
citation was real, the reading was not. Verified numbers survive; the framing
built on top of them is where the error lives. Check the figure against the
source, not the source against the claim.

**Pick on speed and pool pressure, not on a quality ranking.** `gemini-3.1-pro`
is roughly 5x faster; `syn:large:text` is slower but at least as careful with
citations. Both have shipped a decisive error. Neither is trustworthy enough to
promote unread.

Do not trust a delegate's **self-reported** confidence. In the compensation run
two ranges differed by $58k at the low end, so at least one was wrong whatever
it claimed. In the competitors run the delegate rated as "high confidence" a
table row its own caveats contradicted. In the segment run it claimed 24
sourced quotes, which was true, while a third of them were advertising copy.


## 2026-08-16 - experiment 010: six models on the three delegated task types

Full record: `lab/experiments/010-omp-fleet-delegate-models/EXPERIMENT.md`.
Ground truth was independent of the delegates (vendor API, vendor pages read by
a separate agent, the source document). One run per cell.

Alias resolution, re-measured 2026-08-27 by sending a one-token completion to
each alias and reading the `model` field back off the response (more reliable
than the docs page, which is what the 2026-08-16 row below used):

| Alias | 2026-08-16 | 2026-08-27 |
|---|---|---|
| `syn:large:text` | GLM-5.2 | GLM-5.2 |
| `syn:small:text` | GLM-4.7-Flash | GLM-4.7-Flash |
| `syn:large:vision` | Kimi-K3 | Kimi-K3 |
| `syn:small:vision` | Qwen3.6-27B | **Qwen3.8-27B** |

`syn:small:vision` moved in eleven days with no notice. This is not a footnote:
the benchmark rows for that alias were measured against Qwen3.6-27B and are
now describing a model nobody has benchmarked. Aliases can be repointed by the
vendor; re-check before trusting an old row, and pin `hf:<org>/<model>` rather
than an alias whenever the result has to stay comparable over time.

Re-measure with:

    for A in syn:large:text syn:small:text syn:large:vision syn:small:vision; do
      curl -s -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
        -d "{\"model\":\"$A\",\"max_tokens\":300,\"messages\":[{\"role\":\"user\",\"content\":\"Say OK.\"}]}" \
        https://api.synthetic.new/openai/v1/chat/completions | jq -r .model
    done

| Model | Research 9 facts | Extraction 29 rows | Summary 6 Q / word limit | Wall s (research / summary) |
|---|---|---|---|---|
| gemini-3.7-flash | 9/9 | 29/29 | 6/6, 181 words | 110 / 29 |
| gemini-3.1-pro | 9/9 | 29/29 | 6/6, 175 words | 115 / 58 |
| Qwen3.6-27B | 9/9 | 29/29 | 6/6, 175 words | 170 / 44 |
| GLM-5.2 | 9/9 | 29/29 | 6/6, 272 words (over) | 216 / 101 |
| Kimi-K3 | 9/9 | 29/29 | 6/6, 324 words (over) | 290 / 65 |
| GLM-4.7-Flash | 5/9, 3 wrong | 0/29 dates, 15 fabricated cycles | 5/6 | 96 / 40 |

Pool cost of the run: 12 Synthetic runs took the 5h request pool from 0 to
168 of 500 and $1.62 of credits; 8 Google runs took the daily quota to 5.5%.

This does not overturn the earlier observation that Kimi-K3 was the most
honest about its own gaps on demand research; that workload was not measured
here and remains the open question.

## 2026-08-16 - experiment 011: demand research, quote fidelity

Full record: `lab/experiments/011-omp-fleet-demand-research/EXPERIMENT.md`.
Every cited quote was fetched independently (HN Algolia API, Stack Exchange
API, postgresql.org archives) and matched word for word. Sources restricted to
those three for verifiability; Reddit excluded from this run only.

| Model (run) | Quotes | Verbatim | Near | Hosts | Seconds |
|---|---|---|---|---|---|
| gemini-3.7-flash r1 / r2 | 18 / 18 | 18 / 18 | 0 / 0 | HN + dba.SE + SO + lists | 150 / 131 |
| gemini-3.1-pro | 14 | 14 | 0 | HN only | 132 |
| GLM-5.2 | 20 | 19 | 1 | HN + dba.SE | 179 |
| Qwen3.6-27B | 16 | 9 | 7 | HN + dba.SE + SO | 214 |
| Kimi-K3 r1 / r2 | 6 / 15 | 6 / 15 | 0 / 0 | HN only | 565 / 502 |

No model fabricated a quote in 107 checked. Kimi-K3's earlier "most honest
about gaps" observation is explained: it under-delivers and says so. Flash
delivered three times as much, all verifiable, in a quarter of the time.
