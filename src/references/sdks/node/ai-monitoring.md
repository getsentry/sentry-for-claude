# AI Monitoring - Sentry Node.js SDK

> Minimum SDK: `@sentry/node` >=10.61.0 (Gen AI span streaming is on by default at this
> version). OpenAI, Anthropic, LangChain, LangGraph, Google GenAI, and Vercel AI SDK
> auto-instrument and are available since 10.53.0. Flue’s Sentry blueprint requires
> `@sentry/node` >=10.64.0. Eve uses its own OpenTelemetry exporter instead of the
> Sentry Node SDK.

## Prerequisites

This generic `Sentry.init` example applies to the provider integrations below.
Flue’s blueprint owns its SDK setup, so skip the example for Flue.
For Eve, choose between its trace-only exporter and the broader Node SDK setup; do not
initialize both in the same agent runtime.

Tracing must be enabled - AI spans require an active trace:

```typescript
Sentry.init({
  dsn: "...",
  tracesSampleRate: 1.0,
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
});
```

## Integration Matrix

| Integration | Min Library | Auto-Enabled | Status |
| --- | --- | --- | --- |
| OpenAI (`openai`) | openai 4.0+ | Yes | Stable |
| Anthropic (`@anthropic-ai/sdk`) | 0.19.2+ | Yes | Stable |
| Vercel AI SDK (`ai`) | ai 3.0+ | Yes* | Stable |
| LangChain (`@langchain/core`) | 0.1.0+ | Yes | Stable |
| LangGraph (`@langchain/langgraph`) | 0.1.0+ | Yes | Stable |
| Google GenAI (`@google/genai`) | 1.0+ | Yes | Stable |
| Eve (`eve`, Node.js only) | Current | No — run `eve add instrumentation/sentry` | Supported |
| Flue (`@flue/*`, Node.js only) | Current | No — run `flue add tooling sentry` | Supported |

*Vercel AI SDK requires `experimental_telemetry: { isEnabled: true }` on every call.

## PII Control

| `dataCollection.genAI` | `recordInputs` | Prompts captured? |
| --- | --- | --- |
| default on | `true` (default) | Yes |
| `{ inputs: false }` | `true` | No |
| default on | `false` | No |

With `dataCollection`, genAI input/output capture is **on by default**. Supported
integrations default `recordInputs`/`recordOutputs` to `true` (governed by
`dataCollection.genAI`). To disable it, set
`dataCollection: { genAI: { inputs: false, outputs: false } }`. Use integration-level
options to opt out or override specific integrations.

## Configuration Examples

### Auto-enabled integrations

```typescript
import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 1.0,
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
});
// OpenAI, Anthropic, LangChain, LangGraph, Google GenAI activate automatically
```

### Explicit configuration with recordInputs/recordOutputs override

```typescript
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 1.0,
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  integrations: [
    Sentry.openAIIntegration(),
    Sentry.vercelAIIntegration(),
  ],
});
```

### Vercel AI SDK per-call telemetry (required)

```typescript
await generateText({
  model: openai("gpt-4.1"),
  prompt: "Hello",
  experimental_telemetry: { isEnabled: true, recordInputs: true, recordOutputs: true },
});
```

### Eve (official OTLP instrumentation)

Eve’s official Sentry instrumentation exports OpenTelemetry GenAI spans directly to
Sentry. Choose one setup for the agent runtime:

- **Eve OTLP exporter:** traces only.
  If `@sentry/node` is already initialized in that runtime, remove it before adding the
  exporter.
- **Sentry Node SDK:** broader error, log, and trace coverage.
  Keep the generic Node SDK setup above and do not install, or remove, Eve’s exporter.

Do not combine these documented setups.
With tracing enabled, `@sentry/node` includes its `VercelAI` integration by default even
when `vercelAIIntegration()` is absent from the configuration, which creates a second AI
span producer. Both setups also configure OpenTelemetry; coordinating custom
OpenTelemetry ownership requires a separate advanced setup not covered by Eve’s
integration guide. See the
[Eve guide](https://docs.sentry.io/platforms/javascript/guides/node/agent-tracing/eve/)
for the generated exporter’s full shape.

For the Eve OTLP choice, add its instrumentation:

```bash
eve add instrumentation/sentry
```

The command creates `agent/instrumentation.ts` and installs its OpenTelemetry packages.
Set the project-specific OTLP traces endpoint and public key from **Project Settings >
Client Keys (DSN)**:

```bash
SENTRY_OTLP_TRACES_ENDPOINT="___OTLP_TRACES_URL___"
SENTRY_PUBLIC_KEY="___PUBLIC_KEY___"
```

Eve records span metadata by default.
After the user approves prompt and response capture, add `recordInputs: true` and
`recordOutputs: true` to the generated `defineInstrumentation` object.
Preserve its existing `setup` callback and exporter.
Eve emits its session ID as `gen_ai.conversation.id`; do not replace it with a
per-request ID.

Eve’s OTLP path sends traces only.
It does not create Sentry issues or logs because Sentry’s OTLP intake does not accept
span events. Verify by running a tool-using turn and checking Agent Tracing for
`invoke_agent`, `chat`, and `execute_tool` spans.

### Flue (official Sentry blueprint)

On Node.js, when a project uses Flue, run its official blueprint instead of hand-writing
provider integrations.
The blueprint installs `@sentry/node` and `@flue/opentelemetry`, creates a `sentry.ts`
module, and connects Flue traces, logs, and terminal failures to Sentry.
See the
[Flue guide](https://docs.sentry.io/platforms/javascript/guides/node/agent-tracing/flue/)
for the generated bridge and configuration details.

```bash
flue add tooling sentry
```

Configure the generated setup through environment variables:

```bash
SENTRY_DSN="___PUBLIC_DSN___"
SENTRY_TRACES_SAMPLE_RATE=1
# Enable only after the user approves sending prompt and response content:
# SENTRY_AI_RECORD_INPUTS=true
# SENTRY_AI_RECORD_OUTPUTS=true
```

`SENTRY_TRACES_SAMPLE_RATE` defaults to `0`, so errors and logs can arrive while AI
traces remain absent.
The blueprint removes Sentry’s provider integrations because Flue already emits the
model spans; do not add them back or token and cost totals will be doubled.
Flue emits its persisted conversation ID as `gen_ai.conversation.id`; do not replace it
with a per-request ID. Verify a tool-using prompt produces `invoke_agent`, `chat`, and
`execute_tool` spans.
Then emit one Flue log and trigger a terminal failure to confirm the correlated log and
one Sentry issue.

### Browser / Next.js client-side (manual wrapping required)

```typescript
import OpenAI from "openai";
import * as Sentry from "@sentry/nextjs"; // or @sentry/browser

const openai = Sentry.instrumentOpenAiClient(new OpenAI());
```

## Manual Instrumentation - `gen_ai.*` Spans

Use when the library isn’t supported, or for wrapping custom AI logic.

### `gen_ai.request` - LLM call

```typescript
await Sentry.startSpan({
  op: "gen_ai.request",
  name: "chat claude-sonnet-4-6",
  attributes: { "gen_ai.request.model": "claude-sonnet-4-6" },
}, async (span) => {
  span.setAttribute("gen_ai.request.messages", JSON.stringify(messages));
  const result = await myClient.chat(messages);
  span.setAttribute("gen_ai.usage.input_tokens", result.usage.inputTokens);
  span.setAttribute("gen_ai.usage.output_tokens", result.usage.outputTokens);
  return result;
});
```

### `gen_ai.invoke_agent` - Agent lifecycle

```typescript
await Sentry.startSpan({
  op: "gen_ai.invoke_agent",
  name: "invoke_agent Weather Agent",
  attributes: { "gen_ai.agent.name": "Weather Agent", "gen_ai.request.model": "claude-sonnet-4-6" },
}, async (span) => {
  const result = await myAgent.run(task);
  span.setAttribute("gen_ai.usage.input_tokens", result.totalInputTokens);
  span.setAttribute("gen_ai.usage.output_tokens", result.totalOutputTokens);
  return result;
});
```

### `gen_ai.execute_tool` - Tool/function call

```typescript
await Sentry.startSpan({
  op: "gen_ai.execute_tool",
  name: "execute_tool get_weather",
  attributes: {
    "gen_ai.tool.name": "get_weather",
    "gen_ai.tool.type": "function",
    "gen_ai.tool.input": JSON.stringify({ location: "Paris" }),
  },
}, async (span) => {
  const result = await getWeather("Paris");
  span.setAttribute("gen_ai.tool.output", JSON.stringify(result));
  return result;
});
```

## Span Attribute Reference

### Common attributes

| Attribute | Type | Required | Description |
| --- | --- | --- | --- |
| `gen_ai.request.model` | string | Yes | Model identifier (e.g., `claude-sonnet-4-6`, `gemini-2.5-flash`) |
| `gen_ai.operation.name` | string | No | Human-readable operation label |
| `gen_ai.agent.name` | string | No | Agent name (for agent spans) |

### Model config attributes

| Attribute | Type |
| --- | --- |
| `gen_ai.request.reasoning_effort` | string |

### Content attributes (captured by default; gated by `dataCollection.genAI` + `recordInputs/recordOutputs`)

| Attribute | Type | Description |
| --- | --- | --- |
| `gen_ai.request.messages` | string | **JSON-stringified** message array |
| `gen_ai.request.available_tools` | string | **JSON-stringified** tool definitions |
| `gen_ai.response.text` | string | **JSON-stringified** response array |
| `gen_ai.response.tool_calls` | string | **JSON-stringified** tool call array |

> Span attributes only accept primitives - arrays/objects must be JSON-stringified.

### Token usage attributes

| Attribute | Type | Description |
| --- | --- | --- |
| `gen_ai.usage.input_tokens` | int | Total input tokens (including cached) |
| `gen_ai.usage.input_tokens.cached` | int | Subset served from cache |
| `gen_ai.usage.input_tokens.cache_write` | int | Tokens written to cache (Anthropic) |
| `gen_ai.usage.output_tokens` | int | Total output tokens (including reasoning) |
| `gen_ai.usage.output_tokens.reasoning` | int | Subset for chain-of-thought (o3, etc.) |
| `gen_ai.usage.total_tokens` | int | Sum of input + output |

> Cached and reasoning tokens are **subsets** of totals, not additive.
> Incorrect reporting produces wrong cost calculations.

## Agent Workflow Hierarchy

```
Transaction
└── gen_ai.invoke_agent  "Weather Agent"
    ├── gen_ai.request      "chat claude-sonnet-4-6"
    ├── gen_ai.execute_tool "get_weather"
    ├── gen_ai.request      "chat claude-sonnet-4-6"     ← follow-up
    └── gen_ai.execute_tool "format_report"
```

## Streaming

| Integration | Streaming | Token counts in streams |
| --- | --- | --- |
| OpenAI | Yes | Requires `stream_options: { include_usage: true }` |
| Anthropic | Yes | Automatic |
| Vercel AI SDK | Yes | Automatic (with `experimental_telemetry`) |
| LangChain | Yes | Tracked |
| Manual `gen_ai.*` | Yes | Set token counts after stream completes |

## Unsupported Providers

| Provider | Workaround |
| --- | --- |
| Cohere | Manual `gen_ai.*` spans |
| AWS Bedrock | Manual `gen_ai.*` spans |
| Mistral | Manual `gen_ai.*` spans |
| Groq | Manual `gen_ai.*` spans |

## Sampling Strategy

If `tracesSampleRate` < 1.0, use a `tracesSampler` that keeps 100% of gen_ai-related
transactions while sampling other traffic at a lower rate.

## Conversation Tracking

Link AI spans across turns into a chat-style timeline at **Explore > Conversations**.
Eve and Flue emit their framework-owned conversation IDs automatically.
For provider integrations that do not infer an ID, set one explicitly as shown below.

**Prerequisites:** `streamGenAiSpans` defaults to `true` (SDK >=10.61.0, so AI spans
stream as standalone items) and genAI input/output capture enabled (on by default via
`dataCollection`) — Conversations reconstructs the chat from input/output attributes, so
without input/output capture the view will be empty.

```typescript
import * as Sentry from "@sentry/node";

// Set at the start of a conversation
Sentry.setConversationId("conv_abc123");

// All subsequent AI calls carry gen_ai.conversation.id: "conv_abc123"
await openai.chat.completions.create({
  model: "gpt-5.5",
  messages: [{ role: "user", content: "Hello" }],
});

// Later turns in the same conversation are linked automatically
await openai.chat.completions.create({
  model: "gpt-5.5",
  messages: [
    { role: "user", content: "Hello" },
    { role: "assistant", content: "Hi there!" },
    { role: "user", content: "What's the weather?" },
  ],
});
```

A single conversation can span multiple traces (e.g., page refresh), and a single trace
can contain multiple conversations.

### User Attribution

To populate the **User** column in Conversations, call `setUser` once per request or
session before any AI calls:

```typescript
Sentry.setUser({ id: "user_123", email: "jane@example.com", username: "jane" });
```

## Troubleshooting

| Issue | Solution |
| --- | --- |
| No AI spans appearing | Verify `tracesSampleRate > 0`; check SDK >=10.61.0 |
| Token counts missing in streams | Add `stream_options: { include_usage: true }` (OpenAI) |
| Vercel AI spans not tracked | Add `experimental_telemetry: { isEnabled: true }` per call |
| Eve traces missing | Use the project-specific OTLP traces endpoint and the public key only, not the full DSN |
| Eve token or cost totals doubled | Eve’s exporter and `@sentry/node` are both active in the agent runtime. Keep one setup: remove the Node initialization for Eve’s trace-only path, or remove Eve’s exporter for broader Node SDK coverage |
| Flue logs and issues arrive but traces do not | Set `SENTRY_TRACES_SAMPLE_RATE` above `0` |
| Flue token or cost totals doubled | Keep the provider integrations removed as generated by the Flue blueprint |
| Browser OpenAI not traced | Use `Sentry.instrumentOpenAiClient()` - auto-instrumentation is server-only |
| Prompts not captured | genAI capture is on by default; ensure you haven’t set `dataCollection: { genAI: { inputs: false } }`, or pass `recordInputs: true` explicitly |
| AI Agents Dashboard empty | Ensure traces are being sent; check DSN and `tracesSampleRate` |
| Wrong cost calculations | Cached/reasoning tokens are subsets of totals, not additions |
| Conversations view empty | Ensure `streamGenAiSpans` is enabled (default since SDK 10.61.0) and genAI capture is on. For Eve or Flue, confirm the framework emitted `gen_ai.conversation.id`; for integrations that do not infer one, call `Sentry.setConversationId()` |
| User column shows “Unknown” | Call `Sentry.setUser()` once per request or session |
