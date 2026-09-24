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
Branch: (committed directly to `master`, pre-workflow — same as step 0)
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

## ⬜ Step 3 — CheckStructuredDataTool
Branch: `check-structured-data-tool`
- `app/services/geo_audit/structured_data_check.rb` — fetches the live product page
  HTML, parses `<script type="application/ld+json">`, checks for `Product`/`FAQPage`
  schema types
- `app/agent_tools/check_structured_data_tool.rb` — thin wrapper
- Spec: canned HTML fixtures (with/without structured data), no live fetches in tests
- **Concept focus:** this tool has no dependency on the Storefront client at all — it's
  a plain HTTP fetch. Good moment to notice not every tool needs the same shape.

## ⬜ Step 4 — CheckFaqPageTool + CheckFaqMetafieldTool
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

---

## Not in this plan (future / out of scope for now)
- Brand-layer scoring
- Write-back / "fix it for me" tooling (Admin API)
- Hotwire UI wrapper
- `check_fulfillment_clarity` (delivery/returns clarity) — noted idea, not started
