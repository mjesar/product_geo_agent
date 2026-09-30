# ProductGeoAgent: a GEO/AEO audit agent for Shopify products

[![CI status](https://github.com/mjesar/product_geo_agent/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/mjesar/product_geo_agent/actions/workflows/ci.yml)

**ProductGeoAgent is an agentic generative AI tool that checks whether AI shopping assistants (ChatGPT, Gemini, Perplexity, Google AI Overviews) can find, understand and recommend a Shopify product.** It is a Ruby on Rails command-line agent that scores a product's AI discoverability from 0 to 100 and names the top gaps to fix.

Built as a hands-on agentic AI learning project in Ruby, using the [`little_ghost`](https://github.com/littleghostai/little_ghost) gem for tool calling and Gemini as the model.

## What are GEO and AEO?

**GEO (generative engine optimization)** means making your content easy for generative AI tools such as ChatGPT, Gemini and Perplexity to understand, quote and recommend. **AEO (answer engine optimization)** is the same idea aimed at direct answers: a clear FAQ, specific product details and machine-readable markup (schema.org JSON-LD) give an assistant something concrete to cite. Classic SEO is about ranking in a list of links. GEO and AEO are about being the answer.

## What it does

Give it a product from a Shopify store, and the agent:

1. Fetches the product's data (title, description, images, variants) via the Shopify Storefront API
2. Checks for FAQ content — a dedicated FAQ page first, falling back to product metafields
3. Fetches the live product page and checks for structured data (`Product`/`FAQPage` schema.org markup)
4. Asks an LLM directly whether it would recommend this product for a relevant buyer query
5. Synthesizes all of the above into a discoverability score with the top priority gaps to fix

The agent decides which checks to run and in what order — it isn't a fixed pipeline. If a product's description is already strong, it can skip deeper checks; if the FAQ page check comes back empty, it tries the metafield fallback before concluding there's no FAQ content at all.

Seven checks make up the 0 to 100 score: description quality, buyer questions answered, image alt text, variant and spec clarity, FAQ content, structured data, and whether an AI assistant would recommend the product. The [user guide](docs/user-guide.md) walks through each one with real audit output.

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
| `--trace-path=PATH` | Same, but write to `PATH` instead of the default auto-generated filename |

## Why

Most AI-readiness "audits" are just SEO checklists with an AI label on them. This project focuses specifically on what's unique to AI discoverability: whether an LLM would actually cite or recommend the product, not just whether the page is technically well-formed.

## Frequently asked questions

**How do I check whether ChatGPT or other AI assistants can recommend my Shopify product?**
Run `bin/audit PRODUCT_HANDLE`. The agent reads the product through the Shopify Storefront API, checks FAQ content and structured data, asks an LLM whether it would recommend the product, and returns a 0 to 100 score with the top gaps to fix. It measures how well a listing is set up, not whether an assistant will actually recommend it.

**What is AI discoverability?**
How easily AI assistants can find, understand and cite a product. It depends on a specific description, answers to common buyer questions, FAQ content and machine-readable structured data.

**Does structured data (JSON-LD) help AI search?**
It gives software a clean, machine-readable description of the product, which is why the tool checks for it. This tool cannot prove that any particular assistant uses it, so the score treats it as one signal out of seven, not a guarantee.

**Why is the "would an AI recommend it" check usually zero?**
For a small or unknown store, assistants rarely name the product when asked an open buyer question. That is the honest result, not a bug.

**Does it change my store?**
No. It only reads, through the Shopify Storefront API.

**Is it a fixed checklist or a real AI agent?**
A real agent. A model picks the next check after each result, using tool calling. For example, it looks at the product's own FAQ field only when no FAQ page is found.

**Can I trust the score?**
Partly. The arithmetic is plain Ruby, so the same facts always give the same score. Three items (description, buyer questions, specs) are rated by the model and can vary from run to run, and an eval harness to measure that is planned. See the next section.

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
- Gemini API (generative AI model, free tier) as the model provider
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
- [`docs/user-guide.md`](docs/user-guide.md) - plain-language guide to what the tool does, with real audit outputs (no code reading needed)
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
