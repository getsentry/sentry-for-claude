# Error Monitoring — Sentry Browser SDK

> Minimum SDK: `@sentry/browser` ≥7.0.0\
> `makeBrowserOfflineTransport` requires `@sentry/browser` ≥7.48.0\
> `linkedErrorsIntegration` `cause` chain requires Error.cause support (Chrome 93+,
> Firefox 91+)

* * *

## How Automatic Capture Works

The browser SDK hooks into the browser environment and captures errors from multiple
layers automatically:

| Layer | Mechanism | Integration |
| --- | --- | --- |
| Uncaught synchronous exceptions | `window.onerror` | `globalHandlersIntegration` (default on) |
| Unhandled promise rejections | `window.onunhandledrejection` | `globalHandlersIntegration` (default on) |
| Errors in `setTimeout` / `setInterval` / `requestAnimationFrame` / `addEventListener` | Patched browser APIs | `browserApiErrorsIntegration` (default on) |
| Console errors (optional) | Patched `console.error` | `captureConsoleIntegration` (opt-in) |

### What Requires Manual Instrumentation

The global handlers only catch errors that **escape** your code.
These are silently swallowed without manual calls:

- Errors caught by your own `try/catch` blocks
- Business-logic failures (validation errors, unexpected states)
- Async errors in `.then()` chains where `.catch()` is attached
- User-visible conditions that aren’t exceptions (use `captureMessage`)

* * *

## Core Capture APIs

### `Sentry.captureException(error, captureContext?)`

Captures an exception and sends it to Sentry.
Prefer `Error` objects — they include stack traces.

```javascript
import * as Sentry from "@sentry/browser";

// Basic usage
try {
  riskyOperation();
} catch (err) {
  Sentry.captureException(err);
}

// With inline capture context
try {
  await chargeCard(order);
} catch (err) {
  Sentry.captureException(err, {
    level: "fatal",
    tags: { module: "checkout", payment_provider: "stripe" },
    extra: { orderId: order.id, amount: order.total },
    user: { id: "u_123", email: "user@example.com" },
    fingerprint: ["checkout-payment-fail"],
    contexts: {
      payment: { provider: "stripe", amount: 9999, currency: "usd" },
    },
  });
}

// Non-Error values are accepted but may lack stack traces
Sentry.captureException("Something went wrong as a string");
```

**`CaptureContext` shape:**

| Field | Type | Description |
| --- | --- | --- |
| `level` | `"fatal" \| "error" \| "warning" \| "log" \| "info" \| "debug"` | Severity override for this event |
| `tags` | `Record<string, string>` | Indexed, filterable key-value pairs |
| `extra` | `Record<string, unknown>` | Unindexed supplementary data |
| `user` | `{ id?, email?, username?, ip_address? }` | User identity |
| `contexts` | `Record<string, Record<string, unknown>>` | Named structured context blocks |
| `fingerprint` | `string[]` | Custom issue grouping key |

* * *

### `Sentry.captureMessage(message, levelOrContext?)`

Captures a plain-text message as a Sentry issue.

```javascript
// With a severity level (shorthand second argument)
Sentry.captureMessage("Something went wrong", "warning");
Sentry.captureMessage("Payment gateway timeout", "fatal");

// With full CaptureContext
Sentry.captureMessage("User performed invalid action", {
  level: "warning",
  user: { id: "u_456" },
  tags: { feature: "cart", action: "remove-item" },
  extra: { itemId: "sku_789" },
});
```

> Set `attachStacktrace: true` in `Sentry.init()` to automatically attach a stack trace
> to message events.

* * *

### `Sentry.captureEvent(event)`

Sends a fully constructed Sentry event object.
Use `captureException` or `captureMessage` in application code; use `captureEvent` for
custom integrations or forwarding from legacy loggers.

```javascript
Sentry.captureEvent({
  message: "Legacy logger forwarded event",
  level: "warning",
  tags: { source: "legacy-logger", module: "billing" },
  extra: { rawLog: "something went wrong at line 42" },
  timestamp: Date.now() / 1000, // Unix timestamp in seconds
  fingerprint: ["legacy-billing-error"],
});
```

* * *

### Utility APIs

```javascript
// Get the event ID of the last sent error event
const eventId = Sentry.lastEventId();

// Flush all pending events before page unload / shutdown
await Sentry.flush(2000); // wait up to 2 seconds

// Flush and disable the SDK permanently
await Sentry.close(2000);

// Check if SDK is initialized and enabled
if (Sentry.isEnabled()) { /* ... */ }
```

* * *

## Scope Management

Sentry uses three nested scope types.
Data from all three is merged before each event is sent.

| Scope | API | Lifetime | Use Case |
| --- | --- | --- | --- |
| **Global** | `getGlobalScope()` | Entire application | App-wide constants: version, build ID, region |
| **Isolation** | `getIsolationScope()` | Per page load (browser) | User info, session data, tags set via top-level `setTag()` |
| **Current** | `withScope()` | Per-event / narrowest | Per-operation data: one API call, one form submit |

**Merge priority (later overrides earlier):**
```
Global Scope → Isolation Scope → Current Scope → Event-level CaptureContext
```

> **Browser note:** In a browser there is no per-request isolation, so the isolation
> scope effectively behaves like the global scope.
> The distinction matters in server-side runtimes (Node.js, Deno, Cloudflare Workers).

* * *

### `withScope` — Per-Event Scoping (Recommended)

Forks the current scope, runs your callback with the fork, and discards it when done.
This is the preferred way to attach data to a single event without polluting broader
scope.

```javascript
Sentry.withScope((scope) => {
  scope.setTag("transaction_id", "txn_abc123");
  scope.setExtra("requestPayload", { amount: 50, currency: "USD" });
  scope.setLevel("warning");
  scope.setUser({ id: "u_789" });
  scope.setFingerprint(["payment-error", "stripe"]);
  Sentry.captureException(new Error("Payment failed"));
  // scope is discarded after this callback
});

// Events captured here are NOT affected by the above scope
Sentry.captureMessage("This event has no payment tags");
```

* * *

### Scope Methods

Every scope instance exposes the same enrichment API:

```javascript
// Isolation scope — persists for all subsequent events on this page
Sentry.getIsolationScope().setUser({ id: "u_123", email: "user@example.com" });
Sentry.getIsolationScope().setTag("app_version", "3.4.1");

// Global scope — applied to every event in the app
Sentry.getGlobalScope().setTag("datacenter", "us-east-1");
Sentry.getGlobalScope().setContext("build", {
  commit: "abc1234",
  buildDate: "2026-03-03",
});

// Scope method reference
scope.setUser({ id, email, username, ip_address });  // setUser(null) to clear
scope.setTag("key", "value");
scope.setTags({ key1: "v1", key2: "v2" });
scope.setExtra("key", value);
scope.setExtras({ key1: v1, key2: v2 });
scope.setContext("name", { key: value });  // setContext("name", null) to remove
scope.setLevel("warning");
scope.setFingerprint(["my-group-key"]);
scope.addBreadcrumb({ category: "auth", message: "User logged in" });
scope.addEventProcessor((event) => { /* modify or drop */ return event; });
scope.clear(); // reset all scope data
```

* * *

## Event Enrichment

### Tags — Indexed, Searchable Key-Value Pairs

Tags power filtering, search, and tag distribution maps in the Sentry UI.

**Constraints:** Key ≤32 chars (`a-zA-Z0-9_.:-`, no spaces).
Value ≤200 chars, no newlines.

```javascript
// Single tag — applied to all subsequent events (isolation scope)
Sentry.setTag("page_locale", "de-at");
Sentry.setTag("subscription_tier", "pro");
Sentry.setTag("subscription_plan", "pro");

// Multiple tags at once
Sentry.setTags({
  environment: "staging",
  region: "eu-west-1",
  api_version: "v3",
});

// Scoped tag — only on this one event
Sentry.withScope((scope) => {
  scope.setTag("retry_attempt", "3");
  Sentry.captureException(new Error("Max retries exceeded"));
});
```

* * *

### Context — Rich Unindexed Structured Data

Context is **not indexed or searchable** but displays in full on the event details page.
Use it for rich structured data you need for debugging but don’t need to filter on.

```javascript
Sentry.setContext("shopping_cart", {
  itemCount: 3,
  totalAmount: 149.99,
  currency: "USD",
  couponApplied: "SAVE10",
});

Sentry.setContext("device", {
  platform: navigator.platform,
  language: navigator.language,
  screenWidth: screen.width,
  screenHeight: screen.height,
});

// Clear a context by passing null
Sentry.setContext("shopping_cart", null);
```

> **Depth limit:** Nested context objects are normalized to **3 levels deep** by
> default. Use `normalizeDepth` in `init()` to change this.

* * *

### User Information

```javascript
// Set user on login
Sentry.setUser({
  id: "user_abc123",
  email: "alice@example.com",
  username: "alice",
  subscription: "premium", // arbitrary extra field
  org: "acme-corp",
});

// Clear user on logout
Sentry.setUser(null);

// Auto-infer IP address (requires sendDefaultPii: true in init)
Sentry.setUser({ ip_address: "{{auto}}" });
```

* * *

### `initialScope` — Set Context at Startup

```javascript
// Object form
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  initialScope: {
    tags: { "app.version": "1.2.3", region: "us-west" },
    user: { id: 42, email: "john.doe@example.com" },
  },
});

// Callback form (full Scope API access)
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  initialScope: (scope) => {
    scope.setTags({ a: "b", c: "d" });
    scope.setContext("device", { platform: navigator.platform });
    return scope;
  },
});
```

* * *

## Breadcrumbs

Breadcrumbs create a trail of events leading up to an issue.
They’re buffered locally and attached to the next event sent to Sentry.

### Automatic Breadcrumbs

| Source | What is captured |
| --- | --- |
| `console` | `console.log`, `warn`, `error`, `debug` calls |
| `dom` | Click and keypress events on DOM elements |
| `fetch` | All `fetch()` HTTP requests (URL, method, status) |
| `xhr` | All `XMLHttpRequest` calls |
| `history` | `history.pushState`, `history.replaceState`, navigations |
| `sentry` | Internal events when the SDK sends to Sentry |

### Manual Breadcrumbs

```javascript
// Authentication event
Sentry.addBreadcrumb({
  category: "auth",
  message: "User authenticated",
  level: "info",
  data: { userId: user.id, method: "oauth2", provider: "google" },
});

// Navigation event
Sentry.addBreadcrumb({
  type: "navigation",
  category: "navigation",
  data: { from: "/home", to: "/checkout" },
});

// Custom action
Sentry.addBreadcrumb({
  category: "cart",
  message: "Item added to cart",
  level: "info",
  data: { itemId: "sku_123", quantity: 2, price: 29.99 },
});

// Domain event (use feature-flags.md / featureFlagsIntegration for real flag tracking)
Sentry.addBreadcrumb({
  type: "debug",
  category: "checkout",
  message: "Checkout step completed",
  level: "debug",
  data: { step: "shipping", method: "express" },
});
```

**Breadcrumb schema:**

| Field | Type | Description |
| --- | --- | --- |
| `message` | `string` | Human-readable description |
| `type` | `"default" \| "debug" \| "error" \| "info" \| "navigation" \| "http" \| "query" \| "ui" \| "user"` | Breadcrumb type |
| `level` | `"fatal" \| "error" \| "warning" \| "log" \| "info" \| "debug"` | Severity |
| `category` | `string` | Dot-namespaced: `"auth"`, `"ui.click"`, `"api.request"` |
| `data` | `Record<string, unknown>` | Arbitrary structured payload |
| `timestamp` | `number` | Unix timestamp; auto-set if omitted |

* * *

### Breadcrumb Configuration

```javascript
Sentry.init({
  dsn: "___PUBLIC_DSN___",
  maxBreadcrumbs: 50, // default: 100

  beforeBreadcrumb(breadcrumb, hint) {
    // Drop UI click breadcrumbs
    if (breadcrumb.category === "ui.click") return null;

    // Enrich XHR breadcrumbs with request body size
    if (breadcrumb.type === "http" && hint?.xhr) {
      breadcrumb.data = {
        ...breadcrumb.data,
        requestBodySize: hint.xhr.requestBody?.length ?? 0,
      };
    }

    // Drop console.debug noise in production
    if (breadcrumb.category === "console" && breadcrumb.level === "debug") {
      return null;
    }

    return breadcrumb;
  },

  integrations: [
    Sentry.breadcrumbsIntegration({
      console: true,
      dom: { serializeAttribute: ["data-testid", "aria-label"] },
      fetch: true,
      history: true,
      xhr: true,
      sentry: true,
    }),
  ],
});
```

* * *

## Hooks — `beforeSend`, `beforeSendTransaction`, `beforeBreadcrumb`

### `beforeSend` — Modify or Drop Error Events

Called last, just before an error event is sent.
All scope data has already been applied.
Return the event to send it, or `null` to drop it.

```javascript
Sentry.init({
  dsn: "___PUBLIC_DSN___",

  beforeSend(event, hint) {
    const err = hint.originalException;

    // --- Drop known noisy errors ---
    if (event.exception?.values?.[0]?.value?.includes("ResizeObserver")) {
      return null;
    }

    // --- Drop browser extension errors ---
    if (event.exception?.values?.[0]?.stacktrace?.frames?.some(
      (frame) => frame.filename?.includes("extension://")
    )) {
      return null;
    }

    // --- PII scrubbing ---
    if (event.user?.email) {
      delete event.user.email;
    }

    // --- Custom fingerprinting based on original exception ---
    if (err instanceof NetworkError) {
      event.fingerprint = ["network-error", err.statusCode?.toString() ?? "unknown"];
    }

    // --- Add extra context from the original exception ---
    if (err instanceof ApiError) {
      event.extra = {
        ...event.extra,
        requestId: err.requestId,
        endpoint: err.endpoint,
      };
    }

    return event;
  },
});
```

**`hint` object properties:**

| Property | Type | Description |
| --- | --- | --- |
| `originalException` | `unknown` | The original exception that triggered the event |
| `syntheticException` | `Error \| null` | Synthetic Error generated for string/non-Error captures |
| `event_id` | `string` | The generated event ID |
| `data` | `Record<string, unknown>` | Arbitrary extra data |

* * *

### `beforeSendTransaction` — Modify or Drop Transaction Events

Same as `beforeSend` but for performance transaction events.

```javascript
Sentry.init({
  beforeSendTransaction(event) {
    // Drop health check transactions
    if (event.transaction === "/health" || event.transaction === "/ping") {
      return null;
    }

    // Scrub PII from transaction name
    event.transaction = event.transaction?.replace(/\/users\/\d+/, "/users/:id");

    return event;
  },
});
```

* * *

## Event Processors

Event processors intercept every event before it’s sent.
Unlike `beforeSend`, multiple processors can be registered and run in series.

```javascript
// Global event processor — runs on ALL events
Sentry.addEventProcessor((event, hint) => {
  // Add build metadata to every event
  event.tags = {
    ...event.tags,
    build_sha: BUILD_SHA,
    deploy_env: DEPLOY_ENV,
  };

  // Drop events with no stack trace in production
  if (
    IS_PRODUCTION &&
    !event.exception?.values?.[0]?.stacktrace?.frames?.length
  ) {
    return null;
  }

  return event;
});

// Scope-level processor — only applies within withScope
Sentry.withScope((scope) => {
  scope.addEventProcessor((event) => {
    event.tags = { ...event.tags, source: "checkout-flow" };
    return event;
  });
  Sentry.captureException(new Error("Checkout failed"));
});
```

**Key differences vs.
`beforeSend`:**

| Feature | `addEventProcessor` | `beforeSend` |
| --- | --- | --- |
| Execution order | Unspecified among processors | **Always last** (after all processors) |
| Multiple allowed | ✅ Unlimited | ❌ Only one |
| Scope-level support | ✅ Yes | ❌ Global init only |
| Async support | ✅ (slower) | ✅ |

* * *

## Fingerprinting

Every event has a fingerprint array.
Events with the same fingerprint are grouped into the same issue.

### Extending Default Grouping

Use `{{ default }}` to keep Sentry’s default grouping and add extra discriminators:

```javascript
Sentry.init({
  beforeSend(event, hint) {
    const err = hint.originalException;

    if (err instanceof ApiError) {
      // Keep default grouping but split further by RPC function + error code
      event.fingerprint = ["{{ default }}", err.functionName, String(err.errorCode)];
    }

    return event;
  },
});
```

### Overriding Default Grouping

Omit `{{ default }}` to completely replace the auto-generated fingerprint (collapses all
matching errors into one issue):

```javascript
Sentry.init({
  beforeSend(event, hint) {
    const err = hint.originalException;

    if (err?.message?.includes("timeout")) {
      event.fingerprint = ["network-timeout"];
    }

    if (err?.name === "ChunkLoadError") {
      event.fingerprint = ["chunk-load-failure"];
    }

    return event;
  },
});
```

### Inline Fingerprint on Capture

```javascript
Sentry.captureException(err, {
  fingerprint: ["payment-gateway", "stripe", err.code],
});

Sentry.captureMessage("Rate limit exceeded", {
  fingerprint: ["rate-limit", endpoint],
});

// Group by HTTP method + path + status code
Sentry.withScope((scope) => {
  scope.setFingerprint([method, path, String(err.statusCode)]);
  Sentry.captureException(err);
});
```

**Fingerprint variables:**

| Variable | Resolves to |
| --- | --- |
| `{{ default }}` | The auto-generated Sentry fingerprint |
| `{{ transaction }}` | The transaction name |
| `{{ function }}` | The function name in the stack trace |
| `{{ type }}` | The exception type |
| `{{ module }}` | The module name |
| `{{ value }}` | The exception value/message |

* * *

## Event Filtering

### `ignoreErrors` — Pattern-Based Filtering

```javascript
Sentry.init({
  ignoreErrors: [
    // String (partial match):
    "ResizeObserver loop limit exceeded",
    "fb_xd_fragment",
    "Non-Error exception captured",

    // Regex (full control):
    /^Network Error$/,
    /ChunkLoadError/,
    /Loading chunk \d+ failed/,
    /^Script error\.?$/,
  ],
});
```

### `allowUrls` / `denyUrls` — Filter by Script Origin

These filter based on **stack frame URLs** (where the code lives), not the page URL.

```javascript
Sentry.init({
  // Only capture errors from your own scripts
  allowUrls: [
    /https?:\/\/((cdn|www)\.)?myapp\.com/,
  ],

  // Never capture errors from these script origins
  denyUrls: [
    /extensions\//i,
    /^chrome:\/\//i,
    /^moz-extension:\/\//i,
    /^safari-extension:\/\//i,
    /ads\.doubleclick\.net/,
  ],
});
```

### `sampleRate` — Error Volume Reduction

```javascript
Sentry.init({
  sampleRate: 0.25, // Capture 25% of errors (randomly sampled)
});
```

* * *

## Default Integrations

### Auto-Enabled Browser Integrations (9 total)

| Integration | Purpose | Key Config |
| --- | --- | --- |
| `breadcrumbsIntegration` | Records breadcrumbs from console, DOM, fetch, XHR, history | `console`, `dom`, `fetch`, `history`, `xhr` |
| `browserApiErrorsIntegration` | Wraps `setTimeout`, `setInterval`, `requestAnimationFrame`, `addEventListener` in try/catch | `setTimeout`, `setInterval`, `requestAnimationFrame`, `eventTarget` |
| `browserSessionIntegration` | Tracks release health (session per page load / route change) | `lifecycle: "route" \| "page"` |
| `dedupeIntegration` | Prevents duplicate events from rapid-succession throws | None |
| `functionToStringIntegration` | Preserves original function names in wrapped stack traces | None |
| `globalHandlersIntegration` | Attaches `window.onerror` and `window.onunhandledrejection` | `onerror`, `onunhandledrejection` |
| `httpContextIntegration` | Attaches page URL, User-Agent, Referer to every event | None |
| `inboundFiltersIntegration` | Client-side filtering via `ignoreErrors`, `denyUrls`, `allowUrls` | Configured via top-level init options |
| `linkedErrorsIntegration` | Follows `error.cause` chain and attaches linked errors | `key: "cause"`, `limit: 5` |

### Modifying Default Integrations

```javascript
// Disable a single default integration by name
Sentry.init({
  integrations: (defaults) =>
    defaults.filter((i) => i.name !== "Breadcrumbs"),
});

// Reconfigure a default integration
Sentry.init({
  integrations: [
    Sentry.breadcrumbsIntegration({ console: false }),
    Sentry.linkedErrorsIntegration({ limit: 10 }),
    Sentry.globalHandlersIntegration({ onunhandledrejection: false }),
    Sentry.browserSessionIntegration({ lifecycle: "page" }),
  ],
});

// Disable ALL defaults (start from scratch)
Sentry.init({
  defaultIntegrations: false,
  integrations: [
    Sentry.globalHandlersIntegration(),
    Sentry.linkedErrorsIntegration(),
  ],
});
```

### Adding Integrations After `init()`

```javascript
// Lazy-add after init
Sentry.addIntegration(Sentry.reportingObserverIntegration());

// Dynamic import from npm (recommended with bundlers)
const { captureConsoleIntegration } = await import("@sentry/browser");
Sentry.addIntegration(captureConsoleIntegration({ levels: ["error", "warn"] }));
```

* * *

## Transport

### Default Transport

The browser SDK uses a `fetch`-based transport.
Events are sent as POST requests to the Sentry ingestion endpoint.

### Offline Transport — IndexedDB Queue

Stores events when offline and replays them when the browser reconnects:

```javascript
import { makeBrowserOfflineTransport, makeFetchTransport } from "@sentry/browser";
import * as Sentry from "@sentry/browser";

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  transport: makeBrowserOfflineTransport(makeFetchTransport),
});
```

### Tunneling — Bypass Ad-Blockers

Route all Sentry traffic through your own server endpoint:

```javascript
Sentry.init({
  dsn: "___PUBLIC_DSN___", // Still required for header generation
  tunnel: "https://myapp.com/sentry-tunnel",
});
```

Your server endpoint forwards the payload to Sentry’s ingestion URL. See
[Dealing with Ad-Blockers](https://docs.sentry.io/platforms/javascript/troubleshooting/#dealing-with-ad-blockers)
for a full tunneling server implementation.

### Custom Transport

```javascript
import { createTransport } from "@sentry/core";
import * as Sentry from "@sentry/browser";

function makeCustomFetchTransport(options) {
  function makeRequest(request) {
    return fetch(options.url, {
      body: request.body,
      method: "POST",
      referrerPolicy: "origin",
      headers: {
        ...options.headers,
        "X-Custom-Header": "my-value",
      },
    }).then((response) => ({
      statusCode: response.status,
      headers: {
        "x-sentry-rate-limits": response.headers.get("X-Sentry-Rate-Limits"),
        "retry-after": response.headers.get("Retry-After"),
      },
    }));
  }

  return createTransport(options, makeRequest);
}

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  transport: makeCustomFetchTransport,
});
```

* * *

## Best Practices

- **Set user context after authentication** — call `Sentry.setUser()` after login
  completes, not in `Sentry.init`.
- **Clear user on logout** — always call `Sentry.setUser(null)` when the user signs out.
- **Use `withScope` for per-event context** — avoid mutating the isolation scope for
  temporary data.
- **Use tags for filterable data, context for debugging data** — tags are indexed;
  context is not.
- **Filter noise early** — use `ignoreErrors` and `denyUrls` to drop known-bad events
  before `beforeSend`.
- **Avoid capturing in render paths** — wrap Sentry calls in event handlers or
  `try/catch` blocks.
- **Set `release` and `environment`** — required for source map resolution and
  environment-aware alerting.
- **Use `beforeSend` for PII scrubbing** — never send emails, credit card numbers, or
  passwords as tags/extra.
- **Use `{{ default }}` in fingerprints** to extend, not replace, Sentry’s grouping when
  appropriate.

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Errors from browser extensions captured | Add `/extensions\//i`, `/^chrome:\/\//i`, `/^safari-extension:\/\//i` to `denyUrls` |
| `ResizeObserver loop` flooding issues | Add `"ResizeObserver loop limit exceeded"` to `ignoreErrors` |
| Script errors with no details | Cross-origin scripts without CORS headers appear as `"Script error."` — add CORS headers or use `allowUrls` |
| Events sent twice | If using multiple `Sentry.init()` calls, only the first takes effect. Check for duplicate SDK instances. |
| `beforeSend` returning `null` but events still sent | Check `beforeSendTransaction` — it’s a separate hook for performance events |
| User context missing on events | Call `Sentry.setUser()` after authentication completes; verify it’s not being called before auth |
| `configureScope is not a function` | Deprecated in SDK v8. Replace with `getIsolationScope()` or `withScope()` |
| Tags not appearing on events | Verify the tag isn’t being overwritten by a built-in Sentry tag (`browser`, `os`, `url`, `environment`, `release`) |
| High event volume from known errors | Add patterns to `ignoreErrors` or use `sampleRate` to reduce volume |
| Unhandled rejections not captured | Verify `globalHandlersIntegration({ onunhandledrejection: true })` is active (it is by default) |
| `linkedErrorsIntegration` not showing cause chain | Requires `Error.cause` support — Chrome 93+, Firefox 91+. Ensure the SDK version is ≥7.0.0. |
