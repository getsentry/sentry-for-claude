# Sentry Browser SDK

Opinionated wizard that scans your project and guides you through complete Sentry setup
for browser JavaScript — vanilla JS, jQuery, static sites, WordPress, and any JS project
without a framework-specific SDK.

> **Note:** SDK versions and APIs below reflect `@sentry/browser` ≥10.0.0. Always verify
> against
> [docs.sentry.io/platforms/javascript/](https://docs.sentry.io/platforms/javascript/)
> before implementing.

* * *

## Phase 1: Detect

**CRITICAL — Check for frameworks first.** Framework-specific SDKs provide significantly
better coverage and must be recommended before proceeding with `@sentry/browser`.

### Step 1A: Framework Detection (Redirect If Found)

```bash
# Check for React
cat package.json 2>/dev/null | grep -E '"react"'

# Check for Next.js
cat package.json 2>/dev/null | grep '"next"'

# Check for Vue
cat package.json 2>/dev/null | grep '"vue"'

# Check for Angular
cat package.json 2>/dev/null | grep '"@angular/core"'

# Check for Svelte / SvelteKit
cat package.json 2>/dev/null | grep -E '"svelte"|"@sveltejs/kit"'

# Check for Remix
cat package.json 2>/dev/null | grep -E '"@remix-run/react"|"@remix-run/node"'

# Check for Nuxt
cat package.json 2>/dev/null | grep '"nuxt"'

# Check for Astro
cat package.json 2>/dev/null | grep '"astro"'

# Check for Ember
cat package.json 2>/dev/null | grep '"ember-source"'

# Check for Node.js server frameworks (wrong SDK entirely)
cat package.json 2>/dev/null | grep -E '"express"|"fastify"|"@nestjs/core"|"koa"'
```

**If a framework is detected, stop and redirect:**

| Framework detected | Redirect to |
| --- | --- |
| `next` | Load [`nextjs`](../nextjs/index.md) skill — **do not proceed here** |
| `react` (without Next.js) | Load [`react`](../react/index.md) skill — **do not proceed here** |
| `vue` | Suggest `@sentry/vue` — see [docs.sentry.io/platforms/javascript/guides/vue/](https://docs.sentry.io/platforms/javascript/guides/vue/) |
| `@angular/core` | Suggest `@sentry/angular` — see [docs.sentry.io/platforms/javascript/guides/angular/](https://docs.sentry.io/platforms/javascript/guides/angular/) |
| `@sveltejs/kit` | Load [`svelte`](../svelte/index.md) skill — **do not proceed here** |
| `svelte` (SPA, no kit) | Suggest `@sentry/svelte` — see [docs.sentry.io/platforms/javascript/guides/svelte/](https://docs.sentry.io/platforms/javascript/guides/svelte/) |
| `@remix-run` | Suggest `@sentry/remix` — see [docs.sentry.io/platforms/javascript/guides/remix/](https://docs.sentry.io/platforms/javascript/guides/remix/) |
| `nuxt` | Suggest `@sentry/nuxt` — see [docs.sentry.io/platforms/javascript/guides/nuxt/](https://docs.sentry.io/platforms/javascript/guides/nuxt/) |
| `astro` | Suggest `@sentry/astro` — see [docs.sentry.io/platforms/javascript/guides/astro/](https://docs.sentry.io/platforms/javascript/guides/astro/) |
| `ember-source` | Suggest `@sentry/ember` — see [docs.sentry.io/platforms/javascript/guides/ember/](https://docs.sentry.io/platforms/javascript/guides/ember/) |
| `express` / `fastify` / `@nestjs/core` | This is a Node.js server — load [`node`](../node/index.md) or [`nestjs`](../nestjs/index.md) skill |

> **Why redirect matters:** Framework SDKs add router-aware transactions, error
> boundaries, component tracking, and often SSR coverage.
> Using `@sentry/browser` directly in a React or Next.js app loses all of that.

Only continue with `@sentry/browser` if **no framework is detected**.

### Step 1B: Installation Method Detection

```bash
# Check if there's a package.json at all (bundler environment)
ls package.json 2>/dev/null

# Check package manager
ls package-lock.json yarn.lock pnpm-lock.yaml bun.lockb 2>/dev/null

# Check build tool
ls vite.config.ts vite.config.js webpack.config.js rollup.config.js esbuild.config.js 2>/dev/null
cat package.json 2>/dev/null | grep -E '"vite"|"webpack"|"rollup"|"esbuild"'

# Check for CMS or static site indicators
ls wp-config.php wp-content/ 2>/dev/null   # WordPress
ls _config.yml _config.yaml 2>/dev/null    # Jekyll
ls config.toml 2>/dev/null                 # Hugo
ls .eleventy.js 2>/dev/null                # Eleventy

# Check for existing Sentry
cat package.json 2>/dev/null | grep '"@sentry/'
grep -r "sentry-cdn.com\|js.sentry-cdn.com" . --include="*.html" -l 2>/dev/null | head -3
```

**What to determine:**

| Question | Impact |
| --- | --- |
| `package.json` exists + bundler? | → **Path A: npm install** |
| WordPress, Shopify, static HTML, no npm? | → **Path B: Loader Script** |
| Script tags only, no Loader Script access? | → **Path C: CDN bundle** |
| Already has `@sentry/browser`? | Skip install, go straight to feature config |
| Build tool is Vite / webpack / Rollup / esbuild? | Source maps plugin to configure |

* * *

## Phase 2: Recommend

Present a recommendation based on what you found.
Lead with a concrete proposal, don’t ask open-ended questions.

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; captures unhandled errors and promise rejections
- ✅ **Tracing** — recommended for any interactive site; tracks page load and user
  interactions
- ✅ **Session Replay** — recommended for user-facing apps; records sessions around
  errors

**Optional (enhanced observability):**
- ⚡ **User Feedback** — capture reports directly from users after errors
- ⚡ **Logging** — structured logs via `Sentry.logger.*`; requires npm or CDN logs bundle
  (not available via Loader Script)
- ⚡ **Profiling** — JS Self-Profiling API; beta, Chromium-only, requires
  `Document-Policy: js-profiling` response header

**Feature recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Always** for interactive pages — page load + navigation spans are high-value |
| Session Replay | User-facing app, support flows, or checkout pages |
| User Feedback | Support-focused app; want in-app bug reports with screenshots |
| Logging | Structured log search or log-to-trace correlation needed; **npm path only** |
| Profiling | Performance-critical, Chromium-only app; `Document-Policy: js-profiling` header required |

**Installation path recommendation:**

| Scenario | Recommended path |
| --- | --- |
| Project has `package.json` + bundler | **Path A (npm)** — full features, source maps, tree-shaking |
| WordPress, Shopify, Squarespace, static HTML | **Path B (Loader Script)** — zero build tooling, always up to date |
| Static HTML without Loader Script access | **Path C (CDN bundle)** — manual `<script>` tag |

Propose: *“I recommend setting up Error Monitoring + Tracing + Session Replay using Path
A (npm). Want me to also add Logging or User Feedback?”*

* * *

## Phase 3: Guide

### Path A: npm / yarn / pnpm (Recommended — Bundler Projects)

#### Install

```bash
npm install @sentry/browser --save
# or
yarn add @sentry/browser
# or
pnpm add @sentry/browser
```

#### Create `src/instrument.ts`

Sentry must initialize **before any other code runs**. Put `Sentry.init()` in a
dedicated sidecar file:

```typescript
import * as Sentry from "@sentry/browser";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN, // Adjust per build tool (see table below)
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_APP_VERSION, // inject at build time

  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/configuration/options/#dataCollection
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
| Custom webpack | `SENTRY_DSN` | `process.env.SENTRY_DSN` |
| esbuild | `SENTRY_DSN` | `process.env.SENTRY_DSN` |
| Rollup | `SENTRY_DSN` | `process.env.SENTRY_DSN` |

#### Entry Point Setup

Import `instrument.ts` as the **very first import** in your entry file:

```typescript
// src/main.ts or src/index.ts
import "./instrument";  // ← MUST be first

// ... rest of your app
```

#### Source Maps Setup (Strongly Recommended)

Without source maps, stack traces show minified code.
Set up the build plugin to upload source maps automatically:

> **No dedicated browser wizard:** There is no `npx @sentry/wizard -i browser` flag.
> The closest is `npx @sentry/wizard@latest -i sourcemaps` which configures source map
> upload only for an already-initialized SDK.

**Vite (`vite.config.ts`):**

```typescript
import { defineConfig } from "vite";
import { sentryVitePlugin } from "@sentry/vite-plugin";

export default defineConfig({
  build: { sourcemap: "hidden" },
  plugins: [
    // sentryVitePlugin MUST be last
    sentryVitePlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
  ],
});
```

**webpack (`webpack.config.js`):**

```javascript
const { sentryWebpackPlugin } = require("@sentry/webpack-plugin");

module.exports = {
  devtool: "hidden-source-map",
  plugins: [
    sentryWebpackPlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
  ],
};
```

**Rollup (`rollup.config.js`):**

```javascript
import { sentryRollupPlugin } from "@sentry/rollup-plugin";

export default {
  output: { sourcemap: "hidden" },
  plugins: [
    sentryRollupPlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
  ],
};
```

**esbuild (`build.js`):**

```javascript
const { sentryEsbuildPlugin } = require("@sentry/esbuild-plugin");

require("esbuild").build({
  entryPoints: ["src/index.ts"],
  bundle: true,
  sourcemap: "hidden",
  plugins: [
    sentryEsbuildPlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
    }),
  ],
});
```

> ⚠️ esbuild plugin does **not** fully support `splitting: true`. Use `sentry-cli`
> instead if code splitting is enabled.

**Using `sentry-cli` (any toolchain / CI):**

```bash
# After your build step:
npx @sentry/cli sourcemaps inject ./dist
npx @sentry/cli sourcemaps upload ./dist
```

Add `.env` for auth (never commit):
```bash
SENTRY_AUTH_TOKEN=sntrys_...
SENTRY_ORG=my-org-slug
SENTRY_PROJECT=my-project-slug
```

* * *

### Path B: Loader Script (WordPress, Static Sites, Shopify, Squarespace)

**Best for:** Sites without a build system.
The Loader Script is a single `<script>` tag that lazily loads the full SDK, always
stays up to date via Sentry’s CDN, and buffers errors before the SDK loads.

**Get the Loader Script:** Sentry UI → **Settings → Projects → (your project) → SDK
Setup → Loader Script**

Copy the generated tag and place it as the **first script on every page**:

```html
<!DOCTYPE html>
<html>
  <head>
    <!-- Configure BEFORE the loader tag -->
    <script>
      window.sentryOnLoad = function () {
        Sentry.init({
          // DSN is already configured in the loader URL
          tracesSampleRate: 1.0,
          replaysSessionSampleRate: 0.1,
          replaysOnErrorSampleRate: 1.0,
        });
      };
    </script>

    <!-- Loader Script FIRST — before all other scripts -->
    <script
      src="https://js.sentry-cdn.com/YOUR_PUBLIC_KEY.min.js"
      crossorigin="anonymous"
    ></script>
  </head>
  ...
</html>
```

**Loader loading modes:**

| Mode | How | When SDK loads |
| --- | --- | --- |
| **Lazy (default)** | Nothing extra | On first error or manual Sentry call |
| **Eager** | Add `data-lazy="no"` to `<script>` | After all page scripts finish |
| **Manual** | Call `Sentry.forceLoad()` | Whenever you call it |

**Safe to call before SDK loads (buffered):**
- `Sentry.captureException()`
- `Sentry.captureMessage()`
- `Sentry.captureEvent()`
- `Sentry.addBreadcrumb()`
- `Sentry.withScope()`

**For other methods, use `Sentry.onLoad()`:**
```html
<script>
  window.Sentry && Sentry.onLoad(function () {
    Sentry.setUser({ id: "123" });
  });
</script>
```

**Set release via global (optional):**
```html
<script>
  window.SENTRY_RELEASE = { id: "my-app@1.0.0" };
</script>
```

**Loader Script limitations:**
- ❌ No `Sentry.logger.*` (logging) — npm path only
- ❌ No framework-specific features (React ErrorBoundary, Vue Router tracking, etc.)
- ❌ Tracing headers only added to fetch calls made after SDK loads
- ❌ Version changes take a few minutes to propagate via CDN cache
- ⚠️ Use `defer` (not `async`) on all other scripts when using the loader

**CSP requirements:**
```
script-src: https://browser.sentry-cdn.com https://js.sentry-cdn.com
connect-src: *.sentry.io
```

* * *

### Path C: CDN Bundles (Manual Script Tags)

**Best for:** Pages that can’t use the Loader Script but need synchronous loading.

Pick the bundle that matches your feature needs and place it **before all other
scripts**:

**Errors only (minimal footprint):**
```html
<script
  src="https://browser.sentry-cdn.com/10.42.0/bundle.min.js"
  integrity="sha384-L/HYBH2QCeLyXhcZ0hPTxWMnyMJburPJyVoBmRk4OoilqrOWq5kU4PNTLFYrCYPr"
  crossorigin="anonymous"
></script>
```

**Errors + Tracing:**
```html
<script
  src="https://browser.sentry-cdn.com/10.42.0/bundle.tracing.min.js"
  integrity="sha384-DIqcfVcfIewrWiNWfVZcGWExO5v673hkkC5ixJnmAprAfJajpUDEAL35QgkOB5gw"
  crossorigin="anonymous"
></script>
```

**Errors + Session Replay:**
```html
<script
  src="https://browser.sentry-cdn.com/10.42.0/bundle.replay.min.js"
  integrity="sha384-sbojwIJFpv9duIzsI9FRm87g7pB15s4QwJS1m1xMSOdV1CF3pwgrPPEu38Em7M9+"
  crossorigin="anonymous"
></script>
```

**Errors + Tracing + Replay (recommended full setup):**
```html
<script
  src="https://browser.sentry-cdn.com/10.42.0/bundle.tracing.replay.min.js"
  integrity="sha384-oo2U4zsTxaHSPXJEnXtaQPeS4Z/qbTqoBL9xFgGxvjJHKQjIrB+VRlu97/iXBtzw"
  crossorigin="anonymous"
></script>
```

**Errors + Tracing + Replay + User Feedback:**
```html
<script
  src="https://browser.sentry-cdn.com/10.42.0/bundle.tracing.replay.feedback.min.js"
  integrity="sha384-SmHU39Qs9cua0KLtq3A6gis1/cqM1nZ6fnGzlvWAPiwhBDO5SmwFQV65BBpJnB3n"
  crossorigin="anonymous"
></script>
```

**Full bundle (all features):**
```html
<script
  src="https://browser.sentry-cdn.com/10.42.0/bundle.tracing.replay.feedback.logs.metrics.min.js"
  integrity="sha384-gOjSzRxwpXpy0FlT6lg/AVhagqrsUrOWUO7jm6TJwuZ9YVHtYK0MBA2hW2FGrIGl"
  crossorigin="anonymous"
></script>
```

**CDN bundle variants summary:**

| Bundle | Features | When to use |
| --- | --- | --- |
| `bundle.min.js` | Errors only | Absolute minimum footprint |
| `bundle.tracing.min.js` | + Tracing | Performance monitoring |
| `bundle.replay.min.js` | + Replay | Session recording |
| `bundle.tracing.replay.min.js` | + Tracing + Replay | Full observability |
| `bundle.tracing.replay.feedback.min.js` | + User Feedback | + in-app feedback widget |
| `bundle.logs.metrics.min.js` | + Logs + Metrics | Structured logs (CDN) |
| `bundle.tracing.replay.feedback.logs.metrics.min.js` | Everything | Max coverage |

**Initialize after the script tag:**
```html
<script>
  Sentry.init({
    dsn: "https://YOUR_KEY@o0.ingest.sentry.io/YOUR_PROJECT",
    environment: "production",
    release: "my-app@1.0.0",
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
  });
</script>
```

**CDN CSP requirements:**
```
script-src: https://browser.sentry-cdn.com https://js.sentry-cdn.com
connect-src: *.sentry.io
```

* * *

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file, follow its steps, verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing | `./tracing.md` | Page load / API call tracing |
| Session Replay | `./session-replay.md` | User-facing app |
| Logging | `./logging.md` | Structured log search; npm or CDN logs bundle (not Loader Script) |
| Profiling | `./profiling.md` | Performance-critical, Chromium-only |
| User Feedback | `./user-feedback.md` | Capture user reports after errors |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `Sentry.init()` Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `dsn` | `string` | — | **Required.** SDK disabled when empty |
| `environment` | `string` | `"production"` | e.g., `"staging"`, `"development"` |
| `release` | `string` | — | e.g., `"my-app@1.0.0"` or git SHA — links errors to releases |
| `sendDefaultPii` | `boolean` | `false` | Includes IP addresses and request headers. **Will be deprecated in v11** — use `dataCollection` instead |
| `dataCollection` | `object` | — | Fine-grained control over collected data (v10.54+). See table below |
| `tracesSampleRate` | `number` | — | 0–1; `1.0` in dev, `0.1–0.2` in prod |
| `tracesSampler` | `function` | — | Per-transaction sampling; overrides rate |
| `tracePropagationTargets` | `(string\|RegExp)[]` | same-origin | Outgoing URLs that receive distributed tracing headers |
| `replaysSessionSampleRate` | `number` | — | Fraction of all sessions recorded |
| `replaysOnErrorSampleRate` | `number` | — | Fraction of error sessions recorded |
| `enableLogs` | `boolean` | `false` | Enable `Sentry.logger.*` API (npm or CDN logs bundle; not Loader Script) |
| `attachStackTrace` | `boolean` | `false` | Stack traces on `captureMessage()` calls |
| `maxBreadcrumbs` | `number` | `100` | Breadcrumbs stored per event |
| `debug` | `boolean` | `false` | Verbose SDK output to console |
| `tunnel` | `string` | — | Proxy URL to bypass ad blockers |
| `ignoreErrors` | `(string\|RegExp)[]` | `[]` | Drop errors matching these patterns |
| `denyUrls` | `(string\|RegExp)[]` | `[]` | Drop errors from scripts at these URLs |
| `allowUrls` | `(string\|RegExp)[]` | `[]` | Only capture errors from these script URLs |
| `spotlight` | `boolean\|string` | `false` | Forward events to Spotlight local dev overlay |

### Browser-Specific Options

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `cdnBaseUrl` | `string` | — | Base URL for lazy-loading integrations |
| `skipBrowserExtensionCheck` | `boolean` | `false` | Skip check for browser extension context |

### `dataCollection` Option (v10.54+)

Fine-grained control over what data the SDK collects.
Replaces the simple `sendDefaultPii` boolean with granular settings.
When omitted, falls back to `sendDefaultPii` for backwards compatibility.

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `userInfo` | `boolean` | `true` | Auto-populate `user.*` fields from instrumentation |
| `cookies` | `boolean \| { allow: string[] } \| { deny: string[] }` | `true` | Cookie collection; `true` = all (filtered), `false` = none, `allow`/`deny` = specific keys |
| `httpHeaders` | `{ request?, response? }` | `{ request: true, response: true }` | HTTP header collection; each can be `boolean` or `allow`/`deny` object |
| `httpBodies` | `string[]` | `["incomingRequest", "outgoingRequest", "incomingResponse", "outgoingResponse"]` | HTTP body types to collect (when `dataCollection` is explicitly set) |
| `queryParams` | `boolean \| { allow: string[] } \| { deny: string[] }` | `true` | Query parameter collection with sensitive value filtering |
| `genAI` | `{ inputs?, outputs? }` | `{ inputs: true, outputs: true }` | Generative AI input/output recording |
| `stackFrameVariables` | `boolean` | `true` | Capture local variable values in stack frames |
| `frameContextLines` | `number` | `5` | Source code context lines around stack frames |

**Example:**
```typescript
Sentry.init({
  dsn: "...",
  dataCollection: {
    userInfo: true,
    cookies: { deny: ["session_id", "auth_token"] },
    httpHeaders: {
      request: { deny: ["authorization", "cookie"] },
      response: true,
    },
    queryParams: { allow: ["utm_source", "utm_campaign"] },
  },
});
```

### `window.SENTRY_RELEASE` Global (CDN / Loader Path)

Set the release version before the SDK loads:
```html
<script>
  window.SENTRY_RELEASE = { id: "my-app@1.0.0" };
</script>
```

* * *

## Verification

Trigger test events to confirm Sentry is receiving data:

**npm / CDN path:**
```html
<!-- Add temporarily to your page -->
<button onclick="throw new Error('Sentry Browser Test Error')">
  Test Error
</button>
```

**Performance verification (npm path):**
```javascript
import * as Sentry from "@sentry/browser";

Sentry.startSpan({ name: "Test Span", op: "test" }, () => {
  // your operation
});
```

**Manual capture:**
```javascript
Sentry.captureException(new Error("Manual test"));
Sentry.captureMessage("Manual test message", "info");
```

Check the Sentry dashboard:
- **Issues** → error appears within seconds
- **Traces** → page load transaction visible
- **Replays** → session recording visible after page interaction
- **Logs** → structured log entries if logging enabled (npm or CDN logs bundle)

Set `debug: true` in `Sentry.init()` and check the browser console if nothing appears.

* * *

## Phase 4: Cross-Link

After completing browser setup, check for a companion backend missing Sentry coverage:

```bash
ls ../backend ../server ../api ../go ../python 2>/dev/null
cat ../go.mod 2>/dev/null | head -3
cat ../requirements.txt ../pyproject.toml 2>/dev/null | head -3
cat ../Gemfile 2>/dev/null | head -3
cat ../pom.xml 2>/dev/null | grep '<artifactId>' | head -3
cat ../composer.json 2>/dev/null | head -3
```

If a backend exists without Sentry configured, suggest the matching skill:

| Backend detected | Suggest skill |
| --- | --- |
| Go (`go.mod`) | [`go`](../go/index.md) |
| Python (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby (`Gemfile`) | [`ruby`](../ruby/index.md) |
| PHP (`composer.json`) | [`php`](../php/index.md) |
| .NET (`*.csproj`, `*.sln`) | [`dotnet`](../dotnet/index.md) |
| Java (`pom.xml`, `build.gradle`) | See [docs.sentry.io/platforms/java/](https://docs.sentry.io/platforms/java/) |
| Node.js (Express, Fastify) | [`node`](../node/index.md) |
| NestJS (`@nestjs/core`) | [`nestjs`](../nestjs/index.md) |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing | Set `debug: true`, check DSN, open browser console for SDK errors |
| Source maps not working | Build in production mode (`npm run build`); verify `SENTRY_AUTH_TOKEN` is set |
| Minified stack traces | Source maps not uploading — check build plugin config; run `npx @sentry/wizard@latest -i sourcemaps` |
| CDN bundle not found | Check version number in URL; see [browser.sentry-cdn.com](https://browser.sentry-cdn.com/) for latest |
| SRI integrity error | Hash mismatch — re-copy the full `<script>` tag including `integrity` attribute from this skill |
| Loader Script not firing | Verify it’s the **first** `<script>` on the page; check for CSP errors in console |
| Tracing not working with Loader | Fetch calls before SDK loads won’t be traced — wrap early calls in `Sentry.onLoad()` |
| `sentryOnLoad` not called | Must define `window.sentryOnLoad` **before** the loader `<script>` tag |
| Logging not available | `Sentry.logger.*` requires npm or a CDN bundle with `.logs.` in its name — not supported via Loader Script |
| Profiling not working | Verify `Document-Policy: js-profiling` header on document responses; Chromium-only |
| Ad blockers dropping events | Set `tunnel: "/sentry-tunnel"` and add a server-side relay endpoint |
| Session replay not recording | Confirm `replayIntegration()` is in init; check `replaysSessionSampleRate` > 0 |
| Replay CSP errors | Add `worker-src 'self' blob:` and `child-src 'self' blob:` to your CSP |
| `tracePropagationTargets` not matching | Check regex escaping; default is same-origin only |
| Events blocked by browser extension | Add `denyUrls: [/chrome-extension:\/\//]` to filter extension errors |
| High event volume | Lower `sampleRate` (errors) and `tracesSampleRate` from `1.0` in production |
| Source maps uploaded after deploy | Source maps must be uploaded **before** errors occur — integrate into CI/CD |
| esbuild splitting conflict | `sentryEsbuildPlugin` doesn’t support `splitting: true` — use `sentry-cli` instead |
