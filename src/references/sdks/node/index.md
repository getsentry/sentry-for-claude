# Sentry Node.js / Bun / Deno SDK

Opinionated wizard that scans your project and guides you through complete Sentry setup
for server-side JavaScript and TypeScript runtimes: Node.js, Bun, and Deno.

> **NestJS?** Use [[`nestjs`](../nestjs/index.md)](../nestjs/index.md) instead — it uses
> `@sentry/nestjs` with NestJS-native decorators and filters.
> **Next.js?** Use [[`nextjs`](../nextjs/index.md)](../nextjs/index.md) instead — it
> handles the three-runtime architecture (browser, server, edge).

> **Note:** SDK versions below reflect current Sentry docs at time of writing
> (`@sentry/node` ≥10.42.0, `@sentry/bun` ≥10.42.0, `@sentry/deno` ≥10.42.0). Always
> verify against
> [docs.sentry.io/platforms/javascript/guides/node/](https://docs.sentry.io/platforms/javascript/guides/node/)
> before implementing.

* * *

## Phase 1: Detect

Run these commands to identify the runtime, framework, and existing Sentry setup:

```bash
# Detect runtime
bun --version 2>/dev/null && echo "Bun detected"
deno --version 2>/dev/null && echo "Deno detected"
node --version 2>/dev/null && echo "Node.js detected"

# Detect existing Sentry packages
cat package.json 2>/dev/null | grep -E '"@sentry/'
cat deno.json deno.jsonc 2>/dev/null | grep -i sentry

# Detect Node.js framework
cat package.json 2>/dev/null | grep -E '"express"|"fastify"|"@hapi/hapi"|"koa"|"@nestjs/core"|"connect"'

# Detect Bun-specific frameworks
cat package.json 2>/dev/null | grep -E '"elysia"|"hono"'

# Detect Deno frameworks (deno.json imports)
cat deno.json deno.jsonc 2>/dev/null | grep -E '"oak"|"hono"|"fresh"'

# Detect module system (Node.js)
cat package.json 2>/dev/null | grep '"type"'
ls *.mjs *.cjs 2>/dev/null | head -5

# Detect existing instrument file
ls instrument.js instrument.mjs instrument.ts instrument.cjs 2>/dev/null

# Detect logging libraries
cat package.json 2>/dev/null | grep -E '"winston"|"pino"|"bunyan"'

# Detect cron / scheduling
cat package.json 2>/dev/null | grep -E '"node-cron"|"cron"|"agenda"|"bull"|"bullmq"'

# Detect AI / LLM usage
cat package.json 2>/dev/null | grep -E '"openai"|"@anthropic-ai"|"@langchain"|"@vercel/ai"|"@google/generative-ai"'

# Detect OpenTelemetry tracing
cat package.json 2>/dev/null | grep -E '"@opentelemetry/sdk-node"|"@opentelemetry/sdk-trace-node"|"@opentelemetry/sdk-trace-base"'
grep -rn "NodeTracerProvider\|trace\.getTracer\|startActiveSpan" \
  --include="*.ts" --include="*.js" --include="*.mjs" 2>/dev/null | head -5

# Check for companion frontend
ls frontend/ web/ client/ ui/ 2>/dev/null
cat package.json 2>/dev/null | grep -E '"react"|"vue"|"svelte"|"next"'
```

**What to determine:**

| Question | Impact |
| --- | --- |
| Which runtime? (Node.js / Bun / Deno) | Determines package, init pattern, and preload flag |
| Node.js: ESM or CJS? | ESM requires `--import ./instrument.mjs`; CJS uses `require("./instrument")` |
| Framework detected? | Determines which error handler to register |
| `@sentry/*` already installed? | Skip install, go straight to feature config |
| `instrument.js` / `instrument.mjs` already exists? | Merge into it rather than overwrite |
| Logging library detected? | Recommend Sentry Logs |
| Cron / job scheduler detected? | Recommend Crons monitoring |
| AI library detected? | Recommend AI Monitoring |
| OpenTelemetry tracing detected? | Use OTLP path instead of native tracing |
| Companion frontend found? | Trigger Phase 4 cross-link |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Don’t ask open-ended questions — lead with a proposal:

**Route from OTel detection:**
- **OTel tracing detected** (`@opentelemetry/sdk-node` or
  `@opentelemetry/sdk-trace-node` in `package.json`, or `NodeTracerProvider` in source)
  → use OTLP path: `otlpIntegration()` via `@sentry/node-core/light`; do **not** set
  `tracesSampleRate`; Sentry links errors to OTel traces automatically

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; captures unhandled exceptions, promise rejections,
  and framework errors
- ✅ **Tracing** — automatic HTTP, DB, and queue instrumentation via OpenTelemetry

**Optional (enhanced observability):**
- ⚡ **Logging** — structured logs via `Sentry.logger.*`; recommend when
  `winston`/`pino`/`bunyan` or log search is needed
- ⚡ **Profiling** — continuous CPU profiling (Node.js only; not available on Bun or
  Deno); **not available with OTLP path**
- ⚡ **AI Monitoring** — OpenAI, Anthropic, LangChain, Vercel AI SDK; recommend when
  AI/LLM calls detected
- ⚡ **Crons** — detect missed or failed scheduled jobs; recommend when node-cron, Bull,
  or Agenda is detected
- ⚡ **Metrics** — custom counters, gauges, distributions; recommend when custom KPIs
  needed
- ⚡ **Runtime Metrics** — automatic collection of memory, CPU, and event loop metrics;
  `nodeRuntimeMetricsIntegration()` (Node.js) / `bunRuntimeMetricsIntegration()` (Bun)

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| OTLP Integration | OTel tracing detected — **replaces** native Tracing |
| Tracing | **Always for server apps** — HTTP spans + DB spans are high-value; **skip if OTel tracing detected** |
| Logging | App uses winston, pino, bunyan, or needs log-to-trace correlation |
| Profiling | **Node.js only** — performance-critical service; native addon compatible; **skip if OTel tracing detected** (requires `tracesSampleRate`, incompatible with OTLP) |
| AI Monitoring | App calls OpenAI, Anthropic, LangChain, Vercel AI, or Google GenAI |
| Crons | App uses node-cron, Bull, BullMQ, Agenda, or any scheduled task pattern |
| Metrics | App needs custom counters, gauges, or histograms |
| Runtime Metrics | Any Node.js or Bun service wanting automatic memory/CPU/event-loop visibility |

**OTel tracing detected:** *“I see OpenTelemetry tracing in the project.
I recommend Sentry’s OTLP integration for tracing (via your existing OTel setup) + Error
Monitoring + Sentry Logging [+ Metrics/Crons/AI Monitoring if applicable]. Shall I
proceed?”*

**No OTel:** *“I recommend setting up Error Monitoring + Tracing.
Want me to also add Logging or Profiling?”*

* * *

## Phase 3: Guide

### Runtime: Node.js

#### Option 1: Wizard (Recommended for Node.js)

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```
> npx @sentry/wizard@latest -i node
> ```
> 
> It handles login, org/project selection, SDK installation, `instrument.js` creation,
> and package.json script updates.
> 
> **Once it finishes, come back and skip to [Verification](#verification).**

If the user skips the wizard, proceed with Option 2 (Manual Setup) below.

* * *

#### Option 2: Manual Setup — Node.js

##### Install

```bash
npm install @sentry/node --save
# or
yarn add @sentry/node
# or
pnpm add @sentry/node
```

##### Create the Instrument File

**CommonJS (`instrument.js`):**

```javascript
// instrument.js — must be loaded before all other modules
const Sentry = require("@sentry/node");

Sentry.init({
  dsn: process.env.SENTRY_DSN ?? "___DSN___",

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },

  // 100% in dev, lower in production
  tracesSampleRate: process.env.NODE_ENV === "development" ? 1.0 : 0.1,

  // Capture local variable values in stack frames
  includeLocalVariables: true,

  enableLogs: true,
});
```

**ESM (`instrument.mjs`):**

```javascript
// instrument.mjs — loaded via --import flag before any other module
import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: process.env.SENTRY_DSN ?? "___DSN___",

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  tracesSampleRate: process.env.NODE_ENV === "development" ? 1.0 : 0.1,
  includeLocalVariables: true,
  enableLogs: true,
});
```

##### Start Your App with Sentry Loaded First

**CommonJS** — add `require("./instrument")` as the very first line of your entry file:

```javascript
// app.js
require("./instrument"); // must be first

const express = require("express");
// ... rest of your app
```

**ESM** — use the `--import` flag so Sentry loads before all other modules (Node.js
18.19.0+ required):

```bash
node --import ./instrument.mjs app.mjs
```

Add to `package.json` scripts:

```json
{
  "scripts": {
    "start": "node --import ./instrument.mjs server.mjs",
    "dev": "node --import ./instrument.mjs --watch server.mjs"
  }
}
```

Or via environment variable (useful for wrapping existing start commands):

```bash
NODE_OPTIONS="--import ./instrument.mjs" npm start
```

##### Framework Error Handlers

Register the Sentry error handler **after all routes** so it can capture framework
errors:

**Express:**

```javascript
const express = require("express");
const Sentry = require("@sentry/node");

const app = express();

// ... your routes

// Add AFTER all routes — captures 5xx errors by default
Sentry.setupExpressErrorHandler(app);

// Optional: capture 4xx errors too
// Sentry.setupExpressErrorHandler(app, {
//   shouldHandleError(error) { return error.status >= 400; },
// });

app.listen(3000);
```

**Fastify:**

```javascript
const Fastify = require("fastify");
const Sentry = require("@sentry/node");

const fastify = Fastify();

// Add BEFORE routes (unlike Express!)
Sentry.setupFastifyErrorHandler(fastify);

// ... your routes

await fastify.listen({ port: 3000 });
```

**Koa:**

```javascript
const Koa = require("koa");
const Sentry = require("@sentry/node");

const app = new Koa();

// Add as FIRST middleware (catches errors thrown by later middleware)
Sentry.setupKoaErrorHandler(app);

// ... your other middleware and routes

app.listen(3000);
```

**Hapi (async — must await):**

```javascript
const Hapi = require("@hapi/hapi");
const Sentry = require("@sentry/node");

const server = Hapi.server({ port: 3000 });

// ... your routes

// Must await — Hapi registration is async
await Sentry.setupHapiErrorHandler(server);

await server.start();
```

**Connect:**

```javascript
const connect = require("connect");
const Sentry = require("@sentry/node");

const app = connect();

// Add BEFORE routes (like Fastify and Koa)
Sentry.setupConnectErrorHandler(app);

// ... your middleware and routes

require("http").createServer(app).listen(3000);
```

**NestJS** — has its own dedicated skill with full coverage:

> **Use the [[`nestjs`](../nestjs/index.md)](../nestjs/index.md) skill instead.** NestJS
> uses a separate package (`@sentry/nestjs`) with NestJS-native constructs:
> `SentryModule.forRoot()`, `SentryGlobalFilter`, `@SentryTraced`, `@SentryCron`
> decorators, and GraphQL/Microservices support.
> Load that skill for complete NestJS setup.

**Vanilla Node.js `http` module** — wrap request handler manually:

```javascript
const http = require("http");
const Sentry = require("@sentry/node");

const server = http.createServer((req, res) => {
  Sentry.withIsolationScope(() => {
    try {
      // your handler
      res.end("OK");
    } catch (err) {
      Sentry.captureException(err);
      res.writeHead(500);
      res.end("Internal Server Error");
    }
  });
});

server.listen(3000);
```

**Framework error handler summary:**

| Framework | Function | Placement | Async? |
| --- | --- | --- | --- |
| Express | `setupExpressErrorHandler(app)` | **After** all routes | No |
| Fastify | `setupFastifyErrorHandler(fastify)` | **Before** routes | No |
| Koa | `setupKoaErrorHandler(app)` | **First** middleware | No |
| Hapi | `setupHapiErrorHandler(server)` | Before `server.start()` | **Yes** |
| Connect | `setupConnectErrorHandler(app)` | **Before** routes | No |
| NestJS | → Use [[`nestjs`](../nestjs/index.md)](../nestjs/index.md) | Dedicated skill | — |

* * *

### Runtime: Bun

> **No wizard available for Bun.** Manual setup only.

#### Install

```bash
bun add @sentry/bun
```

#### Create `instrument.ts` (or `instrument.js`)

```typescript
// instrument.ts
import * as Sentry from "@sentry/bun";

Sentry.init({
  dsn: process.env.SENTRY_DSN ?? "___DSN___",

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  tracesSampleRate: process.env.NODE_ENV === "development" ? 1.0 : 0.1,
  enableLogs: true,
});
```

#### Start Your App with `--preload`

```bash
bun --preload ./instrument.ts server.ts
```

Add to `package.json`:

```json
{
  "scripts": {
    "start": "bun --preload ./instrument.ts server.ts",
    "dev": "bun --watch --preload ./instrument.ts server.ts"
  }
}
```

#### Bun.serve() — Auto-Instrumentation

`@sentry/bun` automatically instruments `Bun.serve()` via JavaScript Proxy.
No extra setup is required — just initialize with `--preload` and your `Bun.serve()`
calls are traced:

```typescript
// server.ts
const server = Bun.serve({
  port: 3000,
  fetch(req) {
    return new Response("Hello from Bun!");
  },
});
```

#### Framework Error Handlers on Bun

Bun can run Express, Fastify, Hono, and Elysia.
Use the same `@sentry/bun` import and the `@sentry/node` error handler functions
(re-exported by `@sentry/bun`):

```typescript
import * as Sentry from "@sentry/bun";
import express from "express";

const app = express();
// ... routes
Sentry.setupExpressErrorHandler(app);
app.listen(3000);
```

#### Bun Feature Support

| Feature | Bun Support | Notes |
| --- | --- | --- |
| Error Monitoring | ✅ Full | Same API as Node |
| Tracing | ✅ Via `@sentry/node` OTel | Most auto-instrumentations work |
| Logging | ✅ Full | `enableLogs: true` + `Sentry.logger.*` |
| Profiling | ❌ Not available | `@sentry/profiling-node` uses native addons incompatible with Bun |
| Metrics | ✅ Full | `Sentry.metrics.*` |
| Runtime Metrics | ✅ Full | `bunRuntimeMetricsIntegration()` — memory, CPU, event loop (no event loop delay percentiles) |
| Crons | ✅ Full | `Sentry.withMonitor()` |
| AI Monitoring | ✅ Full | OpenAI, Anthropic integrations work |

* * *

### Runtime: Deno

> **No wizard available for Deno.** Manual setup only.
> **Requires Deno 2.0+.** Deno 1.x is not supported.
> **Use `npm:` specifier.** The `deno.land/x/sentry` registry is deprecated.

#### Install via `deno.json` (Recommended)

```json
{
  "imports": {
    "@sentry/deno": "npm:@sentry/deno@10.42.0"
  }
}
```

Or import directly with the `npm:` specifier:

```typescript
import * as Sentry from "npm:@sentry/deno";
```

#### Initialize — Add to Entry File

```typescript
// main.ts — Sentry.init() must be called before any other code
import * as Sentry from "@sentry/deno";

Sentry.init({
  dsn: Deno.env.get("SENTRY_DSN") ?? "___DSN___",

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  tracesSampleRate: Deno.env.get("DENO_ENV") === "development" ? 1.0 : 0.1,
  enableLogs: true,
});

// Your application code follows
Deno.serve({ port: 8000 }, (req) => {
  return new Response("Hello from Deno!");
});
```

> Unlike Node.js and Bun, Deno does not have a `--preload` or `--import` flag.
> Sentry must be the first `import` in your entry file.

#### Required Deno Permissions

The SDK requires network access to reach your Sentry ingest domain:

```bash
deno run \
  --allow-net=o<ORG_ID>.ingest.sentry.io \
  --allow-read=./src \
  --allow-env=SENTRY_DSN,SENTRY_RELEASE \
  main.ts
```

For development, `--allow-all` works but is not recommended for production.

#### Deno Cron Integration

Deno provides native cron scheduling.
Use `denoCronIntegration` for automatic monitoring:

```typescript
import * as Sentry from "@sentry/deno";
import { denoCronIntegration } from "@sentry/deno";

Sentry.init({
  dsn: Deno.env.get("SENTRY_DSN") ?? "___DSN___",
  integrations: [denoCronIntegration()],
});

// Cron is automatically monitored
Deno.cron("daily-cleanup", "0 0 * * *", () => {
  // cleanup logic
});
```

#### Deno Feature Support

| Feature | Deno Support | Notes |
| --- | --- | --- |
| Error Monitoring | ✅ Full | Unhandled exceptions + `captureException` |
| Tracing | ✅ Custom OTel | Automatic spans for `Deno.serve()` and `fetch` |
| Logging | ✅ Full | `enableLogs: true` + `Sentry.logger.*` |
| Profiling | ❌ Not available | No profiling addon for Deno |
| Metrics | ✅ Full | `Sentry.metrics.*` |
| Runtime Metrics | ❌ Not available | No runtime metrics integration for Deno |
| Crons | ✅ Full | `denoCronIntegration()` + `Sentry.withMonitor()` |
| AI Monitoring | ✅ Partial | Vercel AI SDK integration works; OpenAI/Anthropic via `npm:` |

* * *

### OTLP Integration (OTel-First Projects — Node.js Only)

> Use this path **only when OpenTelemetry tracing was detected** in Phase 1 (e.g.,
> `@opentelemetry/sdk-node` or `@opentelemetry/sdk-trace-node` in `package.json`). For
> projects without an existing OTel setup, use the standard `@sentry/node` path above.

The OTLP integration uses `@sentry/node-core/light` — a lightweight Sentry SDK that does
not bundle its own OpenTelemetry.
Instead, it hooks into the user’s existing OTel `TracerProvider` and exports spans to
Sentry via OTLP.

#### When to Use

| Scenario | Recommended path |
| --- | --- |
| New project, no existing OTel | Standard `@sentry/node` (above) — includes built-in OTel |
| Existing OTel setup, want Sentry tracing | `@sentry/node-core/light` + `otlpIntegration()` |
| Existing OTel setup, sending to own Collector | `@sentry/node-core/light` + `otlpIntegration({ collectorUrl })` |

#### Install

```bash
npm install @sentry/node-core @opentelemetry/api @opentelemetry/sdk-trace-node @opentelemetry/sdk-trace-base
# or
yarn add @sentry/node-core @opentelemetry/api @opentelemetry/sdk-trace-node @opentelemetry/sdk-trace-base
# or
pnpm add @sentry/node-core @opentelemetry/api @opentelemetry/sdk-trace-node @opentelemetry/sdk-trace-base
```

> The `@opentelemetry/*` packages are peer dependencies.
> If the project already has them installed, skip duplicates.

#### Initialize

```javascript
// instrument.mjs — load via --import flag before any other module
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import * as Sentry from '@sentry/node-core/light';
import { otlpIntegration } from '@sentry/node-core/light/otlp';

// Register the user's OTel TracerProvider first
const provider = new NodeTracerProvider();
provider.register();

Sentry.init({
  dsn: process.env.SENTRY_DSN ?? '___DSN___',

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/node/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  enableLogs: true,

  // Do NOT set tracesSampleRate — OTel controls sampling
  integrations: [
    otlpIntegration({
      // Export OTel spans to Sentry via OTLP (default: true)
      setupOtlpTracesExporter: true,
    }),
  ],
});
```

**With a custom Collector endpoint:**

```javascript
Sentry.init({
  dsn: process.env.SENTRY_DSN ?? '___DSN___',
  integrations: [
    otlpIntegration({
      collectorUrl: 'http://localhost:4318/v1/traces',
    }),
  ],
});
```

#### Start Your App

Same `--import` pattern as the standard Node.js setup:

```bash
node --import ./instrument.mjs app.mjs
```

#### Key Differences from Standard `@sentry/node`

| Aspect | `@sentry/node` (standard) | `@sentry/node-core/light` (OTLP) |
| --- | --- | --- |
| OTel bundled | ✅ Yes — built-in TracerProvider | ❌ No — uses your existing provider |
| Tracing control | `tracesSampleRate` in `Sentry.init()` | OTel SDK controls sampling |
| Auto-instrumentation | ✅ Built-in (HTTP, DB, etc.) | ❌ You manage OTel instrumentations |
| Profiling | ✅ Available | ❌ Not compatible |
| Error ↔ trace linking | ✅ Automatic | ✅ Automatic (via `otlpIntegration`) |
| Package size | Larger (includes OTel) | Smaller (light mode) |

* * *

### For Each Agreed Feature

Load the corresponding reference file and follow its steps:

| Feature | Reference file | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) — captures, scopes, enrichment, beforeSend |
| OTLP Integration | See [OTLP Integration](#otlp-integration-otel-first-projects--nodejs-only) above | OTel tracing detected — **replaces** native Tracing |
| Tracing | `./tracing.md` | OTel auto-instrumentation, custom spans, distributed tracing, sampling; **skip if OTel tracing detected** |
| Logging | `./logging.md` | Structured logs, `Sentry.logger.*`, log-to-trace correlation |
| Profiling | `./profiling.md` | Node.js only — CPU profiling, Bun/Deno gaps documented; **skip if OTel tracing detected** |
| Metrics | `./metrics.md` | Custom counters, gauges, distributions |
| Runtime Metrics | See inline below | Automatic memory, CPU, and event loop metrics for Node.js and Bun |
| Crons | `./crons.md` | Scheduled job monitoring, node-cron, Bull, Agenda, Deno.cron |
| AI Monitoring | `./ai-monitoring.md` | OpenAI, Anthropic, LangChain, Vercel AI, Google GenAI |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: read the reference file, follow its steps exactly, and verify before
moving on.

### Runtime Metrics

Automatically collect Node.js and Bun runtime health metrics (memory, CPU utilization,
event loop delay/utilization, uptime) at a configurable interval.
Metrics appear in Sentry’s Metrics product under the `node.runtime.*` / `bun.runtime.*`
namespace.

**Node.js** — add `nodeRuntimeMetricsIntegration()` to your `instrument.js`:

```javascript
const Sentry = require("@sentry/node");

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  integrations: [
    Sentry.nodeRuntimeMetricsIntegration(),
    // Optional: change collection interval (default 30 000 ms)
    // Sentry.nodeRuntimeMetricsIntegration({ collectionIntervalMs: 60_000 }),
  ],
});
```

Metrics collected by default: `node.runtime.mem.rss`, `node.runtime.mem.heap_used`,
`node.runtime.mem.heap_total`, `node.runtime.cpu.utilization`,
`node.runtime.event_loop.delay.p50`, `node.runtime.event_loop.delay.p99`,
`node.runtime.event_loop.utilization`, `node.runtime.process.uptime`.

**Bun** — add `bunRuntimeMetricsIntegration()` to your `instrument.ts`:

```typescript
import * as Sentry from "@sentry/bun";
import { bunRuntimeMetricsIntegration } from "@sentry/bun";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  integrations: [
    bunRuntimeMetricsIntegration(),
    // Optional: change collection interval (default 30 000 ms)
    // bunRuntimeMetricsIntegration({ collectionIntervalMs: 60_000 }),
  ],
});
```

Metrics collected: same as Node.js except no event loop delay percentiles (unavailable
in Bun). Prefixed with `bun.runtime.*`.

* * *

## Configuration Reference

### `Sentry.init()` Core Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `dsn` | `string` | — | Required. Also from `SENTRY_DSN` env var |
| `tracesSampleRate` | `number` | — | 0–1; required to enable tracing; **do not set when using OTLP path** |
| `dataCollection` | `object` | conservative unless set | Fine-grained control over auto-collected categories (`userInfo`, `cookies`, `httpHeaders`, `httpBodies`, `queryParams`, `genAI`). When omitted, the SDK falls back to `sendDefaultPii` (default `false`). Passing the object — even `{}` — flips unset categories to their permissive defaults; opt out per category. |
| `includeLocalVariables` | `boolean` | `false` | Add local variable values to stack frames (Node.js) |
| `enableLogs` | `boolean` | `false` | Enable Sentry Logs product (v9.41.0+) |
| `environment` | `string` | `"production"` | Also from `SENTRY_ENVIRONMENT` env var |
| `release` | `string` | — | Also from `SENTRY_RELEASE` env var |
| `debug` | `boolean` | `false` | Log SDK activity to console |
| `enabled` | `boolean` | `true` | Set `false` in tests to disable sending |
| `sampleRate` | `number` | `1.0` | Fraction of error events to send (0–1) |
| `shutdownTimeout` | `number` | `2000` | Milliseconds to flush events before process exit |

### `nativeNodeFetchIntegration()` Options

Configures outgoing `fetch`/`undici` span capture.
Since `@opentelemetry/instrumentation-undici@0.22.0`, response headers like
`content-length` are no longer captured automatically — use `headersToSpanAttributes` to
opt in:

```javascript
Sentry.init({
  integrations: [
    Sentry.nativeNodeFetchIntegration({
      headersToSpanAttributes: {
        requestHeaders: ["x-request-id"],
        responseHeaders: ["content-length", "content-type"],
      },
    }),
  ],
});
```

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `breadcrumbs` | `boolean` | `true` | Record breadcrumbs for outgoing fetch requests |
| `headersToSpanAttributes.requestHeaders` | `string[]` | — | Request header names to capture as span attributes |
| `headersToSpanAttributes.responseHeaders` | `string[]` | — | Response header names to capture as span attributes |

### `otlpIntegration()` Options (`@sentry/node-core/light/otlp`)

For OTel-first projects using `@sentry/node-core/light`. Import:
`import { otlpIntegration } from '@sentry/node-core/light/otlp'`.

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `setupOtlpTracesExporter` | `boolean` | `true` | Auto-configure OTLP exporter to send spans to Sentry; set `false` if you already export to your own Collector |
| `collectorUrl` | `string` | `undefined` | OTLP HTTP endpoint of an OTel Collector (e.g., `http://localhost:4318/v1/traces`); when set, spans are sent to the collector instead of the DSN-derived Sentry endpoint |

### Graceful Shutdown

Flush buffered events before process exit — important for short-lived scripts and
serverless:

```javascript
process.on("SIGTERM", async () => {
  await Sentry.close(2000); // flush with 2s timeout
  process.exit(0);
});
```

### Environment Variables

| Variable | Purpose | Runtime |
| --- | --- | --- |
| `SENTRY_DSN` | DSN (alternative to hardcoding in `init()`) | All |
| `SENTRY_ENVIRONMENT` | Deployment environment | All |
| `SENTRY_RELEASE` | Release version string (auto-detected from git) | All |
| `SENTRY_AUTH_TOKEN` | Source map upload token | Build time |
| `SENTRY_ORG` | Org slug for source map upload | Build time |
| `SENTRY_PROJECT` | Project slug for source map upload | Build time |
| `NODE_OPTIONS` | Set `--import ./instrument.mjs` for ESM | Node.js |

### Source Maps (Node.js)

Readable stack traces in production require uploading source maps with `@sentry/cli` or
the webpack/esbuild/rollup plugins — for example, an inject + upload step in your build:

```json
{
  "scripts": {
    "build": "tsc && sentry-cli sourcemaps inject ./dist && sentry-cli sourcemaps upload ./dist"
  }
}
```

Upload needs a `SENTRY_AUTH_TOKEN` (a build-time secret).

* * *

## Verification

After setup, verify Sentry is receiving events:

```javascript
// Add temporarily to your entry file or a test route, then remove
import * as Sentry from "@sentry/node"; // or @sentry/bun / @sentry/deno

Sentry.captureException(new Error("Sentry test error — delete me"));
```

Or trigger an unhandled exception:

```javascript
// In a route handler or startup — will be captured automatically
throw new Error("Sentry test error — delete me");
```

Then check your [Sentry Issues dashboard](https://sentry.io/issues/) — the error should
appear within ~30 seconds.

**Verification checklist:**

| Check | How |
| --- | --- |
| Error captured | Throw in a handler, verify in Sentry Issues |
| Tracing working | Check Performance tab — should show HTTP spans |
| `includeLocalVariables` working | Stack frame in Sentry should show variable values |
| Source maps working | Stack trace shows readable file names, not minified |

* * *

## Phase 4: Cross-Link

After completing backend setup, check for companion services:

```bash
# Frontend companion
ls frontend/ web/ client/ ui/ 2>/dev/null
cat package.json 2>/dev/null | grep -E '"react"|"vue"|"svelte"|"next"'

# Other backend services
ls ../go.mod ../requirements.txt ../Gemfile 2>/dev/null
```

If a frontend, framework-specific SDK, or other backend is found, suggest the matching
skill:

**Dedicated JavaScript framework skills (prefer these over generic node-sdk):**

| Detected | Prefer skill | Why |
| --- | --- | --- |
| NestJS (`@nestjs/core` in `package.json`) | [[`nestjs`](../nestjs/index.md)](../nestjs/index.md) | Uses `@sentry/nestjs` with NestJS-native decorators, filters, and GraphQL support |
| Next.js (`next` in `package.json`) | [[`nextjs`](../nextjs/index.md)](../nextjs/index.md) | Three-runtime architecture (browser, server, edge), `withSentryConfig`, source map upload |

**Frontend companions:**

| Detected | Suggest |
| --- | --- |
| React app (`react` in `package.json`) | [[`react`](../react/index.md)](../react/index.md) |
| Svelte/SvelteKit | [[`svelte`](../svelte/index.md)](../svelte/index.md) |

**Other backend companions:**

| Detected | Suggest |
| --- | --- |
| Go backend (`go.mod`) | [[`go`](../go/index.md)](../go/index.md) |
| Python backend (`requirements.txt`, `pyproject.toml`) | [[`python`](../python/index.md)](../python/index.md) |
| Ruby backend (`Gemfile`) | [[`ruby`](../ruby/index.md)](../ruby/index.md) |

Connecting frontend and backend with the same DSN or linked projects enables
**distributed tracing** — stack traces that span your browser, API server, and database
in a single trace view.

* * *

## Troubleshooting

| Issue | Cause | Solution |
| --- | --- | --- |
| Events not appearing | `instrument.js` loaded too late | Ensure it’s the first `require()` / loaded via `--import` or `--preload` |
| Tracing spans missing | `tracesSampleRate` not set | Add `tracesSampleRate: 1.0` to `Sentry.init()` |
| ESM instrumentation not working | Missing `--import` flag | Run with `node --import ./instrument.mjs`; `import "./instrument.mjs"` inside app is not sufficient |
| `@sentry/profiling-node` install fails on Bun | Native addon incompatible | Profiling is not supported on Bun — remove `@sentry/profiling-node` |
| Deno: events not sent | Missing `--allow-net` permission | Run with `--allow-net=o<ORG_ID>.ingest.sentry.io` |
| Deno: `deno.land/x/sentry` not working | Deprecated and frozen at v8.55.0 | Switch to `npm:@sentry/deno` specifier |
| `includeLocalVariables` not showing values | Integration not activated or minified code | Ensure `includeLocalVariables: true` in init; check source maps |
| NestJS: errors not captured | Wrong SDK or missing filter | Use [[`nestjs`](../nestjs/index.md)](../nestjs/index.md) — NestJS needs `@sentry/nestjs`, not `@sentry/node` |
| Hapi: `setupHapiErrorHandler` timing issue | Not awaited | Must `await Sentry.setupHapiErrorHandler(server)` before `server.start()` |
| Shutdown: events lost | Process exits before flush | Add `await Sentry.close(2000)` in SIGTERM/SIGINT handler |
| Stack traces show minified code | Source maps not uploaded | Configure `@sentry/cli` source map upload in build step |
| No traces appearing (OTLP) | Missing `@opentelemetry/*` packages or `otlpIntegration` not added | Verify `@opentelemetry/sdk-trace-node` is installed; add `otlpIntegration()` to `integrations`; do **not** set `tracesSampleRate` |
| OTLP: errors not linked to traces | `otlpIntegration` not registered | Ensure `otlpIntegration()` is in the `integrations` array — it registers the propagation context that links errors to OTel traces |
| Profiling not starting (OTLP) | Profiling requires `tracesSampleRate` | Profiling is **not compatible** with the OTLP path; use the standard `@sentry/node` setup instead |
