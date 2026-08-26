# AI Monitoring — Sentry Python SDK

> Minimum SDK: `sentry-sdk` >=2.64.0 (Gen AI span streaming is on by default at this
> version; the `stream_gen_ai_spans` option is available since 2.60.0).

## Prerequisites

Tracing must be enabled — AI spans require an active transaction:

```python
sentry_sdk.init(
    dsn="...",
    traces_sample_rate=1.0,
    stream_gen_ai_spans=True,
    send_default_pii=True,
)
```

## Integration Matrix

| Integration | Package | Min Library | Auto-Enabled | Status |
| --- | --- | --- | --- | --- |
| OpenAI | `sentry-sdk` | openai 1.0+ | ✅ Yes | Stable |
| Anthropic | `sentry-sdk` | anthropic 0.16.0+ | ✅ Yes | Stable |
| LangChain | `sentry-sdk` | langchain 0.1.0+ | ✅ Yes | Stable |
| LangGraph | `sentry-sdk` | langgraph 0.6.6+ | ✅ Yes | Stable |
| OpenAI Agents SDK | `sentry-sdk` | agents 0.0.19+ | ✅ Yes | Stable |
| Google GenAI | `sentry-sdk` | google-genai 1.29.0+ | ✅ Yes | Stable |
| HuggingFace Hub | `sentry-sdk` | huggingface_hub 0.24.7+ | ✅ Yes | Stable |
| LiteLLM | `sentry-sdk` | litellm 1.77.5+ | ❌ **No** | Stable |
| MCP | `sentry-sdk` | mcp 1.15.0+ | ✅ Yes | Stable |
| Pydantic AI | `sentry-sdk` | pydantic-ai 1.0.0+ | ✅ Yes | Stable |

**LiteLLM MUST be explicitly added to `integrations=[]`.**

## PII Control

Every integration follows the same two-layer control:

| `send_default_pii` | `include_prompts` | Prompts/outputs sent? |
| --- | --- | --- |
| `False` (default) | `True` (default) | ❌ No |
| `True` | `True` (default) | ✅ Yes |
| `True` | `False` | ❌ No |

Set `send_default_pii=True` in `sentry_sdk.init()` and leave `include_prompts` at its
default `True`. Use `include_prompts=False` per integration only to opt out.

## Configuration Examples

### Auto-enabled integrations (OpenAI, Anthropic, LangChain, etc.)

```python
import sentry_sdk

sentry_sdk.init(
    dsn="https://<key>@<org>.ingest.sentry.io/<project>",
    traces_sample_rate=1.0,
    stream_gen_ai_spans=True,
    send_default_pii=True,    # required to capture prompts/outputs
)

# OpenAI, Anthropic, LangChain, LangGraph, HuggingFace Hub activate automatically
```

### Explicit configuration with `include_prompts` override

```python
import sentry_sdk
from sentry_sdk.integrations.openai import OpenAIIntegration
from sentry_sdk.integrations.anthropic import AnthropicIntegration

sentry_sdk.init(
    dsn="...",
    traces_sample_rate=1.0,
    stream_gen_ai_spans=True,
    send_default_pii=True,
    integrations=[
        OpenAIIntegration(
            include_prompts=True,
            tiktoken_encoding_name="o200k_base",   # for gpt-4o streaming token counts
        ),
        AnthropicIntegration(include_prompts=True),
    ],
)
```

### Integrations that require explicit registration

```python
import sentry_sdk
from sentry_sdk.integrations.litellm import LiteLLMIntegration

sentry_sdk.init(
    dsn="...",
    traces_sample_rate=1.0,
    stream_gen_ai_spans=True,
    send_default_pii=True,
    integrations=[
        LiteLLMIntegration(include_prompts=True),   # 100+ providers via proxy
    ],
)
```

### Usage examples

```python
from openai import OpenAI
import sentry_sdk

client = OpenAI()

with sentry_sdk.start_transaction(name="AI inference", op="ai-inference"):
    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": "Say hello"}],
    )
```

```python
import anthropic, sentry_sdk

client = anthropic.Anthropic()

with sentry_sdk.start_transaction(name="claude-request"):
    message = client.messages.create(
        model="claude-opus-4-5",
        max_tokens=1024,
        messages=[{"role": "user", "content": "Explain async/await"}],
    )
```

## Manual Instrumentation — `gen_ai.*` Spans

Use when the library isn’t supported, or for wrapping custom AI logic.

### `gen_ai.request` — Raw LLM call

```python
import sentry_sdk, json

messages = [{"role": "user", "content": "Tell me a joke"}]

with sentry_sdk.start_span(op="gen_ai.request", name="chat gpt-4o") as span:
    span.set_data("gen_ai.request.model", "gpt-4o")
    span.set_data("gen_ai.request.messages", json.dumps(messages))   # must JSON-stringify
    span.set_data("gen_ai.request.temperature", 0.7)
    span.set_data("gen_ai.request.max_tokens", 500)

    result = my_llm_client.chat(model="gpt-4o", messages=messages)

    span.set_data("gen_ai.response.text", json.dumps([result.choices[0].message.content]))
    span.set_data("gen_ai.usage.input_tokens", result.usage.prompt_tokens)
    span.set_data("gen_ai.usage.output_tokens", result.usage.completion_tokens)
    span.set_data("gen_ai.usage.total_tokens", result.usage.total_tokens)
```

### `gen_ai.invoke_agent` — Full agent lifecycle

```python
import sentry_sdk

with sentry_sdk.start_span(op="gen_ai.invoke_agent",
                           name="invoke_agent Weather Agent") as span:
    span.set_data("gen_ai.request.model", "gpt-4o")
    span.set_data("gen_ai.agent.name", "Weather Agent")

    final_output = my_agent.run(task="What's the weather in Paris?")

    span.set_data("gen_ai.response.text", str(final_output))
    span.set_data("gen_ai.usage.input_tokens", my_agent.usage.input_tokens)
    span.set_data("gen_ai.usage.output_tokens", my_agent.usage.output_tokens)
```

### `gen_ai.execute_tool` — Tool/function call

```python
import sentry_sdk, json

with sentry_sdk.start_span(op="gen_ai.execute_tool",
                           name="execute_tool get_weather") as span:
    span.set_data("gen_ai.tool.name", "get_weather")
    span.set_data("gen_ai.tool.type", "function")   # "function"|"extension"|"datastore"
    span.set_data("gen_ai.tool.input", json.dumps({"location": "Paris"}))

    result = get_weather(location="Paris")

    span.set_data("gen_ai.tool.output", json.dumps(result))
```

### `gen_ai.handoff` — Agent-to-agent transition

```python
import sentry_sdk

with sentry_sdk.start_span(op="gen_ai.handoff",
                           name="handoff Billing → Refund Agent") as span:
    span.set_data("gen_ai.agent.name", "Refund Agent")
    result = refund_agent.run(context=billing_context)
```

## Span Attribute Reference

### Common attributes

| Attribute | Type | Required | Description |
| --- | --- | --- | --- |
| `gen_ai.request.model` | string | ✅ | Model identifier (e.g., `gpt-4o`, `claude-opus-4-5`) |
| `gen_ai.operation.name` | string | No | Human-readable operation label |
| `gen_ai.agent.name` | string | No | Agent name (for agent spans) |

### Model config attributes

| Attribute | Type |
| --- | --- |
| `gen_ai.request.temperature` | float |
| `gen_ai.request.max_tokens` | int |
| `gen_ai.request.top_p` | float |
| `gen_ai.request.frequency_penalty` | float |
| `gen_ai.request.presence_penalty` | float |
| `gen_ai.request.reasoning_effort` | string |

### Content attributes (PII-gated — only when `send_default_pii=True` + `include_prompts=True`)

| Attribute | Type | Description |
| --- | --- | --- |
| `gen_ai.request.messages` | string | **JSON-stringified** message array |
| `gen_ai.request.available_tools` | string | **JSON-stringified** tool definitions |
| `gen_ai.response.text` | string | **JSON-stringified** response array |
| `gen_ai.response.tool_calls` | string | **JSON-stringified** tool call array |

> ⚠️ Span attributes only accept primitives — arrays/objects must be JSON-stringified
> before calling `span.set_data()`.

### Token usage attributes

| Attribute | Type | Description |
| --- | --- | --- |
| `gen_ai.usage.input_tokens` | int | Total input tokens (including cached) |
| `gen_ai.usage.input_tokens.cached` | int | Subset served from cache |
| `gen_ai.usage.input_tokens.cache_write` | int | Tokens written to cache (Anthropic) |
| `gen_ai.usage.output_tokens` | int | Total output tokens (including reasoning) |
| `gen_ai.usage.output_tokens.reasoning` | int | Subset for chain-of-thought reasoning |
| `gen_ai.usage.total_tokens` | int | Sum of input + output |

> ⚠️ Cached and reasoning tokens are **subsets** of totals, not additive.
> Incorrect reporting produces wrong cost calculations in the dashboard.

## Agent Workflow Hierarchy

```
Transaction
└── gen_ai.invoke_agent  "Weather Agent"
    ├── gen_ai.request   "chat gpt-4o"
    ├── gen_ai.execute_tool "get_weather"
    ├── gen_ai.request   "chat gpt-4o"        ← follow-up
    └── gen_ai.handoff   "→ Report Writer"
        └── gen_ai.invoke_agent "Report Writer"
            ├── gen_ai.request  "chat gpt-4o"
            └── gen_ai.execute_tool "format_report"
```

This populates the **AI Agents Dashboard** in Sentry with per-agent latency, tool call
rates, token consumption, and model cost attribution.

### Conversation Tracking

Link AI spans across turns in a multi-turn conversation.
Sentry groups spans by `gen_ai.conversation.id` into a chat-style timeline at **Explore
\> Conversations**.

**Prerequisites:** SDK >=2.64.0 (where `stream_gen_ai_spans` defaults to `True`, so AI
spans stream as standalone items) and `send_default_pii=True` — Conversations
reconstructs the chat from input/output attributes, so without PII capture the view will
be empty.

```python
import sentry_sdk.ai

# Set at the start of a conversation
sentry_sdk.ai.set_conversation_id("conv_abc123")
# All subsequent AI spans carry gen_ai.conversation.id = "conv_abc123"
```

Some integrations infer the conversation ID automatically.
For example, the OpenAI integration picks it up when you use the `conversation`
parameter:

```python
import openai
import sentry_sdk

sentry_sdk.init(...)

conversation = openai.conversations.create()
response = openai.responses.create(
    model="gpt-5.4",
    input=[{"role": "user", "content": "What are the 5 Ds of dodgeball?"}],
    conversation=conversation.id  # automatically sets gen_ai.conversation.id
)
```

A single conversation can span multiple traces, and a single trace can contain multiple
conversations.

### User Attribution

To populate the **User** column in Conversations, call `set_user` once per request or
session before any AI calls:

```python
sentry_sdk.set_user({"id": "user_123", "email": "jane@example.com", "username": "jane"})
```

## Streaming

| Integration | Streaming | Token counts in streams |
| --- | --- | --- |
| OpenAI | ✅ | Requires `tiktoken>=0.3.0`; set `tiktoken_encoding_name` |
| Anthropic | ✅ | Automatic |
| LangChain | ✅ | Tracked |
| LiteLLM | ✅ | Tracked |
| Manual `gen_ai.*` | ✅ | Set token counts after stream completes |

## Unsupported Providers

| Provider | Workaround |
| --- | --- |
| Cohere | Use `LiteLLMIntegration` or manual `gen_ai.*` spans |
| AWS Bedrock | Manual instrumentation |
| Mistral | `LiteLLMIntegration` |
| Groq | `LiteLLMIntegration` |
| Vertex AI | `GoogleGenAIIntegration` or `LiteLLMIntegration` |

## Sampling Strategy

If your `traces_sample_rate` is below 1.0, you may be losing entire agent runs.
Use a `traces_sampler` that keeps 100% of gen_ai-related transactions while sampling
other traffic at a lower rate.

## Troubleshooting

| Issue | Solution |
| --- | --- |
| No AI spans appearing | Verify `traces_sample_rate > 0`; wrap calls in a transaction |
| Prompts not captured | Set `send_default_pii=True` and verify `include_prompts=True` (default) |
| LiteLLM not tracked | LiteLLM is NOT auto-enabled — add `LiteLLMIntegration` to `integrations=[]` explicitly |
| Token counts missing for OpenAI streaming | Install `tiktoken>=0.3.0` and set `tiktoken_encoding_name` |
| AI Agents Dashboard empty | Wrap agent runs in `gen_ai.invoke_agent` spans |
| User column shows “Unknown” | Call `sentry_sdk.set_user()` once per request or session |
| Wrong cost calculations | Ensure cached/reasoning token counts are subsets of totals, not additions |
