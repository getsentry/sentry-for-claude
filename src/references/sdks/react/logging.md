# Logging — Sentry React SDK

> Minimum SDK: `@sentry/react` ≥9.41.0+ for `Sentry.logger` API and `enableLogs`\
> `consoleLoggingIntegration()`: requires ≥10.13.0+\
> Scope-based attributes (`getGlobalScope`, `getIsolationScope`): requires ≥10.32.0+

> ⚠️ **Not available via CDN/loader snippet** — NPM install required.

* * *

## Enabling Logs

`enableLogs` is opt-in and must be explicitly set in `Sentry.init()`:

```typescript
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  enableLogs: true, // Required — logging is disabled by default
});
```

Without `enableLogs: true`, all `Sentry.logger.*` calls are silently no-ops and nothing
is sent to Sentry.

* * *

## Logger API — Six Levels

```typescript
import * as Sentry from "@sentry/react";

Sentry.logger.trace("Entering processOrder", { fn: "processOrder", orderId: "ord_1" });
Sentry.logger.debug("Cache lookup", { key: "user:123", hit: false });
Sentry.logger.info("Order created", { orderId: "order_456", total: 99.99 });
Sentry.logger.warn("Rate limit approaching", { current: 95, max: 100 });
Sentry.logger.error("Payment failed", { reason: "card_declined", userId: "u_1" });
Sentry.logger.fatal("Database unavailable", { host: "db-primary" });
```

| Level | Method | Typical Use |
| --- | --- | --- |
| `trace` | `Sentry.logger.trace()` | Ultra-granular function entry/exit; high-volume — filter aggressively in production |
| `debug` | `Sentry.logger.debug()` | Development diagnostics, cache hits/misses, local state changes |
| `info` | `Sentry.logger.info()` | Normal business milestones, confirmations |
| `warn` | `Sentry.logger.warn()` | Degraded state, approaching limits, recoverable issues |
| `error` | `Sentry.logger.error()` | Failures requiring attention |
| `fatal` | `Sentry.logger.fatal()` | Critical failures, system unavailable |

**Attribute value types:** `string`, `number`, `boolean` only — `undefined`, arrays, and
objects are not accepted.

* * *

## Parameterized Messages — `Sentry.logger.fmt`

The `fmt` tagged template literal binds each interpolated variable as a **structured,
searchable attribute** in Sentry:

```typescript
const userId = "user_123";
const productName = "Widget Pro";
const amount = 49.99;

Sentry.logger.info(
  Sentry.logger.fmt`User ${userId} purchased ${productName} for $${amount}`
);
```

This produces:
```
message.template:     "User %s purchased %s for $%s"
message.parameter.0:  "user_123"
message.parameter.1:  "Widget Pro"
message.parameter.2:  49.99
```

Each parameter is independently searchable in Sentry’s log explorer.
You can filter by `message.parameter.0 = "user_123"` without matching the full message
string.

> ⚠️ `logger.fmt` must be used as a **tagged template literal** — not as a function
> call. `Sentry.logger.fmt("text")` will not produce structured parameters.

### When to use `fmt` vs plain attributes

| Approach | Use when |
| --- | --- |
| `Sentry.logger.info(msg, { key: val })` | Variables are logically distinct attributes with names |
| `Sentry.logger.info` with a `Sentry.logger.fmt` tagged template | Variables are part of a human-readable sentence |

* * *

## Console Capture — `consoleLoggingIntegration`

Automatically forwards `console.*` calls to Sentry as structured logs.
Requires SDK ≥10.13.0.

```typescript
Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  enableLogs: true,
  integrations: [
    Sentry.consoleLoggingIntegration({
      levels: ["log", "warn", "error"], // which console methods to forward
    }),
  ],
});

// These calls are now automatically sent to Sentry:
console.log("User action recorded", { userId: 123 });
console.warn("Slow render detected", 240, "ms");
console.error("Fetch failed", new Error("timeout"));
```

Multiple arguments are mapped to positional parameters:
```
console.log("Text", 123, true)
  → message.parameter.0 = 123
  → message.parameter.1 = true
```

### Capturable console levels

| Console method | Sentry log level |
| --- | --- |
| `console.log` | `info` |
| `console.info` | `info` |
| `console.warn` | `warn` |
| `console.error` | `error` |
| `console.debug` | `debug` |
| `console.assert` (failing) | `error` |

Configure `levels` to include only the methods you want forwarded.

* * *

## Log Filtering — `beforeSendLog`

Use `beforeSendLog` to drop, modify, or scrub logs before they leave the client.
Return `null` to discard:

```typescript
Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  enableLogs: true,
  beforeSendLog: (log) => {
    // Drop debug and trace logs in production
    if (log.level === "debug" || log.level === "trace") {
      return null;
    }

    // Scrub sensitive attribute keys
    if (log.attributes?.password) {
      delete log.attributes.password;
    }
    if (log.attributes?.["credit_card"]) {
      log.attributes["credit_card"] = "[REDACTED]";
    }

    // Drop noisy health-check logs by message content
    if (log.message?.includes("/health")) {
      return null;
    }

    return log; // send the (possibly modified) log
  },
});
```

### The `log` object shape

| Field | Type | Description |
| --- | --- | --- |
| `level` | `string` | `"trace"` \| `"debug"` \| `"info"` \| `"warn"` \| `"error"` \| `"fatal"` |
| `message` | `string` | The log message text |
| `timestamp` | `number` | Unix timestamp |
| `attributes` | `object` | Key/value pairs attached to this log |

* * *

## Structured Attributes

Every `Sentry.logger.*` call accepts an attributes object as its second argument:

```typescript
Sentry.logger.info("Checkout completed", {
  orderId: "ord_789",
  userId: "usr_123",
  cartValue: 149.99,
  itemCount: 3,
  paymentMethod: "stripe",
  userTier: "premium",
  duration: Date.now() - startTime,
});
```

Attributes become **searchable and filterable** in Sentry’s log explorer.
Prefer one comprehensive log with all relevant context over many small scattered logs
("wide events").

* * *

## Scope-Based Automatic Attributes (SDK ≥10.32.0)

Attributes set on scopes are automatically added to all logs emitted within that scope.

### Global scope — entire session

```typescript
// Set once at app startup — persists for the lifetime of the page
Sentry.getGlobalScope().setAttributes({
  service: "react-checkout",
  version: "2.1.0",
  region: "us-east-1",
});
```

### Isolation scope — logical user session context

```typescript
// Set after user authenticates
Sentry.getIsolationScope().setAttributes({
  org_id: user.orgId,
  user_tier: user.tier,
  account_type: user.accountType,
});
```

### Current scope — single operation

```typescript
Sentry.withScope((scope) => {
  scope.setAttribute("order_id", "ord_789");
  scope.setAttribute("payment_method", "stripe");
  Sentry.logger.info("Processing payment", { amount: 49.99 });
  // order_id and payment_method are included on this log only
});
```

**Constraint:** Scope attributes accept only `string`, `number`, and `boolean` values —
no arrays or objects.

* * *

## Auto-Generated Attributes

These are added by the SDK to every log without any developer configuration:

| Attribute | Source | Notes |
| --- | --- | --- |
| `sentry.environment` | `environment` in `Sentry.init()` | — |
| `sentry.release` | `release` in `Sentry.init()` | — |
| `sentry.sdk.name` | SDK internals | e.g., `"sentry.javascript.react"` |
| `sentry.sdk.version` | SDK internals | — |
| `browser.name` | User-Agent parsing | e.g., `"Chrome"` |
| `browser.version` | User-Agent parsing | e.g., `"121.0.0"` |
| `user.id`, `user.name`, `user.email` | `Sentry.setUser()` | Added when `Sentry.setUser()` is called (`userInfo` defaults to `true`) |
| `sentry.trace.parent_span_id` | Active tracing span | Enables log ↔ trace correlation |
| `sentry.replay_id` | Active Session Replay session | Enables log ↔ replay correlation |
| `message.template` | `logger.fmt` usage | The template string |
| `message.parameter.N` | `logger.fmt` usage | Each interpolated value |

* * *

## Log-to-Trace Correlation

When tracing is enabled alongside logging, logs are **automatically linked** to the
active span:

```typescript
Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  enableLogs: true,
  tracesSampleRate: 1.0,
  integrations: [Sentry.browserTracingIntegration()],
});

// Logs emitted inside a span are linked to it automatically
await Sentry.startSpan({ name: "checkout-flow", op: "ui.action" }, async () => {
  Sentry.logger.info("Validating cart", { cartId: "cart_abc" });
  await validateCart();
  Sentry.logger.info("Initiating payment", { gateway: "stripe" });
  await initiatePayment();
});
// Both logs above have sentry.trace.parent_span_id set to the checkout-flow span ID
```

In the Sentry UI:
- **From a log** → click the trace link to jump to the parent span and full trace
- **From a trace span** → click “Logs” to see all logs emitted during that span
- **From a replay** → logs are shown inline with the user session recording

* * *

## React-Specific Best Practice: Wide Events

Prefer **one comprehensive log with all context** over many fragmented logs:

```typescript
// ✅ Preferred — one wide log with full context
Sentry.logger.info("Checkout completed", {
  orderId: order.id,
  userId: user.id,
  cartValue: cart.total,
  itemCount: cart.items.length,
  paymentMethod: "stripe",
  userTier: user.tier,
  entitlementTier: user.tiers.join(","),
  durationMs: Date.now() - startTime,
});

// ❌ Avoid — fragmented logs with poor context
Sentry.logger.info("Order ID set", { orderId: order.id });
Sentry.logger.info("Cart total calculated", { cartValue: cart.total });
Sentry.logger.info("Checkout done");
```

* * *

## When to Use Each API

| Scenario | Recommended API |
| --- | --- |
| Business event with structured data | `Sentry.logger.info(msg, { ...attrs })` |
| Message with embedded variables | `Sentry.logger.info` with a `Sentry.logger.fmt` tagged template |
| Capture an unexpected exception | `Sentry.captureException(err)` |
| Send an informational string event | `Sentry.captureMessage(msg, "info")` |
| Auto-capture existing `console.*` calls | `consoleLoggingIntegration({ levels: [...] })` |

Use `Sentry.logger.*` for **structured, searchable observability data**. Use
`captureException` for actual errors that need issue grouping and stack traces.

* * *

## Log Level Guide

| Level | When to use | Production volume |
| --- | --- | --- |
| `trace` | Function entry/exit, loop iterations | Filter out in production |
| `debug` | Variable values, code paths taken | Filter out in production |
| `info` | User actions, business milestones, API calls | Keep — low/medium volume |
| `warn` | Degraded paths, retries, near-limits | Keep — low volume |
| `error` | Failures that need investigation | Keep — should be rare |
| `fatal` | System-down, unrecoverable state | Keep — should be very rare |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Logs not appearing in Sentry | Verify `enableLogs: true` is in `Sentry.init()`; requires SDK ≥9.41.0 |
| `logger.fmt` not creating `message.parameter.*` | Use it as a tagged template literal — not as the function call `Sentry.logger.fmt("text", var)` |
| Logs not linked to traces | Ensure `browserTracingIntegration()` is added and `tracesSampleRate` > 0; logs must be emitted inside an active span |
| `consoleLoggingIntegration` not available | Upgrade to `@sentry/react` ≥10.13.0 |
| Scope attributes not appearing on logs | Upgrade to `@sentry/react` ≥10.32.0 for `getGlobalScope`/`getIsolationScope` APIs |
| Too many logs — high volume / costs | Use `beforeSendLog` to drop `trace` and `debug` levels in production |
| Log attributes contain `undefined` | Only `string`, `number`, `boolean` are accepted — filter undefined values before passing |
| `beforeSendLog` not firing | Confirm `enableLogs: true` is set; without it, no logs are sent and no hook is called |
| Sensitive data appearing in logs | Add filtering in `beforeSendLog`; better yet, avoid logging sensitive data at the call site |
| Logs appear but have no user context | Call `Sentry.setUser({ id, email })` after authentication (`userInfo` defaults to `true`) |
