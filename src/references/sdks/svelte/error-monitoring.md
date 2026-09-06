# Error Monitoring — Sentry Svelte/SvelteKit SDK

> Minimum SDK: `@sentry/sveltekit` ≥7.0.0+ / `@sentry/svelte` ≥7.0.0+

* * *

## How Automatic Capture Works

| Layer | Mechanism | Fires when … |
| --- | --- | --- |
| **Client (both)** | `globalHandlersIntegration` | `window.onerror`, unhandled `Promise` rejections |
| **Client (both)** | `browserApiErrorsIntegration` | Errors thrown in `setTimeout`, `setInterval`, `requestAnimationFrame` |
| **Server (SvelteKit)** | `handleErrorWithSentry()` in `hooks.server.ts` | Any unhandled error in a server hook, load function, or route handler |
| **Server (SvelteKit)** | `sentryHandle()` | Instruments incoming requests; captures errors from the request pipeline |
| **Client (SvelteKit)** | `handleErrorWithSentry()` in `hooks.client.ts` | Any unhandled navigation or client-side error SvelteKit surfaces |

No configuration beyond the `Sentry.init()` call is required for baseline error capture.

* * *

## SvelteKit Error Hooks

### `hooks.client.ts`

```typescript
import * as Sentry from "@sentry/sveltekit";

Sentry.init({
  dsn: import.meta.env.PUBLIC_SENTRY_DSN ?? import.meta.env.VITE_SENTRY_DSN,
  dataCollection: {
    // To disable sending user data and HTTP bodies, uncomment the lines below. For more info visit:
    // https://docs.sentry.io/platforms/javascript/guides/sveltekit/configuration/options/#dataCollection
    // userInfo: false,
    // httpBodies: [],
  },
});

// Sentry captures first; your handler runs after
const myErrorHandler = ({ error, event }: { error: unknown; event: unknown }) => {
  console.error("Client error:", error);
};

export const handleError = Sentry.handleErrorWithSentry(myErrorHandler);

// Works with no argument too:
// export const handleError = Sentry.handleErrorWithSentry();
```

### `hooks.server.ts`

```typescript
import * as Sentry from "@sentry/sveltekit";
import { sequence } from "@sveltejs/kit/hooks";

// Sentry.init() is in instrumentation.server.ts (modern) or here (legacy)

const myErrorHandler = ({ error, event }: { error: unknown; event: unknown }) => {
  console.error("Server error:", error);
};

export const handleError = Sentry.handleErrorWithSentry(myErrorHandler);

// sentryHandle() instruments requests and creates root spans
export const handle = Sentry.sentryHandle();

// Composing multiple handles:
// export const handle = sequence(Sentry.sentryHandle(), authHandle, logHandle);
```

### `handleErrorWithSentry()` callback signature

```typescript
export const handleError = Sentry.handleErrorWithSentry(
  (input: {
    error: unknown;
    event: RequestEvent | NavigationEvent;
    status?: number;
    message?: string;
  }) => {
    // Your logic runs AFTER Sentry has already captured the error
  }
);
```

* * *

## Manual Error Capture

```typescript
import * as Sentry from "@sentry/sveltekit"; // or "@sentry/svelte"

// Capture an Error object
try {
  await riskyOperation();
} catch (err) {
  Sentry.captureException(err);
}

// Capture with extra context
try {
  await riskyOperation();
} catch (err) {
  Sentry.captureException(err, {
    tags: { feature: "checkout", region: "eu" },
    extra: { cartId: "abc-123", itemCount: 3 },
    level: "error",   // "fatal" | "error" | "warning" | "info" | "debug"
  });
}

// Plain message (not tied to an exception)
Sentry.captureMessage("User exceeded rate limit", "warning");

// Isolated scope — doesn't pollute global state
Sentry.withScope((scope) => {
  scope.setTag("component", "PaymentForm");
  scope.setUser({ id: "42", email: "user@example.com" });
  Sentry.captureException(new Error("Payment failed"));
});
```

* * *

## Context Enrichment

### User Context

```typescript
// Set globally — persists until cleared
Sentry.setUser({
  id: "user-123",
  email: "jane@example.com",
  username: "jdoe",
  ip_address: "{{ auto }}",  // auto-infer from request
  plan: "enterprise",        // custom fields accepted
});

// Clear on logout
Sentry.setUser(null);
```

### Tags (searchable, indexed)

```typescript
Sentry.setTag("release.channel", "beta");
Sentry.setTags({
  "checkout.step": "payment",
  region: "us-east-1",
  version: "2.1.0",
});
```

Key constraints: ≤32 chars, alphanumeric + `_`, `.`, `:`, `-`. Value: ≤200 chars, no
newlines.

### Context Objects (structured, non-indexed)

```typescript
Sentry.setContext("cart", {
  itemCount: 3,
  totalAmount: 99.99,
  promoCode: "SAVE20",
});

// Clear context
Sentry.setContext("cart", null);
```

### Extra Data (simple key-value)

```typescript
Sentry.setExtra("requestBody", { amount: 99.99, currency: "USD" });
Sentry.setExtras({ cartItems: 3, promoCode: "SAVE20" });
```

### `initialScope` (set once at init)

```typescript
Sentry.init({
  dsn: "...",
  initialScope: {
    tags: { appVersion: "1.0.0", deploymentId: "abc123" },
    user: { id: "anonymous" },
  },
  // Or as a callback:
  // initialScope: (scope) => { scope.setTag("buildId", BUILD_ID); return scope; },
});
```

* * *

## Breadcrumbs

```typescript
// Manual breadcrumb
Sentry.addBreadcrumb({
  message: "User submitted checkout form",
  category: "ui.click",
  level: "info",   // "fatal"|"error"|"warning"|"log"|"info"|"debug"
  type: "user",    // "default"|"debug"|"error"|"info"|"navigation"|"http"|"query"|"ui"|"user"
  data: { formId: "checkout-v2", itemCount: 3 },
});

// Auth breadcrumb
Sentry.addBreadcrumb({
  category: "auth",
  message: "Authenticated user " + user.email,
  level: "info",
});
```

**Auto-captured breadcrumbs (browser):** DOM clicks, keyboard events, XHR/fetch
requests, console calls, navigation changes.

### Filter breadcrumbs with `beforeBreadcrumb`

```typescript
Sentry.init({
  beforeBreadcrumb(breadcrumb, hint) {
    // Drop verbose console breadcrumbs
    if (breadcrumb.category === "console") return null;
    // Sanitize navigation data
    if (breadcrumb.category === "navigation" && breadcrumb.data?.to) {
      breadcrumb.data.to = breadcrumb.data.to.replace(/\/user\/\d+/, "/user/[id]");
    }
    return breadcrumb;
  },
});
```

* * *

## `beforeSend` — Filter and Scrub Events

```typescript
Sentry.init({
  // Drop known noise
  ignoreErrors: [
    "ResizeObserver loop limit exceeded",
    /^Network Error$/,
    /ChunkLoadError/,
  ],

  // Only capture errors from your own scripts
  allowUrls: [/https:\/\/myapp\.com/],

  // Scrub PII, drop by condition
  beforeSend(event, hint) {
    // Drop non-Error objects
    if (hint.originalException && !(hint.originalException instanceof Error)) {
      return null;
    }
    // Scrub email from user context
    if (event.user?.email) {
      event.user.email = "[filtered]";
    }
    // Drop 404 errors
    if (event.tags?.statusCode === "404") {
      return null;
    }
    return event;
  },
});
```

* * *

## Svelte Component Tracking (`@sentry/svelte` only)

Component tracking wraps Svelte’s lifecycle hooks and emits spans for each component’s
`init` and `update` phases.

### Automatic (preprocessor — all components)

```javascript
// svelte.config.js
import { withSentryConfig } from "@sentry/svelte";

export default withSentryConfig(
  { compilerOptions: {} },
  {
    componentTracking: {
      trackComponents: true,   // true = all, or array: ["Navbar", "LoginForm"]
      trackInit: true,         // emit ui.svelte.init spans
      trackUpdates: true,      // emit ui.svelte.update spans
    },
  }
);
```

Spans emitted:
- `ui.svelte.init` — component instantiation → `onMount`
- `ui.svelte.update` — `beforeUpdate` → `afterUpdate`

### Manual (per-component)

```svelte
<script>
  import * as Sentry from "@sentry/svelte";

  Sentry.trackComponent({
    trackInit: true,
    trackUpdates: false,
    componentName: "PaymentForm",  // optional; auto-detected if omitted
  });
</script>
```

* * *

## SvelteKit `+error.svelte` Integration

SvelteKit renders `+error.svelte` for handled errors.
You can surface the Sentry event ID in the error page for user feedback:

```svelte
<!-- src/routes/+error.svelte -->
<script>
  import { page } from "$app/stores";
  import * as Sentry from "@sentry/sveltekit";

  // Show user feedback dialog tied to the last captured event
  function showFeedback() {
    const eventId = Sentry.lastEventId();
    if (eventId) {
      Sentry.showReportDialog({ eventId });
    }
  }
</script>

<h1>{$page.status}: {$page.error?.message}</h1>
<button onclick={showFeedback}>Report this issue</button>
```

* * *

## Error Boundaries (Svelte 5+)

> Requires Svelte 5 + `@sveltejs/kit` ≥2.x. Catches errors thrown in child components
> before they propagate to the page.

`<svelte:boundary>` prevents a component subtree from crashing the whole page and lets
you report the error to Sentry and optionally display a fallback UI:

```svelte
<script>
  import * as Sentry from "@sentry/sveltekit";
</script>

<svelte:boundary onerror={(error, reset) => {
  Sentry.captureException(error);
}}>
  <RiskyComponent />

  {#snippet failed(error, reset)}
    <p>Something went wrong.</p>
    <button onclick={reset}>Try again</button>
  {/snippet}
</svelte:boundary>
```

**Tips:**
- `onerror` fires synchronously before Svelte tears down the subtree — safe to call
  `captureException` here
- `reset` re-mounts the boundary subtree; pair it with `Sentry.lastEventId()` +
  `Sentry.showReportDialog()` for user feedback
- Nest multiple boundaries to isolate independent widgets — a failure in one won’t
  affect others
- Works in both client and server-rendered pages; server-side errors are still captured
  via `hooks.server.ts`

```svelte
<!-- With user feedback dialog on reset -->
<svelte:boundary onerror={(error) => {
  Sentry.captureException(error);
}}>
  <DataWidget />

  {#snippet failed(error, reset)}
    <button onclick={() => {
      const eventId = Sentry.lastEventId();
      if (eventId) Sentry.showReportDialog({ eventId });
      reset();
    }}>Report &amp; retry</button>
  {/snippet}
</svelte:boundary>
```

* * *

## Scopes: `withScope` vs Persistent Context

> Minimum SDK: `@sentry/sveltekit` ≥8.0.0 for isolation scopes; ≥10.32.0 for
> `getGlobalScope`/`getIsolationScope`

| API | Lifetime | Use case |
| --- | --- | --- |
| `Sentry.withScope(fn)` | Isolated to callback | One-off context for a single capture |
| `Sentry.getIsolationScope()` | Per-request (SvelteKit server) | Persistent context scoped to one request |
| `Sentry.getGlobalScope()` | Entire process lifetime | App-wide context (version tags, env) |

> **Note:** `Sentry.configureScope()` is deprecated since SDK v8. Use
> `getIsolationScope()` or `getGlobalScope()` instead.

```typescript
// withScope — temporary, doesn't affect subsequent events
Sentry.withScope((scope) => {
  scope.setTag("component", "checkout");
  Sentry.captureException(err);  // only this event gets the tag
});

// Set persistent scope data (per-request in SvelteKit server)
const scope = Sentry.getIsolationScope();
scope.setTag("tenant", session.tenantId);
scope.setUser({ id: session.userId });

// App-wide context (set once at startup)
const globalScope = Sentry.getGlobalScope();
globalScope.setTag("app.version", "1.0.0");
```

* * *

## Svelte vs SvelteKit: Key Differences

| Concern | Standalone Svelte | SvelteKit |
| --- | --- | --- |
| Error hook files | None — errors via `window.onerror` only | `hooks.client.ts` + `hooks.server.ts` |
| Server-side errors | N/A (client-only) | Auto via `handleErrorWithSentry()` |
| Component errors | `window.onerror` catches uncaught ones | Same + SvelteKit route error handling |
| `+error.svelte` | N/A | Add `Sentry.lastEventId()` for feedback |
| Scope per request | N/A | SvelteKit isolation scope per request |

* * *

## Best Practices

- Export `handleError = Sentry.handleErrorWithSentry()` from **both** hook files in
  SvelteKit — server errors are missed if only one is set
- User context is auto-populated by default via `dataCollection.userInfo` (SDK ≥10.57.0)
- Use `Sentry.withScope()` for one-off context, `Sentry.getIsolationScope()` /
  `Sentry.getGlobalScope()` for persistent context
- Scrub PII in `beforeSend` or use `dataCollection` options to control what data is
  collected
- Set `debug: true` during development to verify events are being captured

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Server errors not appearing | Confirm `handleErrorWithSentry()` is exported from `hooks.server.ts` |
| Client errors not appearing | Confirm `handleErrorWithSentry()` is exported from `hooks.client.ts` |
| `ignoreErrors` patterns not working | Use `RegExp` for patterns with special chars; string values are treated as regex |
| `beforeSend` returning `null` but events still sent | Check that `beforeSendTransaction` is not what fires (different hook) |
| Component tracking not emitting spans | Ensure `withSentryConfig` wraps the config in `svelte.config.js`; requires tracing enabled |
| `Sentry.lastEventId()` returns undefined | Only populated after `captureException`/`captureMessage` or automatic capture |
| Events appear without user context | Call `Sentry.setUser()` after authentication, not inside `Sentry.init()` |
