# Sentry React Router Framework SDK

Opinionated wizard that scans your React Router Framework project and guides you through
complete Sentry setup across client and server entry points.

> **Important:** This SDK is currently beta.
> For React Router non-framework/data/declarative mode (v5/v6/v7), use
> [`react`](../react/index.md) with `@sentry/react` integrations instead.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect React Router Framework indicators and versions
cat package.json | grep -E '"react-router"|"@react-router/"|"react-router-dev"|"react-router-serve"'

# Detect Sentry package choice
cat package.json | grep -E '"@sentry/react-router"|"@sentry/react"|"@sentry/profiling-node"'

# Check entry point visibility and server instrumentation files
ls entry.client.tsx entry.server.tsx instrument.server.mjs react-router.config.ts vite.config.ts 2>/dev/null

# Check if React Router files are still hidden (framework mode helper command available)
cat package.json | grep -E '"reveal"|react-router'

# Detect runtime startup scripts and import strategy
cat package.json | grep -E '"dev"|"start"|NODE_OPTIONS|--import'

# Detect optional logging/profile-related dependencies
cat package.json | grep -E '"pino"|"winston"|"@sentry/profiling-node"'

# Detect companion backend directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod ../requirements.txt ../Gemfile ../pom.xml 2>/dev/null | head -3
```

**What to determine:**

| Question | Impact |
| --- | --- |
| `@sentry/react-router` already installed? | Skip install and move to feature setup |
| Framework entry files exposed? | Need `npx react-router reveal` before manual config |
| Using `@sentry/react` instead? | This is likely non-framework routing; redirect to [`react`](../react/index.md) |
| `react-router.config.ts` + Vite config present? | Source map upload and build-end hook setup path |
| `NODE_OPTIONS --import` available? | Preferred server instrumentation startup path |
| `@sentry/profiling-node` desired/available? | Enable server profiling integration |
| Backend directory found? | Trigger Phase 4 cross-link suggestion |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Do not ask open-ended questions — lead with a proposal:

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; captures client and server errors with framework
  hooks
- ✅ **Tracing** — recommended baseline in framework apps with client/server request flow
- ✅ **Session Replay** — recommended for user-facing applications

**Optional (enhanced observability):**
- ⚡ **Profiling** — server-side profiling with `@sentry/profiling-node`
- ⚡ **Logs** — structured `Sentry.logger.*` ingestion and correlation
- ⚡ **User Feedback** — in-app feedback widget/reporting flows

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Usually yes** in framework apps; route and request timing is high-value |
| Session Replay | User-facing product or difficult UX debugging |
| Profiling | Server performance investigations needed; Node runtime compatibility verified |
| Logs | Team wants log-search and trace correlation in Sentry |
| User Feedback | Product/support teams need direct in-app issue reports |

Propose: *“I recommend Error Monitoring + Tracing + Session Replay first.
Want me to also enable Profiling, Logs, and User Feedback?”*

* * *

## Phase 3: Guide

### Option 1: Wizard (Recommended)

> **You need to run this yourself** — the wizard is interactive and may require browser
> login:
> 
> ```bash
> npx @sentry/wizard@latest -i reactRouter
> ```
> 
> It installs `@sentry/react-router`, exposes React Router entry files, creates
> instrumentation files, updates root error handling, configures source map upload, and
> adds verification examples.
> 
> **Once it finishes, continue at [Verification](#verification).**

If the user skips wizard setup, continue with manual setup below.

* * *

### Option 2: Manual Setup

#### Install packages

```bash
npm install @sentry/react-router --save
```

If profiling is needed:

```bash
npm install @sentry/profiling-node --save
```

#### Expose framework entry files

```bash
npx react-router reveal
```

#### Configure client in `entry.client.tsx`

```tsx
import * as Sentry from "@sentry/react-router";
import { startTransition, StrictMode } from "react";
import { hydrateRoot } from "react-dom/client";
import { HydratedRouter } from "react-router/dom";

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/react-router/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  integrations: [
    Sentry.reactRouterTracingIntegration(),
    Sentry.replayIntegration(),
    Sentry.feedbackIntegration({ colorScheme: "system" }),
  ],
  enableLogs: true,
  tracesSampleRate: 1.0,
  tracePropagationTargets: [/^\//, /^https:\/\/yourserver\.io\/api/],
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,
});

startTransition(() => {
  hydrateRoot(
    document,
    <StrictMode>
      <HydratedRouter onError={Sentry.sentryOnError} />
    </StrictMode>,
  );
});
```

#### Configure server in `instrument.server.mjs`

```javascript
import * as Sentry from "@sentry/react-router";
import { nodeProfilingIntegration } from "@sentry/profiling-node";

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/react-router/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
  enableLogs: true,
  integrations: [nodeProfilingIntegration()],
  tracesSampleRate: 1.0,
  profileSessionSampleRate: 1.0,
});
```

#### Wrap server handlers in `entry.server.tsx`

```tsx
import * as Sentry from "@sentry/react-router";
import { createReadableStreamFromReadable } from "@react-router/node";
import { renderToPipeableStream } from "react-dom/server";
import { ServerRouter } from "react-router";

const handleRequest = Sentry.createSentryHandleRequest({
  ServerRouter,
  renderToPipeableStream,
  createReadableStreamFromReadable,
});

export default handleRequest;

export const handleError = Sentry.createSentryHandleError({
  logErrors: false,
});
```

For custom server logic, use `wrapSentryHandleRequest`, `getMetaTagTransformer`, and
manual `Sentry.captureException` in your custom `handleError`.

#### Load server instrumentation on startup

Prefer `NODE_OPTIONS --import`:

```json
{
  "scripts": {
    "dev": "NODE_OPTIONS='--import ./instrument.server.mjs' react-router dev",
    "start": "NODE_OPTIONS='--import ./instrument.server.mjs' react-router-serve ./build/server/index.js"
  }
}
```

Fallback for platforms where runtime flags are restricted:

```tsx
import "./instrument.server.mjs";
```

This direct-import method can result in incomplete auto-instrumentation compared to
`--import`.

#### Configure source maps

`vite.config.ts`:

```typescript
import { reactRouter } from "@react-router/dev/vite";
import {
  sentryReactRouter,
  type SentryReactRouterBuildOptions,
} from "@sentry/react-router";
import { defineConfig } from "vite";

const sentryConfig: SentryReactRouterBuildOptions = {
  org: "___ORG_SLUG___",
  project: "___PROJECT_SLUG___",
  authToken: process.env.SENTRY_AUTH_TOKEN,
};

export default defineConfig((config) => {
  return {
    plugins: [reactRouter(), sentryReactRouter(sentryConfig, config)],
  };
});
```

`react-router.config.ts`:

```typescript
import type { Config } from "@react-router/dev/config";
import { sentryOnBuildEnd } from "@sentry/react-router";

export default {
  ssr: true,
  buildEnd: async ({ viteConfig, reactRouterConfig, buildManifest }) => {
    await sentryOnBuildEnd({ viteConfig, reactRouterConfig, buildManifest });
  },
} satisfies Config;
```

* * *

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file, follow steps exactly, and verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always |
| Tracing | `./tracing.md` | Route/request performance visibility needed |
| Profiling | `./profiling.md` | Server performance analysis needed |
| Session Replay | `./session-replay.md` | User-facing app |
| Logs | `./logging.md` | Structured logs/correlation needed |
| User Feedback | `./user-feedback.md` | In-app feedback flows needed |
| Framework Features | `./react-router-framework-features.md` | Entry files, wrappers, source maps, startup import strategy |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `Sentry.init()` options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `dsn` | `string` | — | Required; SDK disabled when empty |
| `dataCollection` | `object` | — | Controls what data is collected (userInfo, cookies, httpHeaders, etc.) |
| `dataCollection.userInfo` | `boolean` | `true` | Includes IP-derived user context |
| `dataCollection.cookies` | `CollectBehavior` | `true` | Controls cookie collection and filtering |
| `dataCollection.httpHeaders` | `object` | `{ request: true, response: true }` | Controls HTTP header collection |
| `sendDefaultPii` | `boolean` | `false` | **Deprecated:** Use `dataCollection` instead; removed in v11 |
| `integrations` | `Integration[]` | SDK defaults | Add tracing/replay/feedback/profiling integrations |
| `enableLogs` | `boolean` | `false` | Enables `Sentry.logger.*` ingestion |
| `tracesSampleRate` | `number` | — | Usually `1.0` in testing, lower in production |
| `tracePropagationTargets` | `(string \| RegExp)[]` | SDK defaults | URLs that receive tracing headers |
| `replaysSessionSampleRate` | `number` | — | Fraction of all sessions recorded |
| `replaysOnErrorSampleRate` | `number` | — | Fraction of error sessions recorded |
| `profileSessionSampleRate` | `number` | — | Fraction of transactions profiled (server profiling) |
| `tunnel` | `string` | — | Optional ad-blocker bypass endpoint |
| `debug` | `boolean` | `false` | Verbose SDK diagnostics |

### Framework-specific APIs

| API | Purpose |
| --- | --- |
| `reactRouterTracingIntegration()` | Client-side tracing integration for framework mode |
| `sentryOnError` | Hooks into React Router `HydratedRouter` error reporting |
| `createSentryHandleRequest(...)` | Server request wrapper for framework entry server |
| `createSentryHandleError(...)` | Server error handler wrapper |
| `wrapServerLoader(...)` / `wrapServerAction(...)` | Manual wrapping for server loaders/actions |
| `sentryReactRouter(...)` | Vite plugin for source maps/build integration |
| `sentryOnBuildEnd(...)` | React Router build-end hook for source map processing |

* * *

## Verification

### Wizard-generated path

If wizard examples were generated, open `/sentry-example-page` and trigger test actions.

### Manual error test

```tsx
export async function loader() {
  throw new Error("My first Sentry error!");
}
```

### Manual tracing test

```tsx
import * as Sentry from "@sentry/react-router";

export async function loader() {
  return Sentry.startSpan(
    { op: "test", name: "My First Test Transaction" },
    () => {
      throw new Error("My first Sentry error!");
    },
  );
}
```

### Logs test

```javascript
Sentry.logger.info("User example action completed");
Sentry.logger.warn("Slow operation detected", { operation: "data_fetch", duration: 3500 });
Sentry.logger.error("Validation failed", { field: "email", reason: "Invalid email" });
```

Confirm in Sentry:
- **Issues**: errors appear
- **Traces**: transaction/span data appears
- **Profiles**: profiles appear when profiling enabled
- **Replays**: replay entries appear when enabled
- **Logs**: log events appear when `enableLogs: true`
- **User Feedback**: submissions appear when feedback enabled

* * *

## Phase 4: Cross-Link

After completing React Router Framework setup:

1. Check whether the app is actually non-framework routing (v5/v6/v7 data/declarative
   with `@sentry/react`).
2. If yes, redirect to [`react`](../react/index.md) for non-framework routing
   integrations.

Then check companion backend coverage:

```bash
ls ../backend ../server ../api ../go ../python 2>/dev/null
cat ../go.mod ../requirements.txt ../pyproject.toml ../Gemfile ../pom.xml 2>/dev/null | head -5
```

| Backend detected | Suggest skill |
| --- | --- |
| Go | [`go`](../go/index.md) |
| Python | [`python`](../python/index.md) |
| Ruby | [`ruby`](../ruby/index.md) |
| Node backend services | [`node`](../node/index.md) |
| Java services | Use `@sentry/java` docs |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| `entry.client.tsx` / `entry.server.tsx` missing | Run `npx react-router reveal` first |
| Client errors missing | Ensure `HydratedRouter` includes `onError={Sentry.sentryOnError}` |
| Server errors missing | Use `createSentryHandleRequest` and `createSentryHandleError` wrappers |
| Custom server handlers bypass Sentry | Use `wrapSentryHandleRequest` and manual `captureException` in custom `handleError` |
| Source maps not uploaded | Verify `sentryReactRouter` plugin config and `sentryOnBuildEnd` hook |
| `SENTRY_AUTH_TOKEN` undefined in Vite config | Load env vars in config or use `.env.sentry-build-plugin` |
| Incomplete server auto-instrumentation | Prefer `NODE_OPTIONS='--import ./instrument.server.mjs'` startup |
| Profiling data missing | Confirm `@sentry/profiling-node` installed and `nodeProfilingIntegration` enabled |
| Running unsupported Node auto-instrumentation version | Use instrumentation API/manual wrappers as documented |
| Non-framework app configured with `@sentry/react-router` | Switch to [`react`](../react/index.md) + `@sentry/react` for v5/v6/v7 non-framework routes |
