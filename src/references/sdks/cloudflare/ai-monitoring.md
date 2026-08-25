# AI / LLM Monitoring (Agent Tracing) — Sentry Cloudflare SDK

> Minimum SDK: `@sentry/cloudflare` >=10.61.0 (Gen AI span streaming on by default).
> Workers AI (`env.AI`) auto-instrumentation: v10.67.0+. Vite plugin build-time
> instrumentation: v10.68.0+ (experimental).
> Docs:
> [docs.sentry.io/platforms/javascript/guides/cloudflare/agent-tracing/](https://docs.sentry.io/platforms/javascript/guides/cloudflare/agent-tracing/)

Sentry Agent Tracing captures `gen_ai` spans for LLM calls, agent runs, and tool
executions — token usage, latency, prompts/responses, and error rates — and groups
multi-turn chats in Conversations.

* * *

## The Cloudflare Difference

The Cloudflare Workers runtime (`workerd`) does **not support runtime monkey-patching**,
so the automatic AI instrumentation that Node.js gets for free does not happen here.
On Cloudflare there are three ways to get `gen_ai` spans, in order of preference:

| Path | Covers | How it works |
| --- | --- | --- |
| **1. Workers AI binding** (automatic) | `env.AI.run(...)` | `withSentry` wraps `env` — nothing to do (v10.67.0+) |
| **2. Vite plugin** (build-time, experimental) | `openai`, `@anthropic-ai/sdk`, `@google/genai`, `ai` (Vercel AI SDK) | `sentryCloudflareVitePlugin` injects `diagnostics_channel` calls into the bundled packages at build time (v10.68.0+) |
| **3. Manual client wrapping** | OpenAI, Anthropic, Google Gen AI, LangChain, LangGraph | Wrap each client/graph with the matching `Sentry.instrument*` helper |

LangChain and LangGraph are **not** covered by the Vite plugin’s channel injection —
they always require the manual helpers (path 3).

* * *

## Prerequisites

Tracing must be enabled — AI spans require an active trace.
Pass `dataCollection` so generative AI content (prompts and responses) is collected
according to SDK defaults:

```typescript
import * as Sentry from "@sentry/cloudflare";

export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
    dataCollection: {
      // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
      // https://docs.sentry.io/platforms/javascript/guides/cloudflare/configuration/options/#dataCollection
      // userInfo: false,
      // httpBodies: [],
    },
  }),
  handler,
);
```

**PII warning:** with `dataCollection` set (even `{}`), genAI input/output capture is
**on by default** — prompts and model responses are sent to Sentry.
To turn it off:

```typescript
dataCollection: {
  genAI: { inputs: false, outputs: false },
},
```

Per-integration `recordInputs` / `recordOutputs` options override the global default.

* * *

## Integration Matrix

| AI stack | Supported versions | Instrumentation | Min SDK |
| --- | --- | --- | --- |
| Workers AI (`env.AI`) | — | Automatic via `withSentry` | 10.67.0 |
| OpenAI (`openai`) | `>=4.0.0 <7` | Vite plugin **or** `instrumentOpenAiClient` | 10.68.0 / — |
| Anthropic (`@anthropic-ai/sdk`) | `>=0.19.2 <1.0.0` | Vite plugin **or** `instrumentAnthropicAiClient` | 10.68.0 / — |
| Google Gen AI (`@google/genai`) | `>=0.10.0 <2` | Vite plugin **or** `instrumentGoogleGenAIClient` | 10.68.0 / — |
| Vercel AI SDK (`ai`) | `>=3.0.0 <=7` | `vercelAIIntegration` (+ Vite plugin injection) | 10.6.0; v7 needs 10.64.0 + `/nodejs_compat` entrypoint |
| LangChain (`langchain`) | `>=0.1.0 <2.0.0` | `createLangChainCallbackHandler` (manual only) | — |
| LangGraph (`@langchain/langgraph`) | `>=0.2.0 <2.0.0` | `instrumentLangGraph` (manual only) | — |
| Other providers (Bedrock, Mistral, Groq, …) | — | Manual `gen_ai.*` spans | — |

* * *

## Path 1: Workers AI (Automatic)

The Workers AI binding is auto-instrumented by `withSentry` (v10.67.0+). Calls to
`env.AI.run(...)` create `gen_ai` spans capturing model, request parameters, and token
usage — as long as your handler uses the `env` the SDK passes in:

```typescript
import * as Sentry from "@sentry/cloudflare";

export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
  }),
  {
    async fetch(request, env, ctx) {
      // env.AI is automatically instrumented
      const result = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", {
        messages: [{ role: "user", content: "What is the capital of France?" }],
      });
      return new Response(JSON.stringify(result));
    },
  } satisfies ExportedHandler<Env>,
);
```

**Auto-instrumentation covers the spans — not the grouping.** Workers AI does **not**
infer a conversation ID, so without one every `env.AI.run(...)` call lands as an
isolated span and the Conversations view stays empty.
For any chat-style app, set a conversation ID as part of this setup — don’t treat it as
a later add-on:

1. Generate a stable session ID on the client (e.g. `crypto.randomUUID()` once per chat
   session) and send it with every AI request
2. In the handler, call `Sentry.setConversationId(id)` **before** any `env.AI.run(...)`
   calls

```typescript
async fetch(request, env, ctx) {
  const { conversationId, messages } = await request.json();

  // Before any AI calls — groups this request's gen_ai spans into a Conversation
  Sentry.setConversationId(conversationId);

  const result = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", { messages });
  return new Response(JSON.stringify(result));
}
```

See [Tracking Conversations](#tracking-conversations) for scope semantics, user
attribution, and the Agents SDK pattern.

* * *

## Path 2: Vite Plugin (Build-Time Instrumentation)

> **Experimental** (v10.68.0+): options and behavior may change or be removed in any
> release. Verify against the
> [Vite plugin docs](https://docs.sentry.io/platforms/javascript/guides/cloudflare/features/vite-plugin/)
> before implementing.

`sentryCloudflareVitePlugin` ships with `@sentry/cloudflare` (no extra package) via the
`@sentry/cloudflare/vite` export.
It is designed to run alongside the
[Cloudflare Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/). With
`useDiagnosticsChannelInjection` enabled, it injects
`diagnostics_channel.tracingChannel` calls into supported bundled packages — including
`openai`, `@anthropic-ai/sdk`, `@google/genai`, and `ai` — so the SDK traces them
without monkey-patching.
The matching Sentry integrations are registered automatically; you don’t wrap clients or
add integrations manually.

**Prerequisite:** the injected code uses Node.js `diagnostics_channel` at runtime, so
the Worker must have the `nodejs_compat` compatibility flag (see `./nodejs-compat.md`).

```typescript
// vite.config.ts
import { cloudflare } from "@cloudflare/vite-plugin";
import { sentryCloudflareVitePlugin } from "@sentry/cloudflare/vite";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [
    cloudflare(),
    sentryCloudflareVitePlugin({
      _experimental: {
        useDiagnosticsChannelInjection: true,
      },
    }),
  ],
});
```

Keep `withSentry` in your Worker entry as usual:

```typescript
import * as Sentry from "@sentry/cloudflare/nodejs_compat";
import OpenAI from "openai";

export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
  }),
  {
    async fetch(request, env, ctx) {
      const openai = new OpenAI({ apiKey: env.OPENAI_API_KEY });
      // Traced automatically — the Vite plugin injected channels at build time
      const response = await openai.chat.completions.create({
        model: "gpt-4o",
        messages: [{ role: "user", content: "Hello" }],
      });
      return new Response(response.choices[0].message.content);
    },
  } satisfies ExportedHandler<Env>,
);
```

Both `vite build` and `vite dev` are instrumented.
When the option is disabled or omitted, the plugin is a no-op.

### Auto-Instrumentation (Experimental)

The plugin can also wrap your Worker at build time so you don’t need `withSentry` in
your code. With `autoInstrumentation` enabled, it reads your Wrangler config (probing
`wrangler.json`, `wrangler.jsonc`, `wrangler.toml` at the Vite root — set the top-level
`wranglerConfigPath` option for a custom name, v10.69.0+), wraps the default export with
`Sentry.withSentry()`, and wraps configured classes with the matching helper: Durable
Objects with `instrumentDurableObjectWithSentry`, Workflows with
`instrumentWorkflowWithSentry`, and — since v10.69.0 — Cloudflare Agents SDK classes
(`Agent`, `AIChatAgent`, `McpAgent`) with `instrumentAgentWithSentry`, which also gives
them automatic conversation IDs (see [Tracking Conversations](#tracking-conversations)):

```typescript
// vite.config.ts
sentryCloudflareVitePlugin({
  _experimental: {
    autoInstrumentation: true,
    useDiagnosticsChannelInjection: true,
  },
}),
```

Provide Sentry options via a co-located `instrument.server.*` file (`.ts`, `.mts`,
`.js`, `.mjs`, or `.cjs`) next to your Worker entry — use `defineCloudflareOptions` for
type-checking:

```typescript
// instrument.server.ts
import { defineCloudflareOptions } from "@sentry/cloudflare";

export default defineCloudflareOptions((env) => ({
  dsn: env.SENTRY_DSN,
  tracesSampleRate: 1.0,
}));
```

If no `instrument.server.*` file exists, the SDK reads configuration (DSN, release,
environment, sample rate) from the Worker’s `env` bindings at runtime.

### Migrating From Wrangler

If you deploy with `wrangler` directly today:

1. Set up the
   [Cloudflare Vite plugin](https://developers.cloudflare.com/workers/vite-plugin/get-started/)
   and add a `vite.config.ts` with `cloudflare()` and `sentryCloudflareVitePlugin()` as
   above.
2. Run `vite build` before `wrangler deploy`, and use `vite dev` instead of
   `wrangler dev` for local development.

Your existing `wrangler.jsonc`/`wrangler.toml` stays the input config — the plugin
generates the deployed output during the build.
Everything works without Vite too; you just miss the build-time instrumentation of
bundled dependencies.

* * *

## Path 3: Manual Client Wrapping

Use these when you don’t build with Vite, or for LangChain/LangGraph (which the Vite
plugin doesn’t cover).
All wrappers default `recordInputs`/`recordOutputs` to `true` when
`dataCollection.genAI` inputs/outputs are on (the default).

### OpenAI

```typescript
import OpenAI from "openai";
import * as Sentry from "@sentry/cloudflare";

const openai = new OpenAI({ apiKey: env.OPENAI_API_KEY });
const client = Sentry.instrumentOpenAiClient(openai, {
  recordInputs: true,
  recordOutputs: true,
});

// Use the wrapped client instead of the original instance
const response = await client.chat.completions.create({
  model: "gpt-4o",
  messages: [{ role: "user", content: "Hello" }],
});
```

Traces `chat.completions.create()` and `responses.create()`.

### Anthropic

```typescript
import Anthropic from "@anthropic-ai/sdk";
import * as Sentry from "@sentry/cloudflare";

const anthropic = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
const client = Sentry.instrumentAnthropicAiClient(anthropic, {
  recordInputs: true,
  recordOutputs: true,
});
```

### Google Gen AI

```typescript
import { GoogleGenAI } from "@google/genai";
import * as Sentry from "@sentry/cloudflare";

const genAI = new GoogleGenAI({ apiKey: env.GOOGLE_API_KEY });
const client = Sentry.instrumentGoogleGenAIClient(genAI, {
  recordInputs: true,
  recordOutputs: true,
});
```

### Vercel AI SDK

The `vercelAIIntegration` is **not enabled by default** — add it to `Sentry.init`
options, and pass `experimental_telemetry: { isEnabled: true }` to every `generateText`
/ `generateObject` / `streamText` / `ToolLoopAgent` call:

```typescript
import * as Sentry from "@sentry/cloudflare";
import { generateText } from "ai";

export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
    integrations: [Sentry.vercelAIIntegration()],
  }),
  {
    async fetch(request, env, ctx) {
      const result = await generateText({
        model: openai("gpt-4o"),
        prompt: "Hello",
        experimental_telemetry: {
          isEnabled: true,
          recordInputs: true,
          recordOutputs: true,
        },
      });
      return new Response(result.text);
    },
  } satisfies ExportedHandler<Env>,
);
```

**Version constraints:**

- AI SDK v3–v6: works on the default `@sentry/cloudflare` entrypoint (SDK >=10.6.0)
- AI SDK **v7**: requires SDK >=10.64.0 and the `@sentry/cloudflare/nodejs_compat`
  entrypoint (see `./nodejs-compat.md`). Setting `recordInputs`/`recordOutputs` on the
  integration itself is also only supported there — on the default entrypoint, set them
  per call via `experimental_telemetry`
- Don’t use the AI SDK’s own `registerTelemetry` API (v7+) together with this
  integration — it duplicates spans

### LangChain

Create a callback handler and pass it to LangChain operations (`invoke`, `stream`,
`batch`):

```typescript
import { ChatAnthropic } from "@langchain/anthropic";
import * as Sentry from "@sentry/cloudflare";

const callbackHandler = Sentry.createLangChainCallbackHandler({
  recordInputs: true,
  recordOutputs: true,
});

const model = new ChatAnthropic({ model: "claude-3-5-sonnet-20241022", apiKey: env.ANTHROPIC_API_KEY });
await model.invoke("Tell me a joke", { callbacks: [callbackHandler] });
```

Captures chat model invocations, LLM pipelines, chain executions, and tool calls.
Supported provider packages: `@langchain/anthropic`, `@langchain/openai`,
`@langchain/google-genai`, `@langchain/mistralai`, `@langchain/google-vertexai`,
`@langchain/groq`.

### LangGraph

Instrument the `StateGraph` **before** calling `.compile()`:

```typescript
import { StateGraph, MessagesAnnotation, START, END } from "@langchain/langgraph";
import * as Sentry from "@sentry/cloudflare";

const agent = new StateGraph(MessagesAnnotation)
  .addNode("agent", callLLM)
  .addEdge(START, "agent")
  .addEdge("agent", END);

Sentry.instrumentLangGraph(agent, {
  recordInputs: true,
  recordOutputs: true,
});

const graph = agent.compile({ name: "my_agent" });
```

Captures `gen_ai.create_agent` (compile) and `gen_ai.invoke_agent` (invoke) spans.

* * *

## Tracking Conversations

Conversations groups multi-turn AI activity into a single replay of messages and tool
calls at **Explore > Conversations**. Every AI span in a chat session must share the
same `gen_ai.conversation.id`.

Some integrations infer the ID automatically.
For everything else — **including Workers AI** — set it yourself at the start of every
request or operation that makes AI calls, before those calls run.
Reuse the same session ID across messages in the chat; the ID applies to AI spans on the
current isolation scope (request-scoped).
Pass `null` to unset:

```typescript
Sentry.setConversationId("conv_abc123");
```

**Choose a real chat session ID** — a UUID or `conv_...` value your app creates when the
user starts a chat. Don’t use a user ID, room name, or a shared identifier: those group
unrelated chats into one conversation.

#### Cloudflare Agents SDK: automatic conversation IDs (v10.69.0+)

Wrap Agents SDK classes (`Agent`, `AIChatAgent`, `McpAgent`) with
`instrumentAgentWithSentry` and the conversation ID is set for you — on every chat turn
(`onChatMessage`) and every `@callable()` RPC call, defaulting to the agent instance
name. When the chat is cleared — `clearHistory()` from `useAgentChat`, or anything that
emits the
[`message:clear` observability event](https://developers.cloudflare.com/agents/runtime/operations/observability/#channels)
— the SDK rotates to a fresh conversation ID, so a reset chat groups as a new
conversation.
The Vite plugin’s `autoInstrumentation` applies this wrapper automatically.
See `./durable-objects.md` for the full API.

The conversation ID is the agent instance name, which is correct when one instance is
one chat session (e.g. `useAgent({ name: chatSessionId })`). If your instances are
per-user or a shared singleton like `"default"`, override it with your own session ID
via `Sentry.setConversationId(id)` at the start of `onChatMessage`, before any model or
tool calls.

On SDK versions before 10.69.0 (or with `instrumentDurableObjectWithSentry`), set the ID
manually — see `./tracing.md` for a full `AIChatAgent` example.

### Identifying Users

To populate the **User** column in Conversations, call `setUser` once per request or
session, before any AI calls:

```typescript
Sentry.setUser({ id: "user_123", email: "jane@example.com", username: "jane" });
```

Any of `id`, `email`, or `username` is sufficient.

### Streaming Gen AI Spans

Since SDK 10.61.0, `gen_ai` spans are sent as standalone envelope items instead of being
bundled into the transaction (`streamGenAiSpans` defaults to `true`). This prevents AI
spans with large inputs/outputs from hitting transaction payload limits, and is
**required** for Conversations to work.
**Self-hosted Sentry** users should set `streamGenAiSpans: false` — standalone `gen_ai`
spans may not be ingested by a self-hosted instance.

* * *

## Manual `gen_ai.*` Spans

For unsupported providers (Bedrock, Mistral, Groq, Cohere, …) or custom agent logic,
create spans yourself.
Spans nest like this:

```
invoke_agent My Agent            (gen_ai.invoke_agent)
├── chat gpt-4o                  (gen_ai.chat)          ← 1st LLM call
├── execute_tool get_weather     (gen_ai.execute_tool)  ← tool run
└── chat gpt-4o                  (gen_ai.chat)          ← 2nd LLM call
```

Naming rules: span `op` MUST be `gen_ai.{operation.name}`; span `name` SHOULD be
`"{operation.name} {model-or-agent-or-tool}"`. Attributes only accept primitives —
JSON-stringify arrays/objects.
Messages use the `{role, parts}` format:
`[{"role": "user", "parts": [{"type": "text", "content": "..."}]}]`.

### AI request (`gen_ai.chat`)

```typescript
const messages = [{ role: "user", parts: [{ type: "text", content: "Tell me a joke" }] }];

await Sentry.startSpan(
  {
    op: "gen_ai.chat",
    name: "chat o3-mini",
    attributes: {
      "gen_ai.operation.name": "chat",
      "gen_ai.request.model": "o3-mini",
      "gen_ai.provider.name": "openai",
      "gen_ai.input.messages": JSON.stringify(messages),
    },
  },
  async (span) => {
    const result = await client.chat.completions.create({ model: "o3-mini", messages });
    span.setAttribute("gen_ai.response.model", result.model);
    span.setAttribute(
      "gen_ai.output.messages",
      JSON.stringify([{ role: "assistant", parts: [{ type: "text", content: result.choices[0].message.content }] }]),
    );
    span.setAttribute("gen_ai.usage.input_tokens", result.usage.prompt_tokens);
    span.setAttribute("gen_ai.usage.output_tokens", result.usage.completion_tokens);
    return result;
  },
);
```

`gen_ai.operation.name` MUST be `"chat"`, `"embeddings"`, `"generate_content"`, or
`"text_completion"`.

### Agent lifecycle (`gen_ai.invoke_agent`)

```typescript
await Sentry.startSpan(
  {
    op: "gen_ai.invoke_agent",
    name: "invoke_agent Weather Agent",
    attributes: {
      "gen_ai.operation.name": "invoke_agent",
      "gen_ai.agent.name": "Weather Agent",
      "gen_ai.request.model": "o3-mini",
    },
  },
  async (span) => {
    const result = await myAgent.run();
    span.setAttribute("gen_ai.usage.input_tokens", result.usage.inputTokens);
    span.setAttribute("gen_ai.usage.output_tokens", result.usage.outputTokens);
    return result;
  },
);
```

### Tool call (`gen_ai.execute_tool`)

```typescript
await Sentry.startSpan(
  {
    op: "gen_ai.execute_tool",
    name: "execute_tool get_weather",
    attributes: {
      "gen_ai.operation.name": "execute_tool",
      "gen_ai.tool.name": "get_weather",
      "gen_ai.tool.type": "function",
      "gen_ai.tool.call.arguments": JSON.stringify({ location: "Paris" }),
    },
  },
  async (span) => {
    const result = await getWeather({ location: "Paris" });
    span.setAttribute("gen_ai.tool.call.result", JSON.stringify(result));
    return result;
  },
);
```

### Streaming responses

When the LLM streams, the span must outlive the initial callback — use
`Sentry.startInactiveSpan`, propagate with `Sentry.withActiveSpan`, and call
`span.end()` when the stream completes or errors.
Set `gen_ai.response.streaming: true` and the token counts after the stream finishes.

### Key attributes

| Attribute | Type | Notes |
| --- | --- | --- |
| `gen_ai.request.model` | string | Requested model (required for chat spans) |
| `gen_ai.response.model` | string | Concrete model that responded |
| `gen_ai.provider.name` | string | e.g. `"openai"` |
| `gen_ai.agent.name` | string | Agent name (agent spans) |
| `gen_ai.input.messages` | string | JSON-stringified `{role, parts}` messages (replaces deprecated `gen_ai.request.messages`) |
| `gen_ai.output.messages` | string | JSON-stringified response messages (replaces deprecated `gen_ai.response.text` / `gen_ai.response.tool_calls`) |
| `gen_ai.tool.definitions` | string | JSON-stringified tool list (replaces deprecated `gen_ai.request.available_tools`) |
| `gen_ai.tool.call.arguments` / `gen_ai.tool.call.result` | string | Tool I/O (replace deprecated `gen_ai.tool.input` / `gen_ai.tool.output`) |
| `gen_ai.usage.input_tokens` | int | **Total** input tokens, including cached |
| `gen_ai.usage.input_tokens.cached` | int | Subset of input tokens served from cache |
| `gen_ai.usage.output_tokens` | int | **Total** output tokens, including reasoning |
| `gen_ai.usage.output_tokens.reasoning` | int | Subset used for reasoning |

> Cached and reasoning tokens are **subsets** of the totals, not additive.
> Sentry subtracts them from the totals to compute costs — reporting only the non-cached
> count as `input_tokens` produces wrong or negative cost calculations.

* * *

## Sampling

If `tracesSampleRate < 1.0`, AI calls that fall outside sampled traces produce no spans.
Use a `tracesSampler` that keeps AI-related traffic at 100% while sampling the rest
lower.

* * *

## Verification

Deploy (or `vite dev` / `wrangler dev` with a real DSN), trigger a route that makes an
AI call, then check:

1. **Insights > Agents** in Sentry — the AI Agents dashboard shows the model, token
   usage, and latency
2. The trace view shows `gen_ai.*` spans nested under the request transaction
3. If you set `Sentry.setConversationId(...)`, the calls appear grouped in **Explore >
   Conversations**

Minimal test handler (Workers AI — zero config beyond `withSentry`):

```typescript
async fetch(request, env, ctx) {
  Sentry.setConversationId("test-conversation");
  const result = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", {
    messages: [{ role: "user", content: "Say hello" }],
  });
  return new Response(JSON.stringify(result));
}
```

* * *

## Troubleshooting

| Issue | Cause | Solution |
| --- | --- | --- |
| No `gen_ai` spans at all | Tracing not enabled | Set `tracesSampleRate > 0`; verify the handler is wrapped with `withSentry` |
| OpenAI/Anthropic/Google calls not traced | No runtime patching on workerd | Build with the Vite plugin (`useDiagnosticsChannelInjection: true`) **or** wrap the client with `Sentry.instrument*Client` |
| Vite plugin injection has no effect | Missing `nodejs_compat` flag, or SDK < 10.68.0 | Add `nodejs_compat` to `compatibility_flags`; upgrade `@sentry/cloudflare` |
| Vercel AI spans missing | Integration not added, or telemetry not enabled per call | Add `Sentry.vercelAIIntegration()` to `integrations` and `experimental_telemetry: { isEnabled: true }` on every call |
| Vercel AI SDK v7 not working | Default entrypoint doesn’t support v7 | Use `@sentry/cloudflare/nodejs_compat` (SDK >=10.64.0) — see `./nodejs-compat.md` |
| Workers AI calls not traced | `env` accessed outside the wrapped handler, or SDK < 10.67.0 | Use the `env` passed into the handler; upgrade the SDK |
| Duplicate spans for AI calls made through the Vercel AI SDK (`workers-ai-provider`) | SDK < 10.69.0: both the Vercel AI integration and the Workers AI binding instrumentation recorded the same call | Upgrade to 10.69.0+ — the binding instrumentation now skips calls the Vercel AI integration is already recording |
| LangChain/LangGraph not traced | Expecting Vite plugin coverage | Not covered by channel injection — use `createLangChainCallbackHandler` / `instrumentLangGraph` |
| Agents SDK chats not grouping | Agent wrapped with `instrumentDurableObjectWithSentry`, or SDK < 10.69.0 | Wrap with `instrumentAgentWithSentry` (v10.69.0+) for automatic conversation IDs, or call `setConversationId` manually in `onChatMessage` |
| Agents SDK conversation split unexpectedly | Chat was cleared — `clearHistory()` (or anything emitting `message:clear`) rotates to a fresh conversation ID by design | Expected: a reset chat groups as a new conversation |
| One giant conversation across users | Agent instance name is per-user or a shared singleton (e.g. `"default"`) | Use one agent instance per chat session, or override with `Sentry.setConversationId(chatSessionId)` per turn |
| Prompts/responses not captured | genAI capture disabled | Don’t set `dataCollection: { genAI: { inputs: false } }`, or pass `recordInputs`/`recordOutputs: true` explicitly |
| Conversations view empty | No conversation ID, or gen_ai streaming disabled | Call `Sentry.setConversationId()` before AI calls; keep `streamGenAiSpans` at its default (`true`) |
| Self-hosted: gen_ai spans dropped | Standalone gen_ai envelopes not ingested | Set `streamGenAiSpans: false` |
| User column shows “Unknown” | No user on the scope | Call `Sentry.setUser()` once per request before AI calls |
| Wrong/negative cost calculations | Token subsets reported as totals | `input_tokens`/`output_tokens` must be totals that *include* cached/reasoning counts |
