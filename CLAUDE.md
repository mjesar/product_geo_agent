# ProductGeoAgent — Project Context

## How to work with me on this project
I'm learning AI agent development — this project is explicitly a learning exercise, not
just a deliverable. Please:
- Go step by step, in small chunks. Don't jump ahead or generate a large batch of files
  at once — break even a single class into pieces (e.g., initializer first, then one
  method at a time) if that's what "small" takes.
- **I write the code, not you.** Don't write files under `app/` or `spec/` for me,
  including specs and boilerplate/config files (Gemfile edits, generator output, etc.)
  — describe what's needed and let me write it, then review what I wrote.
- When guiding me through a chunk, you can show a small real snippet (2-5 lines) as a
  reference for unfamiliar syntax/API shape (e.g. Faraday's block syntax), but I should
  still be the one writing the actual file — don't hand me something to copy-paste.
- Explain *why* before/while I write code, especially anything related to the agent
  loop, tool-calling, or `little_ghost`'s API — not just what the code does.
- After I write a chunk, review it, point out bugs/improvements and explain why, before
  moving to the next piece. Pause for me to run it and ask questions before moving on.
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

## Observability & evals (planned — see `docs/development-plan.md` steps 9-10)
RSpec specs prove correctness: the code doesn't crash, and returns the right shape.
They prove nothing about two other things that matter for an agentic system, and both
are real gaps here, not just nice-to-haves:
- **Observability** — right now a completed audit run only shows the final score.
  There's no visibility into which tools the agent called, in what order, with what
  arguments, how long each took, or where it failed. Planned fix: log each tool call
  to Rails' logger (or a structured log file) so a run produces a readable trace,
  useful for debugging during development, not just after the fact.
- **Evals** — RSpec can't tell you whether the agent's *judgment* is any good (is the
  score right, are the flagged gaps the actual gaps), only whether the code ran
  without crashing. Planned fix: a small hand-scored ground-truth set (5-8 real
  sandbox products) the agent gets run against, to catch whether a scoring-rubric
  change made things better or worse.

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
- **Gemini model availability**: `little_ghost`'s own docs example uses
  `gemini-2.5-flash` — this is deprecated for new users (404). Their own suggested
  replacement, `gemini-3.8-flash`, was returning 503 "high demand" errors as of Sept
  2026 (confirmed transient via raw API, not our bug). Currently using
  `gemini-flash-lite-latest`, which works. If this project stops working against
  Gemini with a 404/model-not-found error, check for a model name change first before
  assuming the code broke.

## Repo conventions
- Default branch: `master` (not `main`)
- Commit messages: lowercase, single-line, no trailing period
- No Claude/Anthropic attribution in commits or PR descriptions
- User runs all `git add`/`commit`/`push` themselves, and creates branches/PRs/merges
  themselves via the GitHub UI (see Git workflow below) — suggest the command for
  branch creation and merging, don't run it. For PRs specifically, don't give a
  `gh pr create` command at all — write the PR description text instead (see below).

## Git workflow — branch per step, PR per branch
Follow `docs/development-plan.md` for the sequence of steps. For each step:

1. **Before starting a new step's work**, suggest creating a new branch off `master`
   named after that step (see the plan for exact names, e.g. `get-product-data-tool`).
   Do not start writing code for a new step directly on `master`, and do not continue
   piling unrelated steps onto a branch that already has a merged purpose.
2. **While a step is in progress**, stay on that one branch — don't jump ahead to the
   next step's branch until the current one is merged. Remind the user to commit at
   each natural checkpoint (e.g. once a class + its spec are written and the spec
   passes) rather than waiting until the whole step is done — small commits, not one
   giant commit per branch. Suggest a commit message following the Repo conventions
   above; the user still runs `git add`/`commit` themselves.
   - **Grouping uncommitted changes into commits**: if the pending changes are one
     related unit of work (e.g. a class + its spec, or several edits that only make
     sense together), suggest a single commit. If they're actually separate concerns
     that happen to be uncommitted at the same time (e.g. a workflow-rule change in
     `CLAUDE.md`, an unrelated README edit, and a `.gitignore` tweak), suggest that
     many separate commits instead, each with its own message — don't collapse
     unrelated work into one commit just because it's convenient.
3. **When a step's work is complete and its spec(s) pass**, say clearly that the
   branch is done and it's time to open a PR, then write a PR description
   (see PR descriptions below) for the user to paste in when they open the PR
   themselves from the GitHub UI. Don't run `gh pr create` — that step is manual.
4. **After a PR is merged**, suggest pulling `master` and creating the next step's
   branch — don't leave the local repo on a stale merged branch.
5. Mark the corresponding step in `docs/development-plan.md` as ✅ once merged (🔶 while
   in progress), so the plan file stays an accurate running status, not just a static
   checklist.

This applies whether the work is happening in chat or in Claude Code — both should
proactively suggest the branch/merge checkpoints and offer to draft the PR description
above rather than waiting to be asked.

## PR descriptions
- Write these like a human describing their own work to a teammate, not like
  generated changelog boilerplate. No "This PR introduces...", no restating the diff
  file-by-file, no filler sentences that don't carry information.
- Lead with what changed and why — the why matters more than the what, since the
  what is visible in the diff itself.
- Keep it short: a couple of sentences or a short paragraph is usually enough. Only
  add a bullet list if there are genuinely distinct pieces worth calling out
  separately (e.g. "also fixes an unrelated typo in X") — not one bullet per file
  touched.
- Mention test coverage in a line if relevant (e.g. "specs cover the happy path and
  both error shapes"), don't paste spec output.
- No Claude/Anthropic attribution (per Repo conventions above).

## Build order
See `docs/development-plan.md` for the full step-by-step build plan (branch names,
what each step contains, concept focus). Don't duplicate that list here — update the
plan file directly as steps are added, reordered, or completed.
