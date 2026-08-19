# Backtest Integrity — Lookahead Bias Defence

This file is the project's foundation. Everything else is optional; this is not.
A backtest with lookahead bias is not a weak result — it is an **inverted** one:
it will look better the more contaminated it is, which is exactly why it fools
people who are otherwise careful.

**Doctrine:** Lookahead is not caught by review. It is caught by **structure** —
by making the leak impossible to express in code. Every item below should
ideally be enforced by an assertion or a test, not by remembering to check it.

---

## Part 1 — The leak catalogue

Each entry: what it is, how it shows up, and the structural defence.

### 1.1 Bar timestamp off-by-one (the most common, most damaging)

A bar labeled `09:00` covering `[09:00, 09:05)` is not *known* at 09:00 — it is
known at 09:05. Computing a signal from that bar's close and executing at that
bar's close means trading on information you did not have.

**Defence:** One function, used everywhere, that maps signal time → earliest
executable time. Never index prices directly in strategy code.

```python
def executable_at(signal_bar_close_ts: pd.Timestamp) -> pd.Timestamp:
    """Signal known at bar close -> earliest fill is the NEXT bar's open."""
    return signal_bar_close_ts + BAR_INTERVAL
```

**Test:** Shift all returns forward by one bar. If performance *improves*, you
had a lookahead. This test is cheap and catches an enormous class of bugs.

### 1.2 Full-sample statistics

Any `mean`, `std`, `min`, `max`, `quantile`, or fitted scaler computed over the
whole dataset leaks the future into every point in the past.

```python
# LEAK — uses future data at every historical point
df["z"] = (df.x - df.x.mean()) / df.x.std()
scaler.fit(X); X_scaled = scaler.transform(X)   # fit before split == leak

# SAFE — expanding/rolling, past-only
df["z"] = (df.x - df.x.expanding().mean()) / df.x.expanding().std()
scaler.fit(X_train); X_test_scaled = scaler.transform(X_test)
```

**Defence:** Ban `.fit()` outside a fold. Ban `center=True` on any rolling
window. Grep for both in CI.

### 1.3 Survivorship bias

Backtesting on today's symbol list means testing only on the instruments that
survived. Delisted pairs went to zero or got removed — excluding them is
excluding your losses.

**Defence:** Build a point-in-time universe table: `(date, symbol, tradeable)`.
The strategy may only see symbols where `tradeable == True` on that date.

### 1.4 Intra-bar path assumption

If a bar's high touched your target and its low touched your stop, which came
first? OHLC does not say. Assuming the target is a lookahead that inflates every
stop-loss strategy.

**Defence:** Assume the **stop** fills first, always. If the edge only survives
under the optimistic assumption, it does not exist. Use tick data if the answer
actually matters.

### 1.5 Cross-validation leakage in time series

Standard k-fold shuffles time and trains on the future. Even a chronological
split leaks if labels span a horizon that reaches into the test set.

**Defence:** Walk-forward, or purged k-fold with an embargo — remove training
samples whose label window overlaps the test window, plus a gap after it.

### 1.6 Restatement / revised data (mainly IBKR, equities)

Fundamentals get revised; index membership is announced before it is effective;
adjusted prices are computed with adjustment factors that did not exist yet.

**Defence:** Point-in-time data only. If your source does not provide it, treat
fundamental-driven results as unverifiable and say so out loud.

### 1.7 Funding and fee timing (Binance perps)

Funding is exchanged at specific timestamps, paid by one side to the other.
Applying it at the wrong time, in the wrong direction, or to a position you did
not actually hold across the funding stamp, silently manufactures return.

**Defence:** Model funding as a discrete cashflow at the actual funding
timestamps, applied only to positions held across the stamp. Reconcile against
a real account statement before trusting it.

### 1.8 Liquidity and impact

Assuming you can trade any size at the observed price. If your assumed order is
a meaningful fraction of the bar's volume, you would have moved the price.

**Defence:** Cap position size at a fixed fraction of bar volume. Assert it.

### 1.9 Data-snooping across hypotheses

Not a per-backtest bug — a portfolio-level one. Testing many hypotheses on the
same dataset means the best one looks good by selection alone.

**Defence:** `HYPOTHESIS.md` §5 declares the search budget; the Sharpe bar is
adjusted accordingly. Track total hypotheses tested against this dataset in a
running counter — the number only goes up, and your bar goes up with it.

---

## Part 2 — Structural defences (build these first)

Before any strategy code exists, these should be in place. This is the "concrete
foundation" — the point is that a leak becomes hard to *write*, not just easy to
spot.

1. **A single data-access layer.** Strategy code never touches raw dataframes.
   It asks for `bars_available_at(t)` and physically cannot see `t+1`.
   This one design decision eliminates most of §1.1 and §1.2 by construction.

2. **A `PointInTimeView` object** that raises on any access beyond its cutoff.
   Make the leak an exception, not a silent wrong number.

3. **Cost model as a required argument**, not a default. A backtest that can run
   without costs will eventually be run without costs.

4. **A shift-test in CI.** Shift signals one bar later; assert performance drops.
   If it does not, fail the build.

5. **A synthetic-noise test in CI.** Run the pipeline on random-walk data with
   the same structure. Assert the strategy shows no edge after costs. A pipeline
   that finds edges in noise has a leak, and this catches leaks no review will.

6. **Deterministic reproduction.** Fixed seeds, pinned data snapshot hash.
   A result you cannot reproduce from a clean checkout is not a result.

7. **The holdout is physically separated** — a different directory or a guard
   that requires an explicit environment flag to load.

---

## Part 3 — Rules for autonomous agents in this repository

These are hard constraints for any AI agent working here, including overnight
runs. They exist because an agent optimizing a metric will find the leak that
maximizes it — not out of malice, but because a leak is the cheapest way to
make a number go up.

**Forbidden without explicit human approval in the same session:**
- Loading, plotting, or computing any statistic over the holdout period
- Weakening, deleting, or skipping any test in Part 2
- Changing any cost assumption in `HYPOTHESIS.md` §4
- Editing the "Kill criteria" or "Holdout" sections of any registered hypothesis
- Placing any real order, on any venue, with any size
- Committing a data snapshot or credential to the repository

**Required behaviour:**
- If a result looks too good, the first hypothesis is **a leak, not an edge**.
  Search for the leak before reporting the result. Report both.
- Report metrics after costs, always. A pre-cost number is not a result.
- When a hypothesis fails its kill criteria, say so plainly and stop. Do not
  propose parameter tweaks to rescue it — that is fitting noise, and it is the
  failure mode this whole file exists to prevent.
- State assumptions as assumptions. If timestamp semantics were inferred rather
  than confirmed from documentation, say which.

**Reporting template for any backtest result:**

```
Hypothesis:    <link to registered file>
Data:          <range, snapshot hash>
Costs applied: <fees, slippage, funding>
Result:        Sharpe __ (deflated __), MaxDD __, N trades __
Kill criteria: PASS / FAIL — <which line failed>
Leaks checked: <which items from Part 1 were verified, and how>
Not verified:  <what remains unverified — be explicit>
```

The last line is mandatory and must never be empty. There is always something
unverified; a report claiming otherwise is not more trustworthy, it is less.
