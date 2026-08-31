# Error Monitoring — Sentry NestJS SDK

> Minimum SDK: `@sentry/nestjs` ≥8.0.0\
> `@SentryTraced()` requires ≥8.15.0 · `@SentryCron()` requires ≥8.16.0 · Event Emitter
> auto-instrumentation requires ≥8.39.0

* * *

## How NestJS Error Capture Works

NestJS routes all unhandled exceptions through its **exception filter pipeline** before
they reach the response.
This means errors don’t bubble up to Node’s uncaught exception handler — Sentry only
sees them if you hook into that pipeline.

The SDK provides two integration points:

| Mechanism | Use When |
| --- | --- |
| `SentryGlobalFilter` (via `APP_FILTER`) | You don’t have a custom catch-all filter |
| `@SentryExceptionCaptured()` decorator | You have an existing `@Catch()` filter you want to keep |

Both internally use `isExpectedError()` — a duck-typing check that skips `HttpException`
(4xx) and `RpcException` so only unexpected errors are reported.

* * *

## Exception Filter Setup

### Pattern A: `SentryGlobalFilter` (recommended for most apps)

Register the filter globally in `AppModule`. It automatically handles HTTP, GraphQL, and
RPC contexts.

```typescript
// app.module.ts
import { Module } from "@nestjs/common";
import { APP_FILTER } from "@nestjs/core";
import { SentryModule } from "@sentry/nestjs/setup";
import { SentryGlobalFilter } from "@sentry/nestjs/setup";

@Module({
  imports: [SentryModule.forRoot()],
  providers: [
    {
      provide: APP_FILTER,
      useClass: SentryGlobalFilter,
    },
  ],
})
export class AppModule {}
```

> **Import path matters:** `SentryGlobalFilter` and `SentryModule` come from
> `@sentry/nestjs/setup`, not `@sentry/nestjs`. This separation ensures they’re loaded
> after `Sentry.init()` runs (in `instrument.ts`), so OpenTelemetry instrumentation can
> patch NestJS before it’s imported.

### Pattern B: Decorate an existing catch-all filter

If you already have a `@Catch()` filter, add `@SentryExceptionCaptured()` to its `catch`
method instead of registering `SentryGlobalFilter`:

```typescript
import { Catch, ExceptionFilter, ArgumentsHost } from "@nestjs/common";
import { SentryExceptionCaptured } from "@sentry/nestjs";

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  @SentryExceptionCaptured()  // ← captures before your handler runs
  catch(exception: unknown, host: ArgumentsHost): void {
    // your existing error handling logic
    // Sentry capture already happened via the decorator
  }
}
```

### Pattern C: Per-exception-type filter with manual capture

For filters scoped to a specific exception type, call `Sentry.captureException()`
explicitly:

```typescript
import { Catch, ArgumentsHost, BadRequestException } from "@nestjs/common";
import { BaseExceptionFilter } from "@nestjs/core";
import * as Sentry from "@sentry/nestjs";

@Catch(DatabaseException)
export class DatabaseExceptionFilter extends BaseExceptionFilter {
  catch(exception: DatabaseException, host: ArgumentsHost) {
    Sentry.captureException(exception, {
      tags: { component: "database", query: exception.query },
    });
    return super.catch(new BadRequestException(exception.message), host);
  }
}
```

* * *

## What Is (and Isn’t) Captured Automatically

### HTTP context

| Error Type | Captured? | Reason |
| --- | --- | --- |
| Unhandled exceptions from controllers | ✅ Yes | `SentryGlobalFilter` intercepts |
| `HttpException` (4xx errors) | ❌ No | `isExpectedError()` skips them |
| `HttpException` subclasses (`BadRequestException`, etc.) | ❌ No | Duck-typed as expected |
| Caught + swallowed in service `try/catch` | ❌ No | Never reaches the filter |
| Re-thrown from `try/catch` | ✅ Yes | Reaches filter as unhandled |

### GraphQL context

`SentryGlobalFilter` detects `host.getType<string>() === 'graphql'` and adjusts
behavior:

- `HttpException` → re-thrown without capture (expected, NestJS handles formatting)
- Any other `Error` → captured **and** re-thrown (so GraphQL can format the error
  response)
- Non-`Error` objects → captured **and** re-thrown

> GraphQL errors are always re-thrown so the Apollo/Mercurius error formatter can run.
> This means they appear in Sentry **and** in the GraphQL error response.

### RPC / Microservices context

`SentryGlobalFilter` handles RPC but logs a warning recommending a dedicated filter:

```
IMPORTANT: RpcException should be handled with a dedicated Rpc exception filter, not the generic SentryGlobalFilter
```

For production microservices, use a dedicated RPC filter:

```typescript
import { Catch, RpcExceptionFilter, ArgumentsHost } from "@nestjs/common";
import { Observable, throwError } from "rxjs";
import { RpcException } from "@nestjs/microservices";
import * as Sentry from "@sentry/nestjs";

@Catch(RpcException)
export class SentryRpcExceptionFilter implements RpcExceptionFilter<RpcException> {
  catch(exception: RpcException, host: ArgumentsHost): Observable<any> {
    Sentry.captureException(exception);
    return throwError(() => exception.getError());
  }
}
```

### The Core Rule

> **“Caught exceptions never reach the filter.
> If you catch and swallow an error, Sentry never sees it.”**

```typescript
// ✅ Automatically captured — reaches SentryGlobalFilter
throw new Error("Unhandled database error");

// ✅ Automatically captured — re-thrown reaches filter
try {
  await db.query(sql);
} catch (err) {
  throw err;  // or: throw new InternalServerErrorException(err.message)
}

// ❌ NOT captured — swallowed before reaching filter
try {
  await db.query(sql);
} catch (err) {
  return { error: "Query failed" };  // ← must add captureException here
}

// ✅ Manually captured before graceful return
try {
  await db.query(sql);
} catch (err) {
  Sentry.captureException(err);
  return { error: "Query failed" };
}
```

* * *

## Manual Error Capture

### `Sentry.captureException(error, context?)`

Captures an exception immediately, regardless of the filter pipeline.

```typescript
import * as Sentry from "@sentry/nestjs";

// Basic
Sentry.captureException(new Error("Payment processing failed"));

// With inline context (one-off enrichment — doesn't affect other events)
Sentry.captureException(error, {
  level: "fatal",
  tags: { component: "payments", provider: "stripe" },
  extra: { orderId, customerId },
  user: { id: req.user.id, email: req.user.email },
  fingerprint: ["payment-failure", String(error.code)],
  contexts: {
    order: { id: orderId, total: 9900, currency: "USD" },
  },
});
```

### `Sentry.captureMessage(message, levelOrContext?)`

Captures a plain message — useful for notable conditions that aren’t exceptions.

```typescript
// With severity level
Sentry.captureMessage("Deprecated API version used", "warning");
// Levels: "fatal" | "error" | "warning" | "log" | "info" | "debug"

// With full context
Sentry.captureMessage("Cache miss rate above threshold", {
  level: "warning",
  tags: { cache: "redis", key_pattern: "user:*" },
  extra: { missRate: 0.42, threshold: 0.20 },
});
```

* * *

## How `isExpectedError()` Works

The SDK uses duck-typing — not `instanceof` — to determine if an error is “expected”
(should not be reported).
This is intentional: importing `@nestjs/common` in the main entry point would load it
before OpenTelemetry can patch it, breaking automatic instrumentation.

```typescript
// Internal SDK logic (simplified)
function isExpectedError(exception: unknown): boolean {
  if (typeof exception !== 'object' || exception === null) return false;

  const ex = exception as Record<string, unknown>;

  // HttpException: has getStatus(), getResponse(), initMessage()
  if (
    typeof ex.getStatus === 'function' &&
    typeof ex.getResponse === 'function' &&
    typeof ex.initMessage === 'function'
  ) {
    return true; // ← skipped, not reported
  }

  // RpcException: has getError(), initMessage()
  if (typeof ex.getError === 'function' && typeof ex.initMessage === 'function') {
    return true; // ← skipped, not reported
  }

  return false; // ← reported to Sentry
}
```

**Implication:** If you create custom exception classes that mimic these method
signatures, they will be treated as expected errors and skipped.
Design your exception hierarchy accordingly.

* * *

## Scope Management

The SDK uses Node’s `AsyncLocalStorage` for automatic request isolation — each HTTP
request gets its own scope so breadcrumbs and tags from one request don’t contaminate
another.

### Three Scope Levels

| Scope | Lifetime | Use for |
| --- | --- | --- |
| **Global** | Process lifetime | App-wide metadata (version, build SHA) |
| **Isolation** | One HTTP request | Per-request user, tags |
| **Current** | One span | Per-span metadata |

Precedence when merging: Current > Isolation > Global.

### Top-Level Setters Write to Isolation Scope

All `Sentry.setXxx()` shorthand methods write to the isolation scope — safe for
per-request data:

```typescript
// These are equivalent:
Sentry.setTag("request_id", req.id);
Sentry.getIsolationScope().setTag("request_id", req.id);

// Set user (persists for the current request):
Sentry.setUser({ id: req.user.id, email: req.user.email });

// Clear user:
Sentry.setUser(null);
```

### Per-Request Enrichment Middleware

The recommended pattern for attaching user context to every request:

```typescript
// auth.middleware.ts
import { Injectable, NestMiddleware } from "@nestjs/common";
import { Request, Response, NextFunction } from "express";
import * as Sentry from "@sentry/nestjs";

@Injectable()
export class SentryContextMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    const user = req.user;  // populated by auth guard
    if (user) {
      Sentry.setUser({
        id: String(user.id),
        email: user.email,
        username: user.username,
      });
      Sentry.setTag("user.role", user.role);
      Sentry.setTag("tenant.id", String(user.tenantId));
    }
    next();
  }
}
```

Register in `AppModule`:

```typescript
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(SentryContextMiddleware).forRoutes("*");
  }
}
```

### `withScope` — Temporary Isolated Context

Use `withScope` when you need context on a single capture without affecting other
events:

```typescript
Sentry.withScope((scope) => {
  scope.setTag("operation", "bulk-import");
  scope.setLevel("warning");
  scope.setContext("import", { rowCount: rows.length, filename });
  scope.setFingerprint(["bulk-import-failure", filename]);
  Sentry.captureException(importError);
});
// ← scope above does NOT appear on subsequent events
```

### Background Job Scope Isolation

Background jobs (`@Cron`, `@Interval`, `@OnEvent`, `@Processor`) share the default
isolation scope with HTTP requests.
Without isolation, breadcrumbs from a cron job can leak into the next HTTP error event.

Wrap with `withIsolationScope()`:

```typescript
import * as Sentry from "@sentry/nestjs";
import { Injectable } from "@nestjs/common";
import { Cron, CronExpression } from "@nestjs/schedule";

@Injectable()
export class ReportGenerationService {
  @Cron(CronExpression.EVERY_HOUR)
  async generateReports() {
    await Sentry.withIsolationScope(async () => {
      Sentry.setTag("job", "report-generation");
      Sentry.addBreadcrumb({ message: "Starting report generation", level: "info" });
      try {
        await this.doGenerate();
      } catch (err) {
        Sentry.captureException(err);
      }
    });
  }
}
```

Also applies to `@Interval()`, `@OnEvent()`, `@Processor()`, and any other background
task handler.

* * *

## Context Enrichment

### Tags (searchable, indexed)

```typescript
Sentry.setTag("page_locale", "de-at");
Sentry.setTags({
  "checkout.step": "payment",
  "subscription.tier": "enterprise",
  "region": "eu-west-1",
});
```

Constraints: key max 32 chars, value max 200 chars, no newlines.

### Context (structured, non-searchable)

```typescript
Sentry.setContext("order", {
  id: orderId,
  items: cart.length,
  total_usd: cart.total,
  coupon: couponCode ?? null,
});

// Clear a context:
Sentry.setContext("order", null);
```

> Normalized to 3 levels deep by default.
> The `type` key is reserved — don’t use it.

### User Identity

```typescript
// On authenticated request
Sentry.setUser({
  id: String(user.id),
  email: user.email,
  username: user.username,
  subscription: user.plan,   // arbitrary extra fields accepted
});

// On logout or unauthenticated context
Sentry.setUser(null);
```

### Tags vs Context — Decision Guide

| Feature | Searchable? | Best For |
| --- | --- | --- |
| **Tags** | ✅ Yes | Filtering, grouping, alerting |
| **Context** | ❌ No | Structured debug info (nested objects) |
| **User** | ✅ Partially | User attribution and filtering |

* * *

## Breadcrumbs

Breadcrumbs are automatically captured for HTTP requests, database queries, and console
output. Add manual breadcrumbs for business-logic milestones:

```typescript
Sentry.addBreadcrumb({
  category: "auth",
  message: "User authenticated via OAuth2",
  level: "info",
  data: { provider: "google", userId: user.id },
});

Sentry.addBreadcrumb({
  type: "http",
  category: "api.external",
  message: "POST /payments/charge",
  level: "info",
  data: {
    url: "https://api.stripe.com/v1/charges",
    method: "POST",
    status_code: 422,
  },
});
```

### `beforeBreadcrumb` — Filter or Mutate

```typescript
Sentry.init({
  beforeBreadcrumb(breadcrumb, hint) {
    // Drop verbose DB health-check queries
    if (
      breadcrumb.category === "db.query" &&
      breadcrumb.message?.includes("SELECT 1")
    ) {
      return null;
    }

    // Truncate large query strings
    if (breadcrumb.category === "db.query" && breadcrumb.message) {
      breadcrumb.message = breadcrumb.message.slice(0, 200);
    }

    return breadcrumb;
  },
  maxBreadcrumbs: 50,  // default: 100
});
```

* * *

## `beforeSend` and Filtering Hooks

### `beforeSend` — Modify or Drop Error Events

Last chance to modify or discard events.
Return `null` to drop the event entirely.

```typescript
Sentry.init({
  dsn: "...",
  beforeSend(event, hint) {
    const error = hint.originalException;

    // Drop known non-actionable errors
    if (error instanceof Error && error.message.includes("ECONNRESET")) {
      return null;
    }

    // Scrub PII from user context
    if (event.user?.email) {
      event.user = { ...event.user, email: "[filtered]" };
    }

    // Scrub Authorization headers
    const headers = event.request?.headers as Record<string, string> | undefined;
    if (headers?.["authorization"]) {
      headers["authorization"] = "[filtered]";
    }

    return event;
  },
});
```

### `ignoreErrors` — Pattern-Based Filtering

```typescript
Sentry.init({
  ignoreErrors: [
    "ECONNRESET",
    /^Connection refused$/i,
    /^ETIMEDOUT/,
  ],
});
```

### `beforeSendTransaction` — Filter Performance Events

```typescript
Sentry.init({
  beforeSendTransaction(event) {
    // Drop health check transactions
    if (event.transaction === "GET /health") return null;
    return event;
  },
});
```

* * *

## Fingerprinting and Custom Grouping

All events have a fingerprint.
Events with the same fingerprint group into the same Sentry issue.

### Per-Capture Fingerprinting

```typescript
// Via captureException context argument
Sentry.captureException(error, {
  fingerprint: ["database-connection-error", error.code],
});

// Via withScope
Sentry.withScope((scope) => {
  scope.setFingerprint(["payment-failure", "stripe", String(error.statusCode)]);
  Sentry.captureException(error);
});
```

### `beforeSend` Fingerprinting

```typescript
Sentry.init({
  beforeSend(event, hint) {
    const error = hint.originalException;

    // All DB connection errors → one issue:
    if (error instanceof DatabaseConnectionError) {
      event.fingerprint = ["database-connection-error"];
    }

    // Extend default grouping (keep stack-trace hash + add dimension):
    if (error instanceof ExternalApiError) {
      event.fingerprint = [
        "{{ default }}",
        error.serviceName,
        String(error.statusCode),
      ];
    }

    return event;
  },
});
```

### Template Variables

| Variable | Description |
| --- | --- |
| `{{ default }}` | Sentry’s normally computed hash (extend rather than replace) |
| `{{ transaction }}` | Current transaction/route name |
| `{{ type }}` | Exception class name |

* * *

## Event Processors

Unlike `beforeSend` (one allowed), multiple event processors can be registered:

```typescript
// Global — runs for every event
Sentry.addEventProcessor((event, hint) => {
  event.extra = {
    ...event.extra,
    buildSha: process.env.GIT_COMMIT_SHA,
    nodeVersion: process.version,
  };
  return event;
});

// Scoped — only for a specific capture
Sentry.withScope((scope) => {
  scope.addEventProcessor((event) => {
    event.tags = { ...event.tags, processed_by: "payment_service" };
    return event;
  });
  Sentry.captureException(paymentError);
});
```

**Execution order:** All `addEventProcessor()` callbacks run first, then `beforeSend`
runs last.

* * *

## Configuration Reference

Key `Sentry.init()` options for error monitoring (in `instrument.ts`):

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `string` | env `SENTRY_DSN` | Project identifier; SDK disabled if empty |
| `environment` | `string` | `"production"` | Deployment environment tag |
| `release` | `string` | env `SENTRY_RELEASE` | App version string |
| `sampleRate` | `number` | `1.0` | Fraction of error events to send (0.0–1.0) |
| `dataCollection` | `object` | conservative unless set | Fine-grained control over auto-collected categories (`userInfo`, `cookies`, `httpHeaders`, `httpBodies`, `queryParams`, `genAI`). When omitted, the SDK falls back to `sendDefaultPii` (default `false`). Passing the object — even `{}` — flips unset categories to their permissive defaults; opt out per category. |
| `attachStacktrace` | `boolean` | `false` | Add stack traces to `captureMessage()` |
| `maxBreadcrumbs` | `number` | `100` | Max breadcrumbs per event |
| `ignoreErrors` | `Array<string \| RegExp>` | `[]` | Error message patterns to never report |
| `beforeSend` | `(event, hint) => event \| null` | — | Mutate or drop error events before sending |
| `beforeBreadcrumb` | `(breadcrumb, hint?) => breadcrumb \| null` | — | Mutate or drop breadcrumbs |
| `includeLocalVariables` | `boolean` | `false` | Capture stack-frame local variable values |
| `debug` | `boolean` | `false` | Enable SDK debug logging |

* * *

## Error Capture Scenario Reference

| Scenario | Auto Captured? | Solution |
| --- | --- | --- |
| Unhandled controller exception | ✅ Yes | `SentryGlobalFilter` intercepts |
| `HttpException` (4xx, 5xx) | ❌ No | Expected by design; capture manually if needed |
| `try/catch` with graceful return | ❌ No | `Sentry.captureException()` before return |
| `try/catch` with re-throw | ✅ Yes | Reaches filter as unhandled |
| GraphQL resolver error | ✅ Yes | `SentryGlobalFilter` captures + re-throws |
| RPC microservice error | ⚠️ Partial | Use dedicated `RpcExceptionFilter` |
| Background job (`@Cron`, `@OnEvent`) | ❌ No | Wrap with `withIsolationScope()` + manual capture |
| WebSocket gateway error | ❌ No | Catch manually in gateway methods |
| Caught + swallowed error | ❌ No | Always call `captureException` before swallowing |

* * *

## API Quick Reference

```typescript
// ── Exception Filter Setup ─────────────────────────────────────────────
import { SentryGlobalFilter } from "@sentry/nestjs/setup"   // APP_FILTER token
import { SentryExceptionCaptured } from "@sentry/nestjs"     // decorator for catch()

// ── Capture ───────────────────────────────────────────────────────────
Sentry.captureException(error)
Sentry.captureException(error, { level, tags, extra, contexts, fingerprint, user })
Sentry.captureMessage("text", "warning")
Sentry.captureMessage("text", { level, tags, extra })

// ── User ──────────────────────────────────────────────────────────────
Sentry.setUser({ id, email, username, ...custom })
Sentry.setUser(null)                                         // clear on logout

// ── Tags (searchable, indexed) ────────────────────────────────────────
Sentry.setTag("key", "value")
Sentry.setTags({ key1: "v1", key2: "v2" })

// ── Context (structured, non-searchable) ─────────────────────────────
Sentry.setContext("name", { key: value })
Sentry.setContext("name", null)                              // clear

// ── Breadcrumbs ───────────────────────────────────────────────────────
Sentry.addBreadcrumb({ type, category, message, level, data })

// ── Scopes ────────────────────────────────────────────────────────────
Sentry.withScope((scope) => { scope.setTag(...); Sentry.captureException(...) })
Sentry.withIsolationScope((scope) => { ... })                // background jobs
Sentry.getGlobalScope().setTag(...)
Sentry.getIsolationScope().setTag(...)                       // same as Sentry.setTag()

// ── Fingerprinting ────────────────────────────────────────────────────
scope.setFingerprint(["group-key"])
event.fingerprint = ["{{ default }}", "extra-dimension"]     // in beforeSend

// ── Hooks ─────────────────────────────────────────────────────────────
Sentry.init({ beforeSend(event, hint) { return event | null } })
Sentry.init({ beforeSendTransaction(event) { return event | null } })
Sentry.init({ beforeBreadcrumb(breadcrumb, hint) { return breadcrumb | null } })
Sentry.init({ ignoreErrors: ["string", /regex/] })
```

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| `HttpException` errors not appearing | Expected — by design. Call `Sentry.captureException()` manually if you want 4xx/5xx reported |
| Unhandled controller errors not appearing | Ensure `SentryGlobalFilter` is registered via `APP_FILTER` in `AppModule`, and `SentryModule.forRoot()` is in imports |
| Breadcrumbs from cron jobs appearing in HTTP errors | Wrap cron/event handlers with `Sentry.withIsolationScope()` |
| GraphQL errors not appearing | `SentryGlobalFilter` handles this automatically — verify it’s registered. Check if a custom exception filter intercepts before `SentryGlobalFilter` runs |
| RPC errors appear with a warning | Use a dedicated `@Catch(RpcException)` filter and call `Sentry.captureException()` explicitly |
| User context missing from events | Set `Sentry.setUser()` in middleware **before** the request reaches the controller; isolation scope is per-request |
| `instrument.ts` import order error | `import "./instrument"` must be the **very first line** of `main.ts` — before any other imports |
| Events not appearing | Verify DSN, enable `debug: true` in `Sentry.init()` to see SDK logs, confirm `SentryModule.forRoot()` is imported |
| PII appearing in events | Data is collected by default; opt out via `dataCollection` (e.g. `userInfo: false`, `httpBodies: []`, `cookies: false`) and scrub remaining values in `beforeSend` |
