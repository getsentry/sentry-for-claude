# Error Monitoring — Sentry React SDK

> Minimum SDK: `@sentry/react` ≥8.0.0+\
> `captureReactException()` requires `@sentry/react` ≥9.8.0\
> `reactErrorHandler()` requires `@sentry/react` ≥8.6.0

* * *

## How Automatic Capture Works

The React SDK hooks into the browser environment and captures errors automatically from
multiple layers:

| Layer | Mechanism | Integration |
| --- | --- | --- |
| Uncaught JS exceptions | `window.onerror` | `GlobalHandlers` (default on) |
| Unhandled promise rejections | `window.onunhandledrejection` | `GlobalHandlers` (default on) |
| Errors in `setTimeout` / `setInterval` / `requestAnimationFrame` | Patched browser APIs | `BrowserApiErrors` (default on) |
| React render errors (React <19) | `componentDidCatch` via `<ErrorBoundary>` | `Sentry.ErrorBoundary` |
| React render errors (React 19+) | `createRoot` hooks | `Sentry.reactErrorHandler()` |
| Console errors (optional) | Patched `console.error` | `CaptureConsole` (opt-in) |

### What Requires Manual Instrumentation

The global handlers only catch errors that **escape** your code.
These are silently swallowed without manual calls:

- Errors caught by your own `try/catch` blocks
- Errors swallowed by React Router’s default error boundary
- Business-logic failures (validation errors, unexpected states)
- Async errors inside `Promise.then()` chains where `.catch()` is attached
- User-visible conditions that aren’t exceptions (use `captureMessage`)

### Disabling or Customizing Automatic Capture

```javascript
Sentry.init({
  integrations: [
    Sentry.globalHandlersIntegration({
      onerror: true,
      onunhandledrejection: false,  // handle rejections manually
    }),
  ],
});

// Manual rejection handler:
window.addEventListener("unhandledrejection", (event) => {
  Sentry.captureException(event.reason);
});
```

* * *

## React Error Boundaries

### Strategy: React 19+ vs. React ≤18

|  | React ≤18 | React 19+ |
| --- | --- | --- |
| **Global error reporting** | `window.onerror` + `Sentry.ErrorBoundary` | `Sentry.reactErrorHandler()` on `createRoot` |
| **Scoped fallback UI** | `<Sentry.ErrorBoundary>` | `<Sentry.ErrorBoundary>` (still required) |
| **Complementary?** | N/A | ✅ Use both together |

* * *

### React 19+ — `Sentry.reactErrorHandler()` with `createRoot`

React 19 exposes three hooks on `createRoot` and `hydrateRoot`. Pass
`Sentry.reactErrorHandler()` to each one.
Requires `@sentry/react` ≥8.6.0.

```jsx
// src/main.tsx
import { createRoot } from "react-dom/client";
import * as Sentry from "@sentry/react";

Sentry.init({ dsn: "___PUBLIC_DSN___" });

const container = document.getElementById("app")!;

createRoot(container, {
  // Fires for errors that bubble up WITHOUT any ErrorBoundary catching them.
  // These are fatal — the entire React tree unmounts.
  onUncaughtError: Sentry.reactErrorHandler((error, errorInfo) => {
    // Optional: runs AFTER Sentry has already captured the error
    console.warn("Uncaught React error:", error.message);
    console.warn("Component stack:", errorInfo.componentStack);
  }),

  // Fires for errors caught BY an ErrorBoundary (React 19 re-routes caught errors here).
  // The boundary still renders its fallback UI — this is just the reporting hook.
  onCaughtError: Sentry.reactErrorHandler(),

  // Fires when React recovers from an error automatically (e.g. hydration mismatch).
  onRecoverableError: Sentry.reactErrorHandler(),
}).render(<App />);
```

**SSR / `hydrateRoot`:**

```jsx
import { hydrateRoot } from "react-dom/client";
import * as Sentry from "@sentry/react";

hydrateRoot(document.getElementById("app")!, <App />, {
  onUncaughtError: Sentry.reactErrorHandler(),
  onCaughtError: Sentry.reactErrorHandler(),
  onRecoverableError: Sentry.reactErrorHandler(),
});
```

**Key behavior differences between the three hooks:**

| Hook | Fires when … | Tree state after |
| --- | --- | --- |
| `onUncaughtError` | Error escapes all boundaries | Tree unmounts (fatal) |
| `onCaughtError` | ErrorBoundary catches the error | Boundary renders fallback |
| `onRecoverableError` | React auto-recovers (e.g. hydration) | Tree continues rendering |

#### React 19 + ErrorBoundary Together (Recommended Pattern)

`reactErrorHandler()` is the global net.
`<Sentry.ErrorBoundary>` provides scoped fallback UIs.
Use both:

```jsx
// src/main.tsx — global net via reactErrorHandler
createRoot(document.getElementById("root")!, {
  onUncaughtError: Sentry.reactErrorHandler(),
  onCaughtError: Sentry.reactErrorHandler(),
  onRecoverableError: Sentry.reactErrorHandler(),
}).render(<App />);

// src/App.tsx — scoped fallback UIs via ErrorBoundary
function App() {
  return (
    <Layout>
      <Sentry.ErrorBoundary fallback={<NavError />}>
        <Navigation />
      </Sentry.ErrorBoundary>
      <Sentry.ErrorBoundary fallback={<DashboardError />}>
        <Dashboard />
      </Sentry.ErrorBoundary>
    </Layout>
  );
}
```

* * *

### `<Sentry.ErrorBoundary>` — Full Props Reference

Works with React 16+. Catches errors in its subtree, reports them to Sentry, and renders
a fallback UI.

```typescript
// Full TypeScript signature
interface ErrorBoundaryProps {
  // Fallback UI — static element or render function
  fallback?: React.ReactNode | FallbackRender;
  // FallbackRender receives: { error: Error; componentStack: string; resetError: () => void }

  // Called immediately when a child throws
  onError?: (error: Error, componentStack: string, eventId: string) => void;

  // Called with the Sentry Scope before the error is captured — enrich here
  beforeCapture?: (scope: Scope, error: Error, componentStack: string) => void;

  // Called when resetError() is invoked from the fallback
  onReset?: (error: Error | null, componentStack: string | null, eventId: string | null) => void;

  // Lifecycle hooks
  onMount?: () => void;
  onUnmount?: (error: Error | null) => void;

  // User feedback dialog — shown automatically on error
  showDialog?: boolean;
  dialogOptions?: ReportDialogOptions;
}
```

* * *

#### `fallback` — Render Fallback UI on Error

```jsx
// 1. Static element
<Sentry.ErrorBoundary fallback={<p>Something went wrong. Please refresh.</p>}>
  <Dashboard />
</Sentry.ErrorBoundary>

// 2. Render function — access error details and reset handler
<Sentry.ErrorBoundary
  fallback={({ error, componentStack, resetError }) => (
    <div className="error-state">
      <h2>Something broke</h2>
      <p><strong>Error:</strong> {error.message}</p>
      <details>
        <summary>Component stack</summary>
        <pre style={{ fontSize: 12 }}>{componentStack}</pre>
      </details>
      <button onClick={resetError}>↺ Try Again</button>
    </div>
  )}
>
  <Dashboard />
</Sentry.ErrorBoundary>
```

**`resetError()`** resets the boundary’s internal state and re-attempts rendering
children. Use it for retry UIs.

* * *

#### `onError` — React to a Captured Error

Called immediately when a child throws.
Receives the error, component stack, and the Sentry event ID (useful for linking user
feedback to the event).

```jsx
<Sentry.ErrorBoundary
  onError={(error, componentStack, eventId) => {
    // Report to your own analytics
    myAnalytics.track("error_boundary_triggered", {
      errorMessage: error.message,
      sentryEventId: eventId,
    });
    // Dispatch to Redux or Zustand
    store.dispatch(setGlobalError({ error, eventId }));
    // Show feedback dialog linked to this event
    Sentry.showReportDialog({ eventId });
  }}
  fallback={<ErrorScreen />}
>
  <App />
</Sentry.ErrorBoundary>
```

* * *

#### `beforeCapture` — Enrich the Event Before Sending

Called with the Sentry `Scope` before the error is captured.
Use it to add tags, context, or level enrichment specific to this boundary’s location in
the tree.

```jsx
<Sentry.ErrorBoundary
  beforeCapture={(scope, error, componentStack) => {
    scope.setTag("section", "checkout");
    scope.setTag("error_type", error.constructor.name);
    scope.setExtra("componentStack", componentStack);
    scope.setLevel("fatal");
    scope.setContext("payment", { step: "card-entry" });
  }}
  fallback={<CheckoutError />}
>
  <CheckoutFlow />
</Sentry.ErrorBoundary>
```

* * *

#### `onReset` — Cleanup When the Boundary Resets

Called when `resetError()` is invoked.
Clear stale state in stores or invalidate caches here.

```jsx
<Sentry.ErrorBoundary
  onReset={(error, componentStack, eventId) => {
    queryClient.clear();
    store.dispatch(clearCheckoutState());
  }}
  fallback={({ resetError }) => (
    <div>
      <p>Payment failed to load.</p>
      <button onClick={resetError}>Retry</button>
    </div>
  )}
>
  <CheckoutFlow />
</Sentry.ErrorBoundary>
```

* * *

#### `showDialog` + `dialogOptions` — Crash-Report Modal on Error

```jsx
<Sentry.ErrorBoundary
  showDialog
  dialogOptions={{
    title: "It looks like something went wrong.",
    subtitle: "Our engineering team has been notified.",
    subtitle2: "Want to help us fix it? Tell us what happened.",
    labelName: "Your name",
    labelEmail: "Your email",
    labelComments: "What happened before this error?",
    labelSubmit: "Send Report",
    successMessage: "Thanks! Your report helps us improve.",
    user: { email: "currentuser@example.com", name: "Jane Smith" },
  }}
  fallback={<p>We've logged this issue and are working on a fix.</p>}
>
  <Dashboard />
</Sentry.ErrorBoundary>
```

* * *

#### `onMount` / `onUnmount` — Lifecycle Hooks

```jsx
<Sentry.ErrorBoundary
  onMount={() => analytics.track("error_boundary_mounted", { section: "dashboard" })}
  onUnmount={(error) => {
    if (error) analytics.track("error_boundary_active_on_unmount");
  }}
  fallback={<DashboardError />}
>
  <Dashboard />
</Sentry.ErrorBoundary>
```

* * *

### `Sentry.withErrorBoundary(Component, options)` — HOC Pattern

Equivalent to wrapping with `<Sentry.ErrorBoundary>`. Useful when you want to wrap at
the import or module level instead of in JSX.

```jsx
import * as Sentry from "@sentry/react";

// Basic
const SafeDashboard = Sentry.withErrorBoundary(Dashboard, {
  fallback: <p>Dashboard failed to load.</p>,
});

// Full options — identical to ErrorBoundary props
const SafeCheckout = Sentry.withErrorBoundary(CheckoutFlow, {
  fallback: ({ error, resetError }) => (
    <div>
      <p>Checkout error: {error.message}</p>
      <button onClick={resetError}>Retry</button>
    </div>
  ),
  onError: (error, componentStack, eventId) => {
    analytics.track("checkout_boundary_triggered", { eventId });
  },
  beforeCapture: (scope) => {
    scope.setTag("section", "checkout");
    scope.setLevel("fatal");
  },
  showDialog: true,
});

// Use exactly like the unwrapped component
function App() {
  return <SafeCheckout />;
}
```

* * *

### Nested Error Boundaries — Isolation Pattern

Each boundary only catches errors from **its own subtree**. Nesting lets one broken
feature fail in isolation without crashing the whole page.

```jsx
function App() {
  return (
    // Outermost — catches anything that escapes inner boundaries
    <Sentry.ErrorBoundary
      fallback={<FullPageError />}
      beforeCapture={(scope) => scope.setTag("level", "app")}
    >
      <Layout>
        <Sentry.ErrorBoundary
          fallback={<NavError />}
          beforeCapture={(scope) => scope.setTag("section", "navigation")}
        >
          <Navigation />
        </Sentry.ErrorBoundary>

        <main>
          <Sentry.ErrorBoundary
            fallback={<SidebarError />}
            beforeCapture={(scope) => scope.setTag("section", "sidebar")}
          >
            <Sidebar />
          </Sentry.ErrorBoundary>

          <Sentry.ErrorBoundary
            fallback={<ContentError />}
            beforeCapture={(scope) => scope.setTag("section", "content")}
          >
            <MainContent />
          </Sentry.ErrorBoundary>
        </main>
      </Layout>
    </Sentry.ErrorBoundary>
  );
}
```

**Recommended placement strategy:**

| Boundary location | Purpose |
| --- | --- |
| Outermost (around `<App>`) | Last resort — prevents total blank page |
| Route level | Isolate route failures; different fallback per route |
| Widget / panel level | Let other panels stay functional when one fails |
| Data-fetching components | Catch errors from async rendering |

* * *

### Custom Class-Based Error Boundaries — `captureReactException`

> Requires `@sentry/react` ≥9.8.0

If you need a custom class boundary, use `captureReactException` instead of
`captureException`. It correctly attaches the React `componentStack` as a linked cause
via the `LinkedErrors` integration, producing readable component traces in Sentry.

```jsx
import * as Sentry from "@sentry/react";

class CustomBoundary extends React.Component {
  state = { hasError: false };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error, errorInfo) {
    // errorInfo = { componentStack: "\n  at Dashboard\n  at App..." }
    // captureReactException wires up the componentStack correctly
    Sentry.captureReactException(error, errorInfo);
  }

  render() {
    if (this.state.hasError) return <p>Something went wrong.</p>;
    return this.props.children;
  }
}
```

> **Why not plain `captureException`?** Calling `captureException` inside
> `componentDidCatch` loses the component stack linkage.
> `captureReactException` correctly wires `error.cause` so the component tree appears as
> a linked error in Sentry’s issue detail view.

**What linked errors look like in Sentry:**

```
Error: Cannot read properties of undefined (reading 'map')
  at Dashboard (Dashboard.tsx:42)
Caused by: React component stack:
  at Dashboard
  at Sentry.ErrorBoundary
  at App
```

> Requires React 17+ and the `LinkedErrors` integration (enabled by default).
> Set up source maps for readable component file paths.

* * *

## Manual Error Capture

### `Sentry.captureException(error, captureContext?)`

Captures an error and sends it to Sentry.
Prefer `Error` objects (they include stack traces).
Non-`Error` values (strings, plain objects) are accepted but may lack stack traces.

```javascript
// Basic usage
try {
  riskyOperation();
} catch (err) {
  Sentry.captureException(err);
}

// With full capture context
try {
  await chargeCard(order);
} catch (err) {
  Sentry.captureException(err, {
    level: "fatal",                          // "fatal"|"error"|"warning"|"log"|"info"|"debug"
    tags: { module: "checkout", retried: "true" },
    extra: { cartItems: 3, coupon: "SAVE20" },
    user: { id: "u_123", email: "user@example.com" },
    fingerprint: ["checkout-payment-fail"],  // custom grouping key
    contexts: {
      payment: { provider: "stripe", amount: 9999, currency: "usd" },
    },
  });
}
```

**React-specific tip:** Avoid calling Sentry in the render path.
Wrap Sentry calls in `useEffect` to prevent firing on every render:

```jsx
function UserProfile({ userId }) {
  const { data: profile, error } = useQuery(["user", userId], fetchUser);

  useEffect(() => {
    if (error) {
      Sentry.captureException(error, {
        tags: { component: "UserProfile" },
        extra: { userId },
      });
    }
  }, [error, userId]);

  if (error) return <p>Failed to load profile.</p>;
  return profile ? <Profile data={profile} /> : null;
}
```

* * *

### `Sentry.captureMessage(message, level?)`

Captures a plain-text message as a Sentry issue.
Useful for non-exception events: deprecated API calls, suspicious conditions, rate-limit
hits.

```javascript
// With level as second argument
Sentry.captureMessage("Payment gateway timeout — fallback triggered", "warning");

// All valid levels: "fatal" | "error" | "warning" | "log" | "info" | "debug"
// Default when omitted: "info"

// With full capture context as second argument
Sentry.captureMessage("Payment gateway timeout — fallback triggered", {
  level: "error",
  tags: { service: "payments", gateway: "stripe" },
  extra: { userId: "u_42", orderId: "ord_42" },
});
```

* * *

### `Sentry.captureEvent(event)`

Low-level API for sending a fully constructed Sentry event object.
Use `captureException` or `captureMessage` in application code.
`captureEvent` is for custom integrations or forwarding events from legacy loggers.

```javascript
Sentry.captureEvent({
  message: "Legacy logger forwarded event",
  level: "warning",
  tags: { source: "legacy-logger", module: "billing" },
  extra: { rawLog: "something went wrong at line 42" },
  timestamp: Date.now() / 1000,  // Unix timestamp in seconds
  fingerprint: ["legacy-billing-error"],
});
```

* * *

### Try/Catch Patterns in React

**Event handlers** — errors here are NOT caught by error boundaries (boundaries only
catch render errors):

```jsx
function PaymentForm() {
  const [status, setStatus] = useState("idle");

  async function handleSubmit(event) {
    event.preventDefault();
    setStatus("loading");
    try {
      await processPayment(getFormValues(event.target));
      setStatus("success");
    } catch (err) {
      setStatus("error");
      Sentry.captureException(err, {
        tags: { component: "PaymentForm", action: "submit" },
        extra: { formFields: Object.fromEntries(new FormData(event.target)) },
      });
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      {/* form fields */}
      <button type="submit" disabled={status === "loading"}>
        {status === "loading" ? "Processing..." : "Pay"}
      </button>
      {status === "error" && <p>Payment failed. Please try again.</p>}
    </form>
  );
}
```

**Async operations in effects:**

```jsx
useEffect(() => {
  async function loadData() {
    try {
      const data = await fetchDashboardData();
      setData(data);
    } catch (err) {
      Sentry.captureException(err, {
        tags: { hook: "useEffect", data: "dashboard" },
      });
      setError(err);
    }
  }
  loadData();
}, []);
```

**Promise chains:**

```javascript
fetchUserData(userId)
  .then(processUser)
  .catch((err) => {
    Sentry.captureException(err, {
      tags: { operation: "fetchUserData" },
      extra: { userId },
    });
    return null; // graceful fallback
  });
```

* * *

## Context Enrichment

### `Sentry.setUser(user)` — Identify the Current User

Associates a user identity with all subsequent events.
Call after login; call `Sentry.setUser(null)` on logout.

```typescript
// Accepted fields (all optional):
interface SentryUser {
  id?: string | number;     // your internal user ID
  email?: string;
  username?: string;
  ip_address?: string;      // "{{ auto }}" to infer from request
  segment?: string;         // e.g. "paid", "trial", "beta", "enterprise"
  // Any additional custom fields are accepted
}
```

```javascript
// On login:
Sentry.setUser({
  id: "usr_abc123",
  email: "jane.smith@example.com",
  username: "janesmith",
  segment: "enterprise",
  // Custom fields:
  plan: "pro",
  team_id: "team_789",
  account_age_days: 365,
});

// On logout — clears user from all subsequent events:
Sentry.setUser(null);

// Auto-infer IP address (userInfo defaults to true):
Sentry.setUser({
  id: "usr_abc123",
  ip_address: "{{ auto }}",
});
```

> **Privacy:** `userInfo` (in `dataCollection`) defaults to `true`, which enables
> automatic IP inference.
> Set `dataCollection: { userInfo: false }` to opt out, or enable “Prevent Storing of IP
> Addresses” in your project’s Security & Privacy settings in Sentry to prevent IP
> storage entirely.

* * *

### `Sentry.setContext(name, data)` — Attach Structured Custom Data

Attaches arbitrary structured data to all subsequent events.
Context is **not indexed or searchable** — use tags for filterable data.
Context appears in the issue detail view.

```javascript
// E-commerce checkout context
Sentry.setContext("checkout", {
  step: "payment",
  cart_items: 3,
  total_usd: 99.99,
  coupon_applied: "SAVE20",
  payment_provider: "stripe",
});

// Structured product context (not feature-flag tracking — use feature-flags.md)
Sentry.setContext("experiment", {
  name: "checkout_layout",
  cohort: "variant_b",
});

// Remove a context:
Sentry.setContext("checkout", null);
```

> **Depth:** Sentry normalizes context to **3 levels deep** by default.
> Adjust via `normalizeDepth` in `Sentry.init`. The key `type` is reserved — don’t use
> it in context objects.

* * *

### `Sentry.setTag(key, value)` / `Sentry.setTags(tags)` — Searchable Key-Value Pairs

Tags are **indexed and searchable**. They power Sentry’s filter sidebar, tag
distribution charts, and issue similarity detection.
Use tags for any data you want to filter or aggregate on.

**Constraints:** Key ≤32 chars (`a-z A-Z 0-9 _ . : -`, no spaces).
Value ≤200 chars, no newlines.

```javascript
// Single tag
Sentry.setTag("page_locale", "de-at");
Sentry.setTag("user_plan", "enterprise");
Sentry.setTag("app_version", "2.4.1");

// Multiple at once
Sentry.setTags({
  "release.stage": "canary",
  "tenant.id": "tenant_abc",
  "browser.engine": "blink",
});

// Per-event inline (does not persist to subsequent events)
Sentry.captureException(err, {
  tags: { component: "PaymentForm", retry_attempt: "2" },
});

// Scoped — only applies within the callback
Sentry.withScope((scope) => {
  scope.setTag("operation", "bulk-delete");
  Sentry.captureException(deleteError);
});
// "operation" tag does NOT appear on subsequent events
```

> Do not overwrite Sentry’s built-in tags (`browser`, `os`, `url`, `environment`,
> `release`). Use your own namespaced keys.

* * *

### `Sentry.setExtra(key, value)` / `Sentry.setExtras(extras)` — Arbitrary Data

For loosely-typed supplementary data.
Prefer `setContext` for structured data with a meaningful group name.

```javascript
Sentry.setExtra("raw_api_response", responseText);
Sentry.setExtra("debug_state_dump", JSON.stringify(stateSnapshot));

Sentry.setExtras({
  component_version: "3.2.1",
  last_action: "submit_form",
  form_fields: { total: 5, valid: 3, invalid: 2 },
});
```

* * *

### Inline Context on Capture Calls

All context can be provided per-event using the second argument to `captureException` or
`captureMessage`. This is the cleanest approach for one-off enrichment:

```javascript
Sentry.captureException(err, {
  user: { id: "u_42", email: "user@example.com" },
  level: "fatal",
  tags: { module: "checkout", payment_provider: "stripe" },
  extra: { formState: JSON.stringify(formValues) },
  contexts: {
    payment: { provider: "stripe", last4: "4242", amount_cents: 9999 },
  },
  fingerprint: ["{{ default }}", "stripe-card-error"],
});
```

* * *

## Breadcrumbs

Breadcrumbs are a structured trail of events leading up to an error.
They’re buffered locally and attached to the next event sent to Sentry.

### Automatic Breadcrumbs (Zero Config)

| Type | What’s Captured |
| --- | --- |
| `ui.click` | DOM element clicks (CSS selector or component name if annotation enabled) |
| `ui.input` | Keyboard/input interactions |
| `navigation` | URL changes: `pushState`, `popstate`, hash changes |
| `http` | XHR and `fetch` requests (URL, method, status code) |
| `console` | `console.log`, `warn`, `error`, `info`, `debug` output |
| `sentry` | SDK-internal events |

* * *

### `Sentry.addBreadcrumb(breadcrumb)` — Manual Breadcrumbs

```typescript
interface Breadcrumb {
  type?:      "default" | "debug" | "error" | "info" | "navigation" | "http" | "query" | "ui" | "user";
  category?:  string;      // dot-namespaced: "auth", "ui.click", "api.request"
  message?:   string;      // human-readable description
  level?:     "fatal" | "error" | "warning" | "log" | "info" | "debug";
  timestamp?: number;      // Unix timestamp in seconds (auto-set if omitted)
  data?:      Record<string, unknown>;
}
```

```javascript
// Auth events
Sentry.addBreadcrumb({
  category: "auth",
  message: "User logged in",
  level: "info",
  data: { userId: "u_42", method: "oauth2", provider: "google" },
});

Sentry.addBreadcrumb({
  category: "auth",
  message: "Token refresh failed",
  level: "warning",
  type: "error",
  data: { reason: "expired", expiredAt: "2024-01-15T10:00:00Z" },
});

// Navigation
Sentry.addBreadcrumb({
  type: "navigation",
  category: "navigation",
  message: "User navigated to checkout",
  data: { from: "/cart", to: "/checkout/payment" },
});

// API call outcome
Sentry.addBreadcrumb({
  type: "http",
  category: "api.request",
  message: "POST /api/orders",
  level: "info",
  data: {
    url: "/api/orders",
    method: "POST",
    status_code: 422,
    reason: "Validation failed",
  },
});

// User actions
Sentry.addBreadcrumb({
  type: "user",
  category: "ui.click",
  message: "Clicked 'Place Order' button",
  data: { orderId: "ord_xyz", itemCount: 3, total: 99.99 },
});

// State machine transitions
Sentry.addBreadcrumb({
  category: "state",
  type: "debug",
  message: "State machine transitioned",
  level: "debug",
  data: { from: "PENDING", to: "PROCESSING", trigger: "user_submit" },
});
```

* * *

### Filtering Breadcrumbs — `beforeBreadcrumb`

Configured in `Sentry.init`. Return `null` to discard a breadcrumb entirely.

```javascript
Sentry.init({
  beforeBreadcrumb(breadcrumb, hint) {
    // Drop clicks on password fields (privacy)
    if (breadcrumb.category === "ui.click") {
      const target = hint?.event?.target;
      if (target?.type === "password") return null;
    }

    // Enrich XHR breadcrumbs with request body size
    if (breadcrumb.type === "http" && hint?.xhr) {
      breadcrumb.data = {
        ...breadcrumb.data,
        requestBodySize: hint.xhr.requestBody?.length ?? 0,
      };
    }

    // Drop verbose console.debug breadcrumbs in production
    if (breadcrumb.category === "console" && breadcrumb.level === "debug") {
      return null;
    }

    return breadcrumb;
  },
});
```

**`maxBreadcrumbs`** — Controls how many breadcrumbs are stored.
Default: 100. Set in `Sentry.init`:

```javascript
Sentry.init({ maxBreadcrumbs: 50 });
```

* * *

## Scopes

Scopes are how Sentry attaches context (tags, user, breadcrumbs, extras) to events.
Three scope types are merged before each event is sent.

### The Three Scope Types

| Scope | API | Lifetime | Written by |
| --- | --- | --- | --- |
| **Global** | `Sentry.getGlobalScope()` | Entire process | You (set once) |
| **Isolation** | `Sentry.getIsolationScope()` | Current page/request | `Sentry.setTag()` etc. |
| **Current** | `Sentry.getCurrentScope()` | Innermost execution | `Sentry.withScope()` |

**Merge priority (later wins):**
```
Global → Isolation → Current → Event Sent
(lowest priority)              (highest priority)
```

* * *

### Global Scope — `Sentry.getGlobalScope()`

Applied to **every event** from anywhere in the app.
Use for universal data: app version, build ID, deployment region.

```javascript
const globalScope = Sentry.getGlobalScope();
globalScope.setTag("app_version", "2.4.1");
globalScope.setTag("build_id", import.meta.env.VITE_BUILD_ID);
globalScope.setContext("deployment", {
  region: "us-east-1",
  datacenter: "aws",
  env: "production",
});
```

> **Cannot capture events** — only stores data.

* * *

### Isolation Scope — `Sentry.getIsolationScope()`

In the **browser**, the isolation scope is effectively global — only one ever exists per
page load (unlike Node where it’s forked per request).
All top-level `Sentry.setXxx()` methods write here.

```javascript
// These two are identical in the browser:
Sentry.setTag("user_plan", "pro");
Sentry.getIsolationScope().setTag("user_plan", "pro");

// On login — persists for all subsequent events on this page:
Sentry.setUser({ id: "u_42", email: "user@example.com" });

// On logout — clears user from isolation scope:
Sentry.setUser(null);
```

> **Cannot capture events** — only stores data.

* * *

### `Sentry.withScope(callback)` — Scoped Modifications

Creates a **fork** of the current scope, active only within the callback.
Modifications do not leak to subsequent events.
The most important tool for per-event enrichment without polluting global state.

```javascript
// Add context to one specific capture only
Sentry.withScope((scope) => {
  scope.setTag("operation", "bulk-delete");
  scope.setLevel("warning");
  scope.setContext("bulk", { count: items.length, userId: currentUser.id });
  Sentry.captureException(deleteError);
});
// "operation" tag does NOT appear on any subsequent events

// Rich per-operation isolation
async function processPayment(order) {
  try {
    await stripe.charge(order);
  } catch (err) {
    Sentry.withScope((scope) => {
      scope.setTag("module", "payments");
      scope.setTag("payment_provider", "stripe");
      scope.setLevel("fatal");
      scope.setUser({ id: order.userId });
      scope.setContext("order", {
        id: order.id,
        amount: order.amount,
        currency: order.currency,
        items: order.items.length,
      });
      scope.setExtra("stripe_error_code", err.code);
      scope.addBreadcrumb({
        category: "payment",
        message: "Stripe charge attempt failed",
        level: "error",
        data: { stripeCode: err.code, message: err.message },
      });
      Sentry.captureException(err);
    });
  }
}

// addEventProcessor inside a scope — transform the event before it's sent
Sentry.withScope((scope) => {
  scope.addEventProcessor((event) => {
    event.tags = { ...event.tags, processed_by: "payment_handler" };
    return event;
  });
  Sentry.captureException(err);
});
```

* * *

### Scope Decision Guide

| Goal | API |
| --- | --- |
| Data on ALL events (app version, build ID) | `Sentry.getGlobalScope().setTag(...)` |
| Data on current page view / user session | `Sentry.setTag(...)` (isolation scope) |
| Data on ONE specific capture | `Sentry.withScope((scope) => { ... })` |
| Data inline on a single event | Second arg to `captureException(err, { tags: {...} })` |

> **Do NOT use `Sentry.configureScope()`** — deprecated since SDK v8. Use
> `getIsolationScope()` or `getGlobalScope()` instead.

* * *

## Event Filtering

### `beforeSend(event, hint)` — Modify or Drop Events

Called before every error event is sent.
Return `null` to drop the event.
Mutate `event` to scrub or enrich it.

```javascript
Sentry.init({
  beforeSend(event, hint) {
    const originalError = hint.originalException;

    // Drop non-Error rejections (e.g. cancelled requests)
    if (originalError && !(originalError instanceof Error)) {
      return null;
    }

    // Drop browser extension errors
    if (event.exception?.values?.[0]?.stacktrace?.frames?.some(
      frame => frame.filename?.includes("extension://")
    )) {
      return null;
    }

    // Drop 404 errors from event handlers
    if (originalError?.message?.includes("404")) {
      return null;
    }

    // Scrub PII from user context
    if (event.user?.email) {
      event.user = { ...event.user, email: "[filtered]" };
    }

    // Override fingerprint for known error patterns
    if (originalError?.message?.includes("ChunkLoadError")) {
      event.fingerprint = ["chunk-load-error"];
    }

    return event;
  },
});
```

**Accessing the original error from `hint`:**

```javascript
beforeSend(event, hint) {
  const error = hint.originalException;  // The original Error object
  const syntheticEvent = hint.syntheticException;  // SDK-generated error for messages

  if (error instanceof TypeError && error.message === "Failed to fetch") {
    // Enrich with tag instead of dropping
    event.tags = { ...event.tags, network_error: "true" };
  }
  return event;
}
```

* * *

### `ignoreErrors` — Pattern-Based Filtering

Array of string or RegExp patterns.
Events whose error message matches any pattern are silently dropped before `beforeSend`.

```javascript
Sentry.init({
  ignoreErrors: [
    // Exact strings (substring match):
    "ResizeObserver loop limit exceeded",
    "Non-Error exception captured",
    "Object Not Found Matching Id",

    // Regular expressions:
    /^Network Error$/,
    /ChunkLoadError/,
    /Loading chunk \d+ failed/,
    /^Script error\.?$/,       // cross-origin script errors with no details

    // Browser extension noise:
    "from accessing a cross-origin frame",
    /webkit-masked-url/,
  ],
});
```

* * *

### `allowUrls` / `denyUrls` — URL-Based Filtering

Only capture errors (or skip errors) from scripts at specific URLs.

```javascript
Sentry.init({
  // Only capture errors originating from your own scripts:
  allowUrls: [
    /https:\/\/yourapp\.com/,
    /https:\/\/cdn\.yourapp\.com/,
  ],

  // Skip errors from known third-party noise:
  denyUrls: [
    /extensions\//i,
    /^chrome:\/\//i,
    /^safari-extension:\/\//i,
    /gtm\.js/,
    /analytics\.js/,
  ],
});
```

* * *

### `sampleRate` — Capture Only a Fraction of Errors

```javascript
Sentry.init({
  sampleRate: 0.25,  // Capture 25% of errors (randomly sampled)
});
```

> Use `beforeSend` for conditional filtering (based on error type, URL, user).
> Use `sampleRate` for volume reduction when error rates are very high.

* * *

## Fingerprinting

### Default Grouping Behavior

Sentry groups errors into issues by default using a combination of: exception type,
exception message, and stack trace.
This works well for most cases but can produce false groupings for dynamic error
messages.

### Custom Fingerprinting

Override grouping by providing a `fingerprint` array on the event.

```javascript
// All Stripe card errors grouped together regardless of message:
Sentry.captureException(err, {
  fingerprint: ["stripe-card-error"],
});

// Use {{ default }} to extend (not replace) Sentry's default grouping:
Sentry.captureException(err, {
  fingerprint: ["{{ default }}", "payment-module"],
});

// Dynamic component — group by component name + error type:
Sentry.captureException(err, {
  fingerprint: ["DataGrid", err.constructor.name],
});
```

**Via `beforeSend` for pattern-based fingerprinting:**

```javascript
Sentry.init({
  beforeSend(event, hint) {
    const error = hint.originalException;

    // Group all network timeouts as one issue:
    if (error?.message?.includes("timeout")) {
      event.fingerprint = ["network-timeout"];
    }

    // Group chunk load failures as one issue:
    if (error?.name === "ChunkLoadError") {
      event.fingerprint = ["chunk-load-failure"];
    }

    return event;
  },
});
```

* * *

## User Feedback

### When to Use Which Mechanism

|  | `feedbackIntegration()` Widget | `Sentry.showReportDialog()` |
| --- | --- | --- |
| **Trigger** | Anytime — user-initiated | On error — automatic |
| **UI** | Floating button (bottom-right) | Modal overlay |
| **Requires error?** | No | Yes (`eventId` required) |
| **Screenshots** | Yes (SDK ≥8.0.0) | No |
| **Best for** | General feedback, bug reports | Post-crash reports |

* * *

### `feedbackIntegration()` — Persistent Feedback Widget

Adds a floating feedback button to the page.
Users submit feedback at any time — no error required.

```javascript
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  integrations: [
    Sentry.feedbackIntegration({
      colorScheme: "system", // "system" | "light" | "dark"
    }),
  ],
});
```

#### Complete Configuration Reference

```javascript
Sentry.feedbackIntegration({
  // ── Behavior ──────────────────────────────────────────────────────────
  autoInject: true,         // Auto-inject button into DOM. Set false for programmatic control.
  colorScheme: "system",    // "system" | "light" | "dark"
  showBranding: true,       // Show "Powered by Sentry" logo
  id: "sentry-feedback",    // Container div ID
  tags: {                   // Sentry tags on all feedback submissions
    product_area: "checkout",
    version: "2.4.1",
  },

  // ── User Fields ───────────────────────────────────────────────────────
  showName: true,
  showEmail: true,
  isNameRequired: false,
  isEmailRequired: false,
  enableScreenshot: true,   // Allow screenshot attachment (SDK ≥8.0.0, hidden on mobile)
  useSentryUser: {
    email: "email",         // Which Sentry user field maps to the email input
    name: "username",       // Which Sentry user field maps to the name input
  },

  // ── Labels / Text ─────────────────────────────────────────────────────
  triggerLabel: "Report a Bug",
  triggerAriaLabel: "Report a Bug",   // v8.20.0+
  formTitle: "Report a Bug",
  submitButtonLabel: "Send Bug Report",
  cancelButtonLabel: "Cancel",
  confirmButtonLabel: "Confirm",
  addScreenshotButtonLabel: "Add a screenshot",
  removeScreenshotButtonLabel: "Remove screenshot",
  nameLabel: "Name",
  namePlaceholder: "Your Name",
  emailLabel: "Email",
  emailPlaceholder: "your.email@example.org",
  isRequiredLabel: "(required)",
  messageLabel: "Description",
  messagePlaceholder: "What's the bug? What did you expect?",
  successMessageText: "Thank you for your report!",
  // Screenshot annotation labels (v10.10.0+):
  highlightToolText: "Highlight",
  hideToolText: "Hide",
  removeHighlightText: "Remove",

  // ── Theme Overrides ───────────────────────────────────────────────────
  themeLight: {
    foreground: "#2b2233",
    background: "#ffffff",
    accentForeground: "#ffffff",
    accentBackground: "#6a3fc8",
    successColor: "#268d75",
    errorColor: "#df3338",
  },
  themeDark: {
    foreground: "#ebe6ef",
    background: "#29232f",
    accentForeground: "#ffffff",
    accentBackground: "#6a3fc8",
    successColor: "#2da98c",
    errorColor: "#f55459",
  },

  // ── Callbacks ─────────────────────────────────────────────────────────
  onFormOpen: () => analytics.track("feedback_form_opened"),
  onFormClose: () => analytics.track("feedback_form_closed_without_submit"),
  onSubmitSuccess: (data, eventId) => {
    // data: { name, email, message }
    toast.success(`Thanks! Reference: ${eventId}`);
  },
  onSubmitError: (error) => {
    toast.error("Failed to submit feedback. Please try again.");
  },
})
```

**Programmatic control (when `autoInject: false`):**

```javascript
// In Sentry.init
const feedbackIntegration = Sentry.feedbackIntegration({ autoInject: false });
Sentry.init({ integrations: [feedbackIntegration] });

// Elsewhere — open the widget from a button:
document.getElementById("feedback-btn").addEventListener("click", () => {
  feedbackIntegration.openDialog();
});

// Or attach to a DOM element (converts it to a trigger):
feedbackIntegration.attachTo(document.getElementById("help-menu-item"));
```

* * *

### `Sentry.captureFeedback(feedback, hints?)` — Programmatic Feedback API

Submit feedback without any UI. Ideal for custom feedback forms you build yourself.

```javascript
// Basic
Sentry.captureFeedback({
  name: "John Doe",
  email: "john@example.com",
  message: "The export button does nothing on Firefox.",
});

// With capture context and attachments
Sentry.captureFeedback(
  {
    name: "Jane Smith",
    email: "jane@example.com",
    message: "Chart data looks wrong after filtering by date.",
  },
  {
    captureContext: {
      tags: { page: "analytics-dashboard", browser: navigator.userAgent },
      extra: { chartConfig: JSON.stringify(currentChartConfig) },
    },
    attachments: [
      {
        filename: "screenshot.png",
        data: new Uint8Array(screenshotBuffer),
        contentType: "image/png",
      },
    ],
  }
);
```

* * *

### `Sentry.showReportDialog(options)` — Crash-Report Modal

Shows a user-facing modal after an error.
**Requires** an `eventId` to link the feedback to a Sentry event.

**From `onError` in `ErrorBoundary`:**

```jsx
<Sentry.ErrorBoundary
  onError={(error, componentStack, eventId) => {
    Sentry.showReportDialog({
      eventId,
      user: { name: currentUser.name, email: currentUser.email },
    });
  }}
  fallback={<ErrorScreen />}
>
  <App />
</Sentry.ErrorBoundary>
```

**From `beforeSend`:**

```javascript
Sentry.init({
  beforeSend(event, hint) {
    if (event.exception && event.event_id) {
      Sentry.showReportDialog({ eventId: event.event_id });
    }
    return event;
  },
});
```

**From a manual catch:**

```javascript
function handleCriticalError(err) {
  const eventId = Sentry.captureException(err);
  Sentry.showReportDialog({
    eventId,
    user: { name: auth.user.displayName, email: auth.user.email },
    title: "It looks like we're having issues.",
    subtitle: "Our team has been notified.",
    subtitle2: "If you'd like to help, tell us what happened below.",
    labelComments: "Steps to reproduce:",
    labelSubmit: "Send Report",
    successMessage: "Your feedback has been sent. Thank you!",
  });
}
```

#### Complete `showReportDialog` Options

| Option | Type | Notes |
| --- | --- | --- |
| `eventId` | `string` | **Required.** Links feedback to the Sentry event |
| `dsn` | `string` | Override DSN (defaults to `Sentry.init` DSN) |
| `user.name` | `string` | Pre-fill the name field |
| `user.email` | `string` | Pre-fill the email field |
| `lang` | `string` | ISO language code (e.g. `"de"`, `"fr"`, `"ja"`) |
| `title` | `string` | Modal header text |
| `subtitle` | `string` | First subtitle line |
| `subtitle2` | `string` | Second subtitle line |
| `labelName` | `string` | Label for the name field |
| `labelEmail` | `string` | Label for the email field |
| `labelComments` | `string` | Label for the description field |
| `labelSubmit` | `string` | Submit button text |
| `labelClose` | `string` | Close button text |
| `successMessage` | `string` | Shown after successful submission |
| `onLoad` | `() => void` | Called when dialog opens |
| `onClose` | `() => void` | Called when dialog closes (v7.82.0+) |

* * *

## React Router — Critical Error Boundary Note

React Router’s **default error boundary silently discards errors in production**. Always
provide a custom `errorElement` that captures to Sentry:

```jsx
import { useRouteError } from "react-router-dom";
import * as Sentry from "@sentry/react";

function RootErrorBoundary() {
  const error = useRouteError();

  React.useEffect(() => {
    if (error instanceof Error) {
      Sentry.captureException(error, {
        tags: { source: "react-router-error-element" },
      });
    }
  }, [error]);

  return (
    <div>
      <h1>Something went wrong</h1>
      <p>{error instanceof Error ? error.message : "An unexpected error occurred."}</p>
      <button onClick={() => window.location.reload()}>Reload page</button>
    </div>
  );
}

const router = Sentry.wrapCreateBrowserRouterV6(createBrowserRouter)([
  {
    path: "/",
    element: <Layout />,
    errorElement: <RootErrorBoundary />,  // ← required
    children: [ /* your routes */ ],
  },
]);
```

* * *

## Quick Reference

```javascript
// ── Capture APIs ──────────────────────────────────────────────────────
Sentry.captureException(error)
Sentry.captureException(error, { level, tags, extra, contexts, fingerprint, user })
Sentry.captureMessage("text", "warning")
Sentry.captureMessage("text", { level, tags, extra })
Sentry.captureEvent({ message, level, tags, extra, timestamp })
Sentry.captureReactException(error, reactErrorInfo)   // ≥9.8.0 — custom class boundaries

// ── React 19+ Error Hooks ─────────────────────────────────────────────
createRoot(el, {
  onUncaughtError:   Sentry.reactErrorHandler(optionalCallback),
  onCaughtError:     Sentry.reactErrorHandler(),
  onRecoverableError: Sentry.reactErrorHandler(),
})
hydrateRoot(el, <App />, { /* same three hooks */ })

// ── Error Boundaries (React 16+) ──────────────────────────────────────
<Sentry.ErrorBoundary
  fallback={<UI /> | ({ error, componentStack, resetError }) => <UI />}
  onError={(error, stack, eventId) => {}}
  beforeCapture={(scope, error, stack) => {}}
  onReset={(error, stack, eventId) => {}}
  showDialog  dialogOptions={{}}
  onMount={() => {}}  onUnmount={(error) => {}}
>
Sentry.withErrorBoundary(Component, options)   // HOC equivalent

// ── Context ───────────────────────────────────────────────────────────
Sentry.setUser({ id, email, username, ip_address, segment, ...custom })
Sentry.setUser(null)                           // clear on logout
Sentry.setTag("key", "value")
Sentry.setTags({ key1: "v1", key2: "v2" })
Sentry.setContext("name", { key: value })      // structured, not searchable
Sentry.setContext("name", null)                // remove context
Sentry.setExtra("key", value)
Sentry.setExtras({ key1: v1 })

// ── Breadcrumbs ───────────────────────────────────────────────────────
Sentry.addBreadcrumb({ type, category, message, level, data, timestamp })

// ── Scopes ────────────────────────────────────────────────────────────
Sentry.withScope((scope) => { scope.setTag(...); Sentry.captureException(...) })
Sentry.getGlobalScope()          // all events, process lifetime
Sentry.getIsolationScope()       // current page/session (= Sentry.setTag etc.)
// DON'T: Sentry.configureScope() — deprecated since SDK v8

// ── Filtering ─────────────────────────────────────────────────────────
// Sentry.init({ beforeSend, ignoreErrors, allowUrls, denyUrls, sampleRate })

// ── User Feedback ─────────────────────────────────────────────────────
Sentry.feedbackIntegration({ colorScheme, autoInject, showName, isEmailRequired, ... })
Sentry.captureFeedback({ name, email, message }, { captureContext, attachments })
Sentry.showReportDialog({ eventId, user, title, subtitle, ... })
```

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Errors appearing twice in development | Expected behavior — React Strict Mode re-throws caught errors to the global handler. Validate in production builds only. |
| Missing component stack in issues | Requires React 17+. Ensure `LinkedErrors` integration is enabled (it is by default). |
| React Router errors not captured | React Router’s default boundary swallows errors. Add a custom `errorElement` that calls `captureException`. |
| `CaptureConsole` causing duplicates | React logs caught errors via `console.error`. Remove `CaptureConsole` or exclude `console.error` from its config. |
| `captureReactException` not available | Upgrade to `@sentry/react` ≥9.8.0. |
| `reactErrorHandler` not available | Upgrade to `@sentry/react` ≥8.6.0. |
| Errors captured without user context | Call `Sentry.setUser()` after login, not inside `Sentry.init`. It must be called after authentication completes. |
| `configureScope is not a function` | Deprecated in SDK v8. Replace with `getIsolationScope()` or `withScope()`. |
| Tags not appearing on events | Tags set via `Sentry.setTag()` go to the isolation scope; verify you’re not clearing it unexpectedly. |
| `showReportDialog` shows but has no event | Pass `eventId` from `Sentry.captureException(err)` return value or from `onError` prop. |
| `feedbackIntegration` button not appearing | Confirm `feedbackIntegration()` is in the `integrations` array in `Sentry.init`. Check for z-index conflicts. |
| `beforeSend` returning `null` but events still sent | Check `beforeSendTransaction` — a separate hook for performance events. Also verify no other SDK instance is active. |
| High event volume from known errors | Add patterns to `ignoreErrors`, or use `sampleRate` to reduce volume. Use `beforeSend` for type-specific filtering. |
| Errors from browser extensions captured | Add `/extensions\//i` and `/^chrome:\/\//i` to `denyUrls`. |
