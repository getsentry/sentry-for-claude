# React-Specific Features — Sentry React SDK

> Minimum SDK: `@sentry/react` v8.0.0+

This is the catch-all deep dive for React-specific Sentry features: Redux integration,
component tracking, source maps, and the full integrations catalog.

* * *

## Table of Contents

1. [Redux Integration](#1-redux-integration)
2. [Component Tracking & Performance](#2-component-tracking--performance)
3. [Source Maps](#3-source-maps)
4. [Default Integrations](#4-default-integrations)
5. [Optional Integrations](#5-optional-integrations)
6. [Build Tool Detection & Environment Variables](#6-build-tool-detection--environment-variables)

* * *

## 1. Redux Integration

`Sentry.createReduxEnhancer()` hooks into your Redux store to automatically:

- Capture **Redux actions as breadcrumbs** on every Sentry error event
- Attach the **Redux state as a `redux_state.json` file** to error events
- Keep **Sentry scope tags in sync** with your Redux state

### Setup — Redux Toolkit (`configureStore`)

```typescript
import * as Sentry from "@sentry/react";
import { configureStore } from "@reduxjs/toolkit";
import rootReducer from "./reducers";

const sentryReduxEnhancer = Sentry.createReduxEnhancer({
  // options — see below
});

const store = configureStore({
  reducer: rootReducer,
  enhancers: (getDefaultEnhancers) => {
    return getDefaultEnhancers().concat(sentryReduxEnhancer);
  },
});

export type RootState = ReturnType<typeof store.getState>;
export type AppDispatch = typeof store.dispatch;
export default store;
```

> ⚠️ **Critical:** `sentryReduxEnhancer` is a **store enhancer**, not Redux middleware.
> Do **NOT** pass it inside `applyMiddleware()`.

### Setup — Legacy `createStore` with Middleware

```javascript
import { createStore, applyMiddleware, compose } from "redux";
import thunk from "redux-thunk";
import * as Sentry from "@sentry/react";

const sentryReduxEnhancer = Sentry.createReduxEnhancer();

const store = createStore(
  rootReducer,
  compose(applyMiddleware(thunk), sentryReduxEnhancer),
);
```

* * *

### Options: `actionTransformer` — Filter/Scrub Actions Before Breadcrumbs

Called for every dispatched action.
Return the action to include it as a breadcrumb, a modified copy to scrub sensitive
fields, or `null` to drop it entirely.

```typescript
const sentryReduxEnhancer = Sentry.createReduxEnhancer({
  actionTransformer: (action) => {
    // Drop high-volume or sensitive actions entirely
    if (action.type === "WEBSOCKET_PING") return null;
    if (action.type === "FETCH_SECRETS") return null;

    // Scrub sensitive fields from certain actions
    if (action.type === "USER_LOGIN") {
      return {
        ...action,
        password: "[REDACTED]",
        token: "[REDACTED]",
      };
    }

    if (action.type === "UPDATE_PAYMENT") {
      return {
        ...action,
        payload: {
          ...action.payload,
          cardNumber: null,
          cvv: null,
        },
      };
    }

    // Include all other actions as-is
    return action;
  },
});
```

* * *

### Options: `stateTransformer` — Filter/Scrub State Snapshots

Called on every state update.
Return the state to attach it to error events, a modified copy with sensitive fields
redacted, or `null` to exclude state entirely.

```typescript
const sentryReduxEnhancer = Sentry.createReduxEnhancer({
  stateTransformer: (state: RootState) => {
    // Return null to send NO state with errors (reduces context but protects PII)
    // if (state.topSecret.active) return null;

    // Return a scrubbed copy
    return {
      ...state,
      auth: {
        ...state.auth,
        token: null,        // remove auth token
        refreshToken: null,
        password: null,
      },
      user: {
        ...state.user,
        ssn: "[REDACTED]",
        creditCard: null,
        dateOfBirth: null,
      },
      // Remove entire subtrees you don't need
      cache: null,
      rawApiResponses: null,
    };
  },
});
```

> ⚠️ **Warning:** If `stateTransformer` returns `null`, error events will lack Redux
> state context. Debugging large state-dependent bugs becomes much harder.
> Prefer returning a filtered copy over returning `null`.

* * *

### Options: `configureScopeWithState` — Derive Sentry Tags from Redux State

Called after every state update.
Use it to keep Sentry scope tags/context in sync with your application’s Redux state —
these tags then appear on every error captured after the update.

```typescript
const sentryReduxEnhancer = Sentry.createReduxEnhancer({
  configureScopeWithState: (scope: Sentry.Scope, state: RootState) => {
    // Tag events with current user plan (great for filtering errors by customer tier)
    scope.setTag("user.plan", state.user.plan);
    scope.setTag("user.id", state.user.id);

    // Tag with durable app settings (not Sentry feature-flag tracking —
    // boolean flag evaluations belong in feature-flags.md)
    scope.setTag("settings.darkMode", String(state.settings.darkMode));
    scope.setTag("settings.locale", state.settings.locale);

    // Tag with routing/navigation state
    scope.setTag("app.currentFlow", state.navigation.currentFlow);

    // Conditional tags based on state shape
    if (state.settings.useImperialUnits) {
      scope.setTag("user.usesImperialUnits", "true");
    }

    // Set structured context (not searchable but visible in issue detail)
    scope.setContext("cart", {
      itemCount: state.cart.items.length,
      total: state.cart.total,
      coupon: state.cart.couponCode ?? null,
    });
  },
});
```

* * *

### Options: `attachReduxState` — Control State File Attachment

Controls whether the Redux state (post-`stateTransformer`) is attached as a
`redux_state.json` file on error events.

- **Type:** `boolean`
- **Default:** `true`
- **Min SDK:** `7.69.0`

```typescript
const sentryReduxEnhancer = Sentry.createReduxEnhancer({
  attachReduxState: false, // Don't attach state file — reduces payload size
});
```

* * *

### Options: `normalizeDepth` — Control State Serialization Depth

Set in `Sentry.init()`, not in `createReduxEnhancer()`. Increases the depth at which
Redux state trees are serialized.
The default of `3` is too shallow for most Redux state shapes.

```typescript
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  normalizeDepth: 10, // Default is 3 — increase for deeply nested Redux state
});
```

* * *

### All Options Summary

| Option | Type | Default | Location | Description |
| --- | --- | --- | --- | --- |
| `actionTransformer` | `(action: Action) => Action \| null` | — | `createReduxEnhancer()` | Modify or drop action breadcrumbs |
| `stateTransformer` | `(state: State) => State \| null` | — | `createReduxEnhancer()` | Modify or drop state attached to events |
| `configureScopeWithState` | `(scope: Scope, state: State) => void` | — | `createReduxEnhancer()` | Sync Sentry scope tags/context with Redux state |
| `attachReduxState` | `boolean` | `true` | `createReduxEnhancer()` | Attach state as `redux_state.json` file on errors |
| `normalizeDepth` | `number` | `3` | `Sentry.init()` | Max depth when serializing nested state |

* * *

### Complete Working Example with `@reduxjs/toolkit`

```typescript
// store/sentry.ts
import * as Sentry from "@sentry/react";
import type { RootState } from "./types";

export const sentryReduxEnhancer = Sentry.createReduxEnhancer({
  actionTransformer: (action) => {
    // Drop noisy/sensitive action types
    const DROP_TYPES = new Set([
      "SET_AUTH_TOKEN",
      "REFRESH_TOKEN",
      "WEBSOCKET_HEARTBEAT",
      "UPDATE_CURSOR_POSITION",
    ]);
    if (DROP_TYPES.has(action.type)) return null;

    // Scrub passwords from login actions
    if (action.type === "auth/login/pending") {
      return { ...action, meta: { ...action.meta, arg: { email: action.meta?.arg?.email, password: "[REDACTED]" } } };
    }

    return action;
  },

  stateTransformer: (state: RootState) => ({
    ...state,
    auth: { isAuthenticated: state.auth.isAuthenticated, userId: state.auth.userId },
    // Strip large or sensitive subtrees
    rawData: null,
  }),

  configureScopeWithState: (scope, state: RootState) => {
    scope.setTag("user.plan", state.user.plan ?? "unknown");
    scope.setTag("user.id", state.auth.userId ?? "anonymous");
    scope.setTag("org.id", state.org.id ?? "none");
  },
});

// store/index.ts
import { configureStore } from "@reduxjs/toolkit";
import { sentryReduxEnhancer } from "./sentry";
import rootReducer from "./reducers";

export const store = configureStore({
  reducer: rootReducer,
  enhancers: (getDefaultEnhancers) =>
    getDefaultEnhancers().concat(sentryReduxEnhancer),
});
```

```typescript
// instrument.ts — init with normalizeDepth
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  normalizeDepth: 10, // Required for deeply nested Redux state
  integrations: [Sentry.browserTracingIntegration()],
  tracesSampleRate: 1.0,
});
```

### Performance Considerations

Redux state can be very large.
Keep in mind:

1. **State size:** Large state trees (thousands of items) will slow serialization and
   increase payload size.
   Use `stateTransformer` to return only the relevant slices.
2. **`normalizeDepth`:** Keep it as low as practical.
   `10` is usually sufficient for deeply nested state; avoid setting it to `Infinity`.
3. **`attachReduxState: false`:** For high-traffic production apps where payload size is
   a concern, disabling state attachment reduces each error event’s size.
4. **`configureScopeWithState` cost:** This runs on every Redux dispatch.
   Keep the function fast — avoid heavy computations or deep object traversals.

* * *

## 2. Component Tracking & Performance

### A. React Component Name Annotation (Build-Time)

Replaces opaque CSS selectors in breadcrumbs, Session Replay, and performance spans with
readable React component names.

**Before:** `button.en302zp1.app-191aavw.e16hd6vm2[role="button"]`\
**After:** `CheckoutButton`

**Requirements:**
- SDK v7.91.0+
- Components must be in `.jsx` or `.tsx` files (`.js` and `.ts` are **not** annotated)
- esbuild is **not** supported

The bundler plugins inject `data-sentry-component` and `data-sentry-source-file`
attributes at build time:

```html
<!-- Resulting DOM -->
<button
  data-sentry-component="CheckoutButton"
  data-sentry-source-file="CheckoutButton.tsx"
>
  Checkout
</button>
```

**Enable via Vite (recommended):**

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { sentryVitePlugin } from "@sentry/vite-plugin";

export default defineConfig({
  plugins: [
    react(),
    sentryVitePlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
      reactComponentAnnotation: {
        enabled: true,
        // Exclude components that cause "Passing unknown props on Fragment" errors
        ignoredComponents: ["AnimationWrapper", "LayoutFragment"],
      },
    }),
  ],
  build: {
    sourcemap: "hidden",
  },
});
```

**Enable via Babel plugin directly (without bundler plugin):**

```bash
npm install @sentry/babel-plugin-component-annotate --save-dev
```

```javascript
// babel.config.js
module.exports = {
  plugins: ["@sentry/babel-plugin-component-annotate"],
};
```

**Bundler support:**

| Bundler | Component Annotation |
| --- | --- |
| Vite | ✅ Supported |
| Webpack | ✅ Supported |
| Rollup | ✅ Supported |
| esbuild | ❌ Not supported |

**What you gain:**

| Where | Before | After |
| --- | --- | --- |
| Breadcrumbs | `div.sc-abc123` | `ProductCard` |
| Session Replay | Unreadable selector | Search by `ProductCard` |
| Performance spans | Generic element | `CheckoutButton` render |

* * *

### B. `Sentry.withProfiler()` — React Profiler HOC

`withProfiler` wraps a component with the
[React Profiler API](https://react.dev/reference/react/Profiler) to capture render
timing as Sentry performance spans.

```typescript
import * as Sentry from "@sentry/react";

// Basic — display name inferred from component.displayName or .name
const ProfiledDashboard = Sentry.withProfiler(Dashboard);

// With explicit name (required for anonymous or arrow-function components)
const ProfiledWidget = Sentry.withProfiler(
  ({ data }) => <div>{data.title}</div>,
  { name: "DataWidget" }
);

// Class component decorator syntax
@Sentry.withProfiler
class ExpensiveList extends React.Component {
  render() {
    return <ul>{this.props.items.map(renderItem)}</ul>;
  }
}
```

**Options:**

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | `string` | Component `displayName` or `name` | Display name shown in Sentry traces |
| `includeRender` | `boolean` | `true` | Track initial render phase |
| `includeUpdates` | `boolean` | `true` | Track re-render / update phases |

**What it captures:**
- Mount time (initial render duration)
- Update/re-render time per update
- Number of re-renders
- Component name in the Sentry performance trace waterfall

**Data appears in:** Sentry → Performance → Trace View, as child spans of the current
transaction.

> **Requires tracing:** `browserTracingIntegration` must be in your `Sentry.init`
> integrations.

**When to use (and when not to):**

✅ Use on:
- Root-level route components (Dashboard, CheckoutFlow, UserProfile)
- Components with expensive render logic (large lists, complex calculations)
- Components that re-render frequently and may cause jank

❌ Do **not** use on:
- Every component in the tree — the overhead compounds
- Simple presentational/leaf components
- Components that render hundreds of times per second (e.g., animation frames)

**Performance overhead:** Each profiled component adds a small constant overhead per
render cycle.
Profile the 5–10 most performance-critical components, not the entire tree.

* * *

## 3. Source Maps

Source maps translate minified production stack traces back to your original source
code. Without them, stack traces show obfuscated variable names and collapsed line
numbers.

### Recommended: Sentry Wizard

The fastest path — automatically detects your bundler, installs the plugin, and
configures auth:

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```
> npx @sentry/wizard@latest -i sourcemaps
> ```
> 
> It detects Vite/webpack/CRA, installs the appropriate Sentry bundler plugin, adds
> `SENTRY_AUTH_TOKEN` to `.env.sentry-build-plugin`, and configures
> `sourcemap: "hidden"` with `filesToDeleteAfterUpload`.
> 
> **Once it finishes, come back and the agent will continue.**

If the user skips the wizard, proceed with manual bundler plugin setup below.

* * *

### How Debug IDs Work

Modern Sentry source map matching uses **Debug IDs** — unique identifiers injected by
the bundler plugin into both the compiled `.js` bundle and the corresponding `.js.map`
file. This makes source map matching reliable without needing to manage file names or
release artifacts manually.

**Flow:**
1. Production build runs → bundler plugin injects a Debug ID into each `.js` and
   `.js.map` file
2. Plugin uploads `.js.map` files to Sentry with their Debug IDs
3. Error occurs in production → stack frame contains the Debug ID
4. Sentry uses the Debug ID to locate the exact source map → deobfuscates the trace

Debug IDs are more reliable than release-based matching (older approach) because they
don’t depend on consistent release naming or artifact upload timing.

* * *

### Vite Plugin

**Minimum SDK:** `@sentry/vite-plugin` `2.0.0` / `@sentry/react` `7.47.0`

```bash
npm install @sentry/vite-plugin --save-dev
```

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { sentryVitePlugin } from "@sentry/vite-plugin";

export default defineConfig({
  build: {
    // "hidden" generates source maps but strips the `//# sourceMappingURL=` comment
    // from bundles, so browsers won't load them — they're only for Sentry.
    sourcemap: "hidden",
  },
  plugins: [
    react(),
    // sentryVitePlugin MUST come after all other plugins
    sentryVitePlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,

      // Enable React component name annotation at the same time
      reactComponentAnnotation: {
        enabled: true,
      },

      sourcemaps: {
        // Delete .map files from dist/ after uploading to Sentry
        // so they're not deployed to your CDN/server
        filesToDeleteAfterUpload: [
          "./**/*.map",
          ".*/**/public/**/*.map",
          "./dist/**/client/**/*.map",
        ],
      },
    }),
  ],
});
```

> ⚠️ Place `sentryVitePlugin` **after** all other plugins (especially
> `@vitejs/plugin-react`) to ensure correct source map generation.

* * *

### Webpack Plugin

**Minimum SDK:** `@sentry/webpack-plugin` `2.0.0` / `@sentry/react` `7.47.0`

```bash
npm install @sentry/webpack-plugin --save-dev
```

```javascript
// webpack.config.js
const { sentryWebpackPlugin } = require("@sentry/webpack-plugin");

module.exports = {
  // "hidden-source-map" generates source maps without the `//# sourceMappingURL=`
  // reference comment, so they won't be served publicly.
  devtool: "hidden-source-map",

  plugins: [
    sentryWebpackPlugin({
      org: process.env.SENTRY_ORG,
      project: process.env.SENTRY_PROJECT,
      authToken: process.env.SENTRY_AUTH_TOKEN,
      sourcemaps: {
        filesToDeleteAfterUpload: [
          "./**/*.map",
          "./build/static/**/*.map",
        ],
      },
    }),
  ],
};
```

* * *

### Create React App

CRA has limited configuration access.
Two approaches:

**Option A: CRACO (recommended — no ejection)**

```bash
npm install @craco/craco @sentry/webpack-plugin --save-dev
```

```javascript
// craco.config.js
const { sentryWebpackPlugin } = require("@sentry/webpack-plugin");

module.exports = {
  webpack: {
    configure: (webpackConfig) => {
      webpackConfig.devtool = "hidden-source-map";
      webpackConfig.plugins.push(
        sentryWebpackPlugin({
          org: process.env.SENTRY_ORG,
          project: process.env.SENTRY_PROJECT,
          authToken: process.env.SENTRY_AUTH_TOKEN,
          sourcemaps: {
            filesToDeleteAfterUpload: ["./build/static/**/*.map"],
          },
        })
      );
      return webpackConfig;
    },
  },
};
```

Update `package.json` scripts:
```json
{
  "scripts": {
    "start": "craco start",
    "build": "craco build"
  }
}
```

**Option B: Eject (`npm run eject`)**

After ejecting, edit `config/webpack.config.js` directly — same as the regular webpack
setup above. Ejection is irreversible; prefer CRACO.

* * *

### Manual Upload with `sentry-cli`

Use when you can’t use a bundler plugin (e.g., legacy toolchain, pre-built artifacts):

```bash
npm install @sentry/cli --save-dev
```

```bash
# Upload source maps after a production build
npx sentry-cli sourcemaps upload \
  --org $SENTRY_ORG \
  --project $SENTRY_PROJECT \
  --auth-token $SENTRY_AUTH_TOKEN \
  ./build
```

**`.sentryclirc` configuration file (alternative to env vars):**

```ini
[defaults]
org = my-org-slug
project = my-project-slug
url = https://sentry.io/
```

```bash
# With .sentryclirc, no --org/--project flags needed:
npx sentry-cli sourcemaps upload --auth-token $SENTRY_AUTH_TOKEN ./build
```

> ⚠️ Never commit `SENTRY_AUTH_TOKEN` to source control.
> Always read it from environment variables.

**CI/CD pattern (GitHub Actions):**

```yaml
- name: Build
  run: npm run build

- name: Upload source maps to Sentry
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
    SENTRY_ORG: my-org-slug
    SENTRY_PROJECT: my-react-app
  run: |
    npx sentry-cli sourcemaps upload \
      --org $SENTRY_ORG \
      --project $SENTRY_PROJECT \
      --auth-token $SENTRY_AUTH_TOKEN \
      ./build

- name: Delete source maps from build artifacts
  run: find ./build -name "*.map" -delete

- name: Deploy
  run: # your deploy step
```

* * *

### Environment Variables for Source Maps

Store credentials in `.env.sentry-build-plugin` (auto-loaded by Sentry bundler plugins)
or pass as CI/CD secrets:

```bash
# .env.sentry-build-plugin  ← auto-loaded by @sentry/vite-plugin and @sentry/webpack-plugin
# ADD THIS FILE TO .gitignore — never commit it
SENTRY_AUTH_TOKEN=sntrys_eyJ...
SENTRY_ORG=my-org-slug
SENTRY_PROJECT=my-project-slug
```

**Required token permissions:**

The `SENTRY_AUTH_TOKEN` must have:
- **Project:** Read & Write
- **Release:** Admin

* * *

### Source Map Security

| Strategy | How |
| --- | --- |
| Don’t expose maps to browsers | Use `sourcemap: "hidden"` (Vite) or `devtool: "hidden-source-map"` (webpack) |
| Delete maps after upload | Use `filesToDeleteAfterUpload` in the plugin config |
| Block map access at CDN/server | Configure your server to return 403 for `.js.map` requests |

All three should be used together for maximum security.

* * *

### Troubleshooting Source Maps

| Problem | Likely Cause | Fix |
| --- | --- | --- |
| Stack traces still minified | Source maps not uploaded, or Debug IDs missing | Rebuild with production config, re-run wizard or plugin |
| Maps not applied to old errors | Maps uploaded after errors occurred | Always upload maps **before** deploying — ideally in the same CI step |
| “SourceMapDevToolPlugin” stripping sources | `noSources: true` in your webpack SourceMapDevToolPlugin | Remove `noSources: true` option |
| Plugin only uploads once | Running in `--watch` or dev mode | Plugin only uploads during production builds (`NODE_ENV=production`) |
| SENTRY_AUTH_TOKEN not found | Missing env variable | Check `.env.sentry-build-plugin` exists and is not gitignored incorrectly |
| Component names still not showing | `.js`/`.ts` files instead of `.jsx`/`.tsx` | Rename files or use the Babel plugin directly on all JSX transform targets |

* * *

## 4. Default Integrations

These integrations are **automatically enabled** for every `@sentry/react` installation.
No configuration required.

| Integration | Name Constant | What It Does |
| --- | --- | --- |
| Breadcrumbs | `breadcrumbsIntegration` | Captures breadcrumbs from DOM events (clicks, inputs), XHR, fetch, console calls, history navigation |
| Browser API Errors | `browserApiErrorsIntegration` | Wraps `setTimeout`, `setInterval`, `requestAnimationFrame`, `addEventListener`, `removeEventListener` in try/catch so errors inside them are captured |
| Browser Session | `browserSessionIntegration` | Tracks session health (healthy vs. crashed) for Release Health metrics |
| Dedupe | `dedupeIntegration` | Prevents duplicate error events from being sent — deduplicates based on error type, message, and stack trace |
| Function to String | `functionToStringIntegration` | Preserves original function `.toString()` output after SDK instrumentation, so stack traces show readable names |
| Global Handlers | `globalHandlersIntegration` | Listens to `window.onerror` (uncaught exceptions) and `window.onunhandledrejection` (unhandled promise rejections) |
| HTTP Context | `httpContextIntegration` | Attaches current URL, referrer, and user-agent to every event |
| Inbound Filters | `inboundFiltersIntegration` | Filters known-noisy events by error type, message, or URL (e.g., browser extension errors, localhost-only errors) |
| Linked Errors | `linkedErrorsIntegration` | Follows JavaScript `error.cause` chains and attaches nested errors as linked issues — also used for React component stack linkage |

### Customizing a Default Integration’s Options

Pass the integration explicitly in `integrations` — it overrides the default instance:

```typescript
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  integrations: [
    // Override breadcrumbs to disable console capturing but keep DOM/fetch/XHR
    Sentry.breadcrumbsIntegration({
      console: false,   // don't capture console.log as breadcrumbs
      dom: true,
      fetch: true,
      history: true,
      xhr: true,
    }),

    // Only capture unhandled exceptions; handle rejections manually
    Sentry.globalHandlersIntegration({
      onerror: true,
      onunhandledrejection: false,
    }),
  ],
});
```

### Removing a Default Integration

Use the function form of `integrations` to filter out what you don’t want:

```typescript
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  integrations: (integrations) => {
    // Remove deduplication (e.g., if you want every occurrence recorded separately)
    return integrations.filter(
      (integration) => integration.name !== "Dedupe"
    );
  },
});
```

Common integration names to filter:
- `"Dedupe"` — deduplication
- `"Breadcrumbs"` — all automatic breadcrumbs
- `"GlobalHandlers"` — window.onerror / unhandledrejection
- `"LinkedErrors"` — error cause chain following
- `"HttpContext"` — URL/referrer attachment
- `"InboundFilters"` — built-in noise filtering

### Disabling ALL Default Integrations

```typescript
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  defaultIntegrations: false,
  // Build your own set from scratch:
  integrations: [
    Sentry.globalHandlersIntegration(),
    Sentry.browserTracingIntegration(),
    Sentry.dedupeIntegration(),
  ],
});
```

* * *

## 5. Optional Integrations

These are available but **must be explicitly added** to your `integrations` array.

### Performance & Tracing

| Integration | Min SDK | Description |
| --- | --- | --- |
| `browserTracingIntegration()` | 8.0.0 | Page load tracing, navigation tracing, automatic span creation for fetch/XHR, Core Web Vitals (LCP, FID, CLS), distributed tracing headers |
| `browserProfilingIntegration()` | 10.27.0 (Beta) | JS Self-Profiling API — captures call stacks at 100Hz in Chromium browsers. **Requires** `Document-Policy: js-profiling` HTTP header |

### Session Replay

| Integration | Min SDK | Description |
| --- | --- | --- |
| `replayIntegration()` | 7.27.0 | Session Replay — records DOM mutations, network requests, console output. Configured with `replaysSessionSampleRate` and `replaysOnErrorSampleRate` |
| `replayCanvasIntegration()` | 7.98.0 | Extends `replayIntegration` to record `<canvas>` elements in replays |

### Logging

| Integration | Min SDK | Description |
| --- | --- | --- |
| `consoleLoggingIntegration()` | 9.41.0 | Automatically forwards `console.log/warn/error/info/debug` calls as structured Sentry logs. Requires `enableLogs: true` |

```typescript
Sentry.init({
  enableLogs: true,
  integrations: [
    Sentry.consoleLoggingIntegration({
      levels: ["warn", "error"], // Only capture warnings and errors
    }),
  ],
});
```

### User Feedback

| Integration | Min SDK | Description |
| --- | --- | --- |
| `feedbackIntegration()` | 7.85.0 | Floating feedback button + form (bottom-right). Supports screenshots, custom theming, programmatic control |
| `feedbackModalIntegration()` | 7.85.0 | Modal dialog variant of the feedback form |
| `feedbackScreenshotIntegration()` | 8.0.0 | Adds screenshot capture capability to the feedback widget |

### Error Enhancement

| Integration | Min SDK | Description |
| --- | --- | --- |
| `extraErrorDataIntegration()` | 5.16.0 | Attaches non-standard properties on `Error` objects (e.g., `error.code`, `error.statusCode`, custom fields) as extra context |
| `contextLinesIntegration()` | 7.47.0 | Shows source code lines above and below the erroring line in the stack trace (requires source maps) |
| `httpClientIntegration()` | 7.50.0 | Captures failed HTTP requests (4xx/5xx responses) as Sentry error events, with request/response bodies. Opt-in because it may capture PII |
| `reportingObserverIntegration()` | 5.9.0 | Captures [Reporting Observer API](https://developer.mozilla.org/en-US/docs/Web/API/ReportingObserver) events (deprecation warnings, browser interventions, CSP violations) |
| `captureConsoleIntegration()` | 3.3.0 | Captures `console.error`/`console.warn` calls as Sentry issues (not logs). Legacy alternative to `consoleLoggingIntegration` |

### Stack Frame Rewriting

| Integration | Min SDK | Description |
| --- | --- | --- |
| `rewriteFramesIntegration()` | 5.7.0 | Rewrites stack frame file paths — useful for normalizing paths in monorepos, Docker containers, or when paths differ between build and deploy environments |

* * *

### `httpClientIntegration` — Full Setup

Captures HTTP requests that fail (4xx/5xx) as error events, with the request URL,
method, status code, and optionally request/response bodies.

```typescript
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  integrations: [
    Sentry.httpClientIntegration({
      // Capture errors for these HTTP status code ranges
      failedRequestStatusCodes: [[400, 499], [500, 599]],

      // Only capture errors for these URL patterns
      failedRequestTargets: [
        "https://api.myapp.com",
        /^https:\/\/internal\.service\//,
      ],
    }),
  ],
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/react/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
});
```

### Adding Integrations After Init

If you need to add an integration after `Sentry.init()` has been called (e.g., after
user consent):

```typescript
// After the user accepts analytics cookies:
Sentry.addIntegration(Sentry.replayIntegration({
  maskAllText: true,
  blockAllMedia: true,
}));
```

### Lazy Loading Integrations (Code Splitting)

```typescript
// Dynamic import (works with any bundler)
import("@sentry/browser").then((lazySentry) => {
  Sentry.addIntegration(lazySentry.replayIntegration());
});

// CDN lazyLoadIntegration() — for Sentry loader script environments
async function enableFeedback() {
  try {
    const feedbackIntegration =
      await Sentry.lazyLoadIntegration("feedbackIntegration");
    Sentry.addIntegration(feedbackIntegration({ colorScheme: "system" }));
  } catch (e) {
    // Ad-blockers or network failures — fail gracefully
    console.warn("Could not load Sentry feedback integration", e);
  }
}
```

Lazy-loadable integrations: `replayIntegration`, `replayCanvasIntegration`,
`feedbackIntegration`, `feedbackModalIntegration`, `feedbackScreenshotIntegration`,
`captureConsoleIntegration`, `contextLinesIntegration`, `linkedErrorsIntegration`,
`dedupeIntegration`, `extraErrorDataIntegration`, `httpClientIntegration`,
`reportingObserverIntegration`, `rewriteFramesIntegration`,
`browserProfilingIntegration`

* * *

## 6. Build Tool Detection & Environment Variables

### Detecting the Build Tool

```bash
# Run from project root
ls vite.config.ts vite.config.js webpack.config.js webpack.config.ts \
   craco.config.js next.config.js next.config.ts 2>/dev/null

cat package.json | grep -E '"vite"|"react-scripts"|"webpack"|"@craco"'
```

| File/Package Found | Build Tool |
| --- | --- |
| `vite.config.*` or `"vite"` in deps | Vite |
| `"react-scripts"` in deps | Create React App |
| `craco.config.js` or `"@craco/craco"` | CRA + CRACO |
| `webpack.config.*` or `"webpack"` in deps | Custom Webpack |
| `next.config.*` or `"next"` in deps | Next.js (use `@sentry/nextjs` instead) |

* * *

### DSN Environment Variable Patterns

| Build Tool | Variable Name | How to Access in Code |
| --- | --- | --- |
| Vite | `VITE_SENTRY_DSN` | `import.meta.env.VITE_SENTRY_DSN` |
| Create React App | `REACT_APP_SENTRY_DSN` | `process.env.REACT_APP_SENTRY_DSN` |
| Custom Webpack | `SENTRY_DSN` | `process.env.SENTRY_DSN` (requires `DefinePlugin`) |
| Any | `SENTRY_DSN` | Build-time injection (not available at runtime in browser) |

**Vite — `.env` file:**
```bash
# .env.production
VITE_SENTRY_DSN=https://<key>@<org>.ingest.sentry.io/<id>
VITE_SENTRY_ENVIRONMENT=production
```

```typescript
// instrument.ts
Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.VITE_SENTRY_ENVIRONMENT ?? "development",
});
```

**Create React App — `.env.production` file:**
```bash
# .env.production  (committed — DSN is public)
REACT_APP_SENTRY_DSN=https://<key>@<org>.ingest.sentry.io/<id>
REACT_APP_SENTRY_ENVIRONMENT=production
```

```typescript
// instrument.ts
Sentry.init({
  dsn: process.env.REACT_APP_SENTRY_DSN,
  environment: process.env.REACT_APP_SENTRY_ENVIRONMENT ?? "development",
});
```

**Custom Webpack — `webpack.config.js` with `DefinePlugin`:**
```javascript
const webpack = require("webpack");

module.exports = {
  plugins: [
    new webpack.DefinePlugin({
      "process.env.SENTRY_DSN": JSON.stringify(process.env.SENTRY_DSN),
      "process.env.SENTRY_ENVIRONMENT": JSON.stringify(
        process.env.NODE_ENV ?? "development"
      ),
    }),
  ],
};
```

```typescript
// instrument.ts
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.SENTRY_ENVIRONMENT,
});
```

* * *

### Conditional Initialization (Development vs Production)

Prevent Sentry from running in local development to avoid polluting your issue inbox
with dev noise:

```typescript
// instrument.ts
import * as Sentry from "@sentry/react";

const IS_PRODUCTION =
  import.meta.env.PROD ||                           // Vite
  process.env.NODE_ENV === "production";             // webpack / CRA

if (IS_PRODUCTION) {
  Sentry.init({
    dsn: import.meta.env.VITE_SENTRY_DSN,           // or your env var pattern
    environment: "production",
    integrations: [
      Sentry.browserTracingIntegration(),
      Sentry.replayIntegration({
        maskAllText: false,
        blockAllMedia: false,
      }),
    ],
    tracesSampleRate: 0.2,              // 20% in production
    replaysSessionSampleRate: 0.1,
    replaysOnErrorSampleRate: 1.0,
  });
} else {
  // In development: optionally init with verbose debug and full sampling
  Sentry.init({
    dsn: import.meta.env.VITE_SENTRY_DSN,
    environment: "development",
    debug: true,                        // Verbose SDK logging
    tracesSampleRate: 1.0,              // 100% in dev so nothing is missed
    integrations: [Sentry.browserTracingIntegration()],
    // No Replay in dev — too noisy
  });
}
```

* * *

### Complete `instrument.ts` Reference — All Features

A kitchen-sink example combining every feature:

```typescript
// src/instrument.ts
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.VITE_APP_ENV ?? "production",
  release: import.meta.env.VITE_APP_VERSION,

  // ── Integrations ─────────────────────────────────────────────
  integrations: [
    // Tracing (navigation + API + Core Web Vitals)
    Sentry.browserTracingIntegration(),

    // Session Replay
    Sentry.replayIntegration({
      maskAllText: false,
      blockAllMedia: false,
    }),

    // Profiling (Beta — Chromium only, needs Document-Policy header)
    // Sentry.browserProfilingIntegration(),

    // Structured logging (requires enableLogs: true)
    Sentry.consoleLoggingIntegration({
      levels: ["warn", "error"],
    }),

    // Capture HTTP 4xx/5xx as Sentry errors
    Sentry.httpClientIntegration({
      failedRequestStatusCodes: [[400, 499], [500, 599]],
    }),

    // Show source lines in stack traces (requires source maps)
    Sentry.contextLinesIntegration(),

    // Capture non-standard Error properties
    Sentry.extraErrorDataIntegration(),

    // User feedback widget
    Sentry.feedbackIntegration({
      colorScheme: "system",
      showBranding: false,
      triggerLabel: "Report a Bug",
    }),
  ],

  // ── Tracing ───────────────────────────────────────────────────
  tracesSampleRate: 0.2,
  tracePropagationTargets: [
    "localhost",
    /^https:\/\/api\.myapp\.com/,
  ],

  // ── Session Replay ────────────────────────────────────────────
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,

  // ── Profiling ─────────────────────────────────────────────────
  profileSessionSampleRate: 1.0,

  // ── Logging ───────────────────────────────────────────────────
  enableLogs: true,
  beforeSendLog: (log) => {
    if (log.level === "debug") return null; // Drop debug logs
    if (log.attributes?.password) delete log.attributes.password;
    return log;
  },

  // ── Redux ─────────────────────────────────────────────────────
  normalizeDepth: 10,

  // ── Filtering ─────────────────────────────────────────────────
  ignoreErrors: [
    "ResizeObserver loop limit exceeded",
    /^Loading chunk \d+ failed/,
  ],
  denyUrls: [
    /extensions\//i,
    /^chrome:\/\//i,
  ],

  beforeSend(event) {
    // Strip credit card numbers from messages just in case
    if (event.message) {
      event.message = event.message.replace(/\b\d{16}\b/g, "[CARD]");
    }
    return event;
  },
});
```

```typescript
// store/index.ts — wire in Redux enhancer
import { configureStore } from "@reduxjs/toolkit";
import * as Sentry from "@sentry/react";

export const store = configureStore({
  reducer: rootReducer,
  enhancers: (getDefaultEnhancers) =>
    getDefaultEnhancers().concat(
      Sentry.createReduxEnhancer({
        stateTransformer: (state) => ({ ...state, auth: null }),
        configureScopeWithState: (scope, state) => {
          scope.setTag("user.plan", state.user.plan);
        },
      })
    ),
});
```

* * *

## Quick Reference

```typescript
// ── Redux ─────────────────────────────────────────────────────
Sentry.createReduxEnhancer({
  actionTransformer: (action) => action | null,
  stateTransformer: (state) => state | null,
  configureScopeWithState: (scope, state) => void,
  attachReduxState: true,
})
// normalizeDepth goes in Sentry.init(), not createReduxEnhancer()

// ── Component Tracking ────────────────────────────────────────
Sentry.withProfiler(Component, { name?, includeRender?, includeUpdates? })
sentryVitePlugin({ reactComponentAnnotation: { enabled: true, ignoredComponents: [] } })
// Babel plugin direct: @sentry/babel-plugin-component-annotate

// ── Source Maps ───────────────────────────────────────────────
npx @sentry/wizard@latest -i sourcemaps  // automated setup
// Vite: build.sourcemap = "hidden" + sentryVitePlugin()
// Webpack: devtool: "hidden-source-map" + sentryWebpackPlugin()
// CRA: use CRACO + sentryWebpackPlugin
// Manual: npx sentry-cli sourcemaps upload --auth-token $TOKEN ./dist

// ── Integrations (opt-in) ─────────────────────────────────────
Sentry.browserTracingIntegration()         // Tracing + Core Web Vitals
Sentry.replayIntegration()                 // Session Replay
Sentry.browserProfilingIntegration()       // JS Profiler (Beta, Chromium only)
Sentry.consoleLoggingIntegration()         // console → Sentry logs
Sentry.feedbackIntegration()               // Feedback widget
Sentry.httpClientIntegration()             // 4xx/5xx as errors
Sentry.contextLinesIntegration()           // Source lines in stack traces
Sentry.extraErrorDataIntegration()         // Non-standard Error properties
Sentry.reportingObserverIntegration()      // Browser deprecation/CSP reports
Sentry.rewriteFramesIntegration()          // Rewrite stack frame paths
Sentry.captureConsoleIntegration()         // console → Sentry issues (legacy)

// ── Remove a Default Integration ─────────────────────────────
Sentry.init({
  integrations: (integrations) =>
    integrations.filter((i) => i.name !== "Dedupe"),
})

// ── Add Integration After Init ────────────────────────────────
Sentry.addIntegration(Sentry.replayIntegration())

// ── Environment Variables ─────────────────────────────────────
// Vite:   import.meta.env.VITE_SENTRY_DSN
// CRA:    process.env.REACT_APP_SENTRY_DSN
// Webpack: process.env.SENTRY_DSN (via DefinePlugin)
```
