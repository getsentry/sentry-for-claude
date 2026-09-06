# Sentry TanStack Start React SDK

Opinionated wizard that scans your TanStack Start React project and guides you through
complete Sentry setup for browser and server runtimes.

> **Note:** This SDK is currently alpha and documented as compatible with TanStack Start
> `1.0 RC`. Always verify against
> [docs.sentry.io/platforms/javascript/guides/tanstackstart-react/](https://docs.sentry.io/platforms/javascript/guides/tanstackstart-react/)
> before implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect TanStack Start / Router and existing Sentry
cat package.json | grep -E '"@tanstack/react-start"|"@tanstack/react-router"|"@sentry/tanstackstart-react"'

# Check if Sentry is already present
cat package.json | grep '"@sentry/'

# Detect key files used by the TanStack Start setup
ls src/router.tsx src/start.ts src/server.ts instrument.server.mjs vite.config.ts vite.config.js 2>/dev/null

# Check whether source map upload credentials are configured
cat .env .env.local .env.sentry-build-plugin 2>/dev/null | grep "SENTRY_AUTH_TOKEN"

# Detect deployment hints in scripts
cat package.json | grep -E '"dev"|"build"|"start"|NODE_OPTIONS|--import'

# Detect logging libraries
cat package.json | grep -E '"pino"|"winston"|"loglevel"'

# Detect companion backend directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod ../requirements.txt ../Gemfile ../pom.xml 2>/dev/null | head -3
```

**What to determine:**

| Question | Impact |
| --- | --- |
| `@tanstack/react-start` present? | Confirms this skill is the right setup path |
| `@sentry/tanstackstart-react` already installed? | Skip install and go to feature tuning |
| `src/router.tsx` exists? | Client-side `Sentry.init` placement |
| `src/start.ts` exists? | Global middleware setup for server-side errors |
| `src/server.ts` exists? | Server entry instrumentation placement |
| `instrument.server.mjs` exists? | Runtime startup instrumentation path |
| `vite.config.ts` exists? | Add `sentryTanstackStart` plugin and source maps |
| `SENTRY_AUTH_TOKEN` configured? | Source map upload readiness |
| Backend directory found? | Trigger Phase 4 cross-link suggestion |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Do not ask open-ended questions — lead with a proposal:

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; captures unhandled client and server errors
- ✅ **Tracing** — high-value for request and route timing across browser and server
- ✅ **Session Replay** — recommended for user-facing apps

**Optional (enhanced observability):**
- ⚡ **Logs** — recommend when structured log search and log-to-trace correlation are
  needed
- ⚡ **User Feedback** — recommend when product teams want in-app issue reports

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Usually yes** for TanStack Start; route + fetch instrumentation gives immediate value |
| Session Replay | User-facing app, login flows, checkout flows, or hard-to-reproduce UX bugs |
| Logs | Existing logging strategy, support workflow, or trace/log correlation needs |
| User Feedback | Team wants direct user reports without leaving the app |

Propose: *“I recommend Error Monitoring + Tracing + Session Replay.
Want me to also enable Logs and User Feedback?”*

* * *

## Phase 3: Guide

### Install

```bash
npm install @sentry/tanstackstart-react --save
```

### Configure Client-Side Sentry in `src/router.tsx`

Initialize Sentry inside the router factory and gate it to the browser:

```tsx
import * as Sentry from "@sentry/tanstackstart-react";
import { createRouter } from "@tanstack/react-router";

export const getRouter = () => {
  const router = createRouter();

  if (!router.isServer) {
    Sentry.init({
      dsn: "___PUBLIC_DSN___",
      dataCollection: {
        // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
        // https://docs.sentry.io/platforms/javascript/guides/tanstackstart-react/configuration/options/#dataCollection
        // userInfo: false,
        // httpBodies: [],
      },

      integrations: [
        Sentry.tanstackRouterBrowserTracingIntegration(router),
        Sentry.replayIntegration(),
        Sentry.feedbackIntegration({
          colorScheme: "system",
        }),
      ],

      enableLogs: true,
      tracesSampleRate: 1.0,
      replaysSessionSampleRate: 0.1,
      replaysOnErrorSampleRate: 1.0,
    });
  }

  return router;
};
```

### Configure Server-Side Sentry in `instrument.server.mjs`

Create `instrument.server.mjs` in project root:

```javascript
import * as Sentry from "@sentry/tanstackstart-react";

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/tanstackstart-react/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  enableLogs: true,
  tracesSampleRate: 1.0,
});
```

### Configure Vite Plugin in `vite.config.ts`

`sentryTanstackStart` should be the last plugin:

```typescript
import { defineConfig } from "vite";
import { sentryTanstackStart } from "@sentry/tanstackstart-react/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";

export default defineConfig({
  plugins: [
    tanstackStart(),
    sentryTanstackStart({
      org: "___ORG_SLUG___",
      project: "___PROJECT_SLUG___",
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
  ],
});
```

If the token is stored in `.env`, load it with `loadEnv` in the Vite config before
passing it to the plugin.

### Instrument Server Entry Point in `src/server.ts`

Wrap the fetch handler with `wrapFetchWithSentry`:

```typescript
import { wrapFetchWithSentry } from "@sentry/tanstackstart-react";
import handler, { createServerEntry } from "@tanstack/react-start/server-entry";

export default createServerEntry(
  wrapFetchWithSentry({
    fetch(request: Request) {
      return handler.fetch(request);
    },
  }),
);
```

### Add Global Server Middleware in `src/start.ts`

These middleware capture server-side request and function errors:

```tsx
import {
  sentryGlobalFunctionMiddleware,
  sentryGlobalRequestMiddleware,
} from "@sentry/tanstackstart-react";
import { createStart } from "@tanstack/react-start";

export const startInstance = createStart(() => {
  return {
    requestMiddleware: [sentryGlobalRequestMiddleware],
    functionMiddleware: [sentryGlobalFunctionMiddleware],
  };
});
```

Sentry middleware should be first in each array.

### Runtime Startup Patterns

Choose one runtime method:

| Runtime pattern | Use when … | Notes |
| --- | --- | --- |
| `--import` flag | You can control Node startup flags | Preferred for production monitoring |
| Direct import in `src/server.ts` | Host restricts startup flags (for example serverless hosts) | Limits instrumentation to native Node APIs |

`--import` examples:

```json
{
  "scripts": {
    "dev": "NODE_OPTIONS='--import ./instrument.server.mjs' vite dev --port 3000",
    "build": "vite build && cp instrument.server.mjs .output/server",
    "start": "node --import ./.output/server/instrument.server.mjs .output/server/index.mjs"
  }
}
```

Direct import fallback (top of `src/server.ts`):

```typescript
import "../instrument.server.mjs";
```

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file, follow steps exactly, and verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always |
| Tracing | `./tracing.md` | Route/API performance visibility needed |
| Session Replay | `./session-replay.md` | User-facing app |
| Logs | `./logging.md` | Structured logs and correlation needed |
| User Feedback | `./user-feedback.md` | In-app feedback collection needed |
| TanStack Start Features | `./tanstackstart-features.md` | Server entry, Vite plugin, source maps, runtime startup |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `Sentry.init()` Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `dsn` | `string` | — | Required; SDK is disabled when empty |
| `sendDefaultPii` | `boolean` | `false` | **Deprecated** (use `dataCollection`) — sends default PII such as request headers and IP-derived user context; equivalent to enabling all `dataCollection` categories |
| `dataCollection` | `DataCollection` | SDK defaults | Recommended replacement for `sendDefaultPii`; granular control over which categories are collected (`userInfo`, `cookies`, `httpHeaders`, `httpBodies`, `queryParams`, `genAI`, …) |
| `integrations` | `Integration[]` | SDK defaults | Include TanStack Router tracing, replay, feedback as needed |
| `enableLogs` | `boolean` | `false` | Enables `Sentry.logger.*` APIs |
| `tracesSampleRate` | `number` | — | `1.0` in development, lower in production |
| `replaysSessionSampleRate` | `number` | — | Fraction of all sessions recorded |
| `replaysOnErrorSampleRate` | `number` | — | Fraction of error sessions recorded |
| `tunnel` | `string` | — | Optional ad-blocker bypass endpoint |
| `debug` | `boolean` | `false` | SDK diagnostic logging |

### TanStack Start-Specific APIs

| API | Purpose |
| --- | --- |
| `tanstackRouterBrowserTracingIntegration(router)` | Browser navigation tracing |
| `wrapFetchWithSentry(...)` | Server request tracing + error capture on fetch handler |
| `sentryGlobalRequestMiddleware` | Captures request-level server errors |
| `sentryGlobalFunctionMiddleware` | Captures server function errors |
| `sentryTanstackStart({...})` | Vite plugin for source maps and middleware instrumentation |

* * *

## Verification

Trigger test events to confirm Sentry receives data.

### Issues Test (Frontend)

```tsx
<button
  type="button"
  onClick={() => {
    throw new Error("Sentry Test Error");
  }}
>
  Break the world
</button>
```

### Tracing Test (Frontend + API Route)

```tsx
<button
  type="button"
  onClick={async () => {
    await Sentry.startSpan({ name: "Example Frontend Span", op: "test" }, async () => {
      const res = await fetch("/api/sentry-example");
      if (!res.ok) {
        throw new Error("Sentry Example Frontend Error");
      }
    });
  }}
>
  Break the world
</button>
```

### Logs Test

```javascript
Sentry.logger.info("User example action completed");
Sentry.logger.warn("Slow operation detected", { operation: "data_fetch", duration: 3500 });
Sentry.logger.error("Validation failed", { field: "email", reason: "Invalid email" });
```

Confirm in Sentry:
- **Issues**: frontend/server errors appear
- **Traces**: browser and server spans appear
- **Replays**: session replay appears when enabled
- **Logs**: log lines appear when `enableLogs: true`
- **User Feedback**: submissions appear when feedback integration is enabled

* * *

## Phase 4: Cross-Link

After completing TanStack Start setup, check whether a companion backend exists without
Sentry:

```bash
ls ../backend ../server ../api ../go ../python 2>/dev/null
cat ../go.mod ../requirements.txt ../pyproject.toml ../Gemfile ../pom.xml 2>/dev/null | head -5
```

If a backend exists without Sentry configured, suggest the matching skill:

| Backend detected | Suggest skill |
| --- | --- |
| Go (`go.mod`) | [`go`](../go/index.md) |
| Python (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby (`Gemfile`) | [`ruby`](../ruby/index.md) |
| Java (`pom.xml`, `build.gradle`) | Use `@sentry/java` docs |
| Node.js backend services | [`node`](../node/index.md) |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing | Set `debug: true`, verify DSN, and ensure client/server init files both run |
| No server traces | Confirm `src/server.ts` uses `wrapFetchWithSentry` and runtime loads `instrument.server.mjs` |
| Server errors missing from route handlers | Ensure `sentryGlobalRequestMiddleware` and `sentryGlobalFunctionMiddleware` are first in arrays |
| Source maps not resolving | Verify `SENTRY_AUTH_TOKEN`, `org`, and `project` in `sentryTanstackStart` config |
| `SENTRY_AUTH_TOKEN` undefined in Vite config | Use `loadEnv(mode, process.cwd(), "")` or `.env.sentry-build-plugin` |
| Replay not recording | Ensure `replayIntegration()` is in `integrations` and sample rates are non-zero |
| Feedback widget not visible | Confirm `feedbackIntegration()` is configured and check CSS z-index conflicts |
| Logs missing in Sentry | Set `enableLogs: true` and use `Sentry.logger.*` APIs |
| Direct-import setup misses library spans | Prefer `--import` startup when possible; direct import supports native Node instrumentation only |
| SSR rendering exceptions not auto-captured | Capture manually with `Sentry.captureException` in error boundaries / fallback handlers |
