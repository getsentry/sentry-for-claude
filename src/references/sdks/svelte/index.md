# Sentry Svelte SDK

Opinionated wizard that scans your project and guides you through complete Sentry setup
for Svelte and SvelteKit.

> **Note:** SDK versions and APIs below reflect current Sentry docs at time of writing
> (`@sentry/sveltekit` ≥10.8.0, SvelteKit ≥2.31.0). Always verify against
> [docs.sentry.io/platforms/javascript/guides/sveltekit/](https://docs.sentry.io/platforms/javascript/guides/sveltekit/)
> before implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect framework type
cat package.json | grep -E '"svelte"|"@sveltejs/kit"|"@sentry/svelte"|"@sentry/sveltekit"'

# Check for SvelteKit indicators
ls svelte.config.js svelte.config.ts vite.config.ts vite.config.js 2>/dev/null

# Check SvelteKit version (determines which setup pattern to use)
cat package.json | grep '"@sveltejs/kit"'

# Check if Sentry is already installed
cat package.json | grep '"@sentry/'

# Check existing hook files
ls src/hooks.client.ts src/hooks.client.js src/hooks.server.ts src/hooks.server.js \
   src/instrumentation.server.ts 2>/dev/null

# Detect logging libraries (Node side)
cat package.json | grep -E '"pino"|"winston"|"consola"'

# Detect if there's a backend (Go, Python, Ruby, etc.) in adjacent directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod ../requirements.txt ../Gemfile 2>/dev/null | head -3
```

**What to determine:**

| Question | Impact |
| --- | --- |
| `@sveltejs/kit` in `package.json`? | SvelteKit path vs. plain Svelte path |
| SvelteKit ≥2.31.0? | Modern (`instrumentation.server.ts`) vs. legacy setup |
| `@sentry/sveltekit` already present? | Skip install, go straight to feature config |
| `vite.config.ts` present? | Source map upload via Vite plugin available |
| Backend directory found? | Trigger Phase 4 cross-link suggestion |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Don’t ask open-ended questions — lead with a proposal:

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; auto-captures unhandled errors on client and server
- ✅ **Tracing** — SvelteKit has both client-side navigation spans and server-side
  request spans; always recommend
- ✅ **Session Replay** — recommended for user-facing SvelteKit apps (client-side only)

**Optional (enhanced observability):**
- ⚡ **Logging** — structured logs via `Sentry.logger.*`; recommend when app uses
  server-side logging or needs log-to-trace correlation

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Always for SvelteKit** (client + server); for plain Svelte when calling APIs |
| Session Replay | User-facing app, login flows, or checkout pages present |
| Logging | App already uses server-side logging, or structured log search is needed |

Propose: *“I recommend setting up Error Monitoring + Tracing + Session Replay.
Want me to also add structured Logging?”*

* * *

## Phase 3: Guide

### Determine Setup Path

| Your project | Package | Setup complexity |
| --- | --- | --- |
| SvelteKit (≥2.31.0) | `@sentry/sveltekit` | 5 files to create/modify |
| SvelteKit (<2.31.0) | `@sentry/sveltekit` | 3 files (init in hooks.server.ts) |
| Plain Svelte (no `@sveltejs/kit`) | `@sentry/svelte` | Single entry point |

* * *

### Path A: SvelteKit (Recommended — Modern, ≥2.31.0)

#### Option 1: Wizard (Recommended)

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```
> npx @sentry/wizard@latest -i sveltekit
> ```
> 
> It handles login, org/project selection, SDK installation, client/server hooks, Vite
> plugin config, source map upload, and adds a `/sentry-example-page`.
> 
> **Once it finishes, come back and skip to [Verification](#verification).**

If the user skips the wizard, proceed with Option 2 (Manual Setup) below.

#### Option 2: Manual Setup

**Step 1 — Install**

```bash
npm install @sentry/sveltekit --save
```

**Step 2 — `svelte.config.js`** — Enable instrumentation

```javascript
import adapter from "@sveltejs/adapter-auto";

const config = {
  kit: {
    adapter: adapter(),
    experimental: {
      instrumentation: { server: true },
      tracing: { server: true },
    },
  },
};

export default config;
```

**Step 3 — `src/instrumentation.server.ts`** — Server-side init (runs once at startup)

```typescript
import * as Sentry from "@sentry/sveltekit";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.SENTRY_ENVIRONMENT,
  release: process.env.SENTRY_RELEASE,

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/sveltekit/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  tracesSampleRate: 1.0,    // lower to 0.1–0.2 in production
  enableLogs: true,
});
```

**Step 4 — `src/hooks.client.ts`** — Client-side init

```typescript
import * as Sentry from "@sentry/sveltekit";

Sentry.init({
  dsn: import.meta.env.PUBLIC_SENTRY_DSN ?? import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/sveltekit/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  tracesSampleRate: 1.0,

  integrations: [
    Sentry.replayIntegration({
      maskAllText: true,
      blockAllMedia: true,
    }),
  ],

  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,
  enableLogs: true,
});

export const handleError = Sentry.handleErrorWithSentry();
```

**Step 5 — `src/hooks.server.ts`** — Server hooks (no init here in modern setup)

```typescript
import * as Sentry from "@sentry/sveltekit";
import { sequence } from "@sveltejs/kit/hooks";

export const handleError = Sentry.handleErrorWithSentry();

// sentryHandle() instruments incoming requests and creates root spans
export const handle = Sentry.sentryHandle();

// If you have other handle functions, compose with sequence():
// export const handle = sequence(Sentry.sentryHandle(), myAuthHandle);
```

**Step 6 — `vite.config.ts`** — Source maps (requires `SENTRY_AUTH_TOKEN`)

```typescript
import { sveltekit } from "@sveltejs/kit/vite";
import { sentrySvelteKit } from "@sentry/sveltekit";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [
    // sentrySvelteKit MUST come before sveltekit()
    sentrySvelteKit({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
    sveltekit(),
  ],
});
```

Add to `.env` (never commit):
```bash
SENTRY_AUTH_TOKEN=sntrys_...
SENTRY_ORG=my-org-slug
SENTRY_PROJECT=my-project-slug
```

* * *

### Path B: SvelteKit Legacy (<2.31.0 or `@sentry/sveltekit` <10.8.0)

Skip `instrumentation.server.ts` and `svelte.config.js` changes.
Instead, put `Sentry.init()` directly in `hooks.server.ts`:

```typescript
// src/hooks.server.ts (legacy — init goes here)
import * as Sentry from "@sentry/sveltekit";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 1.0,
  enableLogs: true,
});

export const handleError = Sentry.handleErrorWithSentry();
export const handle = Sentry.sentryHandle();
```

`hooks.client.ts` and `vite.config.ts` are identical to the modern path.

* * *

### Path C: Plain Svelte (no SvelteKit)

**Install:**

```bash
npm install @sentry/svelte --save
```

**Configure in entry point** (`src/main.ts` or `src/main.js`) **before** mounting the
app:

```typescript
import * as Sentry from "@sentry/svelte";
import App from "./App.svelte";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/sveltekit/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },

  integrations: [
    Sentry.browserTracingIntegration(),
    Sentry.replayIntegration({
      maskAllText: true,
      blockAllMedia: true,
    }),
  ],

  tracesSampleRate: 1.0,
  tracePropagationTargets: ["localhost", /^https:\/\/yourapi\.io/],
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,
  enableLogs: true,
});

const app = new App({ target: document.getElementById("app")! });
export default app;
```

**Optional: Svelte component tracking** (auto-injects tracking into all components):

```javascript
// svelte.config.js
import { withSentryConfig } from "@sentry/svelte";

export default withSentryConfig(
  { compilerOptions: {} },
  { componentTracking: { trackComponents: true } }
);
```

* * *

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file, follow its steps, then verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing | `./tracing.md` | API calls / distributed tracing needed |
| Session Replay | `./session-replay.md` | User-facing app |
| Logging | `./logging.md` | Structured logs / log-to-trace correlation |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `Sentry.init()` Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `dsn` | `string` | — | **Required.** Use env var; SDK is disabled when empty |
| `environment` | `string` | `"production"` | e.g., `"staging"`, `"development"` |
| `release` | `string` | — | e.g., `"my-app@1.2.3"` or git SHA |
| `dataCollection` | `object` | — | Control what data is collected (userInfo, cookies, headers, etc.) |
| `dataCollection.userInfo` | `boolean` | `true` | Auto-populate `user.*` fields from instrumentation |
| `dataCollection.cookies` | `boolean\|object` | `true` | Cookie collection and filtering |
| `dataCollection.httpHeaders` | `object` | `{request: true, response: true}` | HTTP header collection for requests/responses |
| `dataCollection.httpBodies` | `string[]` | `["incomingRequest", "outgoingRequest", "incomingResponse", "outgoingResponse"]` | Which HTTP body types to collect |
| `dataCollection.queryParams` | `boolean\|object` | `true` | Query parameter collection and filtering |
| `tracesSampleRate` | `number` | — | 0–1; use `1.0` in dev, `0.1–0.2` in prod |
| `tracesSampler` | `function` | — | Per-transaction sampling; overrides `tracesSampleRate` |
| `tracePropagationTargets` | `(string\|RegExp)[]` | — | URLs that receive distributed tracing headers |
| `replaysSessionSampleRate` | `number` | — | Fraction of all sessions recorded (client only) |
| `replaysOnErrorSampleRate` | `number` | — | Fraction of error sessions recorded (client only) |
| `enableLogs` | `boolean` | `false` | Enable `Sentry.logger.*` API |
| `beforeSendLog` | `function` | — | Filter/modify logs before send |
| `debug` | `boolean` | `false` | Verbose SDK output to console |

### Server-Only Options (`instrumentation.server.ts` / `hooks.server.ts`)

| Option | Type | Notes |
| --- | --- | --- |
| `serverName` | `string` | Hostname tag on server events |
| `includeLocalVariables` | `boolean` | Attach local vars to stack frames |
| `shutdownTimeout` | `number` | ms to flush events before process exit (default: 2000) |

### Adapter Compatibility

| Adapter | Support |
| --- | --- |
| `@sveltejs/adapter-auto` / adapter-vercel (Node) | ✅ Full |
| `@sveltejs/adapter-node` | ✅ Full |
| `@sveltejs/adapter-cloudflare` | ⚠️ Partial — requires extra setup |
| Vercel Edge Runtime | ❌ Not supported |

### SvelteKit File Summary

| File | Purpose | Modern | Legacy |
| --- | --- | --- | --- |
| `src/instrumentation.server.ts` | Server `Sentry.init()` — runs once at startup | ✅ Required | ❌ |
| `src/hooks.client.ts` | Client `Sentry.init()` + `handleError` | ✅ Required | ✅ Required |
| `src/hooks.server.ts` | `handleError` + `sentryHandle()` (no init) | ✅ Required | ✅ Init goes here |
| `svelte.config.js` | Enable `experimental.instrumentation.server` | ✅ Required | ❌ |
| `vite.config.ts` | `sentrySvelteKit()` plugin for source maps | ✅ Recommended | ✅ Recommended |
| `.env` | `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` | ✅ For source maps | ✅ For source maps |

* * *

## Verification

After setup, trigger test events to confirm Sentry is receiving data:

```svelte
<!-- src/routes/sentry-test/+page.svelte -->
<script>
  import * as Sentry from "@sentry/sveltekit";
</script>

<button onclick={() => { throw new Error("Sentry client test"); }}>
  Test Client Error
</button>

<button onclick={() => Sentry.captureMessage("Sentry test message", "info")}>
  Test Message
</button>
```

```typescript
// src/routes/sentry-test/+server.ts
export const GET = () => {
  throw new Error("Sentry server test");
};
```

Check the Sentry dashboard:
- **Issues** → both errors should appear within seconds
- **Traces** → look for route-based transactions
- **Replays** → session recording visible after page interaction
- **Logs** → structured log entries (if logging enabled)

If nothing appears, set `debug: true` in `Sentry.init()` and check the browser/server
console for SDK output.

* * *

## Phase 4: Cross-Link

After completing Svelte/SvelteKit setup, check for a companion backend missing Sentry
coverage:

```bash
# Look for backend in adjacent directories
ls ../backend ../server ../api ../go ../python 2>/dev/null
cat ../go.mod 2>/dev/null | head -3
cat ../requirements.txt ../pyproject.toml 2>/dev/null | head -3
cat ../Gemfile 2>/dev/null | head -3
```

If a backend exists without Sentry configured, suggest the matching skill:

| Backend detected | Suggest skill |
| --- | --- |
| Go (`go.mod`) | [`go`](../go/index.md) |
| Python (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby (`Gemfile`) | [`ruby`](../ruby/index.md) |
| Node.js (Express, Fastify, etc.) | Use `@sentry/node` — see [docs.sentry.io/platforms/javascript/guides/express/](https://docs.sentry.io/platforms/javascript/guides/express/) |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing | Set `debug: true`, check DSN, open browser console for SDK errors |
| Source maps not working | Run `npm run build` (not `dev`), verify `SENTRY_AUTH_TOKEN` is set |
| Server errors not captured | Ensure `handleErrorWithSentry()` is exported from `hooks.server.ts` |
| Client errors not captured | Ensure `handleErrorWithSentry()` is exported from `hooks.client.ts` |
| Session replay not recording | Confirm `replayIntegration()` is in client init only (never server) |
| `sentryHandle()` + other handles not composing | Wrap with `sequence(Sentry.sentryHandle(), myHandle)` |
| Ad-blocker blocking events | Set `tunnel: "/sentry-tunnel"` and add a server-side relay endpoint |
| SvelteKit instrumentation not activating | Confirm `experimental.instrumentation.server: true` in `svelte.config.js` |
| Cloudflare adapter issues | Consult [docs.sentry.io/platforms/javascript/guides/sveltekit/](https://docs.sentry.io/platforms/javascript/guides/sveltekit/) for adapter-specific notes |
| `wrapLoadWithSentry` / `wrapServerLoadWithSentry` errors | These are legacy wrappers — remove them; `sentryHandle()` instruments load functions automatically in ≥10.8.0 |
