# Agent Development Concepts — Learning Notes

Running notes on agent-development concepts as I learn them while building
`ProductGeoAgent`. Update this as new concepts come up during the build — this is the
learning record, not just a technical doc.

## What makes something an "agent" vs. a single API call

A single LLM call is: send a prompt, get text back, done. An **agent** has a
**reasoning loop**: the model can look at real data (from a tool call) and decide what
to do next before giving a final answer. The loop is:

```
question → model reasons → (needs data? → call tool → get result → reason again) → final answer
```

The part in parentheses can repeat multiple times before the model is ready to answer.
That's the actual mechanism that makes it "agentic" rather than just "an API call
with extra steps."

## Tools

A tool is a function (in our case, a Ruby method) described to the model via a JSON
schema — name, description, and expected input parameters. The model doesn't run the
tool itself; it returns a structured "please call this tool with these arguments"
response, and *my code* actually executes it, then feeds the result back into the
conversation for the model to reason over.

Each round-trip (model decides → my code executes → result goes back) is a separate
API request. A single user question might cost several requests if the agent needs
multiple tool calls before it can answer.

## Why multiple granular tools instead of one combined tool

Two ways to structure tool access:
- **One mega-tool** that internally runs all the checks and returns one big result.
  Simple, but the *agent* isn't deciding anything — my Ruby code is doing all the
  orchestration, and the LLM is just summarizing what it's handed.
- **Multiple granular tools**, where the agent itself decides which to call, in what
  order, and whether to retry with a different one. This is what makes the reasoning
  loop actually meaningful — the model is making real decisions, not just passing
  through a fixed pipeline.

Chose the second for `ProductGeoAgent`, specifically so the agent can:
- Skip deeper checks on a product whose description is already strong
- Try `check_faq_page` first, and only fall back to `check_faq_metafield` if that
  comes back empty

## Self-correction / conditional retry

Borrowed from the "agentic RAG" idea (a retrieval agent decides whether to retrieve at
all, and can retry with a different approach if the first attempt didn't help). Applied
here as: if `check_faq_page` finds nothing, the agent tries `check_faq_metafield`
before concluding there's genuinely no FAQ content — rather than giving up after one
failed lookup. This is driven by the system prompt's instructions, not fixed
if/else logic in Ruby — the *model* decides to retry.

## System prompt as strategy, not a script

The system prompt tells the agent the *strategy* ("try X first, fall back to Y if X
finds nothing, always run Z last") rather than a literal step-by-step script. The model
fills in the actual decision-making at runtime based on what each tool call returns.

## What a "trace" looks like

For a real audit, the sequence of tool calls (the trace) is the interesting part to
watch — e.g.:
```
get_product_data → (thin description) → check_faq_page (empty) →
check_faq_metafield (empty) → check_structured_data (missing) →
check_ai_citation (not mentioned) → final score + gaps
```
Different products will produce different traces depending on what the agent finds
along the way — that variability is the actual demonstration of "the agent is
deciding," not just executing a fixed script.

## Specs vs. evals

RSpec specs and evals answer different questions, and it's worth keeping them
distinct rather than expecting one to stand in for the other:

- **Specs prove the code handles the model's requests correctly.** Given that the
  model asked to call `check_faq_page`, does the tool return the right shape? Given a
  missing product, does it raise the right error? These are deterministic questions
  with a correct answer, so they belong in RSpec with mocked model responses.
- **Evals prove the model's decisions are good.** Given the system prompt, does the
  model actually choose to call `check_faq_page` before `check_faq_metafield`? Is the
  final score reasonable? These aren't deterministic, an LLM can make a different
  (even correct) choice on a different run, so no mock can honestly answer them —
  only real runs against real products, compared to a hand-scored expectation (the
  planned eval harness, step 10), can.

`GeoAuditAgent`'s own spec suite reflects this split: `geo_audit_agent_spec.rb`
checks wiring only (tools registered, system prompt content) — no mocking of
multi-turn model behavior was built, since a fake model response would only prove
Ruby handles that fake response correctly, never that the real model would choose it.
`geo_audit_agent_live_spec.rb` is the one place that runs the real agent against a
real product with the real model — tagged `:live` and excluded from the default
suite, since it costs real Gemini quota and depends on the sandbox being reachable.

That first live run immediately proved the value of keeping it separate: it surfaced
a real bug (Gemini's `thought_signature` requirement for multi-turn tool calls isn't
supported by `little_ghost` 0.10.0's Gemini adapter — see Known limitations in
`CLAUDE.md`) that no mocked spec could ever have caught, since every mocked spec
necessarily assumes the model/adapter round-trip already works.

## Open questions / things to learn next
- How does `little_ghost` actually expose tool-call decisions — do I get visibility
  into *why* it picked a tool, or just the fact that it did?
- What happens if the model tries to call a tool that doesn't exist or with malformed
  arguments — how does the gem handle that failure mode?
- How much does the system prompt's exact wording affect whether it actually follows
  the "try X, fall back to Y" strategy reliably?
