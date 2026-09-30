# ProductGeoAgent

A Ruby on Rails CLI agent that rates how AI-discoverable a Shopify product is (GEO/AEO) — whether AI shopping assistants (ChatGPT, Gemini, Perplexity, AI Overviews) would actually surface, recommend, or cite it.

Built as a hands-on agent-development learning project using the [`little_ghost`](https://github.com/littleghostai/little_ghost) Ruby gem.

## What it does

Give it a product from a Shopify store, and the agent:

1. Fetches the product's data (title, description, images, variants) via the Shopify Storefront API
2. Checks for FAQ content — a dedicated FAQ page first, falling back to product metafields
3. Fetches the live product page and checks for structured data (`Product`/`FAQPage` schema.org markup)
4. Asks an LLM directly whether it would recommend this product for a relevant buyer query
5. Synthesizes all of the above into a discoverability score with the top priority gaps to fix

The agent decides which checks to run and in what order — it isn't a fixed pipeline. If a product's description is already strong, it can skip deeper checks; if the FAQ page check comes back empty, it tries the metafield fallback before concluding there's no FAQ content at all.

**[→ Architecture map](https://claude.ai/artifact/PrAVHZAaoiwTp3bQYcqCPk)** — diagrams of the system architecture, the agent's decision flow, and the dev workflow used to build this.

## Usage

```bash
bin/audit PRODUCT_HANDLE
```

Runs a full audit against a real Shopify product and prints a live view of what the
agent does as it happens: which tool it calls each turn, what it finds, and the final
score with the model's own explanation of the biggest gaps.

| Flag | What it does |
|---|---|
| `--verbose` | Also print each tool's full raw input and result, not just the summary — for debugging, not for a clean read |
| `--trace` | Write a redacted, JSON-lines trace of every event (including the real request/response sent to the model) to `traces/` |
| `--trace=PATH` | Same, but write to `PATH` instead of the default auto-generated filename |

## Why

Most AI-readiness "audits" are just SEO checklists with an AI label on them. This project focuses specifically on what's unique to AI discoverability: whether an LLM would actually cite or recommend the product, not just whether the page is technically well-formed.

## What calibrating it found

Before trusting the score, I ran the agent against three sandbox products (a full listing, a thin one and a blank one) and compared each score to what it should have been. That turned up two grounding failures in the generated explanations. The first was stale evidence: a check got stricter but the sentence describing its failure did not, so the model gave advice that was right for the old check and wrong for reality. The second was unreliable arithmetic: given correct per-item numbers, it still wrote "lost 55 points" when 75 were lost. The fix both times was to move the computation into Ruby and let the model describe only finished, already-correct results. Each fix was verified on one run per product, which confirms direction, not stability, so an eval harness is next. [Full write-up](docs/agent-concepts.md#grounding-keeping-the-models-words-tied-to-real-facts).

## Related work

This project covers agents and tool-calling end to end. For the other two pillars of
this agentic-commerce work — MCP server design, and RAG (pgvector + Voyage embeddings)
— see [`shop_mcp_server`](https://github.com/mjesar/shop_mcp_server), a separate
project exposing a Shopify-style store to LLM agents.

## Tech stack

- Ruby on Rails
- [`little_ghost`](https://github.com/littleghostai/little_ghost) for the agent/tool-calling loop
- Gemini API (free tier) as the model provider
- Shopify Storefront GraphQL API (read-only, no OAuth app install required)
- PostgreSQL

## Status

🚧 In development — the full pipeline works end to end: five tools, `GeoAuditAgent`
wiring them together with a real reasoning loop, deterministic scoring, retry/backoff
and usage tracking, and a CLI (`bin/audit`) with live visibility into what the agent
is doing, including a redacted `--trace` file for later inspection. It has been
calibrated against real sandbox products (see above). Next up: an eval harness to
measure how stable the agent's ratings are from run to run.

## Docs

- [Architecture map](https://claude.ai/artifact/PrAVHZAaoiwTp3bQYcqCPk) — diagrams: system architecture, agent decision flow, dev workflow
- [`docs/development-plan.md`](docs/development-plan.md) — step-by-step build plan, one branch/PR per step
- [`docs/agent-concepts.md`](docs/agent-concepts.md) — running notes on agent-development concepts learned while building this
- [`docs/shopify-auth-setup.md`](docs/shopify-auth-setup.md) — how the Storefront API token was set up

## Setup

```bash
bundle install
bin/rails db:create db:migrate
cp .env.example .env   # then fill in your keys
```

Required environment variables:

- `GEMINI_API_KEY` — Gemini API key (free tier), used by the agent's model and the AI citation check tool
- `SHOPIFY_STOREFRONT_TOKEN` — Shopify Storefront API access token (read-only)
- `SHOPIFY_STORE_DOMAIN` — e.g. `your-sandbox-store.myshopify.com`
- `SHOPIFY_STOREFRONT_PASSWORD` — only needed if the store is password-protected (see [`docs/shopify-auth-setup.md`](docs/shopify-auth-setup.md))
