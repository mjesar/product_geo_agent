# Development Plan

Step-by-step build plan for `ProductGeoAgent`. Each step below = one branch = one PR.
Don't start a step's branch until the previous PR is merged into `master`.

Status key: ⬜ not started · 🔶 in progress · ✅ merged · ⏭️ skipped (deliberate)

---

## ✅ Step 0 — Project setup
Branch: (done directly on `master`, pre-workflow)
- Rails app scaffolded with PostgreSQL
- `little_ghost`, `dotenv-rails` gems added
- `.env` / `.env.example` set up
- GitHub repo created, README added
- `CLAUDE.md` + `docs/agent-concepts.md` + `docs/shopify-auth-setup.md` added
- Shopify Storefront token generated and verified via curl

## ✅ Step 1 — ShopifyStorefront::Client
Branch: `storefront-client` (PR #5, merged)
- `app/services/shopify_storefront/client.rb`
- Wraps Storefront GraphQL POST requests
- Injectable Faraday connection (dependency injection, for testability)
- Normalizes GraphQL-body errors and HTTP-level errors into one `Client::Error`
- Spec: happy path, variables passed through, GraphQL error, HTTP error (4 examples)
- **Concept focus:** dependency injection, why GraphQL needs two error shapes handled as one

## ✅ Step 2 — GetProductDataTool
Branch: `get-product-data-tool`
- `app/agent_tools/get_product_data_tool.rb`
- Wraps `ShopifyStorefront::Client` to fetch one product's title, description,
  images/alt text, variants, SEO fields by handle
- Spec: mocks the client (not Faraday — client is already tested), covers found/not-found
- **Concept focus:** tool schema definition (what little_ghost needs to describe this
  to the model), and why this spec mocks the client instead of re-stubbing HTTP

## ✅ Step 3 — CheckStructuredDataTool
Branch: `check-structured-data-tool`
- `app/services/shopify_storefront/password_auth.rb` — the sandbox store is on a
  no-plan/development Shopify plan, which force-locks storefront password protection
  on (the toggle in Admin → Online Store → Preferences is disabled, not just unchecked
  — confirmed via screenshot, not assumption). POSTs the storefront password to
  `/password`, captures the resulting `storefront_digest` cookie, so the real page can
  be fetched instead of the password splash page. Needed for this tool to produce real
  results against the sandbox; most live (non-development-plan) stores won't need this.
- `app/services/geo_audit/structured_data_check.rb` — fetches the live product page
  HTML (carrying the password cookie above), parses `<script type="application/ld+json">`,
  checks for `Product`/`FAQPage` schema types
- `app/agent_tools/check_structured_data_tool.rb` — thin wrapper
- Spec: canned HTML fixtures (with/without structured data), no live fetches in tests —
  the password-auth piece gets its own spec stubbing the HTTP layer, same as
  `ShopifyStorefront::Client`
- **Concept focus:** this tool has no dependency on the Storefront *GraphQL* client at
  all — it's a plain HTTP fetch (plus, as it turns out, a small auth wrinkle specific to
  this store's plan tier). Good moment to notice not every tool needs the same shape,
  and that the storefront password gate is a different auth boundary from the
  Storefront API token entirely.

## ✅ Step 4 — CheckFaqPageTool + CheckFaqMetafieldTool
Branch: `faq-check-tools`
- `app/services/geo_audit/faq_check.rb` — page lookup via Storefront client
- `app/agent_tools/check_faq_page_tool.rb`
- `app/agent_tools/check_faq_metafield_tool.rb` — fallback, separate tool
- Spec: both tools independently, plus a scenario proving they're independent
  (metafield tool works even if page tool wasn't called first — the *agent* decides
  the fallback order, not the code)
- **Concept focus:** this is where self-correction / conditional tool selection
  actually gets exercised for the first time — worth a note in `docs/agent-concepts.md`
  once this is built and tested against the agent (step 6)

## ✅ Step 5 — CheckAiCitationTool
Branch: `check-ai-citation-tool`
- `app/services/geo_audit/citation_check.rb` — direct Gemini call, no tools attached,
  asks a category-relevant question, checks if product/store name appears in response
- `app/agent_tools/check_ai_citation_tool.rb`
- Spec: mock the Gemini client response — **do not** call the real Gemini API in specs
  (burns real quota, and tests should be deterministic)
- **Concept focus:** the hardest/most novel tool — this is the one that's actually
  unique to "AEO" rather than dressed-up SEO. Expect this step to take longest.

## ✅ Step 6 — GeoAuditAgent (wiring it all together)
Branch: `product-geo-agent` (PR #10, merged)
- `app/agents/geo_audit_agent.rb` — the `little_ghost` agent itself. Named
  `GeoAuditAgent`, not `ProductGeoAgent`, because `config/application.rb` already
  defines a top-level `ProductGeoAgent` module (Rails' own app namespace, derived
  from the app name) — Zeitwerk silently hands back that empty module instead of
  loading the agent file if the names collide, so the class needs a different name.
- System prompt encoding the strategy (start with get_product_data, judge depth,
  FAQ fallback logic, citation check last, summarize with score + gaps)
- Spec: `geo_audit_agent_spec.rb` covers wiring only (tools registered, system prompt
  content) — mocking multi-turn model behavior turned out to only prove Ruby handles a
  fake response correctly, never that the real model would choose that order, so that
  question is answered by `geo_audit_agent_live_spec.rb` (`:live`, opt-in) instead. See
  "Specs vs. evals" in `docs/agent-concepts.md`.
- **Concept focus:** this is the first time you'll actually *watch* the reasoning
  loop happen end-to-end — the payoff step for everything built so far

## ✅ Step 7 — Move scoring out of the model
Branch: `deterministic-scoring` (PR #11, merged)
- The system prompt no longer asks the model to calculate a score. Instead,
  `GeoAuditAgent` declares a `result_schema` that forces its final answer into three
  categorical ratings (`description_quality`, `buyer_questions_answered`,
  `specs_clarity`, each `poor`/`fair`/`good` plus a one-sentence reason) — the model
  judges, it never does arithmetic
- An `after_tool` hook copies every tool's raw result into `context.state` as it runs,
  so `run.result.state` holds the full set of tool results once the audit finishes,
  alongside `run.result.structured_result.value` for the ratings
- `app/services/geo_audit/score.rb` — pure Ruby. Sums the four measurable rubric items
  (FAQ content, structured data, AI citation, alt-text coverage) directly from the tool
  results, and the three qualitative ones from the model's ratings (`poor` = 0, `fair`
  = half weight, `good` = full weight), rounding once on the total rather than per item
- `app/services/geo_audit/gaps_explanation.rb` — a second, separate, tool-free Gemini
  call that reads the finished score back as plain text (rendered from
  `app/prompts/geo_audit/gaps_explanation.erb`) and writes 2-3 sentences about the
  biggest gaps. It never sees the first conversation and can't change the number
- `app/services/geo_audit/auditor.rb` — orchestrates all three: runs the agent, scores
  it, explains it, returns `{run:, score:, explanation:}`. Lives outside `GeoAuditAgent`
  itself, which stays a thin, declarative `little_ghost` agent. Nothing calls `Auditor`
  yet outside its own spec — Step 8 (the CLI) is what gives it a real caller
- Spec: `score_spec.rb` (no Gemini calls at all), `gaps_explanation_spec.rb` (stubbed
  model response), `auditor_spec.rb` (mocks all three collaborators to test the wiring
  itself) — the `:live` spec gets updated and run once, at the very end of this step,
  after everything else is settled
- **Concept focus:** what belongs in code vs. in the model — determinism belongs in
  code, judgment belongs in the model. See the "System prompts" section in
  `docs/agent-concepts.md`, plus its new section on hooks and structured output.

## ✅ Step 8 — CLI entrypoint + observability
`bin/audit` grew from a minimal wrapper into a real CLI with live visibility into
what the agent is doing, retries, and usage tracking — enough of a scope expansion
that it's tracked as sub-steps, each its own branch/PR. Product listing, run history,
and an interactive menu (8.5-8.7) were deliberately skipped, see below.

### ✅ Step 8.0 — minimal entrypoint
Branch: `cli-entrypoint` (PR #12, merged)
- `bin/audit HANDLE` — validates the handle argument, runs `GeoAudit::Auditor`,
  catches a failed run cleanly (prints the reason, exits non-zero) instead of a raw
  Ruby backtrace
- Deliberately minimal — no output yet on the success path; that's 8.4's job

### ✅ Step 8.1 — central model settings
Branch: `central-model-settings` (merged)
- `app/services/geo_audit/models.rb` — `GeoAudit::Models.for(role)`, one place for
  model names by role (`agent`, `citation`, `explanation`, `chat` for later), instead
  of the same literal string hardcoded in three files
- `GeoAuditAgent`, `CitationCheck`, `GapsExplanation` all read their model through it
- **Concept focus:** none new — this is upkeep, but the kind that pays off the next
  time Gemini retires a model name

### ✅ Step 8.2 — retry with backoff
Branch: `retry-with-backoff` (PR #14, merged)
- `little_ghost`'s Gemini adapter has no retry/backoff logic at all (confirmed by
  reading the adapter source — other adapters like OpenAI-compatible and Bedrock do,
  Gemini doesn't), so this is entirely our own
- `app/services/geo_audit/retry_policy.rb` — pure decision logic: given an error and
  an attempt number, returns a delay in seconds or `nil`. Only retries
  `LittleGhost::Providers::HTTPError` with status `503` (5s/15s/30s) or `429`
  (15s/30s/60s); everything else fails immediately
- `app/services/geo_audit/retrier.rb` — wraps a block, used by `CitationCheck` and
  `GapsExplanation`'s bare `LittleGhost.generate` calls, which don't go through any
  Agent hook. Takes an injectable `sleeper:` so specs never actually wait
- `app/services/geo_audit/model_error_recovery.rb` — a callable registered as
  `GeoAuditAgent.after_model_error`, for the agent's own reasoning-loop calls.
  Returning `LittleGhost::Support::Callbacks.replace(request: ...)` is what actually
  triggers a retry (mutating the payload hash does nothing — confirmed by reading
  `Support::Callbacks`); little_ghost hard-caps this at 3 recovery attempts total,
  non-configurable
- **Concept focus:** two separate retry paths were needed, not one, because
  `after_model_error` (Agent-turn calls) and a bare `.generate` call (no Agent, no
  hooks) are fundamentally different integration points. Also a real Ruby gotcha hit
  while building `ModelErrorRecovery`: `context.state[k] ||= {}` evaluates to the
  plain `{}` literal, not the `DataMap`-normalized value actually stored, so
  mutating that expression's result silently writes to an orphaned hash instead of
  the real per-run state — see the comment in `model_error_recovery.rb`

### ✅ Step 8.3 — usage counting
Committed directly to `master` (no branch/PR this time — a process slip, not worth
unwinding since the commit itself is solid and tested)
- `app/services/geo_audit/usage.rb` — `Usage::Tracker`/`Snapshot`/`PartSnapshot`,
  broken down by part (`agent`, `citation`, `explanation`) with calls, retries, and
  tokens tracked separately, plus a combined total
- `app/services/geo_audit/model_call_counter.rb` — a new `before_model` hook
  counting every agent-turn attempt, including retries
- `Retrier` gained optional `tracker:`/`part:`, recording calls/retries/tokens for
  the two bare `.generate` paths by reading the raw response's usage before
  `CitationCheck`/`GapsExplanation` reduce it down to text — no return-shape changes
  needed on either
- `Auditor` times the whole call with an injectable monotonic clock and reads
  `run.usage` directly (confirmed populated even when a run fails, unlike
  `run.result`, which is `nil` on failure) into the `agent` part
- Added to `Auditor::Result` as `usage:`/`elapsed_seconds:` — not printed yet,
  that's 8.4's job
- **Concept focus:** `GeoAuditAgent`'s hooks are class-level singletons registered
  once and reused across every run, and `CitationCheck` is only ever instantiated by
  little_ghost itself (inside its tool wrapper), not by our own code — neither can
  take a normal per-call constructor argument. Both reach the current audit's
  tracker through a `Thread.current` slot `Auditor` sets before the run and clears
  in an `ensure`, safe only because `bin/audit` runs one audit per process at a time

### ✅ Step 8.4 — visibility: events + terminal output
Branch: `audit-visibility`
- Everything that does something announces an event to a reporter object (not
  `ActiveSupport::Notifications` — little_ghost already exposes the right hook
  points, so a plain reporter interface is simpler); a terminal printer, a
  `--trace` file writer, and later a database saver each subscribe independently
- Levels: default (one line per event), `--verbose` (full tool inputs/results),
  `--trace` (raw request/response to a file, redacted)
- On failure: print the failed step and reason, then partial results from
  `context.state`, then exit cleanly, no backtrace
- This is what the old "observability" step (formerly Step 10) meant — folded in
  here instead of staying separate, since it's the same work
- Each agent tool needs `exclusive true` set: little_ghost otherwise dispatches tools
  through a thread-spawning executor, and `CurrentAudit`'s `Thread.current` state (set
  by `Auditor` on the calling thread) isn't visible inside a tool's own thread without
  it — `before_tool`/`after_tool` hooks raise `CurrentAudit::MissingError` instead of
  seeing the current run. Found while wiring hooks against a real run, not obvious
  up front from the little_ghost docs
- **Follow-up, not fixed here**: `GetProductDataTool` returns "not found" as a normal
  successful tool result rather than raising, so on a handle that doesn't resolve the
  agent still runs its full checklist (FAQ page, FAQ metafield, structured data,
  citation) against nothing, burning several Gemini calls for no reason — confirmed
  live, a nonexistent-handle smoke test made 4 real calls before being killed. Two
  options, not decided yet: teach the system prompt to stop early on a not-found
  result, or have `Auditor` check the handle resolves before invoking the agent at all
- **Follow-up (🔶 in progress, branch `reporter-redesign`, not its own numbered step)**:
  the first real run against `Terminal` exposed the actual problem with the original
  design — `tool_finished`'s `summary:` was just `value.to_s`, the entire raw Ruby
  hash stringified, so every tool line wrapped across several lines of unreadable
  JSON-looking text instead of being an actual one-line summary. Separately, `Auditor`
  computed the gaps explanation but never told the reporter about it, so the one thing
  that explains *why* a product scored what it did was invisible on every run.
  Reworked `Reporter::Terminal` into a cleaner "Thinking... / ✓ tool → summary" view
  with ANSI color (auto-detected via `io.tty?`, off when piped or in specs), added
  `GeoAudit::ToolSummary` (one real human sentence per tool, keyed by tool name) to
  replace the raw dump, and added the missing `:explanation` event. `ModelCallLogger`
  also now emits `tool_names:` as a plain array alongside the existing `decision:`
  string, so `Terminal` doesn't have to string-match "answered without a tool call" to
  know whether a turn chose a tool

### ⏭️ Step 8.5 — product list — skipped
Branch would have been: `product-list`
- Would have been a Storefront query for handle + title with pagination, no Gemini
  involved; `bin/audit list` printing it, becoming a tool for chat mode later

### ⏭️ Step 8.6 — saving results + history — skipped
Branch would have been: `audit-history`
- Would have been a Postgres table for audit runs (handle, score, breakdown,
  explanation, usage, redacted trace, timestamp); `bin/audit history` reading it back

### ⏭️ Step 8.7 — interactive menu — skipped
Branch would have been: `interactive-menu`
- Would have been a numbered menu to pick a product, watch the audit run live, and
  browse history — depended on 8.5 and 8.6 existing, so skipping those made this
  moot too

**Why skipped:** none of these three teach a new agent-development concept — they're
the only steps in this plan with no "Concept focus" note, pure CLI/CRUD/UX work
(a paginated query, a database table, a `gets` menu). Nothing downstream needs them
either: Step 9 only needs a few real product handles, gettable from the Shopify admin
directly, and Step 10's hand-scored expectations were already planned to live in a
file (`spec/evals/` or `docs/evals.md`), not a database. For a project whose point is
learning agent concepts and producing a portfolio piece, not shipping a full internal
tool, the cost (no product browsing, no persisted run history, no interactive menu)
is worth it to spend the remaining time on Steps 9 and 10 instead, which actually are
agent-concept work. Chat mode (typed English routed to a command) was floated as a
later, unscheduled idea that would have used 8.5-8.7's CLI commands as its own tools
— shelved along with them, not a loss since it was never committed to.

## ⬜ Step 9 — Real sandbox run + scoring calibration
No new branch necessarily — likely small fixup commits/PRs as needed. Runs after
Step 8 completes, since calibration is much easier to watch with 8.4's live output
in hand than by guessing from a silent final score.
- Run against 3-5 real sandbox products
- Sanity-check the scoring weights actually produce sensible-feeling results
- Add FAQ content to the sandbox store manually (per the known-limitations note in
  `CLAUDE.md`) so both FAQ branches get exercised in a real run, not just in specs
- Update `docs/agent-concepts.md` with what was learned from watching real traces

## ⬜ Step 10 — Eval harness: does the agent's judgment hold up?
Branch: `eval-harness`
- Pick 5-8 real products from the sandbox store, hand-score what each one *should*
  get (expected score + expected gaps flagged), then run the real agent against them
  and compare
- Lives in `spec/evals/` or `docs/evals.md` — exact shape TBD once we see it; may not
  fit neatly into RSpec's assert-and-pass model since eval output is closer to
  "how far off was this" than "pass/fail"
- Needs the full agent (step 6) and ideally the visibility work (step 8.4) to make
  failures diagnosable, not just visible
- **Strongest eval candidate found so far: `specs_clarity` is not stable.** On
  `the-complete-snowboard` (same product, same `specs_clarity` wording throughout),
  four runs rated it fair, good, good, fair, which moved the score 65, 85, 85, 80.
  The cleanest evidence is the last flip (good to fair, 2026-09-30 to 2026-10-01),
  where nothing relevant changed in between. The first flip (fair to good) is
  confounded: the store FAQ page had just been added, so the model saw different
  context. Either way, the instability is in the model's judgment, not in the code,
  and each flip moves the score by 5 points. One run per product cannot see this,
  so the harness should run each product several times and report the spread, not
  a single number
- **Concept focus:** evals vs. tests — RSpec specs prove the code doesn't crash and
  returns the right shape; they say nothing about whether the agent's actual
  judgment (the score, the gaps it flags) is any good. An eval harness is the
  repeatable way to tell whether a scoring-rubric change made things better or
  worse, not just "did it run"

---

## Not in this plan (future / out of scope for now)
- Brand-layer scoring
- Write-back / "fix it for me" tooling (Admin API)
- Hotwire UI wrapper
- `check_fulfillment_clarity` (delivery/returns clarity) — noted idea, not started
