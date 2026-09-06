# Sentry React SDK

Opinionated wizard that scans your React project and guides you through complete Sentry
setup.

> **Note:** SDK versions and APIs below reflect current Sentry docs at time of writing
> (`@sentry/react` ≥8.0.0). Always verify against
> [docs.sentry.io/platforms/javascript/guides/react/](https://docs.sentry.io/platforms/javascript/guides/react/)
> before implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect React version
cat package.json | grep -E '"react"|"react-dom"'

# Check for existing Sentry
cat package.json | grep '"@sentry/'

# Detect router and framework mode hints
cat package.json | grep -E '"react-router-dom"|"react-router"|"@react-router/"|"@tanstack/react-router"|"@sentry/react-router"'

# Detect state management
cat package.json | grep -E '"redux"|"@reduxjs/toolkit"'

# Detect build tool
ls vite.config.ts vite.config.js webpack.config.js craco.config.js 2>/dev/null
cat package.json | grep -E '"vite"|"react-scripts"|"webpack"'

# Detect logging libraries
cat package.json | grep -E '"pino"|"winston"|"loglevel"'

# Check for companion backend in adjacent directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod ../requirements.txt ../Gemfile ../pom.xml 2>/dev/null | head -3
```

**What to determine:**

| Question | Impact |
| --- | --- |
| React 19+? | Use `reactErrorHandler()` hook pattern |
| React <19? | Use `Sentry.ErrorBoundary` |
| `@sentry/react` already present? | Skip install, go straight to feature config |
| React Router Framework mode indicators (`@sentry/react-router`, `@react-router/*`)? | Use [`react-router-framework`](../react-router-framework/index.md) |
| `react-router-dom` v5 / v6 / v7? | Determines which router integration to use |
| `@tanstack/react-router`? | Use `tanstackRouterBrowserTracingIntegration()` |
| Redux in use? | Recommend `createReduxEnhancer()` |
| Vite detected? | Source maps via `sentryVitePlugin` |
| CRA (`react-scripts`)? | Source maps via `@sentry/webpack-plugin` in CRACO |
| Backend directory found? | Trigger Phase 4 cross-link suggestion |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Don’t ask open-ended questions — lead with a proposal:

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; captures unhandled errors, React error boundaries,
  React 19 hooks
- ✅ **Tracing** — React SPAs benefit from page load, navigation, and API call tracing
- ✅ **Session Replay** — recommended for user-facing apps; records sessions around
  errors

**Optional (enhanced observability):**
- ⚡ **Logging** — structured logs via `Sentry.logger.*`; recommend when structured log
  search is needed
- ⚡ **Profiling** — JS Self-Profiling API (⚠️ experimental; requires cross-origin
  isolation headers)

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Always for React SPAs** — page load + navigation spans are high-value |
| Session Replay | User-facing app, login flows, or checkout pages |
| Logging | App needs structured log search or log-to-trace correlation |
| Profiling | Performance-critical app; server sends `Document-Policy: js-profiling` header |

**React-specific extras:**
- React 19 detected → set up `reactErrorHandler()` on `createRoot`
- React Router v5/v6/v7 non-framework detected → configure matching router integration
  (see Phase 3)
- React Router Framework mode detected → switch to
  [`react-router-framework`](../react-router-framework/index.md)
- Redux detected → add `createReduxEnhancer()` to Redux store
- Vite detected → configure `sentryVitePlugin` for source maps (essential for readable
  stack traces)

Propose: *“I recommend setting up Error Monitoring + Tracing + Session Replay.
Want me to also add Logging or Profiling?”*

* * *

## Phase 3: Guide

### Install

```bash
npm install @sentry/react --save
```

### Create `src/instrument.ts`

Sentry must initialize **before any other code runs**. Put `Sentry.init()` in a
dedicated sidecar file:

```typescript
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN, // Adjust per build tool (see table below)
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_APP_VERSION, // inject at build time

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/react/configuration/options/#dataCollection
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

  // Tracing
  tracesSampleRate: 1.0, // lower to 0.1–0.2 in production
  tracePropagationTargets: ["localhost", /^https:\/\/yourapi\.io/],

  // Session Replay
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,

  enableLogs: true,
});
```

**DSN environment variable by build tool:**

| Build Tool | Variable Name | Access in code |
| --- | --- | --- |
| Vite | `VITE_SENTRY_DSN` | `import.meta.env.VITE_SENTRY_DSN` |
| Create React App | `REACT_APP_SENTRY_DSN` | `process.env.REACT_APP_SENTRY_DSN` |
| Custom webpack | `SENTRY_DSN` | `process.env.SENTRY_DSN` |

### Entry Point Setup

Import `instrument.ts` as the **very first import** in your entry file:

```tsx
// src/main.tsx (Vite) or src/index.tsx (CRA/webpack)
import "./instrument";              // ← MUST be first

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>
);
```

### React Version-Specific Error Handling

**React 19+** — use `reactErrorHandler()` on `createRoot`:

```tsx
import { reactErrorHandler } from "@sentry/react";

createRoot(document.getElementById("root")!, {
  onUncaughtError: reactErrorHandler(),
  onCaughtError: reactErrorHandler(),
  onRecoverableError: reactErrorHandler(),
}).render(<App />);
```

**React <19** — wrap your app in `Sentry.ErrorBoundary`:

```tsx
import * as Sentry from "@sentry/react";

createRoot(document.getElementById("root")!).render(
  <Sentry.ErrorBoundary fallback={<p>Something went wrong</p>} showDialog>
    <App />
  </Sentry.ErrorBoundary>
);
```

Use `<Sentry.ErrorBoundary>` for any sub-tree that should catch errors independently
(route sections, widgets, etc.).

### Router Integration

Configure the matching integration for your router (non-framework mode):

| Router | Integration | Notes |
| --- | --- | --- |
| React Router v7 | `reactRouterV7BrowserTracingIntegration` | `useEffect`, `useLocation`, `useNavigationType`, `createRoutesFromChildren`, `matchRoutes` from `react-router` |
| React Router v6 | `reactRouterV6BrowserTracingIntegration` | `useEffect`, `useLocation`, `useNavigationType`, `createRoutesFromChildren`, `matchRoutes` from `react-router-dom` |
| React Router v5 | `reactRouterV5BrowserTracingIntegration` | Wrap routes in `withSentryRouting(Route)` |
| TanStack Router | `tanstackRouterBrowserTracingIntegration(router)` | Pass router instance — no hooks required |
| No router / custom | `browserTracingIntegration()` | Names transactions by URL path |

**React Router v6/v7 setup:**

```typescript
// in instrument.ts integrations array:
import React from "react";
import {
  createRoutesFromChildren, matchRoutes,
  useLocation, useNavigationType,
} from "react-router-dom"; // or "react-router" for v7
import * as Sentry from "@sentry/react";
import { reactRouterV6BrowserTracingIntegration } from "@sentry/react";
import { createBrowserRouter } from "react-router-dom";

// Option A — createBrowserRouter (recommended for v6.4+):
const sentryCreateBrowserRouter = Sentry.wrapCreateBrowserRouterV6(createBrowserRouter);
const router = sentryCreateBrowserRouter([...routes]);

// Option B — createBrowserRouter for React Router v7:
// const sentryCreateBrowserRouter = Sentry.wrapCreateBrowserRouterV7(createBrowserRouter);

// Option C — integration with hooks (v6 without data APIs):
Sentry.init({
  integrations: [
    reactRouterV6BrowserTracingIntegration({
      useEffect: React.useEffect,
      useLocation,
      useNavigationType,
      matchRoutes,
      createRoutesFromChildren,
    }),
  ],
});
```

**TanStack Router setup:**

```typescript
import { tanstackRouterBrowserTracingIntegration } from "@sentry/react";

// Pass your TanStack router instance:
Sentry.init({
  integrations: [tanstackRouterBrowserTracingIntegration(router)],
});
```

### Redux Integration (when detected)

```typescript
import * as Sentry from "@sentry/react";
import { configureStore } from "@reduxjs/toolkit";

const store = configureStore({
  reducer: rootReducer,
  enhancers: (getDefaultEnhancers) =>
    getDefaultEnhancers().concat(Sentry.createReduxEnhancer()),
});
```

### Source Maps Setup (strongly recommended)

Without source maps, stack traces show minified code.
Set up the build plugin to upload source maps automatically:

**Vite (`vite.config.ts`):**

```typescript
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { sentryVitePlugin } from "@sentry/vite-plugin";

export default defineConfig({
  build: { sourcemap: "hidden" },
  plugins: [
    react(),
    sentryVitePlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
  ],
});
```

**Create React App (via CRACO):**

```bash
npm install @craco/craco @sentry/webpack-plugin --save-dev
```

```javascript
// craco.config.js
const { sentryWebpackPlugin } = require("@sentry/webpack-plugin");

module.exports = {
  webpack: {
    plugins: {
      add: [
        sentryWebpackPlugin({
          org: process.env.SENTRY_ORG,
          project: process.env.SENTRY_PROJECT,
          authToken: process.env.SENTRY_AUTH_TOKEN,
        }),
      ],
    },
  },
};
```

`SENTRY_ORG` / `SENTRY_PROJECT` / `SENTRY_AUTH_TOKEN` are build-time values; the auth
token is a secret (never commit it).

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file, follow its steps, verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing | `./tracing.md` | SPA navigation / API call tracing |
| Session Replay | `./session-replay.md` | User-facing app |
| Logging | `./logging.md` | Structured log search / log-to-trace |
| Profiling | `./profiling.md` | Performance-critical app |
| React Features | `./react-features.md` | Redux, component tracking, source maps, integrations catalog |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `Sentry.init()` Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `dsn` | `string` | — | **Required.** SDK disabled when empty |
| `environment` | `string` | `"production"` | e.g., `"staging"`, `"development"` |
| `release` | `string` | — | e.g., `"my-app@1.0.0"` or git SHA — links errors to releases |
| `dataCollection` | `object` | — | Fine-grained control over data collection (see table below); **recommended over `sendDefaultPii`** |
| `sendDefaultPii` | `boolean` | `false` | ⚠️ **Legacy** — use `dataCollection` instead; includes IP addresses and request headers |
| `tracesSampleRate` | `number` | — | 0–1; `1.0` in dev, `0.1–0.2` in prod |
| `tracesSampler` | `function` | — | Per-transaction sampling; overrides rate |
| `tracePropagationTargets` | `(string\|RegExp)[]` | — | Outgoing URLs that receive distributed tracing headers |
| `replaysSessionSampleRate` | `number` | — | Fraction of all sessions recorded |
| `replaysOnErrorSampleRate` | `number` | — | Fraction of error sessions recorded |
| `enableLogs` | `boolean` | `false` | Enable `Sentry.logger.*` API |
| `attachStacktrace` | `boolean` | `false` | Stack traces on `captureMessage()` calls |
| `maxBreadcrumbs` | `number` | `100` | Breadcrumbs stored per event |
| `debug` | `boolean` | `false` | Verbose SDK output to console |
| `tunnel` | `string` | — | Proxy URL to bypass ad blockers |

### `dataCollection` Options (SDK ≥10.57.0)

Fine-grained control over what data the SDK collects.
Replaces the simple `sendDefaultPii` boolean with per-feature toggles:

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `userInfo` | `boolean` | `true` | Collect user IP and headers (equivalent to `sendDefaultPii: true`) |
| `cookies` | `boolean \| { allow: string[] } \| { deny: string[] }` | `true` | Cookie collection and filtering; `true` = all cookies (sensitive keys filtered) |
| `httpHeaders.request` | `boolean \| { allow: string[] } \| { deny: string[] }` | `true` | HTTP request header collection |
| `httpHeaders.response` | `boolean \| { allow: string[] } \| { deny: string[] }` | `true` | HTTP response header collection |
| `urlQueryParams` | `boolean \| { allow: string[] } \| { deny: string[] }` | `true` | Query parameter collection and filtering (SDK ≥10.67.0; replaces deprecated `queryParams`) |
| `httpBodies` | `HttpBodyCollectionTarget[]` | `["incomingRequest", "outgoingRequest", "incomingResponse", "outgoingResponse"]` | Collect request/response bodies; options: `'incomingRequest'`, `'outgoingRequest'`, `'incomingResponse'`, `'outgoingResponse'` |
| `graphQL.document` | `boolean` | `true` | Attach the GraphQL document (query/mutation source text) — requires a GraphQL integration enabled (SDK ≥10.66.0) |
| `graphQL.variables` | `boolean` | `true` | Attach GraphQL operation variables — requires a GraphQL integration enabled (SDK ≥10.66.0) |
| `databaseQueryData` | `boolean` | `true` | Collect DB query parameters, inline literal values, mutation/request bodies, and returned result data (SDK ≥10.66.0) |
| `genAI.inputs` | `boolean` | `true` | Record AI model inputs (for AI monitoring) |
| `genAI.outputs` | `boolean` | `true` | Record AI model outputs (for AI monitoring) |
| `stackFrameVariables` | `boolean` | `true` | Capture local variable values in stack frames |
| `frameContextLines` | `number` | `5` | Source code context lines around stack frames |

> **Deprecated:** `queryParams` still works but is deprecated in favor of `urlQueryParams` (same shape and default).

**Example:** Allow only specific cookies and headers:

```typescript
Sentry.init({
  dataCollection: {
    cookies: { allow: ['session', 'user_id'] },
    httpHeaders: {
      request: { allow: ['authorization', 'x-request-id'] },
      response: { deny: ['set-cookie'] },
    },
  },
});
```

### React Compatibility Matrix

| React Version | Error handling approach | SDK minimum |
| --- | --- | --- |
| React 19+ | `reactErrorHandler()` on `createRoot` | `@sentry/react` ≥8.0.0 |
| React 16–18 | `Sentry.ErrorBoundary` component | `@sentry/react` ≥7.0.0 |
| React 16 | `componentDidCatch` class boundaries | `@sentry/react` ≥6.0.0 |

* * *

## Verification

Trigger test events to confirm Sentry is receiving data:

```tsx
// Add a temporary test button anywhere in your app
import * as Sentry from "@sentry/react";

function SentryTest() {
  return (
    <>
      <button onClick={() => { throw new Error("Sentry React test error"); }}>
        Test Error
      </button>
      <button onClick={() => Sentry.captureMessage("Sentry test message", "info")}>
        Test Message
      </button>
    </>
  );
}
```

Check the Sentry dashboard:
- **Issues** → error appears within seconds
- **Traces** → page load and navigation transactions visible
- **Replays** → session recording visible after page interaction
- **Logs** → structured log entries if logging enabled

Set `debug: true` in `Sentry.init()` and check the browser console if nothing appears.

* * *

## Phase 4: Cross-Link

After completing React setup, check for a companion backend missing Sentry coverage:

```bash
ls ../backend ../server ../api ../go ../python 2>/dev/null
cat ../go.mod 2>/dev/null | head -3
cat ../requirements.txt ../pyproject.toml 2>/dev/null | head -3
cat ../Gemfile 2>/dev/null | head -3
cat ../pom.xml 2>/dev/null | grep '<artifactId>' | head -3
```

If a backend exists without Sentry configured, suggest the matching skill:

| Backend detected | Suggest skill |
| --- | --- |
| Go (`go.mod`) | [`go`](../go/index.md) |
| Python (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby (`Gemfile`) | [`ruby`](../ruby/index.md) |
| Java (`pom.xml`, `build.gradle`) | Use `@sentry/java` — see [docs.sentry.io/platforms/java/](https://docs.sentry.io/platforms/java/) |
| Node.js (Express, Fastify) | Use `@sentry/node` — see [docs.sentry.io/platforms/javascript/guides/express/](https://docs.sentry.io/platforms/javascript/guides/express/) |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing | Set `debug: true`, check DSN, open browser console for SDK errors |
| Source maps not working | Build in production mode (`npm run build`); verify `SENTRY_AUTH_TOKEN` is set |
| Minified stack traces | Source maps not uploading — check plugin config and auth token |
| `instrument.ts` not running first | Verify it’s the first import in entry file before React/app imports |
| React 19 errors not captured | Confirm `reactErrorHandler()` is passed to all three `createRoot` options |
| React <19 errors not captured | Ensure `<Sentry.ErrorBoundary>` wraps the component tree |
| Router transactions named `<unknown>` | Add router integration matching your router version |
| `tracePropagationTargets` not matching | Check regex escaping; default is `localhost` and your DSN origin only |
| Session replay not recording | Confirm `replayIntegration()` is in init; check `replaysSessionSampleRate` |
| Redux actions not in breadcrumbs | Add `Sentry.createReduxEnhancer()` to store enhancers |
| Ad blockers dropping events | Set `tunnel: "/sentry-tunnel"` and add server-side relay endpoint |
| High replay storage costs | Lower `replaysSessionSampleRate`; keep `replaysOnErrorSampleRate: 1.0` |
| Profiling not working | Verify `Document-Policy: js-profiling` header is set on document responses |
