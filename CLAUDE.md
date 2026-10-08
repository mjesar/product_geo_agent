# ProductGeoAgent — Project Context

## How to work with me on this project
I'm learning AI agent development — this project is explicitly a learning exercise, not
just a deliverable. Please:
- **You write the code, chunk by chunk — not the whole file in one shot.** I want to
  stay engaged and follow what's happening rather than have a finished file appear all
  at once with nothing to absorb it. Write one small piece per turn (e.g. a class's
  initializer, pause; then one method, pause; then the next), for files under `app/`
  and `spec/` alike.
- Explain *why* before/while you write each chunk — what the piece does and why it's
  shaped that way — especially anything related to the agent loop, tool-calling, or
  `little_ghost`'s API. Don't just narrate what the code does.
- After each chunk, pause. Let me read it, run it, and ask questions before writing the
  next piece — don't chain multiple pieces together without checking in.
- Specs can move faster than app code — a full spec file in one turn is fine, since
  specs are verification, not the learning target. App code under `app/` still goes
  chunk by chunk.
- When introducing a new agent concept (tool schemas, reasoning loops, conditional
  tool selection, self-correction, etc.), briefly explain the concept itself, not just
  the implementation.

## What this is
A Ruby on Rails CLI agent that rates how AI-discoverable a Shopify product is (GEO/AEO) —
whether AI shopping assistants would surface, recommend, or cite it. Built as an
agent-development learning project using the `little_ghost` gem.

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
The `little_ghost` agent class is `GeoAuditAgent` (`app/agents/geo_audit_agent.rb`), not
`ProductGeoAgent` — that name is already taken by Rails' own app module (defined in
`config/application.rb`, derived from the app name). Reusing it doesn't raise an error;
Zeitwerk just silently hands back the empty app module instead of loading the agent file,
so this isn't a naming preference, it's a hard collision. Leave the class named
`GeoAuditAgent`.

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

System prompt strategy (not a fixed pipeline): the agent starts with the product data,
uses the description to judge how deep to go, falls back from the FAQ page to the FAQ
metafield before concluding there's no FAQ content, checks structured data, and runs
the AI citation check last. It then returns three poor/fair/good ratings and no number:
the score is computed in Ruby, and the top gaps are explained by a second, tool-free
call.

The current prompt is the source of truth, not a copy here:
`app/prompts/geo_audit/system_prompt.erb`.

## Scoring rubric (weights calibrated in step 9, not changed)
Source of truth: `WEIGHTS` in `app/services/geo_audit/score.rb`. If this table and that
file ever differ, the file wins. Step 9 ran the rubric against real sandbox products and
fixed leaks in the checks and prompts, but the weights themselves are unchanged from the
original draft. Three items (description, buyer questions, specs) are rated
poor/fair/good by the model (none, half or full points); the rest are computed in code.

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

## Observability & evals (observability built in step 8.4, evals built in step 10, see `docs/development-plan.md`)
RSpec specs prove correctness: the code doesn't crash, and returns the right shape.
They prove nothing about two other things that matter for an agentic system, and both
were real gaps here, not just nice-to-haves:
- **Observability**: built in step 8.4 (`audit-visibility`, plus the
  `reporter-redesign` follow-up). Before it, a completed audit run only showed the final
  score, with no visibility into which tools the agent called, in what order, with what
  arguments, how long each took, or where it failed. Now a reporter object receives an
  event from every part of an audit, so `bin/audit` prints a readable live trace (and
  `--verbose` / `--trace` go deeper), useful for debugging during development and for
  showing the agent's actual behavior, not just the final score.
- **Evals**: RSpec can't tell you whether the agent's *judgment* is any good (is the
  score right, are the flagged gaps the actual gaps), only whether the code ran
  without crashing. Built in step 10: hand-written expectations per sandbox product
  (`spec/evals/expectations.yml`) that `bin/eval` runs the real agent against several
  times, reporting a verdict per check across the runs, plus drift against a saved
  baseline (`spec/evals/baseline.json`). Conventions: write a product's expectations
  before its first run, never in CI or the default `rspec` run (it makes real Gemini
  calls), and only replace the baseline on purpose with `--save-baseline`. The store's
  state matters: the FAQ page and metafield settings change every product's result.

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
- **Gemini free tier rate limits**: one audit makes roughly 7-8 requests (5-6 agent
  turns, 1 for the citation tool's own call, 1 for the gaps explanation), and hit 9
  in one minute during testing. As of 2026-09-28, `gemini-flash-lite-latest` (mapped
  to "Gemini 3.5 Flash Lite" in Google AI Studio) was rate-limited at 15
  requests/minute, 500/day, 250K tokens/minute on the free tier — requests are the
  binding constraint, not tokens. These numbers change; check
  https://aistudio.google.com/rate-limit instead of trusting this note.
  `little_ghost`'s Gemini adapter has no built-in retry (confirmed by reading its
  source — other adapters like OpenAI-compatible do), so `GeoAudit::RetryPolicy`
  retries 503s (5s/15s/30s backoff) and 429s (15s/30s/60s) ourselves, both for the
  agent's own turns (`GeoAudit::ModelErrorRecovery`, via `after_model_error`) and the
  two bare `LittleGhost.generate` calls (`GeoAudit::Retrier`). See step 8.2 in
  `docs/development-plan.md`. A real 429's error body hasn't been seen yet (only 503s
  so far) — if one shows up, check whether it carries a structured `retryDelay`
  field worth parsing instead of the flat backoff.
- No delivery-date or review-aggregation checks in v1 (Storefront API has no universal
  fields for these) — noted as a possible future `check_fulfillment_clarity` tool
- **Gemini model availability**: `little_ghost`'s own docs example uses
  `gemini-2.5-flash` — this is deprecated for new users (404). Their own suggested
  replacement, `gemini-3.8-flash`, was returning 503 "high demand" errors as of Sept
  2026 (confirmed transient via raw API, not our bug). Currently using
  `gemini-flash-lite-latest`, which works. If this project stops working against
  Gemini with a 404/model-not-found error, check for a model name change first before
  assuming the code broke.
- **Multi-turn tool calling against Gemini needed three `little_ghost` fixes (now
  released in 0.11.0)**: the first real multi-tool run in this project surfaced three
  bugs in `little_ghost` 0.10.0, none in this app's own code: Gemini
  `thought_signature` not echoed back on the next turn
  ([#110](https://github.com/littleghostai/little_ghost/issues/110), fixed by
  [#112](https://github.com/littleghostai/little_ghost/pull/112)), the tool-call id
  sent as `functionResponse.name` instead of the function name
  ([#111](https://github.com/littleghostai/little_ghost/issues/111), fixed by
  [#113](https://github.com/littleghostai/little_ghost/pull/113)), and `Agent` subclass
  hooks silently dropped on `.ask`
  ([#114](https://github.com/littleghostai/little_ghost/issues/114), fixed by
  [#115](https://github.com/littleghostai/little_ghost/pull/115)). All three PRs were
  merged upstream, and the `Gemfile` now uses the released `~> 0.11.0` instead of the
  old fork pin. If a Gemini tool-calling run ever fails with a 400 about
  `thought_signature` or `functionResponse`, check the installed `little_ghost`
  version first.
- **Sandbox storefront is password-protected, and the toggle to disable it is locked**:
  the store is on a no-plan/development Shopify plan, and Shopify force-enables
  password protection for those — Admin → Online Store → Preferences shows the toggle
  greyed out, not just switched on. `CheckStructuredDataTool` (step 3) needs a real
  page fetch to test against actual data, so it includes a small
  `ShopifyStorefront::PasswordAuth` piece that logs in via `/password`.
  **Non-obvious wrinkle found while building it**: the login POST needs a Rails CSRF
  `authenticity_token` scraped from a prior `GET /password` (tied to that request's
  session cookie) — without it, Shopify silently treats *any* password, right or
  wrong, as incorrect and always re-renders the same error page, which looked
  deceptively like a generic response at first. `PasswordAuth` does a `GET` for the
  token, then `POST`s it alongside the password, using a `faraday-cookie_jar`-backed
  connection so the session cookie carries automatically between the two requests and
  into later page fetches. If the store ever moves to a paid plan, this becomes
  unnecessary but shouldn't need removing — `authenticate!` already no-ops when
  `GET /password` doesn't return a form (i.e. the store isn't gated).

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
