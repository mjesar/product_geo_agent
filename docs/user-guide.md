# User guide: how to check whether AI assistants can recommend your Shopify product

This guide shows store owners, and anyone evaluating the project, how to check whether
AI shopping assistants (ChatGPT, Gemini, Perplexity) can find and recommend a Shopify
product using this tool. You do not need to read any code. Every output shown below is a
real run against a real (sandbox) Shopify store, not a mock-up.

## What is AI discoverability, and what does this tool do?

More and more shoppers ask an AI assistant (ChatGPT, Gemini, Perplexity and so on) what
to buy, instead of searching a store. Whether a product shows up in those answers
depends on whether the assistant can understand it: is there a real description, are the
common buyer questions answered, is the page marked up so software can read it?

Making a product easy for AI assistants to find and recommend is called **generative
engine optimization (GEO)** or **answer engine optimization (AEO)**. It is the AI-era
cousin of SEO: instead of trying to rank in a list of links, you are trying to be the
answer the assistant gives. **AI discoverability** is how well a product is set up for
that. **Structured data** (schema.org JSON-LD) is machine-readable markup on the product
page that tells software the product's name, description and price without guessing from
the page layout.

This tool takes one product from a Shopify store and scores out of 100 how well it is
set up for that. It then names the biggest gaps in plain English, so the store owner
knows what to fix first. It never changes anything in the store. It only reads.

The "agent" part: the tool is not a fixed checklist. An AI model decides which check to
run next based on what it has found so far. For example, if the store has no FAQ page,
it looks for FAQ content somewhere else before concluding there is none.

## What does the audit check?

Seven things, worth 100 points in total:

| What it looks at | Points | Who decides |
|---|---|---|
| Is the description detailed and specific? | 15 | the AI model rates it poor, fair or good (none, half or full points) |
| Does the product's own text answer common buyer questions (sizing, care, what is in the box)? | 20 | the AI model, same three levels |
| Do the product images have alt text? | 10 | code, based on the share of images that have it |
| Are the variants clear and informative (not just "Default Title")? | 10 | the AI model, same three levels |
| Does the store have FAQ content, as a FAQ page or a product-level field? | 15 | code, yes or no |
| Does the product page carry machine-readable data (a Product block with a description and offers)? | 15 | code, yes or no |
| When an AI is asked a buyer question, does it recommend this product without being told its name? | 15 | code, based on what the AI answered |

Two of these are worth knowing about up front. The last one is almost always a zero for
a small or unknown store, because assistants simply do not know the product yet, and that
is the honest answer, not a bug. And only three of the seven are judged by the model. The
rest, and the final number, are plain code, so the same facts always give the same score.

## How do I run an audit?

You need a Shopify store with a read-only Storefront API token and a Gemini API key
(the free tier is enough). Setup, including the environment variables, is in the
[README](../README.md#setup). Then:

```bash
bin/audit PRODUCT_HANDLE
```

The handle is the last part of a product's URL, for example `the-complete-snowboard`. A
run takes roughly 20 to 70 seconds and makes about 7 requests to the model, depending on
how busy the model service is.

| Flag | What it does |
|---|---|
| `--verbose` | Also prints each check's full raw input and result. Useful for debugging. |
| `--trace` | Saves a redacted, line-by-line record of the whole run to the `traces/` folder. |
| `--trace-path=PATH` | Same, but saves to a path you choose. |

To see how an audit runs, step by step, including the two points where the agent makes
a real decision (how hard to look, and whether to try the FAQ fallback), open the
[architecture map](https://claude.ai/artifact/PrAVHZAaoiwTp3bQYcqCPk). It also marks
which of those decisions have been seen in a real run.

## How do I read the results? A real example

This is the latest run on a product whose listing was written properly. The numbers in
square brackets are explained underneath.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Auditing: the-complete-snowboard                            [1]
  Model: gemini:gemini-flash-lite-latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
→ Thinking...                                        (1.3s)   [2]
  ✓ get_product_data → "The Complete Snowboard" · 5 variants · $699.95   [3]
→ Thinking...                                        (1.7s)
  ✓ check_faq_page → FAQ page found: "FAQ"
→ Thinking...                                        (1.3s)
  ✓ check_structured_data → Product schema: yes · FAQ schema: no
→ Thinking...                                        (1.4s)
  ✓ check_ai_citation → not mentioned as a recommendation
→ Thinking...                                        (1.9s)
  ✓ Reasoning complete                                        [4]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Score: 80 / 100                                             [5]

  Why: Your product earned an 80 / 100 score, with Total points
  lost amounting to 20. The biggest issue is the AI citation
  check, which lost 15 of 15 points because the AI assistant
  did not mention this product; unfortunately, this is hard
  for you to fix directly since it depends on external AI
  models discovering and citing your brand. Additionally,
  you lost 5 of 10 points for clear specs/variants because
  the variants are labeled with distinct color names, but
  they lack informative differences since every color shares
  the exact same length and specifications—to address this,
  update your product copy or metafields to highlight unique
  details or use cases for each color variation.              [6]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  7 Gemini calls · 10010 in / 1285 out tokens · 18.4s total   [7]
```

1. **The product and the model** being used for this run.
2. **"Thinking..."** is the model deciding what to do next. The time is how long that
   decision took.
3. **A tick and a check name** is one real check that ran, with a one-line summary of
   what it found. Here it found 5 variants at one price, a FAQ page, and product data
   on the page, and it asked an AI whether it would recommend the product (it would
   not).
4. **"Reasoning complete"** means the model has everything it needs.
5. **The score**, worked out by code from what the checks found, not by the model.
6. **The explanation** of the biggest gaps. This is the one part written by the model,
   from a finished breakdown of points lost. (The suggestion about giving each color its
   own specifications is debatable, since colors of one board really do share specs. It
   is an example of the model's advice being worth reading critically.)
7. **Cost of the run:** how many requests, how many tokens, and the total time.

## Real audit results, including the ones that were wrong

I ran the tool against three products in a sandbox store, chosen to be one good listing
(`the-complete-snowboard`, which I gave a full description), one thin listing
(`the-videographer-snowboard`, three short sentences) and one blank listing
(`the-out-of-stock-snowboard`, nothing written). I compared each score with what it
should have been, and fixed the tool when it was wrong. The scores over time:

| Round | Good listing | Thin listing | Blank listing | What was going on |
|---|---|---|---|---|
| 1 | 65 | 33 | 25 | The store had no FAQ page yet |
| 2 | 85 | 68 | 50 | FAQ page added. Each should have gone up 15 points, not 20, 35 and 25 |
| 3 | 85 | 48 | 40 | After the fix described below |
| 4 | 80 | 48 | 25 | After two more fixes (see the last section) |

### Why round 2 was wrong

The store has one FAQ page, and it already earns its own 15 points. But the tool also
let the model count that same page again when judging whether *each product's own text*
answers buyer questions. So every product got credit for a FAQ page the product itself
never mentioned. The thin listing, which says nothing about sizing or care, jumped from
33 to 68 the moment the FAQ page existed. The fix was one sentence in the model's
instructions: judge only the product's own content.

Here is the thin listing, run against the same store and the same product text, before
and after that one sentence.

**Before the fix: 68 (too high)**

<details>
<summary>Full output</summary>

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Auditing: the-videographer-snowboard
  Model: gemini:gemini-flash-lite-latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
→ Thinking...                                        (1.2s)
  ✓ get_product_data → "The Videographer Snowboard" · 1 variant · $885.95
→ Thinking...                                       (20.1s)
  ✓ check_faq_page → FAQ page found: "FAQ"
→ Thinking...                                        (1.3s)
  ✓ check_structured_data → Product schema: yes · FAQ schema: no
→ Thinking...                                        (1.4s)
  ✓ check_ai_citation → not mentioned as a recommendation
→ Thinking...                                        (1.9s)
  ✓ Reasoning complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Score: 68 / 100

  Why: Your product is losing the most points due to a complete
  lack of specific variants—it currently only shows a
  generic 'Default Title' instead of actual length and width
  options—which you can fix by adding your specific product
  variants. Additionally, AI assistants are not citing your
  product because the description is too thin, missing
  crucial details like board flex, length options, and
  sizing recommendations that you need to add directly to
  the product copy.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  7 Gemini calls · 8247 in / 1222 out tokens · 51.1s total
```

</details>

Notice that the explanation never mentions buyer questions. That item was given full
credit, which is the bug.

**After the fix: 48 (what it should be)**

<details>
<summary>Full output</summary>

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Auditing: the-videographer-snowboard
  Model: gemini:gemini-flash-lite-latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
→ Thinking...                                        (1.8s)
  ✓ get_product_data → "The Videographer Snowboard" · 1 variant · $885.95
→ Thinking...                                        (1.3s)
  ✓ check_faq_page → FAQ page found: "FAQ"
→ Thinking...                                        (6.7s)
  ✓ check_structured_data → Product schema: yes · FAQ schema: no
→ Thinking...                                        (1.7s)
  ✓ check_ai_citation → not mentioned as a recommendation
→ Thinking...                                       (11.7s)
  ✓ Reasoning complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Score: 48 / 100

  Why: Your product is losing the most ground because zero points
  were awarded for answering common buyer questions, lacking
  specific flex ratings and sizing guides in the text, and
  offering only a single unlabeled Default Title variant
  instead of clear specs and length options. To fix these
  gaps, you need to add comprehensive buyer-focused details
  addressing board width and binding compatibility, while
  updating your product setup to include distinct, labeled
  size and length variants rather than a generic default.
  Additionally, you must improve your AI citation
  visibility, as current AI assistants are not mentioning
  this product in their responses.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  7 Gemini calls · 8337 in / 1055 out tokens · 36.7s total
```

</details>

Now the explanation names "zero points for answering common buyer questions", which is
exactly the item that had been wrongly credited before.

The blank listing shows the same thing.

**Before the fix: 50 (too high)**

<details>
<summary>Full output</summary>

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Auditing: the-out-of-stock-snowboard
  Model: gemini:gemini-flash-lite-latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
→ Thinking...                                        (1.2s)
  ✓ get_product_data → "The Out of Stock Snowboard" · 1 variant · $885.95
→ Thinking...                                        (1.4s)
  ✓ check_faq_page → FAQ page found: "FAQ"
→ Thinking...                                       (17.6s)
  ✓ check_structured_data → Product schema: yes · FAQ schema: no
→ Thinking...                                        (2.0s)
  ✓ check_ai_citation → not mentioned as a recommendation
→ Thinking...                                       (14.0s)
  ✓ Reasoning complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Score: 50 / 100

  Why: Your product page is missing a description entirely and
  lacks size, length, or width variants (offering only a
  single "Default Title"), costing you a combined 25
  points—you need to add a detailed description of the
  snowboard's materials and shape, and set up clear variant
  options. Additionally, while you have a general FAQ page,
  the product page itself fails to answer critical
  buyer-specific questions like sizing guidance, which cost
  you 10 points and likely contributed to AI assistants
  failing to cite the product.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  7 Gemini calls · 7991 in / 1123 out tokens · 70.0s total
```

</details>

A listing with no description at all was being given 10 points for "answering buyer
questions", and the explanation even says so ("while you have a general FAQ page, the
product page itself fails to answer... which cost you 10 points").

**After the fix: 40 (what it should be)**

<details>
<summary>Full output</summary>

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Auditing: the-out-of-stock-snowboard
  Model: gemini:gemini-flash-lite-latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
→ Thinking...                                        (1.2s)
  ✓ get_product_data → "The Out of Stock Snowboard" · 1 variant · $885.95
→ Thinking...                                        (1.5s)
  ✓ check_faq_page → FAQ page found: "FAQ"
→ Thinking...                                        (1.1s)
  ✓ check_structured_data → Product schema: yes · FAQ schema: no
→ Thinking...                                        (7.3s)
  ✓ check_ai_citation → not mentioned as a recommendation
→ Thinking...                                        (3.0s)
  ✓ Reasoning complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Score: 40 / 100

  Why: Your product is losing a massive 35 combined points
  because the product description is completely blank and
  the sole variant is stuck on an uninformative "Default
  Title." To fix this, you need to write a detailed product
  description covering materials and use cases, and replace
  the default variant with distinct choices for length and
  width. Additionally, you are losing 15 points because AI
  assistants are currently failing to mention this product,
  which you can resolve by building out that descriptive
  text and buyer-focused details so search crawlers actually
  have context to index.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  7 Gemini calls · 8225 in / 1072 out tokens · 27.2s total
```

</details>

Two of these numbers deserve a second look, and I would rather say so than hide it. The
blank listing still scores 40 here, although 15 of those points come from a product
data block that has an empty description (that was the next problem, described below).
And the explanation says "35 combined points" for two gaps that are really worth 25, so
the model's own arithmetic was off. That is the third thing this page covers.

## What changed after that

Two more problems turned up when the later runs were compared with the expected scores,
and both were fixed:

- **Points that every product gets.** A product with an empty description still carried
  a product data block on its page, and the tool gave it full credit for having one. The
  tool now requires the block to contain a description and offers. A product with no
  images used to get full credit for alt text and now gets none. The blank listing
  dropped from 40 to 25.
- **The explanation's arithmetic.** The model was given correct numbers and still added
  them up wrong in its prose. The tool now works out how many points each gap lost, sorts
  them, and hands the model a finished list to describe. Checked on all three listings,
  every number in the explanation then matched the score breakdown.

The full reasoning for both, including the code involved, is in the grounding section
of [`agent-concepts.md`](agent-concepts.md#grounding-keeping-the-models-words-tied-to-real-facts),
and the dated log of findings is in the Step 9 entry of
[`development-plan.md`](development-plan.md).

## Can I trust the score? What it does and does not mean

- **It is a measure of how well a listing is set up, not a prediction of sales or of
  exact AI behavior.** Two listings with the same score can still differ.
- **The AI-citation line will usually be zero for a small or unknown store.** That is
  the honest answer, not a failure of the tool.
- **The model-rated items can vary from run to run.** On the same unchanged good
  listing, the variants were rated fair, then good, then good, then fair, which moves
  the score by 5 points each time. The code-calculated items do not vary. This is the
  main reason the next planned step is an evaluation harness that runs each product
  several times and reports the spread.
- **Each fix above was checked on one run per product.** That shows the direction of the
  change, not that the tool is now proven correct.
- **It only reads.** Nothing in the store is ever changed.

## Where to go next

- [README](../README.md): setup, the flags, and how the project is put together.
- [`docs/agent-concepts.md`](agent-concepts.md): the ideas behind it (what makes it an
  agent, how the score left the model, the grounding section).
- [`docs/development-plan.md`](development-plan.md): the build plan, step by step, with
  what each step found.
