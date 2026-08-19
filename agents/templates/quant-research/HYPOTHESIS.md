# Hypothesis Pre-Registration — `<short-name>`

> **Fill this out COMPLETELY before writing a single line of strategy code.**
> Copy to `research/hypotheses/YYYY-MM-DD-<short-name>.md`, commit it, and do
> not edit the "Kill criteria" or "Holdout" sections afterwards. Editing them
> after seeing results is the definition of moving the goalposts, and it is the
> single most common way a backtest lies to you.
>
> Why pre-registration: you will test many ideas. If you decide what counts as
> success *after* looking at results, you will always find something that looks
> good — that is p-hacking, and it converts noise into false confidence. Writing
> the bar down first is what makes a passing result mean anything.

**Status:** `draft` | `registered` | `in-backtest` | `paper` | `live-small` | `killed`
**Registered on:** YYYY-MM-DD (date this file was committed, unedited from here)
**Killed on:** YYYY-MM-DD — reason: ...

---

## 1. Economic rationale — why should this edge exist?

State the *mechanism* that creates the edge. Who is on the other side of the
trade, and why are they willing to lose? A statistical pattern with no
mechanism is a data-mining artifact until proven otherwise.

> Weak: "RSI below 30 is followed by positive returns in my sample."
> Strong: "Perp funding spikes force leveraged longs to close at market. Forced
> flow is price-insensitive, so it overshoots. The edge is providing liquidity
> to forced sellers and it should be strongest when open interest is high."

**Mechanism:**

**Who pays for this edge, and why do they keep paying:**

**Under what conditions should this edge disappear:**
(If you cannot name conditions that would kill it, you have not understood it.)

---

## 2. Universe and data

| Field | Value |
|---|---|
| Venue | Binance USDⓈ-M Futures / IBKR / ... |
| Instruments | (exact symbol list or the rule that generates it) |
| Bar interval | |
| Sample start / end | |
| Data source | (exchange REST/WS dump, vendor, ...) |

**Point-in-time universe construction:** How do you know which symbols were
*tradeable on each historical date*? Using today's symbol list is survivorship
bias and it inflates results badly — Binance has delisted many pairs, and the
ones that survived are not a random sample.

**Bar timestamp semantics (write this out explicitly):**
- Does timestamp `T` mark the bar's OPEN or CLOSE?
- The bar labeled `T` covers the interval [____, ____)
- Therefore the earliest moment a signal from this bar can be ACTED ON is: ____

> This one line is responsible for more inflated backtests than any other
> single thing. Get it wrong by one bar and a losing strategy looks profitable.

---

## 3. The rules — fully specified, no free parameters left

Entry, exit, sizing, and rebalancing must be complete enough that a second
person could implement them and get the same trades.

**Entry:**

**Exit (all of them — target, stop, time-based, signal-reversal):**

**Position sizing:**

**Intra-bar ambiguity rule:** If in one bar both the stop and the target were
touched, which is assumed to hit first? (Without tick data you cannot know.
The only honest assumption is **stop first** — pessimistic. Anything else is
a hidden lookahead.)

---

## 4. Cost model — decided BEFORE seeing any result

Costs assumed after the fact are costs tuned to make the result survive.

| Cost | Assumption | Basis |
|---|---|---|
| Taker fee | | actual fee tier |
| Maker fee / rebate | | |
| Slippage | | be pessimistic; assume worse than observed |
| Funding (perps) | | direction AND timing of payment |
| Borrow / financing (IBKR) | | |

**Fill assumptions:** Do you assume limit orders always fill? (They do not.)
What happens to unfilled orders? Is your assumed size within the bar's actual
traded volume?

---

## 5. Parameter search budget — declare it up front

Multiple testing is the silent killer. If you try 500 configurations and pick
the best, its Sharpe is inflated by selection alone — even on pure noise.

| Field | Value |
|---|---|
| Number of tunable parameters | |
| Total configurations to be evaluated | |
| Optimization method | grid / walk-forward / CPCV |

**Multiple-testing adjustment to be applied:** (e.g. Deflated Sharpe Ratio.)
The more configurations you try, the higher the Sharpe bar must be. Write the
adjusted bar into section 6 below — not the raw one.

---

## 6. Kill criteria — the goalposts. DO NOT EDIT AFTER REGISTRATION.

Every line must be a number and a comparison. "Looks promising" is not a
criterion. If any single line fails, the hypothesis is **killed** — not tweaked,
not re-optimized, killed. Tweaking a failed hypothesis and re-testing on the
same data is how you fit noise.

**To proceed from backtest → paper, ALL must hold on out-of-sample data:**

- [ ] Sharpe (after all costs from §4) ≥ ______
- [ ] Deflated Sharpe (adjusted for §5 search budget) ≥ ______
- [ ] Max drawdown ≤ ______
- [ ] Number of independent trades ≥ ______ (too few = no statistical meaning)
- [ ] Profitable in ≥ ______ of ______ non-overlapping sub-periods
- [ ] Edge survives doubling the slippage assumption: yes/no
- [ ] Performance does not depend on a single instrument or a single month
- [ ] Result is stable across neighbouring parameter values (a knife-edge
      optimum is an overfit, not an edge)

**Automatic kill, no discussion:**
- Any lookahead finding from `INTEGRITY.md` that materially changes results
- Edge concentrated in a period with known data-quality problems
- Result cannot be reproduced from a clean checkout by re-running the pipeline

**To proceed from paper → small live, ALL must hold:**

- [ ] Paper ran for ≥ ______ (calendar time, not backtest time)
- [ ] Realized paper Sharpe within ______ of backtest expectation
- [ ] Realized slippage/fill rate within ______ of §4 assumptions
- [ ] Zero unexplained divergences between paper and backtest signals

> The paper stage's real purpose is **not** more evidence that the edge exists.
> It is testing whether your *execution model* was right. If paper diverges
> from backtest, your backtest is wrong — regardless of how good it looked.

---

## 7. Holdout — touch exactly once

| Field | Value |
|---|---|
| Holdout period | ______ to ______ |
| Held out from | all development, all parameter selection, all plotting |
| Touched on | (date — fill in when you finally run it) |

**Rule:** You may evaluate on the holdout **once**. The moment you look at it
and then change anything, it is no longer out-of-sample and you need a new one.
Every additional peek quietly converts your holdout into training data.

**Agent instruction:** Any autonomous run is forbidden from reading, loading,
plotting, or computing statistics over the holdout period unless the run's
explicit stated goal is the single final evaluation.

---

## 8. Result log (append-only)

| Date | Stage | What was run | Outcome | Decision |
|---|---|---|---|---|
| | | | | |
