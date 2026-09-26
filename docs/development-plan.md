# Development Plan

Step-by-step build plan for `ProductGeoAgent`. Each step below = one branch = one PR.
Don't start a step's branch until the previous PR is merged into `master`.

Status key: ⬜ not started · 🔶 in progress · ✅ merged

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

## 🔶 Step 2 — GetProductDataTool
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

## ⬜ Step 5 — CheckAiCitationTool
Branch: `check-ai-citation-tool`
- `app/services/geo_audit/citation_check.rb` — direct Gemini call, no tools attached,
  asks a category-relevant question, checks if product/store name appears in response
- `app/agent_tools/check_ai_citation_tool.rb`
- Spec: mock the Gemini client response — **do not** call the real Gemini API in specs
  (burns real quota, and tests should be deterministic)
- **Concept focus:** the hardest/most novel tool — this is the one that's actually
  unique to "AEO" rather than dressed-up SEO. Expect this step to take longest.

## ⬜ Step 6 — ProductGeoAgent (wiring it all together)
Branch: `product-geo-agent`
- `app/agents/product_geo_agent.rb` — the `little_ghost` agent itself
- System prompt encoding the strategy (start with get_product_data, judge depth,
  FAQ fallback logic, citation check last, summarize with score + gaps)
- Spec: integration-style spec mocking all 5 tools, asserting the agent calls them
  in the expected conditional order for a few scenarios (thin product vs. strong
  product, FAQ found on first try vs. fallback needed)
- **Concept focus:** this is the first time you'll actually *watch* the reasoning
  loop happen end-to-end — the payoff step for everything built so far

## ⬜ Step 7 — CLI entrypoint
Branch: `cli-entrypoint`
- `bin/audit` — takes a product handle, runs `ProductGeoAgent`, prints the trace +
  final score readably
- Spec (if reasonably testable) or manual verification against the sandbox store
- **Concept focus:** none new — this is packaging, not agent concepts

## ⬜ Step 8 — Real sandbox run + scoring calibration
No new branch necessarily — likely small fixup commits/PRs as needed
- Run against 3-5 real sandbox products
- Sanity-check the scoring weights actually produce sensible-feeling results
- Add FAQ content to the sandbox store manually (per the known-limitations note in
  `CLAUDE.md`) so both FAQ branches get exercised in a real run, not just in specs
- Update `docs/agent-concepts.md` with what was learned from watching real traces

## ⬜ Step 9 — Observability: instrument the reasoning loop
Branch: `agent-observability`
- Log each tool call the agent makes — tool name, arguments, duration,
  success/failure — to Rails' logger or a structured log file, so a completed audit
  run produces a readable trace of what happened and how long each step took, not
  just the final score
- Needs the full agent (step 6) to exist first, since there's no reasoning loop to
  instrument before then
- Should earn its keep during development itself (debugging why the agent picked a
  particular path or stalled on a tool call), not just be a resume line
- **Concept focus:** observability for agentic systems — without this, a reasoning
  loop is a black box; structured logging turns "the agent didn't answer" into
  "get_product_data timed out after 8s" as a diagnosable trace, not a guess

## ⬜ Step 10 — Eval harness: does the agent's judgment hold up?
Branch: `eval-harness`
- Pick 5-8 real products from the sandbox store, hand-score what each one *should*
  get (expected score + expected gaps flagged), then run the real agent against them
  and compare
- Lives in `spec/evals/` or `docs/evals.md` — exact shape TBD once we see it; may not
  fit neatly into RSpec's assert-and-pass model since eval output is closer to
  "how far off was this" than "pass/fail"
- Needs the full agent (step 6) and ideally the observability trace (step 9) to make
  failures diagnosable, not just visible
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
