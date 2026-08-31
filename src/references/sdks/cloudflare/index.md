# Sentry Cloudflare SDK

Opinionated wizard that scans your Cloudflare project and guides you through complete
Sentry setup for Workers, Pages, Durable Objects, Queues, Workflows, and Hono.

> **Note:** SDK versions and APIs below reflect current Sentry docs at time of writing
> (`@sentry/cloudflare` v10.69.0). Always verify against
> [docs.sentry.io/platforms/javascript/guides/cloudflare/](https://docs.sentry.io/platforms/javascript/guides/cloudflare/)
> before implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect Cloudflare project
ls wrangler.toml wrangler.jsonc wrangler.json 2>/dev/null

# Detect existing Sentry
cat package.json 2>/dev/null | grep -E '"@sentry/'

# Detect project type (Workers vs Pages)
ls functions/ functions/_middleware.js functions/_middleware.ts 2>/dev/null && echo "Pages detected"
cat wrangler.toml 2>/dev/null | grep -E 'main|pages_build_output_dir'

# Detect framework
cat package.json 2>/dev/null | grep -E '"hono"|"remix"|"astro"|"svelte"'

# Detect Durable Objects
cat wrangler.toml 2>/dev/null | grep -i 'durable_objects'

# Detect D1 databases
cat wrangler.toml 2>/dev/null | grep -i 'd1_databases'

# Detect Queues
cat wrangler.toml 2>/dev/null | grep -i 'queues'

# Detect Workflows
cat wrangler.toml 2>/dev/null | grep -i 'workflows'

# Detect Scheduled handlers (cron triggers)
cat wrangler.toml 2>/dev/null | grep -i 'crons\|triggers'

# Detect compatibility flags
cat wrangler.toml 2>/dev/null | grep -i 'compatibility_flags'
cat wrangler.jsonc 2>/dev/null | grep -i 'compatibility_flags'

# Detect AI/LLM libraries
cat package.json 2>/dev/null | grep -E '"openai"|"@anthropic-ai"|"ai"|"@google/genai"|"@langchain"|"langchain"'

# Detect Cloudflare Agents SDK
cat package.json 2>/dev/null | grep -E '"agents"|"@cloudflare/ai-chat"'

# Detect Vite build (enables build-time AI/DB instrumentation via the Sentry Vite plugin)
ls vite.config.ts vite.config.js vite.config.mts 2>/dev/null
cat package.json 2>/dev/null | grep -E '"@cloudflare/vite-plugin"'

# Detect logging libraries
cat package.json 2>/dev/null | grep -E '"pino"|"winston"'

# Check for companion frontend
ls frontend/ web/ client/ 2>/dev/null
cat package.json 2>/dev/null | grep -E '"react"|"vue"|"svelte"|"next"'
```

**What to determine:**

| Question | Impact |
| --- | --- |
| Workers or Pages? | Determines wrapper: `withSentry` vs `sentryPagesPlugin` |
| Hono framework? | Recommend standalone `@sentry/hono` package (v10.55.0+) for cleaner integration |
| `@sentry/cloudflare` already installed? | Skip install, go to feature config |
| Durable Objects configured? | Recommend `instrumentDurableObjectWithSentry` |
| Cloudflare Agents SDK (`agents`, `@cloudflare/ai-chat`)? | Recommend `instrumentAgentWithSentry` (v10.69.0+) — DO instrumentation plus `@callable()` RPC spans and **automatic conversation IDs**. See `./durable-objects.md` |
| D1 databases bound? | Auto-instrumented by `withSentry` when accessed via `env.DB` (no manual wrap) |
| Queues configured? | `withSentry` auto-instruments queue handlers |
| Workflows configured? | Recommend `instrumentWorkflowWithSentry` |
| Cron triggers configured? | `withSentry` auto-instruments scheduled handlers; recommend Crons monitoring |
| `nodejs_als` or `nodejs_compat` flag set? | **Required** — SDK needs `AsyncLocalStorage`. Recommend `nodejs_compat` generally, and with it the `@sentry/cloudflare/nodejs_compat` entrypoint (drop-in swap, unlocks Prisma + Vercel AI SDK v7, becomes default in v11) |
| Prisma ORM used? | Recommend `prismaIntegration` via the `/nodejs_compat` entrypoint — see `./nodejs-compat.md` |
| Workers AI (`env.AI`) used? | Auto-instrumented by `withSentry` — creates `gen_ai` spans (v10.67.0+). **Chat-style app?** Also wire `Sentry.setConversationId()` so multi-turn sessions group in Conversations (automatic for Agents SDK classes wrapped with `instrumentAgentWithSentry`, v10.69.0+) — see `./ai-monitoring.md` |
| AI/LLM libraries? | Recommend Agent Tracing — see `./ai-monitoring.md`. On workerd, `openai`/`@anthropic-ai/sdk`/`@google/genai` need the Vite plugin or manual client wrapping |
| Builds with Vite (or could)? | Recommend `sentryCloudflareVitePlugin` (v10.68.0+, experimental) — build-time instrumentation of bundled AI/DB packages. See `./ai-monitoring.md` |
| Companion frontend? | Trigger Phase 4 cross-link |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Don’t ask open-ended questions — lead with a proposal:

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; captures unhandled exceptions in fetch, scheduled,
  queue, email, and Durable Object handlers
- ✅ **Tracing** — automatic HTTP request spans, outbound fetch tracing, D1 query spans

**Optional (enhanced observability):**
- ⚡ **Logging** — structured logs via `Sentry.logger.*`; recommend when log search is
  needed
- ⚡ **Crons** — detect missed/failed scheduled jobs; recommend when cron triggers are
  configured
- ⚡ **D1 Instrumentation** — automatic query spans and breadcrumbs; recommend when D1 is
  bound
- ⚡ **Durable Objects** — automatic error capture and spans for DO methods; recommend
  when DOs are configured
- ⚡ **Workflows** — automatic span creation for workflow steps; recommend when Workflows
  are configured
- ⚡ **AI / Agent Tracing** — Workers AI, OpenAI, Anthropic, Google Gen AI, Vercel AI
  SDK, LangChain, LangGraph; recommend when AI libraries or `env.AI` detected.
  For chat apps, include conversation tracking (`setConversationId`) in the same pass —
  spans alone leave the Conversations view empty

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Always** — HTTP request tracing and outbound fetch are high-value |
| Logging | App needs structured log search or log-to-trace correlation |
| Crons | Cron triggers configured in `wrangler.toml` |
| D1 Instrumentation | D1 database bindings present |
| Durable Objects | Durable Object bindings configured |
| Workflows | Workflow bindings configured |
| AI / Agent Tracing | App uses Workers AI (`env.AI`), OpenAI, Anthropic, Google Gen AI, Vercel AI SDK, LangChain, or LangGraph |
| Metrics | App needs custom counters, gauges, or distributions |

Propose: *“I recommend setting up Error Monitoring + Tracing.
Want me to also add D1 instrumentation and Crons monitoring?”*

**Exception — AI apps:** when Workers AI or an LLM SDK is detected, conversation
tracking is **not optional** — include it in the baseline proposal alongside Error
Monitoring + Tracing, and implement it in the same pass (see `./ai-monitoring.md`). An
AI setup that produces spans but no Conversations is incomplete.

* * *

## Phase 3: Guide

### Option 1: Source Maps Wizard

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```
> npx @sentry/wizard@latest -i sourcemaps
> ```
> 
> This sets up source map uploading so your production stack traces show readable code.
> It does **not** set up the SDK initialization — you still need to follow Option 2
> below for the actual SDK setup.
> 
> **Once it finishes, continue with Option 2 for SDK setup.**

> **Note:** Unlike framework SDKs (Next.js, SvelteKit), there is no Cloudflare-specific
> wizard integration. The `sourcemaps` wizard only handles source map upload
> configuration.

* * *

### Option 2: Manual Setup

#### Prerequisites: Compatibility Flags

The SDK requires `AsyncLocalStorage`. Add **one** of these flags to your Wrangler
config:

**wrangler.toml:**
```toml
compatibility_flags = ["nodejs_als"]
# or: compatibility_flags = ["nodejs_compat"]
```

**wrangler.jsonc:**
```jsonc
{
  "compatibility_flags": ["nodejs_als"]
}
```

> `nodejs_als` is the minimum — it only enables `AsyncLocalStorage`. **`nodejs_compat`
> is generally recommended:** it’s a superset of `nodejs_als` and unlocks the
> `/nodejs_compat` entrypoint below (more integrations and features), which becomes the
> SDK default in v11. Prefer `nodejs_compat` unless you have a specific reason to keep
> the runtime minimal.

#### `/nodejs_compat` Entrypoint (recommended)

When your Worker runs with the `nodejs_compat` flag, use the dedicated
`@sentry/cloudflare/nodejs_compat` entrypoint instead of the default one.
It’s a drop-in import swap — everything (`withSentry`, `sentryPagesPlugin`, etc.)
works the same — but it unlocks additional Node.js-only functionality on Cloudflare,
such as the `prismaIntegration` and Vercel AI SDK v7 support:

```typescript
// Drop-in replacement — everything else works the same
import * as Sentry from "@sentry/cloudflare/nodejs_compat";
```

**For new projects, default to this entrypoint** (add the `nodejs_compat` flag and
import from `@sentry/cloudflare/nodejs_compat` from the start).
Requires SDK v10.64.0+. It becomes the **default entrypoint in v11**, so adopting it now
is the recommended path and eases the upgrade.
See `./nodejs-compat.md` for full setup (Prisma).

#### Install

```bash
npm install @sentry/cloudflare
```

#### Workers Setup

Wrap your handler with `withSentry`. This automatically instruments `fetch`,
`scheduled`, `queue`, `email`, and `tail` handlers:

```typescript
import * as Sentry from "@sentry/cloudflare";

export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
    enableLogs: true,
    dataCollection: {
      // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
      // https://docs.sentry.io/platforms/javascript/guides/cloudflare/configuration/options/#dataCollection
      // userInfo: false,
      // httpBodies: [],
    },
  }),
  {
    async fetch(request, env, ctx) {
      return new Response("Hello World!");
    },
  } satisfies ExportedHandler<Env>,
);
```

**Key points:**
- The first argument is a callback that receives `env` — use this to read secrets like
  `SENTRY_DSN`
- The SDK reads DSN, environment, release, debug, tunnel, and traces sample rate from
  `env` automatically (see [Environment Variables](#environment-variables))
- `withSentry` wraps all exported handlers — you do not need separate wrappers for
  `scheduled`, `queue`, etc.

#### AI apps: set a conversation ID (required, same edit)

If this Worker makes AI calls (`env.AI.run(...)` or an LLM SDK), `withSentry` gives you
`gen_ai` spans automatically — but **never a conversation ID**, so multi-turn chats
won’t group and Sentry’s Conversations view stays empty.
This is part of the Workers setup, not a follow-up: add `Sentry.setConversationId()` in
the same edit that adds `withSentry`. (Exception: Cloudflare Agents SDK classes wrapped
with `instrumentAgentWithSentry` get conversation IDs automatically, v10.69.0+ — see
`./durable-objects.md`.)

1. The client generates a stable session ID once per chat session (e.g.
   `crypto.randomUUID()`) and sends it with every AI request
2. The handler sets it **before** any AI calls:

```typescript
async fetch(request, env, ctx) {
  const { conversationId, messages } = await request.json();
  Sentry.setConversationId(conversationId); // before env.AI.run / LLM calls

  const result = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", { messages });
  return new Response(JSON.stringify(result));
}
```

See `./ai-monitoring.md` for user attribution (`setUser`), the Agents SDK pattern, and
non-Workers-AI providers.

#### Automatic Binding Instrumentation

`withSentry` (and `sentryPagesPlugin`) wraps the `env` object so that supported bindings
are **automatically instrumented on access** — no manual wrapping needed.
As long as your handler uses the `env` passed in by the SDK:

| Binding | Auto-instrumented | Docs status |
| --- | --- | --- |
| **D1** (`env.DB`) | Query spans + breadcrumbs | Documented |
| **Workers AI** (`env.AI`) | `gen_ai` spans (v10.67.0+) — spans only; conversation grouping needs the extra step below | Documented |
| **Queue producers** | Producer send spans | Verified in SDK source; not yet in published docs |
| **R2 buckets** | Object operation spans | Verified in SDK source; not yet in published docs |
| **RateLimit** | `limit()` spans | Verified in SDK source; not yet in published docs |

> **Required step for AI apps:** auto-instrumentation produces `gen_ai` spans but never
> sets a conversation ID, so multi-turn chats don’t group and Sentry’s Conversations
> view stays empty. If the app makes AI calls (`env.AI` or an LLM SDK), wiring
> `Sentry.setConversationId()` is part of *this* setup — do it in the same edit as
> `withSentry`, don’t defer it.
> Read `./ai-monitoring.md` (Tracking Conversations) for the pattern: client generates a
> stable session ID, handler calls `Sentry.setConversationId(id)` before any AI calls.
> Skipping this is the most common gap in Cloudflare AI setups.
> 
> Because D1 is auto-instrumented via `env`, the manual `instrumentD1WithSentry` wrapper
> is no longer needed (it’s deprecated and slated for removal in v11). See
> `./durable-objects.md`.
> 
> To link Durable Object and service-binding (JSRPC) calls into one trace, set
> `enableRpcTracePropagation: true` on both caller and receiver — **recommended**
> whenever you use RPC, Durable Objects, or Workflows.
> See [RPC Trace Propagation](#configuration-reference) and `./tracing.md`.

#### Pages Setup

Use `sentryPagesPlugin` as middleware:

```typescript
// functions/_middleware.ts
import * as Sentry from "@sentry/cloudflare";

export const onRequest = Sentry.sentryPagesPlugin((context) => ({
  dsn: context.env.SENTRY_DSN,
  tracesSampleRate: 1.0,
  enableLogs: true,
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/cloudflare/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
}));
```

**Chaining multiple middlewares:**

```typescript
import * as Sentry from "@sentry/cloudflare";

export const onRequest = [
  // Sentry must be first
  Sentry.sentryPagesPlugin((context) => ({
    dsn: context.env.SENTRY_DSN,
    tracesSampleRate: 1.0,
  })),
  // Add more middlewares here
];
```

**Using `wrapRequestHandler` directly** (for frameworks like SvelteKit on Cloudflare
Pages):

```typescript
import * as Sentry from "@sentry/cloudflare";

export const handle = ({ event, resolve }) => {
  return Sentry.wrapRequestHandler(
    {
      options: {
        dsn: event.platform.env.SENTRY_DSN,
        tracesSampleRate: 1.0,
      },
      request: event.request,
      context: event.platform.ctx,
    },
    () => resolve(event),
  );
};
```

#### Hono on Cloudflare Workers

**Recommended (v10.55.0+):** Use the standalone `@sentry/hono` package for Hono apps:

```bash
npm install @sentry/hono @sentry/cloudflare
```

The `@sentry/cloudflare` package is a peer dependency and must stay in sync with
`@sentry/hono`.

```typescript
import { Hono } from "hono";
import { sentry } from "@sentry/hono/cloudflare";

type Bindings = { SENTRY_DSN: string };

const app = new Hono<{ Bindings: Bindings }>();

// Initialize Sentry middleware as early as possible
app.use(
  sentry(app, (env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
  })),
);

app.get("/", (ctx) => ctx.json({ message: "Hello" }));

app.get("/error", () => {
  throw new Error("Test error");
});

export default app;
```

The `sentry()` middleware automatically captures errors and creates transaction spans
with route patterns.

**Legacy approach (deprecated):** Using `@sentry/cloudflare` with `withSentry` still
works, but `honoIntegration` is deprecated:

```typescript
import { Hono } from "hono";
import * as Sentry from "@sentry/cloudflare";

const app = new Hono();

app.get("/", (ctx) => ctx.json({ message: "Hello" }));

export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
  }),
  app,
);
```

#### Set Up the SENTRY_DSN Secret

Store your DSN as a Cloudflare secret — do not hardcode it:

```bash
# Local development: add to .dev.vars
echo 'SENTRY_DSN="https://examplePublicKey@o0.ingest.sentry.io/0"' >> .dev.vars

# Production: set as a secret
npx wrangler secret put SENTRY_DSN
```

Add the binding to your `Env` type:

```typescript
interface Env {
  SENTRY_DSN: string;
  // ... other bindings
}
```

#### Source Maps Setup

Source maps make production stack traces readable.
Most Cloudflare projects build with Vite via Wrangler — wire the Sentry Vite plugin so
maps upload on build:

```bash
npm install @sentry/vite-plugin --save-dev
```

```typescript
import { defineConfig } from "vite";
import { sentryVitePlugin } from "@sentry/vite-plugin";

export default defineConfig({
  build: {
    sourcemap: true,
  },
  plugins: [
    sentryVitePlugin({
      org: "___ORG_SLUG___",
      project: "___PROJECT_SLUG___",
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
  ],
});
```

`SENTRY_AUTH_TOKEN` is a build-time secret.
The `npx @sentry/wizard@latest -i sourcemaps` shortcut noted above automates this setup.

> Don’t confuse `@sentry/vite-plugin` (`sentryVitePlugin` — source map upload) with
> `sentryCloudflareVitePlugin` from `@sentry/cloudflare/vite` (build-time
> instrumentation of bundled AI/DB dependencies, v10.68.0+ experimental).
> They are complementary and can run in the same `vite.config.ts`. See
> `./ai-monitoring.md` for the latter.

* * *

### Automatic Release Detection

The SDK can automatically detect the release version via Cloudflare’s version metadata
binding:

**wrangler.toml:**
```toml
[version_metadata]
binding = "CF_VERSION_METADATA"
```

Release priority (highest to lowest):
1. `release` option passed to `Sentry.init()`
2. `SENTRY_RELEASE` environment variable
3. `CF_VERSION_METADATA.id` binding

* * *

### For Each Agreed Feature

Load the corresponding reference file and follow its steps:

| Feature | Reference file | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) — unhandled exceptions, manual capture, scopes, enrichment |
| Tracing | `./tracing.md` | HTTP request tracing, outbound fetch spans, D1/Workers AI spans, distributed tracing, RPC trace propagation |
| Logging | `./logging.md` | Structured logs via `Sentry.logger.*`, log-to-trace correlation |
| Crons | `./crons.md` | Scheduled handler monitoring, `withMonitor`, check-in API |
| Durable Objects / Workflows / D1 | `./durable-objects.md` | Instrument Durable Object and Workflow classes; D1 auto-instrumentation |
| AI / Agent Tracing | `./ai-monitoring.md` | AI/LLM libraries or Workers AI detected — `gen_ai` spans, Vite plugin build-time instrumentation, Conversations, manual agent spans |
| Node.js Compat | `./nodejs-compat.md` | `nodejs_compat` flag set, or Prisma / Vercel AI SDK v7 detected — `/nodejs_compat` entrypoint, `prismaIntegration` |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: read the reference file, follow its steps exactly, and verify before
moving on.

* * *

## Configuration Reference

### `Sentry.init()` Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `dsn` | `string` | — | Required. Read from `env.SENTRY_DSN` automatically if not set |
| `tracesSampleRate` | `number` | — | 0–1; 1.0 in dev, lower in prod recommended |
| `tracesSampler` | `function` | — | Dynamic sampling function; mutually exclusive with `tracesSampleRate` |
| `dataCollection` | `object` | `{}` | Controls what data the SDK captures (`userInfo`, `httpBodies`, etc.). See [Data Collection Reference](#data-collection-reference) |
| `sendDefaultPii` | `boolean` | `false` | Legacy. Prefer `dataCollection` for control over captured data |
| `enableLogs` | `boolean` | `false` | Enable Sentry Logs product |
| `environment` | `string` | auto | Read from `env.SENTRY_ENVIRONMENT` if not set |
| `release` | `string` | auto | Detected from `CF_VERSION_METADATA.id` or `SENTRY_RELEASE` |
| `debug` | `boolean` | `false` | Read from `env.SENTRY_DEBUG` if not set. Log SDK activity to console |
| `tunnel` | `string` | — | Read from `env.SENTRY_TUNNEL` if not set |
| `beforeSend` | `function` | — | Filter/modify error events before sending |
| `beforeSendTransaction` | `function` | — | Filter/modify transaction events before sending |
| `beforeSendLog` | `function` | — | Filter/modify log entries before sending |
| `tracePropagationTargets` | `(string\|RegExp)[]` | all URLs | Control which outbound requests get trace headers |
| `skipOpenTelemetrySetup` | `boolean` | `false` | Opt-out of OpenTelemetry compatibility tracer |
| `instrumentPrototypeMethods` | `boolean \| string[]` | `false` | Durable Object: instrument prototype methods for RPC spans |
| `enableRpcTracePropagation` | `boolean` | `false` | Links RPC calls (Worker↔DO, Worker↔Worker service bindings) into one trace. **Recommended** when using RPC / Durable Objects / Workflows — set on **both** caller and receiver (v10.52.0+). See `./tracing.md` |

### Data Collection Reference

```typescript
dataCollection: {
  // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
  // https://docs.sentry.io/platforms/javascript/configuration/options/#dataCollection
  // userInfo: false,
  // httpBodies: [],
},
```

### Environment Variables (Read from `env`)

The SDK reads these from the Cloudflare `env` object automatically:

| Variable | Purpose |
| --- | --- |
| `SENTRY_DSN` | DSN for Sentry init |
| `SENTRY_RELEASE` | Release version string |
| `SENTRY_ENVIRONMENT` | Environment name (`production`, `staging`) |
| `SENTRY_TRACES_SAMPLE_RATE` | Traces sample rate (parsed as float) |
| `SENTRY_DEBUG` | Enable debug mode (`"true"` / `"1"`) |
| `SENTRY_TUNNEL` | Tunnel URL for event proxying |
| `CF_VERSION_METADATA` | Cloudflare version metadata binding (auto-detected release) |

### Default Integrations

These are registered automatically by `getDefaultIntegrations()`:

| Integration | Purpose |
| --- | --- |
| `dedupeIntegration` | Prevent duplicate events (disabled for Workflows) |
| `inboundFiltersIntegration` | Filter events by type, message, URL |
| `functionToStringIntegration` | Preserve original function names |
| `conversationIdIntegration` | Stamp `gen_ai.conversation.id` (set via `setConversationId`) onto AI spans |
| `linkedErrorsIntegration` | Follow `cause` chains in errors |
| `fetchIntegration` | Trace outbound `fetch()` calls, create breadcrumbs |
| `honoIntegration` | **Deprecated in v10.55.0** — use `@sentry/hono` package instead. Auto-capture Hono `onError` exceptions |
| `httpServerIntegration` | Incoming HTTP request handling |
| `requestDataIntegration` | Attach request data to events |
| `consoleIntegration` | Capture `console.*` calls as breadcrumbs |

> **Not default:** `prismaIntegration` is available on Cloudflare **only** via the
> `@sentry/cloudflare/nodejs_compat` entrypoint and must be added manually (see
> `./nodejs-compat.md`). `spotlightIntegration` (v10.69.0+) forwards events to a local
> [Spotlight](https://spotlightjs.com/) sidecar for local development — add it manually
> in dev:
> 
> ```typescript
> integrations: [Sentry.spotlightIntegration()], // default sidecar: http://localhost:8969/stream
> ```

* * *

## Verification

After setup, verify Sentry is working:

```typescript
// Add temporarily to your fetch handler, then remove
export default Sentry.withSentry(
  (env: Env) => ({
    dsn: env.SENTRY_DSN,
    tracesSampleRate: 1.0,
  }),
  {
    async fetch(request, env, ctx) {
      throw new Error("Sentry test error — delete me");
    },
  } satisfies ExportedHandler<Env>,
);
```

Deploy and trigger the route, then check your
[Sentry Issues dashboard](https://sentry.io/issues/) — the error should appear within
~30 seconds.

**Verification checklist:**

| Check | How |
| --- | --- |
| Errors captured | Throw in a fetch handler, verify in Sentry |
| Tracing working | Check Performance tab for HTTP spans |
| Source maps working | Check stack trace shows readable file/line names |
| D1 spans (if configured) | Run a D1 query via `env.DB` (auto-instrumented), check for `db.query` spans |
| Workers AI spans (if configured) | Call `env.AI.run(...)`, check for `gen_ai` spans (see `./ai-monitoring.md`) |
| Conversations (chat apps) | Send two requests with the same `Sentry.setConversationId(...)` value, check they group in Explore > Conversations |
| Scheduled monitoring (if configured) | Trigger a cron, check Crons dashboard |

* * *

## Phase 4: Cross-Link

After completing Cloudflare setup, check for companion services:

```bash
# Check for companion frontend
ls frontend/ web/ client/ ui/ 2>/dev/null
cat package.json 2>/dev/null | grep -E '"react"|"vue"|"svelte"|"next"|"astro"'

# Check for companion backend in adjacent directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod ../requirements.txt ../Gemfile 2>/dev/null | head -3
```

If a frontend is found, suggest the matching SDK skill:

| Frontend detected | Suggest skill |
| --- | --- |
| React | [`react`](../react/index.md) |
| Next.js | [`nextjs`](../nextjs/index.md) |
| Svelte/SvelteKit | [`svelte`](../svelte/index.md) |
| Vue/Nuxt | See [docs.sentry.io/platforms/javascript/guides/vue/](https://docs.sentry.io/platforms/javascript/guides/vue/) |

If a backend is found in a different directory:

| Backend detected | Suggest skill |
| --- | --- |
| Go (`go.mod`) | [`go`](../go/index.md) |
| Python (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby (`Gemfile`) | [`ruby`](../ruby/index.md) |
| Node.js (Express, Fastify) | [`node`](../node/index.md) |

Connecting frontend and backend with linked Sentry projects enables **distributed
tracing** — stack traces that span your browser, Cloudflare Worker, and backend API in a
single trace view.

* * *

## Troubleshooting

| Issue | Cause | Solution |
| --- | --- | --- |
| Events not appearing | DSN not set or `debug: false` hiding errors | Set `debug: true` temporarily in init options; verify `SENTRY_DSN` secret is set with `wrangler secret list` |
| `AsyncLocalStorage is not defined` | Missing compatibility flag | Add `nodejs_als` or `nodejs_compat` to `compatibility_flags` in `wrangler.toml` |
| Stack traces show minified code | Source maps not uploaded | Configure `@sentry/vite-plugin` or run `npx @sentry/wizard -i sourcemaps`; verify `SENTRY_AUTH_TOKEN` in CI |
| Events lost on short-lived requests | SDK not flushing before worker terminates | Ensure `withSentry` or `sentryPagesPlugin` wraps your handler — they use `ctx.waitUntil()` to flush |
| Hono errors not captured | Hono app not instrumented | Use `@sentry/hono/cloudflare` — import `sentry` middleware and call `app.use(sentry(app, options))` |
| Durable Object errors missing | DO class not instrumented | Wrap class with `Sentry.instrumentDurableObjectWithSentry()` (Agents SDK classes: `instrumentAgentWithSentry`, v10.69.0+) — see `./durable-objects.md` |
| D1 queries not creating spans | Not using the SDK-provided `env`, or accessing DB outside the wrapped handler | Use the `env` passed into your handler — `withSentry` auto-instruments D1 bindings on access. No manual wrapping needed |
| Spans inside `waitUntil()` missing | Root span already ended before the background task ran | Wrap deferred work in `Sentry.startSpan({ ..., forceTransaction: true }, ...)` — see `./tracing.md` |
| Traces not linked across RPC / DO calls | RPC trace propagation not enabled | Set `enableRpcTracePropagation: true` on **both** caller and receiver (v10.52.0+) — see `./tracing.md` |
| Scheduled handler not monitored | `withSentry` not wrapping the handler | Ensure `export default Sentry.withSentry(...)` wraps your entire exported handler object |
| Release not auto-detected | `CF_VERSION_METADATA` binding not configured | Add `[version_metadata]` with `binding = "CF_VERSION_METADATA"` to `wrangler.toml` |
| Duplicate events in Workflows | Dedupe integration filtering step failures | SDK automatically disables dedupe for Workflows; verify you use `instrumentWorkflowWithSentry` |
