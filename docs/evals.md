# Evals: checking whether the agent's judgment holds up

This project scores how discoverable a Shopify product is to AI shopping assistants. The
score is mostly plain Ruby, but three of its seven items are rated by a model: how good
the description is, how well the product's own text answers buyer questions, and how
clear the variants are. Those three ratings are the part that can be wrong, and the part
that can change between two runs on the same product.

The eval harness is how that gets measured. It runs the real agent against real sandbox
products several times and compares what it did with what a person wrote down beforehand.

<!-- diagram: expectations file + N live runs -> comparator -> report (PASS/FLAKY/OFF/FAIL) -> drift against the saved baseline -->

## Why specs are not enough

The RSpec suite proves the code runs and returns the right shape. It makes no network
calls, so it cannot say whether the model's decisions are any good. That gap was real:
on one unchanged product (`the-complete-snowboard`), the model rated variant clarity
fair, then good, then good, then fair across four runs, and each flip moved the score by
5 points. Nothing in the code had changed. One run per product cannot see that, so the
harness runs each product several times and reports the spread, not a single number.
For the general idea, see [specs vs. evals](agent-concepts.md#specs-vs-evals).

## Running it

```bash
bin/eval                                  # every product in the expectations file, 5 audits each
bin/eval --runs 3                         # fewer audits per product
bin/eval the-complete-snowboard           # one product only
bin/eval --save-baseline                  # after the run, record it as the new baseline
bundle exec rspec spec/services/geo_audit/eval   # the harness's own specs (no network)
```

`bin/eval` makes real Gemini calls, so it is never part of the normal `rspec` run or CI.
One audit is about 7 requests, so 5 audits of one product is about 35. The free tier
allowed 15 requests a minute and 500 a day when this was written (check
[Google's rate-limit page](https://aistudio.google.com/rate-limit), the numbers change).
The runner spaces audits out to stay under the per-minute limit, skips the written
gaps explanation (one fewer request per audit, and explanation quality is a separate
question), and keeps a failed audit as an error instead of discarding the rest. The raw
runs are saved to `tmp/evals/` (not committed) so a run's output is never lost.

It exits with a non-zero status if any product has a failing check.

## What the expectations record

Expectations live in [`spec/evals/expectations.yml`](../spec/evals/expectations.yml), one
block per product. The file is loaded and checked by `GeoAudit::Eval::Expectations`,
which rejects typos and unknown keys, so a misspelled key cannot quietly turn a check off.
Each product has three kinds of expectation:

- **Ratings** (the three the model judges). `accept` lists every rating that would not be
  called a failure, and `expected` optionally names the one value actually predicted.
  `accept: [poor, fair]` with `expected: poor` means "poor is my bet, fair would not
  worry me, good would". Keeping the two apart matters: a run that lands on fair is not a
  failure, but it is not where the prediction was either, and the report says so.
- **Facts** (the items computed in code from tool results): the alt text count, whether
  the FAQ came from the page or the metafield, whether structured data was found, whether
  the AI mentioned the product. These come from the store and the live page, so they are
  exact values, not ranges.
- **Tools**: which tools the run must call, or must not.

The most important rule is to **write a product's expectations before its first run**.
Written afterwards, they tend to describe whatever the agent said, and then they prove
nothing. When a product already has history, as `the-complete-snowboard` does, the file
says so in a comment instead of pretending to be blind.

## Reading a report

This is the real output of the first run, on `the-collection-snowboard-liquid` (a product
with an empty description, a hidden store FAQ page and a `custom.faq` metafield):

```text
the-collection-snowboard-liquid: 5 completed run(s)
score  min 25  median 25  max 25

PASS  rating  description_quality        expected poor                          observed poor x5
PASS  rating  buyer_questions_answered   expected poor or fair (expect poor)    observed poor x5
PASS  rating  specs_clarity              expected poor or fair (expect poor)    observed poor x5
PASS  fact    alt_text                   expected 1 of 1 with alt               observed 1 of 1 with alt x5
PASS  fact    faq_source                 expected metafield                     observed metafield x5
PASS  fact    structured_data            expected false                         observed false x5
PASS  fact    ai_citation                expected false                         observed false x5
PASS  tool    get_product_data           expected called                        observed called x5
PASS  tool    check_faq_page             expected called                        observed called x5
PASS  tool    check_faq_metafield        expected called                        observed called x5
PASS  tool    check_structured_data      expected called                        observed called x5
PASS  tool    check_ai_citation          expected called                        observed called x5

RESULT: PASS (12 PASS)
```

Each check gets one label, judged across all the runs:

| Label | Meaning |
|---|---|
| `FAIL` | at least one run was outside what was accepted, or the evidence was never produced |
| `FLAKY` | no run failed, but the observed value changed between runs |
| `OFF` | every run agreed, but not with the predicted value (ratings only) |
| `PASS` | every run matched |

A check whose evidence was never produced counts as a fail, not a guess. For example, a
`structured_data: false` expectation fails if the structured data tool never ran, rather
than passing by accident.

This run was also the first time the metafield fallback ran against a real store. The
agent called `check_faq_page`, found nothing because the page was hidden, then called
`check_faq_metafield` and found the content, in every run. The model also did not count
that FAQ text a second time in `buyer_questions_answered`, which was a risk.

## Baseline and drift

`--save-baseline` records a compact summary of a run in
[`spec/evals/baseline.json`](../spec/evals/baseline.json): what each check observed, each
run's score, and the model and git commit it came from. The next `bin/eval` compares
against it and adds a section to the report:

```text
drift vs baseline (gemini:gemini-flash-lite-latest, af4b0c2, 20261001T113322Z):
  none
```

Drift compares the **typical** result across runs, not single runs, so one odd run out of
five is not reported. A rating's typical value is its median (poor, then fair, then good),
a fact or tool call's is its most common value, and the score's is its median. A score
counts as drifted when it moves by 5 points or more, which is the smallest a rating change
can move it. Drift is informational and never fails a product, because a change can be an
improvement. The baseline is only replaced on purpose.

## What this does not prove

- **It has run on easy products.** An empty description and a single `Default Title`
  variant leave almost no room for the model to vary. Ten identical audits show the
  harness works end to end, not that the model is stable on harder ones. The unstable
  case that motivated all this goes through the harness next.
- **Two products is a small set.** Nothing here shows the rubric is right, only whether the
  agent behaves consistently with what was written down.
- **Some facts come from the same tools the agent calls.** Checking that the agent called
  them and carried their output through is real, but it does not independently test the
  tools themselves.
- **The expectations are a person's predictions.** If they are wrong, a pass means little.
- **The agent has never skipped a check.** The prompt allows a strong product to be audited
  faster, but every real run so far has called all five tools. A strong product with
  tool expectations is where that would show up, and it is untested.

## Setup the store needs

The store's settings are part of the test, and they are global:

- **The FAQ page is one store-wide page** (`handle: "faq"`), so every product sees the same
  one. To exercise the metafield fallback it has to be hidden, which also changes every
  other product's FAQ result. Expectations are written for the state the store is in, and
  the harness does not check that state before a run yet.
- **A product metafield only reaches the Storefront API if its definition has Storefront
  access turned on.** Without it, a saved `custom.faq` value comes back empty and the
  agent reports no FAQ content.
- **The store must be reachable** with `SHOPIFY_STORE_DOMAIN` and `SHOPIFY_STOREFRONT_TOKEN`
  set, as for `bin/audit`.

## Adding a product

1. Pick a product where the model has room to vary (a real description, several variants).
2. Read its facts from the store and the live page, without running the agent.
3. Add it to `spec/evals/expectations.yml` with the reasoning in comments, and commit it.
4. Run `bin/eval PRODUCT_HANDLE`, read the report, then `--save-baseline` if the run is
   representative.

## Where the pieces are

| Piece | File |
|---|---|
| Expectations file and its loader | `spec/evals/expectations.yml`, `app/services/geo_audit/eval/expectations.rb` |
| Judge one run against expectations | `app/services/geo_audit/eval/comparator.rb` |
| Run N audits, with pacing | `app/services/geo_audit/eval/runner.rb` |
| Verdicts across runs, and the text report | `app/services/geo_audit/eval/report.rb`, `report_formatter.rb` |
| Baseline and drift | `app/services/geo_audit/eval/baseline.rb`, `drift.rb` |
| The command | `bin/eval` |

The build order and the reasoning behind each choice are in Step 10 of the
[development plan](development-plan.md).
