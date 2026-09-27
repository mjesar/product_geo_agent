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

## System prompts

**System prompt vs. user message**

A **user message** is the specific ask for one turn — "Audit the Shopify product with
handle 'the-complete-snowboard'." A **system prompt** is standing instructions the
model follows on *every* message in the conversation, regardless of what the user
message says. `GeoAuditAgent`'s system prompt (`app/prompts/geo_audit/system_prompt.erb`)
never mentions a specific product — it says what an audit *is*, what order to run the
five tools in, and how to score the result. The user message just supplies the one
thing that varies: which product handle to run it against.

Think of the system prompt as the job description, and the user message as the
specific work order for today.

**Practices for writing one** (cross-checked against `system_prompt.erb`):

- **Role and goal first.** Before any instructions, say what the model *is* and what
  it's for. `system_prompt.erb` opens with "You audit a single Shopify product for how
  discoverable it would be to AI shopping assistants" — that framing shapes everything
  that follows, since "for AI assistants" produces different judgment than "reads well
  to a human" would.
- **Explain why, not just what.** "Never pass the product's own name into the question
  you'd ask — the point is whether it comes up unprompted" tells the model the *reason*
  for the rule, not just the rule. A model that understands why is more likely to apply
  the same judgment correctly to a case the prompt didn't spell out explicitly.
- **Say what to do, not only what not to do.** A rule like "don't stop after
  check_faq_page finds nothing" only describes a gap. "Call check_faq_metafield before
  concluding there's no FAQ content" tells the model the actual next action to take.
- **Strategy, not a script.** The prompt says try X first, fall back to Y if X finds
  nothing, always run Z last — it doesn't hardcode "if description.length < 50 then...".
  The model fills in the actual decision at runtime based on what each tool call
  returns. A literal step-by-step script would just be Ruby wearing a prompt as a
  costume, and would defeat the point of having an agent at all.
- **Cover edge cases explicitly.** "If it finds nothing" (empty FAQ result), "once you
  already know the product's title" (an ordering dependency) — naming edge cases in the
  prompt is cheaper than discovering the model mishandles them during a real run.
- **Specify the output format.** The rubric table plus "finish with the overall score
  and the top 2-3 gaps" tells the model exactly what shape the final answer needs, not
  just what to think about along the way.
- **No contradictions.** A prompt that says "be thorough" in one line and "be concise"
  in another forces the model to guess which one wins — conflicting instructions can
  degrade a model's output in unpredictable ways, worse than either instruction alone.
- **Test changes with evals, not vibes.** A wording change can shift model behavior in
  ways that read fine on the page but don't hold up in a real run (see the eval
  harness step in `docs/development-plan.md`).
  A prompt is code that happens to be written in English, and needs the same "does this
  actually work" verification any other code change gets.

**Tool descriptions are prompts too**

It's tempting to think only the system prompt counts as "the prompt" and tool
definitions are just plumbing, but every tool's `description` field is also read by the
model at decision time — it's how the model decides *which* tool to call and *when*.
`GetProductDataTool`'s description ends with "Always call this first — the
description's length and quality determine how deep the remaining checks need to go,"
which is doing real prompting work, not just documentation. A vague tool description
("fetches product data") gives the model far less to reason from, even sitting under a
well-written system prompt.

**System prompt vs. prompt engineering vs. context engineering**

These get used interchangeably but mean different things:
- A **system prompt** is one specific artifact: the standing instructions text itself.
- **Prompt engineering** is the practice of writing and iterating on prompt text
  (system prompts, user messages, tool descriptions) to get better model behavior —
  wording, examples, structure.
- **Context engineering** is the broader discipline: deciding *everything* that ends up
  in the model's context window before it responds — which tools are available, what
  data a tool call returns and in how much detail, what's summarized vs. included in
  full, what conversation history is kept vs. dropped. The system prompt is one piece
  of the context; so is every tool result the agent has accumulated by the time it
  makes its final decision. Prompt engineering optimizes the words; context engineering
  optimizes what's in the room at all.

**What belongs in code vs. in the model**

Right now, `system_prompt.erb` asks the model to calculate the final score out of 100
itself, by reading the rubric table and doing the weighted arithmetic in its head.
That's the wrong split of responsibility: arithmetic is exactly the kind of thing a
language model is bad at being *consistent* about — the same tool results could produce
a slightly different score on two different runs, since nothing about token-by-token
generation guarantees the same arithmetic twice.

**Planned improvement** (see the new step in `docs/development-plan.md`): move score
calculation into Ruby, computed directly from the tool results the agent already
collected (FAQ content found → +15, structured data present → +15, etc.), and leave the
model responsible only for what it's actually good at — explaining the gaps in plain
language. The general rule this suggests: if a step has one deterministic correct
answer, do it in code; if a step requires judgment over unstructured content, that's
where the model earns its keep.

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
