# AI / Agent Monitoring — What & Why

## What it is

Tracing specialized for LLM apps.
LLM calls, agent runs, tool calls, and agent-to-agent handoffs are captured as
`gen_ai.*` spans carrying model, token usage, cost, and latency.
It is built on [tracing](tracing.md), so tracing must be on
(`tracesSampleRate`/`traces_sample_rate` > 0) — without spans there is nothing to attach
`gen_ai` data to.

Sentry supports detected AI SDKs on **JavaScript, Python, Laravel, and Cloudflare**.
Provider integrations cover OpenAI, Anthropic, Vercel AI, LangChain/LangGraph, Google
GenAI, HuggingFace, Pydantic AI, and Laravel AI (`litellm` needs explicit registration).
On Cloudflare, Workers AI is auto-instrumented through its binding and the Cloudflare
Agents SDK uses a class wrapper.
Eve and Flue ship their own Sentry setup commands instead of using provider
auto-instrumentation.
Every other platform is manual `gen_ai.*` instrumentation, or unsupported — the platform
`index.md` says which.

**Auto-instrumentation is runtime-dependent, not just language-dependent.** It patches
the AI client at require/import time, so it only applies on a patchable runtime.
On workerd (Cloudflare Workers) and in browser/client-side code there is nothing to
patch — those need build-time instrumentation (the Cloudflare Vite plugin) or a manual
client wrapper (`Sentry.instrumentOpenAiClient` and friends).
Check the platform’s `ai-monitoring.md` before assuming “it’s JavaScript, so it’s
automatic”.

## What the artifact shows

A trace *is* the agent run: a `gen_ai.invoke_agent` span parents the `gen_ai.chat` (LLM
call), `gen_ai.execute_tool`, and `gen_ai.handoff` children it triggered.
Read cost and latency off the child spans’ token attributes.
Two views surface it: the **AI Agents** dashboard and **Explore > Conversations**.

The span `op` is `gen_ai.{operation}` — `chat`, `embeddings`, `generate_content`,
`text_completion` for calls, plus `invoke_agent`, `execute_tool`, `handoff`. The span
**name** repeats the operation with its subject: `chat gpt-4o`,
`invoke_agent Weather Agent`, `execute_tool get_weather`,
`handoff from triage to billing`. Attributes accept primitives only; arrays/objects are
JSON-stringified. The canonical attribute set lives under
`references/semantics/gen_ai.md` in skills that hydrate semantic conventions (see the
instrument skill’s Semantic conventions list).
The SDK docs can lag, and deprecated attributes are omitted from that reference on
purpose.

## Conversations

Conversations groups spans by `gen_ai.conversation.id` into a chat-style timeline.
A conversation can span multiple traces (a page refresh mid-chat), and one trace can
hold spans from multiple conversations — the two are independent.

**Conversation ID format matters:** use a short, opaque identifier — alphanumeric with
dashes or underscores only (a UUID, or a prefixed id like `conv_5j66Up…`). Never use a
URL, email, or other free-form text: Sentry uses the id as a URL path segment, so a
value containing a slash breaks Conversations for that session.
Some integrations infer the id automatically (Python OpenAI Agents, Node OpenAI, Laravel
AI agents using `Conversational` + `RemembersConversations`); everything else sets it
explicitly. The view also needs input/output capture and gen_ai span streaming (both on
by default on recent JS/Python SDKs; Laravel AI spans are emitted directly) or it
renders empty, and a `setUser`/`set_user` call to populate the User column where
supported.

## Token accounting (avoid negative costs)

Sentry computes cost from token attributes, and cached/reasoning counts are **subsets**
of the totals, not separate buckets: `gen_ai.usage.input_tokens` already includes
`.input_tokens.cached`, and `gen_ai.usage.output_tokens` already includes
`.output_tokens.reasoning`. Reporting a subset larger than its total makes Sentry
subtract past zero and show a negative cost.

## Input/output message shape

`gen_ai.input.messages` and `gen_ai.output.messages` are JSON-stringified arrays of
`{role, parts}`, where each part is `{type, content}` — part types include `text`,
`reasoning`, `tool_call`, and `tool_call_response`.

Extended thinking (Anthropic `thinking`, Gemini `thought`, DeepSeek `reasoning_content`)
belongs in a **`reasoning` part, never folded into a `text` part**: Sentry surfaces
reasoning separately and filters it out of the user-facing Conversations view, so
thinking passed as `text` shows up as if the model said it.
When prior thinking is fed back into a multi-turn request, keep those same `reasoning`
parts in the assistant messages inside `gen_ai.input.messages`.

The system prompt is separate from the messages — it goes in
`gen_ai.system_instructions` — as is the tool catalog offered to the model,
`gen_ai.tool.definitions`. Both are model input and carry the same PII weight as the
messages.

## PII

Prompts and model outputs are user content and are **likely PII**. JavaScript captures
input/output by default (governed by `dataCollection.genAI`); Python gates it behind
`send_default_pii=True`; Laravel gates it behind `SENTRY_SEND_DEFAULT_PII=true`. Confirm
the privacy policy and regulations allow it and **ask the user before enabling capture**
— see [data-scrubbing.md](data-scrubbing.md).

## Setup essentials

- Tracing must be on; then detect the AI SDK and let auto-instrumentation handle it
  (JS/Python/Laravel AI), or instrument `gen_ai.*` spans manually.
- Sample AI traces at **100%** — see Sampling below.
- Set a `gen_ai.conversation.id` wherever multi-turn chats need grouping.

## Sampling

An agent run is one span tree and the sampling decision is made at the **root**;
children inherit it unconditionally.
Drop the root and every `gen_ai` child goes with it — so at any rate below 1.0 you lose
whole agent runs, not a fraction of each.
Which root depends on the app:

- **The `gen_ai` span is itself the root** (cron job, queue consumer, CLI): the sampler
  function sees the `gen_ai.*` op directly — match on it and return 1.0.
- **The `gen_ai` spans hang off an HTTP transaction** (most web apps): the sampler never
  runs for them, because the request was already sampled before any AI code executed.
  Keep the AI-serving routes at 1.0 instead.

If AI is the core product, skip the sampler and keep tracing at 1.0 outright.

**Read the app’s current rate before changing it, and ask.** If tracing is below 1.0
with no sampler configured, say what the current rate is and what a dropped root costs,
then wait for an answer — raising trace volume is the user’s cost decision, the same as
the PII gate above.

When 100% tracing isn’t affordable, metrics and logs are sampled independently of
traces: emit token counts and per-call log records on every LLM call to keep full
cost/usage coverage alongside sampled traces.

## Related

- [`tracing.md`](tracing.md) — AI monitoring is tracing; spans are the substrate.
- [`data-scrubbing.md`](data-scrubbing.md) — prompt/output capture is the PII decision.
- [`reduce-volume.md`](reduce-volume.md) — the volume/cost tradeoff across signals.
