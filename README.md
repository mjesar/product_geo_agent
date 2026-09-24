# ProductGeoAgent

A Ruby on Rails CLI agent that rates how AI-discoverable a Shopify product is — whether AI shopping assistants (ChatGPT, Gemini, Perplexity, AI Overviews) would actually surface, recommend, or cite it.

Built as a hands-on agent-development learning project using the [`little_ghost`](https://github.com/littleghostai/little_ghost) Ruby gem, and as a source of reusable building blocks for a planned GEO/AEO Shopify app.

## What it does

Give it a product from a Shopify store, and the agent:

1. Fetches the product's data (title, description, images, variants) via the Shopify Storefront API
2. Checks for FAQ content — a dedicated FAQ page first, falling back to product metafields
3. Fetches the live product page and checks for structured data (`Product`/`FAQPage` schema.org markup)
4. Asks an LLM directly whether it would recommend this product for a relevant buyer query
5. Synthesizes all of the above into a discoverability score with the top priority gaps to fix

The agent decides which checks to run and in what order — it isn't a fixed pipeline. If a product's description is already strong, it can skip deeper checks; if the FAQ page check comes back empty, it tries the metafield fallback before concluding there's no FAQ content at all.

**[→ Architecture map](https://claude.ai/artifact/PrAVHZAaoiwTp3bQYcqCPk)** — diagrams of the system architecture, the agent's decision flow, and the dev workflow used to build this.

## Why

Most AI-readiness "audits" are just SEO checklists with an AI label on them. This project focuses specifically on what's unique to AI discoverability: whether an LLM would actually cite or recommend the product, not just whether the page is technically well-formed.

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

🚧 Early development — building tool-by-tool, starting with product data retrieval.

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
