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

## What calibrating it found

Before trusting the score, I ran the agent against three sandbox products (a full listing, a thin one and a blank one) and compared each score to what it should have been. That turned up two grounding failures in the generated explanations. The first was stale evidence: a check got stricter but the sentence describing its failure did not, so the model gave advice that was right for the old check and wrong for reality. The second was unreliable arithmetic: given correct per-item numbers, it still wrote "lost 55 points" when 75 were lost. The fix both times was to move the computation into Ruby and let the model describe only finished, already-correct results. Each fix was verified on one run per product, which confirms direction, not stability, so Step 10 built an eval harness (`bin/eval`) that runs each product several times. [Full write-up](docs/agent-concepts.md#grounding-keeping-the-models-words-tied-to-real-facts).

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
calibrated against real sandbox products (see above). An eval harness (`bin/eval`)
runs each product several times against hand-written expectations to measure how stable
the agent's ratings are from run to run; it has run on two products so far.

## Docs

- [Architecture map](https://claude.ai/artifact/PrAVHZAaoiwTp3bQYcqCPk) — diagrams: system architecture, agent decision flow, dev workflow
- [`docs/user-guide.md`](docs/user-guide.md) - plain-language guide to what the tool does, with real audit outputs (no code reading needed)
- [`docs/development-plan.md`](docs/development-plan.md) — step-by-step build plan, one branch/PR per step
- [`docs/evals.md`](docs/evals.md) - how the eval harness checks whether the agent's ratings hold up (`bin/eval`)
- [`docs/agent-concepts.md`](docs/agent-concepts.md) — running notes on agent-development concepts learned while building this
- [`docs/faq.md`](docs/faq.md) - short answers on building AI agents with Ruby on Rails, and on checking whether AI assistants can recommend a Shopify product
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

## Frequently asked questions

Short answers for developers building AI agents with Ruby on Rails, and for store owners
checking whether AI assistants can recommend a Shopify product, are in
[`docs/faq.md`](docs/faq.md). A few of them:

- [How do I build an AI agent in Ruby on Rails?](docs/faq.md#how-do-i-build-an-ai-agent-in-ruby-on-rails)
- [What is tool calling (function calling), and how does it work in Ruby?](docs/faq.md#what-is-tool-calling-function-calling-and-how-does-it-work-in-ruby)
- [How do I stop an LLM from getting numbers wrong?](docs/faq.md#how-do-i-stop-an-llm-from-getting-numbers-wrong)
- [How do I test an AI agent with RSpec?](docs/faq.md#how-do-i-test-an-ai-agent-with-rspec)
- [How do I check whether ChatGPT or other AI assistants can recommend my Shopify product?](docs/faq.md#how-do-i-check-whether-chatgpt-or-other-ai-assistants-can-recommend-my-shopify-product)
- [Does it work with BigCommerce?](docs/faq.md#does-it-work-with-bigcommerce)
- [Can I trust the score?](docs/faq.md#can-i-trust-the-score)
