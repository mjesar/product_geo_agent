# FAQ: building AI agents with Ruby on Rails, and auditing Shopify products for GEO/AEO

Short answers to common questions, taken from real work on ProductGeoAgent: an agentic
generative AI tool built with Ruby on Rails, the
[`little_ghost`](https://github.com/littleghostai/little_ghost) gem and Gemini. The first
part is for developers building AI agents in Ruby. The second is for store owners who
want to know whether AI assistants can recommend a Shopify product.

## Building AI agents with Ruby on Rails

### How do I build an AI agent in Ruby on Rails?

An agent is a loop. The model looks at what it knows and asks for a tool to be run, your
code runs it, the result goes back to the model, and this repeats until the model can
answer. In Rails that takes three pieces: tools (plain Ruby classes with a name, a
description and an input schema), a system prompt that explains the strategy, and an agent
class that registers the tools. ProductGeoAgent does this with the `little_ghost` gem:
[`geo_audit_agent.rb`](../app/agents/geo_audit_agent.rb) registers five tools from
[`app/agent_tools/`](../app/agent_tools), and the strategy lives in
[`system_prompt.erb`](../app/prompts/geo_audit/system_prompt.erb). The concepts are
explained with real examples in [`agent-concepts.md`](agent-concepts.md).

### What is tool calling (function calling), and how does it work in Ruby?

The model never runs code. It returns a structured request such as "call `check_faq_page`
with this product handle". Your Ruby code executes the tool and sends the result back as
the next message. Each round trip is a separate API request, so one audit here makes about
7 to 8 requests to the model. A tool is a class like
[`CheckFaqPageTool`](../app/agent_tools/check_faq_page_tool.rb): a name, a description the
model reads to decide when to use it, and a JSON input schema.

### How is an AI agent different from a single LLM call?

A single call sends a prompt and gets text back. An agent can look at real data between
steps and decide what to do next. In ProductGeoAgent the model picks the next check after
each result: it looks at the product's own FAQ field only when no FAQ page was found. That
decision is made by the model, not by an `if/else` in Ruby. See
[what makes something an agent](agent-concepts.md#what-makes-something-an-agent-vs-a-single-api-call).

### How should I organize an AI agent in a Rails app?

The layout used here: `app/agents/` for the agent class, `app/agent_tools/` for one class
per tool, `app/prompts/` for ERB prompt templates, and `app/services/` for everything that
is plain Ruby (scoring, retries, reporting). Keeping scoring and retries in services means
they can be tested without calling a model.

### Which Ruby gem can I use to build an AI agent with Gemini?

This project uses `little_ghost`, which has a Gemini adapter and runs the tool-calling
loop. With the released version (0.10.0) I hit three bugs in multi-turn Gemini tool
calling: thought signatures not sent back, the tool-call id sent as the function name,
and subclass hooks silently dropped. They are reported upstream as issues
[#110](https://github.com/littleghostai/little_ghost/issues/110),
[#111](https://github.com/littleghostai/little_ghost/issues/111) and
[#114](https://github.com/littleghostai/little_ghost/issues/114), with fixes in pull
requests #112, #113 and #115. All were still open as of October 2026, and this project's
Gemfile pins a fork that combines them. If you use `little_ghost` with Gemini, check those
first.

### How do I get structured JSON output from an agent in Ruby?

Use a result schema. In `little_ghost`, `result_schema` forces the final answer into a JSON
shape, validated with one automatic repair attempt.
[`GeoAuditAgent`](../app/agents/geo_audit_agent.rb) uses it to get exactly three ratings
(poor, fair or good, each with a one-sentence reason) instead of parsing a score out of
prose.

### How do I stop an LLM from getting numbers wrong?

Do not let it calculate. A model writes one word at a time and has no calculator, so sums
in prose are sometimes wrong. This project saw "lost 55 points" when 75 had been lost.
Compute the numbers in Ruby
([`Item#lost`, `Result#gaps` and `Result#total_lost`](../app/services/geo_audit/score.rb))
and give the model finished values to describe. The write-up is in
[the grounding section](agent-concepts.md#grounding-keeping-the-models-words-tied-to-real-facts).

### How do I handle Gemini rate limits and 503 errors in a Rails agent?

Retry with a wait between tries. The `little_ghost` Gemini adapter has no retry of its own,
so the app adds one. [`RetryPolicy`](../app/services/geo_audit/retry_policy.rb) retries 503
errors after 5, 15 and 30 seconds and 429 errors after 15, 30 and 60 seconds, both for the
agent's own turns and for separate model calls. Free-tier limits change, so check Google AI
Studio's rate limit page for current numbers.

### How do I test an AI agent with RSpec?

Separate what tests can prove from what they cannot. Specs with stubbed model and network
calls prove that tools, scoring and retries behave correctly, and the default suite makes
no network calls. They cannot prove the model makes good decisions. A spec tagged `:live`
runs the real agent against a real store and is excluded from the default run, and a
hand-scored eval set (planned) is how judgment gets measured. See
[specs vs. evals](agent-concepts.md#specs-vs-evals).

### How can I see what an AI agent is doing while it runs?

Send an event from every step to a reporter object. In [`bin/audit`](../bin/audit), a
terminal reporter prints each model turn and tool result as it happens, `--verbose` adds
the full inputs and outputs, and `--trace` writes a redacted JSON-lines record of every
request and response to `traces/`.

### Do I need MCP, a vector database or RAG to build an agent?

No. This agent uses none of them. It calls the Shopify Storefront GraphQL API directly,
because the job is structured scoring and not document retrieval. MCP servers and RAG are
different patterns, covered in a separate project,
[`shop_mcp_server`](https://github.com/mjesar/shop_mcp_server).

### Is Ruby a good language for AI agents?

For the orchestration part, in my experience yes. Most of an agent is HTTP calls to a
model API, running your own tools, and ordinary business logic, which Rails handles well.
Python has more machine-learning libraries, but an agent that calls a hosted model (here
Gemini) does not need them.

## Checking whether AI assistants can recommend a Shopify product

### How do I check whether ChatGPT or other AI assistants can recommend my Shopify product?

Run `bin/audit PRODUCT_HANDLE`. The agent reads the product through the Shopify Storefront
API, checks FAQ content and structured data, asks an LLM whether it would recommend the
product, and returns a 0 to 100 score with the top gaps to fix. It measures how well a
listing is set up, not whether an assistant will actually recommend it. The
[user guide](user-guide.md) shows real outputs.

### What is AI discoverability?

How easily AI assistants can find, understand and cite a product. It depends on a
specific description, answers to common buyer questions, FAQ content and machine-readable
structured data.

### What are GEO and AEO?

GEO (generative engine optimization) means making content easy for generative AI tools such
as ChatGPT, Gemini and Perplexity to understand, quote and recommend. AEO (answer engine
optimization) is the same idea aimed at direct answers. Classic SEO is about ranking in a
list of links, and GEO and AEO are about being the answer.

### Does structured data (JSON-LD) help AI search?

It gives software a clean, machine-readable description of the product, which is why the
tool checks for it. This tool cannot prove that any particular assistant uses it, so the
score treats it as one signal out of seven, not a guarantee.

### Why is the "would an AI recommend it" check usually zero?

For a small or unknown store, assistants rarely name the product when asked an open buyer
question. That is the honest result, not a bug.

### Does it change my store?

No. It only reads, through the Shopify Storefront API.

### Can I trust the score?

Partly. The arithmetic is plain Ruby, so the same facts always give the same score. Three
items (description, buyer questions, specs) are rated by the model and can vary from run
to run, and an eval harness to measure that is planned. See
[what calibrating it found](../README.md#what-calibrating-it-found).

## Shopify, BigCommerce and other platforms

### Does this work with Shopify?

Yes. Shopify is the only platform supported today. The tool reads a store through
Shopify's Storefront GraphQL API, read-only, and reads the live product page for
structured data. Nothing in your store is changed.

### What do I need to run it against my Shopify store?

A read-only Storefront API access token with the product listings, product tags and
content scopes, your store domain (for example `your-store.myshopify.com`), and a Gemini
API key (the free tier is enough). The steps for getting the token are in
[`shopify-auth-setup.md`](shopify-auth-setup.md), and the environment variables are
listed in the [README](../README.md#setup).

### Does it work on a password-protected Shopify store?

Yes. Stores on a development plan are password-protected, which blocks reading the live
page. If you set `SHOPIFY_STOREFRONT_PASSWORD`, the tool logs in to the storefront first
and then reads the page. If the store is not password-protected, that step does nothing.

### Does it work with BigCommerce?

No, not today. The data-fetching tools call Shopify's API and use Shopify's product page
address, so a BigCommerce product cannot be audited with this tool as it stands.

### Could it be extended to BigCommerce or other platforms?

In principle, yes. The scoring and the explanation only work from what the checks return
(the product's description, images and variants, whether FAQ content exists, whether the
page has structured data, and whether an AI recommended it), so they would likely carry
over. What would have to be rewritten is the part that fetches that data from another
platform's API and page addresses. A related project,
[`ucp_catalog`](https://github.com/mjesar/ucp_catalog), is an early-stage Ruby gem aiming
to talk to catalog APIs from several providers through one configurable interface, with
Shopify first and other providers to follow as they offer compatible APIs. It is still in
development.
