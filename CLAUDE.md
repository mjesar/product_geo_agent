# ProductGeoAgent — Project Context

## How to work with me on this project
I'm learning AI agent development — this project is explicitly a learning exercise, not
just a deliverable. Please:
- Go step by step. Don't jump ahead or generate a large batch of files at once.
- Explain *why* before/while writing code, especially anything related to the agent
  loop, tool-calling, or `little_ghost`'s API — not just what the code does.
- Pause after each meaningful step (e.g., one tool, one service class) so I can run it,
  understand it, and ask questions before moving to the next piece.
- Prefer building things by hand over generating them wholesale, even if slower —
  the point is that I understand every piece, not that it gets done fastest.
- When introducing a new agent concept (tool schemas, reasoning loops, conditional
  tool selection, self-correction, etc.), briefly explain the concept itself, not just
  the implementation.

## What this is
A Ruby on Rails CLI agent that rates how AI-discoverable a Shopify product is (GEO/AEO) —
whether AI shopping assistants would surface, recommend, or cite it. Built as an
agent-development learning project using the `little_ghost` gem, and to produce reusable
building blocks for a separate planned Shopify app (`geo-aeo-shopify-app`).

## Stack
- Ruby on Rails, PostgreSQL
- `little_ghost` gem for the agent/tool-calling loop
- Gemini API (free tier) as the model provider
- Shopify Storefront GraphQL API (read-only) for store data
- Plain HTTP fetch for live page structured-data checks
- Faraday for HTTP calls (no `shopify_api`/`shopify_app` gem — unnecessary machinery
  for a single static-token client; see rationale below)
- RSpec for testing — every tool and service class gets specs as it's built, not
  bolted on at the end
- CLI-first — no UI. A Hotwire wrapper may come later, not now.

## Scope (locked in — don't expand without discussion)
- Product-level audits only. Brand-layer scoring is explicitly OUT of scope (brand data
  isn't reliably available via Storefront API; would need external web/press/Wikidata
  lookups — dropped for now).
- Read-only. No write-back to the store. No Admin API write scopes.
- No MCP layer. Shopify's Storefront MCP is scoped for buyer-facing shopping chat widgets,
  not external audit tools, and is a narrower subset of the raw GraphQL API (no metafields).
  Call the Storefront GraphQL API directly instead.
- No MongoDB / vector search / embeddings. This is structured API scoring, not document
  retrieval — no semantic search need here.
- No `shopify_api`/`shopify_app` gems — these assume OAuth session management per-shop,
  which doesn't apply here (one static Storefront token, no embedded app).

## Agent architecture
Five granular tools, agent orchestrates and conditionally calls them — NOT one combined tool.
This is deliberate: the point of the project is to see the agent make real decisions
(skip a check if a product's already strong; retry via a fallback tool before concluding
"not found"), not to hide all logic in fixed Ruby code.

Tools:
1. `GetProductDataTool` — Storefront API: title, description, images/alt text, variants, SEO
2. `CheckFaqPageTool` — Storefront API: `page(handle: "faq")`
3. `CheckFaqMetafieldTool` — Storefront API fallback, only called if (2) finds nothing
4. `CheckStructuredDataTool` — plain HTTP fetch of the live product page, parse
   `<script type="application/ld+json">` for `Product`/`FAQPage` schema
5. `CheckAiCitationTool` — direct Gemini call: "would you recommend this product?" —
   run last, once full context is available

System prompt strategy (not a fixed pipeline):
> Always start with get_product_data. Use description length/quality to judge how deep
> to go. Try check_faq_page first; if it finds nothing, try check_faq_metafield before
> concluding there's no FAQ content. Always run check_ai_citation last. Summarize with
> a score and the top 2-3 gaps.

## Scoring rubric (draft weights, subject to tuning)
| Check                              | Weight |
|-------------------------------------|--------|
| Description quality/length          | 15     |
| Answers common buyer questions      | 20     |
| Alt text on images                  | 10     |
| Clear specs/variants                | 10     |
| FAQ content (page or metafield)     | 15     |
| Structured data (Product/FAQPage)   | 15     |
| AI citation check                   | 15     |

## Testing approach
- RSpec for everything — service classes (`GeoAudit::*`), the Storefront client, and
  each agent tool.
- Mock/stub external calls (Storefront API, Gemini) in specs — no live network calls
  in the test suite. Use fixtures/VCR-style canned responses for Storefront GraphQL
  responses so tests are fast and don't depend on the sandbox store being reachable.
- Write specs alongside each piece as it's built, not as a separate pass at the end —
  this mirrors how it was done on `shop_mcp_server`.
- Cover both the happy path and the fallback/edge cases explicitly, since those edge
  cases (empty FAQ, no structured data, no citation found) are the actual point of
  this project's scoring logic.

## Shopify auth setup (already done, for reference)
- App type: custom app, created via Dev Dashboard (legacy custom app UI is gone as of
  Jan 2026 for new apps)
- Storefront tokens are NOT generated via a UI button anymore. Flow used:
  1. Grant app `unauthenticated_read_product_listings`, `unauthenticated_read_product_tags`,
     `unauthenticated_read_content` scopes (via a released app version)
  2. Get Admin API access token via OAuth code exchange
     (`/admin/oauth/access_token`)
  3. Run `storefrontAccessTokenCreate` mutation against Admin GraphQL API using that token
  4. Resulting token goes in `SHOPIFY_STOREFRONT_TOKEN`
- Storefront endpoint: `https://{store}.myshopify.com/api/{version}/graphql.json`
- Admin endpoint: `https://{store}.myshopify.com/admin/api/{version}/graphql.json`
- Current API version in use: `2026-07`
- Test store: `test-store-plus-9eiwvuh4.myshopify.com` (sandbox, seeded default products —
  several have empty descriptions, which is realistic/useful test data, not a bug)

## Known limitations (don't be surprised by these)
- Sandbox seed products likely have no FAQ page/metafields by default — add one manually
  to exercise both branches of the fallback logic
- `check_ai_citation` will almost always return "not mentioned" for sandbox/unknown
  products — that's the correct, honest result, not a bug
- Gemini free tier rate limits mean each audit costs several requests (one per tool
  round-trip) — don't stress-test it
- No delivery-date or review-aggregation checks in v1 (Storefront API has no universal
  fields for these) — noted as a possible future `check_fulfillment_clarity` tool

## Repo conventions
- Default branch: `master` (not `main`)
- Commit messages: lowercase, single-line, no trailing period
- No Claude/Anthropic attribution in commits or PR descriptions
- User runs all `git add`/`commit`/`push` themselves

## Build order
1. `ShopifyStorefront::Client` + `GetProductDataTool` (+ specs) — prove one real
   product's data flows end-to-end (curl already confirmed the raw API call works)
2. `CheckStructuredDataTool` (+ specs) — simplest independent check
3. `CheckFaqPageTool` + `CheckFaqMetafieldTool` (+ specs) — build together to test
   branching logic
4. `CheckAiCitationTool` (+ specs) — hardest/most novel, save for once loop mechanics
   are proven
5. Wire all 5 into `ProductGeoAgent`, write system prompt, test on 2-3 real sandbox
   products
