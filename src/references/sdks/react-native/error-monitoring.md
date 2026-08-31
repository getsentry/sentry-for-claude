# Error Monitoring & Crash Reporting — Sentry React Native SDK

> **Minimum SDK:** `@sentry/react-native` ≥ 6.0.0 (≥ 8.0.0 recommended) **Native SDKs:**
> `sentry-cocoa` (iOS/tvOS/macOS) · `sentry-android` (Java + NDK) **React Native:**
> 0.71+ required for Fabric renderer support

React Native is unique: errors can originate from three different layers — the
**JavaScript runtime**, **native iOS** (ObjC/Swift, Mach exceptions), or **native
Android** (Java, JNI/C++ via NDK). The Sentry RN SDK bridges all three.

* * *

## Table of Contents

1. [Core Capture APIs](#1-core-capture-apis)
2. [Native Crash Handling — iOS & Android](#2-native-crash-handling--ios--android)
3. [ANR / App Hang Detection](#3-anr--app-hang-detection)
4. [Unhandled Promise Rejections](#4-unhandled-promise-rejections)
5. [Sentry.wrap(App) — Top-Level Error Boundary](#5-sentrywrapapp--top-level-error-boundary)
6. [ErrorBoundary Component](#6-errorboundary-component)
7. [Scope Management](#7-scope-management)
8. [Context Enrichment — Tags, User, Extra, Contexts](#8-context-enrichment--tags-user-extra-contexts)
9. [Breadcrumbs — Automatic & Manual](#9-breadcrumbs--automatic--manual)
10. [beforeSend / beforeSendTransaction Hooks](#10-beforesend--beforesendtransaction-hooks)
11. [Fingerprinting & Grouping](#11-fingerprinting--grouping)
12. [Event Processors](#12-event-processors)
13. [Attachments — Screenshots & View Hierarchy](#13-attachments--screenshots--view-hierarchy)
14. [Redux Integration](#14-redux-integration)
15. [Device & App Context](#15-device--app-context)
16. [Release Health & Sessions](#16-release-health--sessions)
17. [Offline Event Caching](#17-offline-event-caching)
18. [Default Integrations](#18-default-integrations)
19. [Full init() Options Reference](#19-full-init-options-reference)
20. [Quick Reference Cheatsheet](#20-quick-reference-cheatsheet)
21. [Troubleshooting](#21-troubleshooting)

* * *

## 1. Core Capture APIs

Three fundamental data concepts:
- **Event** — a single submission to Sentry (exception, message, or raw event)
- **Issue** — a group of similar events clustered by Sentry
- **Capturing** — the act of reporting an event

### `Sentry.captureException(error, context?)`

Captures any thrown `Error` (or non-Error value) and sends it to Sentry.

```typescript
import * as Sentry from "@sentry/react-native";

// Basic usage
try {
  aFunctionThatMightFail();
} catch (err) {
  Sentry.captureException(err);
}

// With inline context (plain object)
Sentry.captureException(new Error("something went wrong"), {
  tags: { section: "checkout" },
  user: { email: "user@example.com" },
  extra: { orderId: "abc-123" },
  level: "warning",
  fingerprint: ["{{ default }}", "checkout-error"],
});

// With a scope callback — clones scope for this capture only
Sentry.captureException(new Error("something went wrong"), (scope) => {
  scope.setTag("section", "articles");
  scope.setLevel("warning");
  return scope;
});

// New Scope instance — merges with global scope
const scope = new Sentry.Scope();
scope.setTag("section", "articles");
Sentry.captureException(new Error("something went wrong"), scope);

// Isolate entirely — return the scope from a function to ignore global attrs
Sentry.captureException(new Error("clean slate"), () => scope);
```

### `Sentry.captureMessage(message, level?)`

Sends a textual message.
Useful for non-exception events or informational milestones.

```typescript
// Default level is "info"
Sentry.captureMessage("Something noteworthy happened");

// Explicit severity level
// "fatal" | "error" | "warning" | "log" | "info" | "debug"
Sentry.captureMessage("Payment declined", "warning");
Sentry.captureMessage("Critical system failure", "fatal");
Sentry.captureMessage("Debug checkpoint reached", "debug");
```

### `Sentry.captureEvent(event)`

Low-level method to send a fully constructed Sentry event object.
Used for advanced cases where you build the event manually.

```typescript
Sentry.captureEvent({
  message: "Manual event",
  level: "error",
  tags: { custom_tag: "value" },
  extra: { arbitrary_data: true },
  fingerprint: ["my-custom-fingerprint"],
  timestamp: Date.now() / 1000,
});
```

### Error Levels

| Level | Use Case |
| --- | --- |
| `fatal` | App crash, total loss of functionality |
| `error` | Feature broken, user action failed |
| `warning` | Degraded state, non-critical failure |
| `info` | Informational, noteworthy events |
| `log` | Low-priority operational logs |
| `debug` | Development diagnostics |

* * *

## 2. Native Crash Handling — iOS & Android

The React Native SDK delegates to two native SDKs for platform-level crash capture:
- **iOS/tvOS/macOS** — `sentry-cocoa`
- **Android** — `sentry-android` (Java/Kotlin + NDK for C/C++)

### How Native Crash Capture Works

Native crashes (segfaults, SIGSEGV, unhandled C++ exceptions, OOM kills) are captured
**entirely at the OS level** — not in JavaScript.
The crash handler is registered during native SDK initialization.
Crash reports are:

1. Persisted to disk in binary envelope format at crash time
2. **Not sent at crash time** — queued and sent on the **next app launch**

```
iOS:     [crash] → written to disk by sentry-cocoa
                 → [next launch] → sentry-cocoa reads and transmits

Android: [crash] → written to disk by sentry-android
                 → [next app restart] → sentry-android reads and transmits
```

### Native Configuration Options

```typescript
Sentry.init({
  dsn: "https://examplePublicKey@o0.ingest.sentry.io/0",

  // Disable all native SDK functionality (JS layer only)
  enableNative: false,

  // Prevent native layer from capturing hard crashes
  enableNativeCrashHandling: false,

  // Manually initialize native SDKs yourself (advanced)
  autoInitializeNativeSdk: false,

  // Sync Android Java scope data to NDK layer (for C/C++ crash context)
  enableNdkScopeSync: true,

  // Android 12+: use ApplicationExitInfo for enhanced tombstone reports
  enableTombstone: true,

  // Attach all thread states to Android events (has a performance impact)
  attachThreads: false,

  // Called after native SDKs have finished initializing
  onReady: () => {
    console.log("Sentry native SDKs initialized");
  },
});
```

### Offline Caching Behavior

| Platform | Offline Behavior |
| --- | --- |
| **Android** | Events cached on device; transmitted on **app restart** |
| **iOS** | Events cached on device; transmitted when the **next event fires** |

### Linked Errors (Chained `.cause`)

The `NativeLinkedErrors` integration (enabled by default) reads the `.cause` property on
errors recursively, linking the error chain up to **5 levels deep**:

```typescript
try {
  await fetchMovieReviews(movie);
} catch (originalError) {
  const wrapperError = new Error(`Failed to fetch reviews for: ${movie}`);
  wrapperError.cause = originalError; // SDK reads this chain
  Sentry.captureException(wrapperError);
}
```

### Native SDK Log Forwarding

The SDK can forward native SDK internal log messages (from iOS and Android native
layers) to the JavaScript console.
This is a **debugging tool** — it surfaces native SDK diagnostics in Metro without
requiring Xcode or Logcat.

**Requirements:** `debug: true` must be enabled in `Sentry.init`.

```typescript
import * as Sentry from "@sentry/react-native";

Sentry.init({
  dsn: "YOUR_DSN",
  debug: true, // required — native logs are only forwarded when debug is enabled

  onNativeLog: ({ level, component, message }) => {
    // Use consoleSandbox to avoid feedback loops with Sentry's console integration
    Sentry.consoleSandbox(() => {
      console.log(`[Sentry Native] [${level.toUpperCase()}] [${component}] ${message}`);
    });
  },
});
```

| Parameter | Type | Values |
| --- | --- | --- |
| `level` | `string` | `"debug"`, `"info"`, `"warning"`, `"error"`, `"fatal"` |
| `component` | `string` | Native module name (e.g., `"Sentry"`) |
| `message` | `string` | The log message from the native SDK |

> **Always use `Sentry.consoleSandbox()`** inside the callback.
> Without it, your `console.log` call may be intercepted by the Sentry `Breadcrumbs`
> integration, which creates a breadcrumb that triggers another log event — an infinite
> loop.

> **Never enable `debug: true` in production.** Native log forwarding is for local
> development and CI debugging only.

* * *

## 3. ANR / App Hang Detection

### Android — Application Not Responding (ANR)

ANR detection is handled by the native `sentry-android` SDK. Android’s OS flags an ANR
when:
- An **activity doesn’t respond to user input within 5 seconds**
- A **broadcast receiver doesn’t complete within 10 seconds**

The SDK detects this via a watchdog thread monitoring the main thread.
When the UI thread is blocked, an ANR event is created and sent to Sentry.
ANR detection on Android is **always enabled** via the native SDK and is not
configurable from JavaScript.

### iOS / tvOS / macOS — App Hangs

On Apple platforms, `sentry-cocoa` monitors the main thread with a watchdog.
Any block exceeding the configured threshold triggers an error event.

```typescript
Sentry.init({
  dsn: "___PUBLIC_DSN___",

  // Disable app hang tracking (Apple platforms only)
  enableAppHangTracking: false,

  // Detection threshold in seconds (default: 2)
  // Main thread must be blocked longer than this value to trigger
  appHangTimeoutInterval: 1,
});
```

> **Note:** `enableAppHangTracking` and `appHangTimeoutInterval` apply to **iOS, tvOS,
> and macOS** only.

### iOS Watchdog Terminations & OOM

```typescript
Sentry.init({
  // Track out-of-memory kills and watchdog terminations on iOS (default: true)
  enableWatchdogTerminationTracking: true,
});
```

* * *

## 4. Unhandled Promise Rejections

The SDK automatically captures unhandled promise rejections via the built-in
`UnhandledRejection` integration.
Any promise that rejects without a `.catch()` or `try/catch` is captured as a Sentry
error event with no configuration needed.

```typescript
// This is automatically captured by Sentry:
async function doSomething() {
  throw new Error("Unhandled rejection");
}
doSomething(); // No await, no .catch()

// To disable (if you handle these yourself elsewhere):
Sentry.init({
  integrations: (integrations) =>
    integrations.filter((i) => i.name !== "UnhandledRejection"),
});
```

* * *

## 5. `Sentry.wrap(App)` — Top-Level Error Boundary

`Sentry.wrap` wraps your **root component** and should be used in every React Native app
using Sentry.

```typescript
// index.js / app entry point
import { AppRegistry } from "react-native";
import * as Sentry from "@sentry/react-native";
import App from "./src/App";
import { name as appName } from "./app.json";

Sentry.init({
  dsn: "https://examplePublicKey@o0.ingest.sentry.io/0",
});

AppRegistry.registerComponent(appName, () => Sentry.wrap(App));
```

**What `Sentry.wrap` does:**

| Capability | Description |
| --- | --- |
| **React render error boundary** | Catches errors thrown during component rendering |
| **UI interaction tracking** | Records touch events as `ui.click` breadcrumbs automatically |
| **User Feedback Widget** | `Sentry.showFeedbackWidget()` requires this wrapper |
| **Session Replay buffering** | Buffers pre-error session data for the feedback widget |

* * *

## 6. `ErrorBoundary` Component

`Sentry.ErrorBoundary` is a React error boundary that catches render-time errors,
reports them to Sentry with full React component stack context, and renders a fallback
UI.

### Basic Usage

```typescript
import * as Sentry from "@sentry/react-native";

function App() {
  return (
    <Sentry.ErrorBoundary fallback={<Text>An error has occurred</Text>}>
      <Dashboard />
    </Sentry.ErrorBoundary>
  );
}
```

### Fallback as a Function

```typescript
import * as Sentry from "@sentry/react-native";

function App() {
  return (
    <Sentry.ErrorBoundary
      fallback={({ error, componentStack, resetError }) => (
        <View style={styles.errorContainer}>
          <Text style={styles.title}>Something went wrong</Text>
          <Text style={styles.message}>{error.toString()}</Text>
          <Text style={styles.stack}>{componentStack}</Text>
          <Button title="Try again" onPress={resetError} />
        </View>
      )}
    >
      <MainContent />
    </Sentry.ErrorBoundary>
  );
}
```

The fallback function receives:
- `error` — the thrown error object
- `componentStack` — React’s component stack trace string
- `resetError` — function to clear error state and re-render children

### Higher-Order Component (HOC) Pattern

```typescript
import * as Sentry from "@sentry/react-native";

const SafeDashboard = Sentry.withErrorBoundary(Dashboard, {
  fallback: <View><Text>Dashboard unavailable</Text></View>,
});
```

### Multiple Boundaries with Contextual Tags

```typescript
function App() {
  return (
    <View>
      <Sentry.ErrorBoundary
        fallback={<SidebarFallback />}
        beforeCapture={(scope) => scope.setTag("section", "sidebar")}
      >
        <Sidebar />
      </Sentry.ErrorBoundary>

      <Sentry.ErrorBoundary
        fallback={<ContentFallback />}
        beforeCapture={(scope) => scope.setTag("section", "content")}
      >
        <MainContent />
      </Sentry.ErrorBoundary>
    </View>
  );
}
```

Nesting error boundaries allows granular isolation: an error in `Sidebar` won’t crash
`MainContent`, and each boundary tags its errors with a `section` for easy filtering in
Sentry.

### Show User Feedback Dialog on Error

```typescript
<Sentry.ErrorBoundary
  showDialog       // auto-opens user feedback dialog when error is caught
  fallback={<ErrorScreen />}
>
  <App />
</Sentry.ErrorBoundary>
```

### Full Props Reference

| Prop | Type | Description |
| --- | --- | --- |
| `fallback` | `ReactNode \| ({ error, componentStack, resetError }) => ReactNode` | UI rendered when an error is caught |
| `showDialog` | `boolean` | Open User Feedback widget on error |
| `dialogOptions` | `object` | Options passed to the feedback dialog |
| `onError` | `(error, componentStack, eventId) => void` | Called when an error is caught; useful for state propagation |
| `beforeCapture` | `(scope, error, componentStack) => void` | Called before sending to Sentry; add tags/context here |
| `onMount` | `() => void` | Called on `componentDidMount` |
| `onUnmount` | `() => void` | Called on `componentWillUnmount` |

### Manual Error Boundary (Class Component)

```typescript
import React from "react";
import * as Sentry from "@sentry/react-native";

class CustomErrorBoundary extends React.Component {
  state = { hasError: false };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    Sentry.captureException(error, {
      extra: { componentStack: info.componentStack },
    });
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? null;
    }
    return this.props.children;
  }
}
```

> **Important:** Custom error boundaries **must be class components** — this is a React
> requirement, not a Sentry limitation.

* * *

## 7. Scope Management

Scopes hold contextual data (tags, user, breadcrumbs, contexts) that is merged into
captured events. There are three scope layers with different lifetimes.

### Three Scope Types

#### Global Scope

Applied to **every event** regardless of origin.
Used for low-level environmental data.

```typescript
const globalScope = Sentry.getGlobalScope();
globalScope.setTag("app_type", "mobile");
globalScope.setContext("runtime", { name: "Hermes", version: "0.11.0" });
```

#### Isolation Scope

Separates events from each other (per-session in mobile).
All `Sentry.setXXX()` convenience methods write here.

```typescript
// These are equivalent:
Sentry.setTag("my-tag", "my value");
Sentry.getIsolationScope().setTag("my-tag", "my value");

// Set user for the entire session:
Sentry.setUser({ id: "42", email: "user@example.com" });
```

#### Current Scope

The locally active scope.
Best accessed via `withScope()`.

### Scope Data Precedence

Scopes merge in order: **global → isolation → current**. A key on the current scope
overrides the same key on outer scopes.

```typescript
Sentry.getGlobalScope().setExtras({ shared: "global", global: "data" });
Sentry.getIsolationScope().setExtras({ shared: "isolation", isolation: "data" });
Sentry.getCurrentScope().setExtras({ shared: "current", current: "data" });

// Resulting event extras: { shared: "current", global: "data", isolation: "data", current: "data" }
```

### `withScope()` — Temporary Isolated Scopes

Creates a **cloned scope** valid only inside the callback.
Changes do not affect the outer scope.

```typescript
// Error 1 gets the tag; Error 2 does NOT
Sentry.withScope((scope) => {
  scope.setTag("my-tag", "my value");
  scope.setLevel("warning");
  Sentry.captureException(new Error("my error")); // tagged
});
Sentry.captureException(new Error("my other error")); // NOT tagged

// Temporarily override user identity for one capture
Sentry.withScope((scope) => {
  scope.setUser({ id: "service-account" });
  Sentry.captureException(backgroundJobError);
  // original user identity restored after this block
});
```

### Convenience Methods (All Write to Isolation Scope)

```typescript
Sentry.setTag(key, value)
Sentry.setTags({ key: value })
Sentry.setAttribute(key, value)          // SDK ≥8.17.2
Sentry.setAttributes({ key: value })     // SDK ≥8.17.2
Sentry.setUser({ id, email, username })
Sentry.setContext(name, object)
Sentry.setExtra(key, value)
Sentry.setExtras({ key: value })
Sentry.addBreadcrumb(breadcrumb)
```

* * *

## 8. Context Enrichment — Tags, User, Extra, Contexts

### Tags — Indexed & Searchable

Tags are **key/value string pairs** indexed in Sentry, enabling full-text search, filter
sidebars, and distribution maps in the UI.

```typescript
Sentry.setTag("page_locale", "de-at");
Sentry.setTag("app_version", "3.2.1");
Sentry.setTag("user_plan", "enterprise");
```

**Tag constraints:**

| Property | Constraint |
| --- | --- |
| Key max length | 32 characters |
| Key allowed characters | `a-zA-Z`, `0-9`, `_`, `.`, `:`, `-` |
| Value max length | 200 characters |
| Value forbidden | Newline `\n` characters |

### User Identity

```typescript
// Set on login
Sentry.setUser({
  id: "42",
  email: "john.doe@example.com",
  username: "johndoe",
  ip_address: "{{auto}}", // Sentry resolves this automatically
  // Any additional key-value pairs
  plan: "enterprise",
  role: "admin",
});

// Clear on logout
Sentry.setUser(null);
```

### Custom Structured Contexts

Structured contexts attach arbitrary nested objects to events.
They appear on the issue detail page but are **not searchable** (use tags for searchable
data).

```typescript
Sentry.setContext("character", {
  name: "Mighty Fighter",
  age: 19,
  attack_type: "melee",
});

Sentry.setContext("order", {
  id: "ORD-9821",
  total: 129.99,
  items: ["item-1", "item-2"],
  shipping: { method: "express", address: "123 Main St" },
});
```

> **Notes:**
> - The key `"type"` is reserved by Sentry — do not use it
> - Context nesting is normalized to **3 levels** by default (configurable via
>   `normalizeDepth`)
> - Avoid sending entire app state blobs; exceeding max payload size triggers HTTP `413`

### Extra Data (Deprecated)

```typescript
// Deprecated — use setContext() instead
Sentry.setExtra("server_name", "web-01");
Sentry.setExtras({ key1: "value1", key2: "value2" });
```

### Inline Context on Capture Calls

```typescript
Sentry.captureException(new Error("something went wrong"), {
  tags: { section: "articles" },
  user: { id: "42", email: "user@example.com" },
  extra: { requestId: "abc-123" },
  contexts: { order: { id: "ORD-9821" } },
  level: "warning",
  fingerprint: ["{{ default }}", "order-error"],
});
```

### Clearing Context

```typescript
// Clear all scope data
Sentry.getCurrentScope().clear();

// Reset user
Sentry.setUser(null);

// Remove a specific tag
Sentry.setTag("key", undefined);
```

* * *

## 9. Breadcrumbs — Automatic & Manual

Breadcrumbs form a timeline of events leading up to an error.
They buffer until the next event is captured — they do not create Sentry issues on their
own.

### Manual Breadcrumbs

```typescript
import * as Sentry from "@sentry/react-native";

// Navigation event
Sentry.addBreadcrumb({
  category: "navigation",
  message: "Navigated to screen",
  level: "info",
  data: {
    from: "HomeScreen",
    to: "ProfileScreen",
    params: { userId: "42" },
  },
});

// Authentication event
Sentry.addBreadcrumb({
  category: "auth",
  message: "User logged in: " + user.email,
  level: "info",
});

// API failure before throwing
Sentry.addBreadcrumb({
  category: "api",
  message: "Checkout API call failed",
  level: "error",
  data: {
    url: "/api/checkout",
    status: 500,
    method: "POST",
  },
});
```

**Breadcrumb properties:**

| Property | Description |
| --- | --- |
| `type` | `"default"`, `"http"`, `"navigation"`, `"user"` |
| `category` | Dot-separated string (e.g., `"ui.click"`, `"http"`, `"auth"`) |
| `message` | Human-readable description |
| `level` | `"fatal"`, `"critical"`, `"error"`, `"warning"`, `"log"`, `"info"`, `"debug"` |
| `timestamp` | Unix timestamp (auto-set if omitted) |
| `data` | Arbitrary `{ key: value }` metadata |

> **Warning:** Unknown keys beyond those above are silently dropped during processing.

### Automatic Breadcrumbs

| Source | Category | How |
| --- | --- | --- |
| Touch interactions | `ui.click` | Via `Sentry.wrap` on root component |
| HTTP requests | `http` | Fetch/XHR patching (default) |
| Console output | `console` | `console.log/warn/error` patching (default) |
| Navigation | `navigation` | Via navigation integrations |
| Redux actions | `redux.action` | Via `Sentry.createReduxEnhancer` |
| Native lifecycle | various | From native SDKs (connectivity changes, lifecycle events) |

### `beforeBreadcrumb` Hook

```typescript
Sentry.init({
  beforeBreadcrumb(breadcrumb, hint) {
    // Drop all UI click breadcrumbs
    if (breadcrumb.category === "ui.click") {
      return null;
    }

    // Scrub auth tokens from HTTP breadcrumbs
    if (breadcrumb.category === "http" && breadcrumb.data?.url) {
      breadcrumb.data.url = breadcrumb.data.url.replace(
        /token=[^&]*/,
        "token=REDACTED"
      );
    }

    // Add extra metadata to console breadcrumbs
    if (breadcrumb.category === "console") {
      breadcrumb.data = { ...breadcrumb.data, deviceTime: Date.now() };
    }

    return breadcrumb; // return null to drop
  },
});
```

### Breadcrumb Capacity

```typescript
Sentry.init({
  // Default is 100; oldest breadcrumbs are discarded when full
  maxBreadcrumbs: 50,
});
```

* * *

## 10. `beforeSend` / `beforeSendTransaction` Hooks

These hooks fire immediately before an event is transmitted, giving you a final chance
to modify or suppress it.

> **Important:** `beforeSend` only runs on **JavaScript-layer events**. It does not
> affect native Android/iOS crash events captured by the native SDKs.

### `beforeSend` — Error Events

```typescript
Sentry.init({
  beforeSend(event, hint) {
    // hint.originalException — the original thrown Error object
    // hint.syntheticException — auto-generated when non-Error is thrown
    // hint.event_id — the generated event ID

    // Drop events matching a pattern
    if (event.exception?.values?.[0]?.value?.includes("ResizeObserver")) {
      return null;
    }

    // Scrub PII before sending
    if (event.user) {
      delete event.user.email;
      delete event.user.ip_address;
    }

    // Set fingerprint based on error message
    const error = hint.originalException as Error;
    if (error?.message?.match(/database unavailable/i)) {
      event.fingerprint = ["database-unavailable"];
    }

    // Attach extra data
    event.extra = {
      ...event.extra,
      build_number: "42",
    };

    return event; // return null to drop, return event to send
  },
});
```

### `beforeSendTransaction` — Performance Transactions

```typescript
Sentry.init({
  beforeSendTransaction(event) {
    // Drop health check transactions
    if (event.transaction === "/health") return null;

    // Normalize internal transaction names
    if (event.transaction?.startsWith("/internal/")) {
      event.transaction = "/internal/*";
    }

    return event;
  },
});
```

### `ignoreErrors` / `ignoreTransactions`

Pre-filter before `beforeSend` even runs — more efficient for known noise patterns:

```typescript
Sentry.init({
  ignoreErrors: [
    "ResizeObserver loop limit exceeded",
    "Non-Error exception captured",
    /^Script error\.?$/,
  ],
  ignoreTransactions: [
    "/healthcheck",
    /^\/admin\/internal\//,
  ],
});
```

* * *

## 11. Fingerprinting & Grouping

Fingerprinting controls how Sentry groups events into issues.
By default, Sentry groups by stack trace.
You can override this to merge or split issues.

### SDK-Level Fingerprinting

```typescript
// Static fingerprint — all matching events become one issue
Sentry.captureException(new Error("DB connection failed"), {
  fingerprint: ["database-connection-error"],
});

// Dynamic — include URL and status for more granular groups
Sentry.captureException(networkErr, {
  fingerprint: ["{{ default }}", networkErr.url, String(networkErr.status)],
});

// Dynamic via beforeSend
Sentry.init({
  beforeSend(event, hint) {
    const error = hint.originalException as Error;
    if (error?.message?.match(/network request failed/i)) {
      event.fingerprint = [
        "network-error",
        event.request?.url ?? "unknown-url",
      ];
    }
    return event;
  },
});
```

### Fingerprint Variables

| Variable | Resolves to |
| --- | --- |
| `{{ default }}` | Sentry’s default grouping hash |
| `{{ error.type }}` | Exception class name |
| `{{ error.value }}` | Exception message text |
| `{{ transaction }}` | Current transaction name |
| `{{ level }}` | Event severity level |
| `{{ message }}` | Captured message |
| `{{ stack.function }}` | Top stack frame function name |
| `{{ stack.module }}` | Top stack frame module |

### Server-Side Fingerprint Rules (Project Settings)

```
# Group all DB errors together regardless of message
error.type:DatabaseUnavailable -> system-down
error.type:ConnectionError -> system-down

# Subdivide connection errors by transaction
error.value:"connection error: *" -> connection-error, {{ transaction }}

# Custom issue title
logger:my.package.* level:error -> error-logger, {{ logger }} title="Error from Logger {{ logger }}"
```

### Fingerprint Priority

1. SDK-set `fingerprint` (in `captureException`, `beforeSend`, or `captureEvent`)
2. Server-side fingerprint rules (Sentry project settings)
3. Sentry’s default stack-trace-based grouping

* * *

## 12. Event Processors

Event processors run on **every event** before transmission.
They differ from `beforeSend` in two key ways:
1. `beforeSend` always runs **last**, after all event processors
2. Processors added to a scope only apply to events **within that scope**

### Global Event Processor

```typescript
import * as Sentry from "@sentry/react-native";

Sentry.addEventProcessor((event, hint) => {
  // Enrich all events with app metadata
  event.extra = {
    ...event.extra,
    appBuildTime: BUILD_TIMESTAMP,
    buildChannel: BUILD_CHANNEL,
  };
  // Feature-flag evaluations: use featureFlagsIntegration — see feature-flags.md

  // Drop events from test environments
  if (isTestEnvironment()) return null;

  return event;
});
```

### Scoped Event Processor

```typescript
Sentry.withScope((scope) => {
  scope.addEventProcessor((event, hint) => {
    // Only runs for events captured inside this withScope block
    event.tags = { ...event.tags, flow: "checkout" };
    return event;
  });

  Sentry.captureException(checkoutError); // ✅ processor fires
});

Sentry.captureException(otherError); // ❌ processor does NOT fire
```

### Async Event Processors

```typescript
Sentry.addEventProcessor(async (event, hint) => {
  const deviceInfo = await getDeviceInfo();
  event.contexts = { ...event.contexts, device: deviceInfo };
  return event;
});
```

### Execution Order

```
[All addEventProcessor / scope.addEventProcessor functions]
  ↓ (in registration order)
[beforeSend / beforeSendTransaction]
  ↓ (always last)
[Sentry servers]
```

* * *

## 13. Attachments — Screenshots & View Hierarchy

### Automatic Screenshot on Error

Captures a PNG screenshot at the moment an error occurs.
Attached to the event in Sentry’s issue detail view.

```typescript
Sentry.init({
  // Available since @sentry/react-native v4.11.0
  attachScreenshot: true,
});
```

Screenshots appear under **“Attachments”** on the event detail page in Sentry.

> **PII consideration:** Screenshots may capture sensitive data visible on screen
> (forms, personal information).
> Review before enabling in production.

### View Hierarchy Capture

Captures a JSON representation of the native component hierarchy at crash time.

```typescript
Sentry.init({
  attachViewHierarchy: true,
});
```

The view hierarchy appears in Sentry’s **“View Hierarchy”** tab on the event.

### Manual File Attachments

```typescript
Sentry.captureException(err, {
  attachments: [
    {
      filename: "config.json",
      data: JSON.stringify(appConfig),
      contentType: "application/json",
    },
    {
      filename: "debug.log",
      data: logFileContents,         // string or Uint8Array
      contentType: "text/plain",
    },
    {
      filename: "screenshot.png",
      data: base64PngData,
      contentType: "image/png",
    },
  ],
});
```

### Attachments via Scope

```typescript
Sentry.withScope((scope) => {
  scope.addAttachment({
    filename: "state_snapshot.json",
    data: JSON.stringify(store.getState()),
    contentType: "application/json",
  });
  Sentry.captureException(error);
});
```

> **Size limits:** Attachments must not push the total event payload over Sentry’s
> maximum. Oversized payloads return HTTP `413 Payload Too Large`.

* * *

## 14. Redux Integration

The `createReduxEnhancer` captures Redux state snapshots and action history as
breadcrumbs on error events.

### Setup

```typescript
import { createStore } from "redux";
import * as Sentry from "@sentry/react-native";

const store = createStore(
  rootReducer,
  Sentry.createReduxEnhancer({
    // Transform action before recording — return null to skip
    actionTransformer: (action) => {
      if (action.type === "SENSITIVE_ACTION") return null;
      if (action.type === "SET_PASSWORD") {
        return { ...action, payload: "[REDACTED]" };
      }
      return action;
    },

    // Transform state snapshot — avoid sending large state trees
    stateTransformer: (state) => ({
      selectedTab: state.ui.selectedTab,
      userPlan: state.user.plan,
      cartItemCount: state.cart.items.length,
    }),
  })
);
```

### With Redux Toolkit

```typescript
import { configureStore } from "@reduxjs/toolkit";
import * as Sentry from "@sentry/react-native";

const store = configureStore({
  reducer: rootReducer,
  enhancers: (getDefaultEnhancers) =>
    getDefaultEnhancers().concat(
      Sentry.createReduxEnhancer({
        actionTransformer: (action) => {
          // Drop auth-related actions from breadcrumbs
          if (action.type.startsWith("auth/")) return null;
          return action;
        },
      })
    ),
});
```

Dispatched actions appear in Sentry as `redux.action` breadcrumbs.
State at the time of an error is attached to the event under `state.value`.

* * *

## 15. Device & App Context

The SDK automatically attaches rich device context to every event — no configuration
required.

### Automatic Context (No Setup Needed)

| Context Section | Fields | Source |
| --- | --- | --- |
| **Device** | Model, manufacturer, brand, screen resolution, orientation, free memory, battery level, charging state | Native SDK |
| **OS** | Name (`iOS`/`Android`), version, build number, kernel version | Native SDK |
| **App** | App ID, version name, version code, build type | Native SDK |
| **React Native** | RN version, JS engine (Hermes/JSC), architecture | JS SDK |
| **Expo Constants** | Execution environment, app name/slug/version, Expo SDK version, EAS project ID, session ID, debug mode | `expoConstantsIntegration` (Expo only) |

These appear in Sentry under the **“Device”**, **“Operating System”**, **“App”**, and
(for Expo apps) **“expo_constants”** sections of any event.

### Expo Constants Context

When running in an Expo app, the `expoConstantsIntegration` is enabled automatically and
attaches an `expo_constants` context to every event.
No configuration is required.

The context includes the following fields (only non-empty values are set):

| Field | Type | Source |
| --- | --- | --- |
| `execution_environment` | `string` | `'bare'`, `'standalone'`, or `'storeClient'` |
| `app_ownership` | `string` | `'expo'` in Expo Go, otherwise absent |
| `debug_mode` | `boolean` | Whether the app is in debug mode |
| `expo_version` | `string` | Expo Go client version |
| `expo_runtime_version` | `string` | EAS Update runtime version |
| `session_id` | `string` | Unique per app session |
| `status_bar_height` | `number` | Device status bar height in points |
| `app_name` | `string` | `expoConfig.name` from `app.json` |
| `app_slug` | `string` | `expoConfig.slug` from `app.json` |
| `app_version` | `string` | `expoConfig.version` from `app.json` |
| `expo_sdk_version` | `string` | Expo SDK version from `app.json` |
| `eas_project_id` | `string` | EAS project ID from `easConfig.projectId` |

To view the context in Sentry, open any event from an Expo app and look for the
`expo_constants` section in the event detail page.

### Overriding or Extending Device Context

```typescript
Sentry.setContext("device", {
  custom_hardware_id: "DEVICE-UUID-123",
});

Sentry.setContext("app", {
  app_version: "3.2.1",
  app_build: "421",
  custom_build_flavor: "staging",
});
```

### Release, Distribution & Environment

```typescript
Sentry.init({
  // Used in Sentry for regression detection and release health
  release: "com.myapp@3.2.1+421",

  // Distinguishes builds within a release (e.g., Xcode build number)
  dist: "421",

  // Shown on every event for filtering
  environment: "production", // "staging" | "development" | "production"
});
```

* * *

## 16. Release Health & Sessions

Sentry tracks **session-based metrics** to surface crash-free rates and regressions
across app versions.

### How Sessions Work

A session begins when the app comes to the foreground and ends when it goes to
background for longer than `sessionTrackingIntervalMillis` (default: 30 seconds).
Each session maps to a release version, enabling Sentry to compute:

- **Crash-free session rate** — % of sessions without a fatal crash
- **Crash-free user rate** — % of users without a crash in a given release

```typescript
Sentry.init({
  release: "com.myapp@3.2.1+421",
  autoSessionTracking: true,                    // default: true
  sessionTrackingIntervalMillis: 30000,          // default: 30s background threshold
});
```

Sessions are sent automatically.
No additional API calls are required.

* * *

## 17. Offline Event Caching

The SDK caches events locally when the device has no network connectivity.
Events are transmitted automatically when connectivity is restored.

```typescript
Sentry.init({
  // Maximum number of envelopes to cache on disk (default: 30)
  maxCacheItems: 30,
});
```

| Platform | Cache Location | Transmission Trigger |
| --- | --- | --- |
| Android | Internal app storage | App restart |
| iOS | App sandbox `Library/Caches/` | Next event fires |

Offline caching works for both JS-layer events and native crash reports.

* * *

## 18. Default Integrations

The following integrations are enabled automatically:

| Integration | Purpose |
| --- | --- |
| **InboundFilters** | Drops events matching `ignoreErrors`, `denyUrls`, `allowUrls`. Default-ignores `"Script error"` |
| **FunctionToString** | Preserves original function names even when SDK wraps handlers |
| **Breadcrumbs** | Patches `console`, `fetch`, `XHR` to auto-capture breadcrumbs |
| **NativeLinkedErrors** | Reads `.cause` chains up to 5 levels deep |
| **HttpContext** | Attaches URL, user-agent, referrer to events |
| **Dedupe** | Prevents duplicate consecutive events from being reported |
| **UnhandledRejection** | Auto-captures unhandled promise rejections |
| **ExpoConstants** | Attaches `expo_constants` context (execution environment, app name, EAS project ID, etc.) to every event. Active only when running in an Expo app |

### Customizing Default Integrations

```typescript
// Disable all defaults (rarely needed)
Sentry.init({ defaultIntegrations: false });

// Disable console breadcrumbs only
Sentry.init({
  integrations: [
    Sentry.breadcrumbsIntegration({
      console: false,  // disable console breadcrumbs
      fetch: true,
      xhr: true,
      sentry: true,
      // Note: `dom` and `history` are web-only — not applicable in React Native
    }),
  ],
});

// Remove a specific integration
Sentry.init({
  integrations: (integrations) =>
    integrations.filter((i) => i.name !== "Breadcrumbs"),
});
```

### Opt-In Integrations

```typescript
Sentry.init({
  integrations: [
    // Capture failed HTTP requests (non-2xx) as Sentry errors (v5.3.0+)
    Sentry.httpClientIntegration({
      failedRequestStatusCodes: [[400, 599]],
      failedRequestTargets: ["https://api.myapp.com"],
    }),

    // Rewrite stack frame file paths (useful for custom source map layouts)
    Sentry.rewriteFramesIntegration({ root: "/" }),
  ],
  // Shorthand for httpClientIntegration with default settings:
  enableCaptureFailedRequests: true,
});
```

* * *

## 19. Full `init()` Options Reference

```typescript
import * as Sentry from "@sentry/react-native";

Sentry.init({
  // ── Core ──────────────────────────────────────────────────────────
  dsn: "https://examplePublicKey@o0.ingest.sentry.io/0",
  enabled: true,              // false disables all SDK transmission
  debug: false,               // log SDK internals to console
  release: "com.myapp@3.2.1+421",
  dist: "421",                // distinguishes builds within a release
  environment: "production",
  sampleRate: 1.0,            // 0.0–1.0; fraction of error events to send

  // ── Filtering ─────────────────────────────────────────────────────
  ignoreErrors: ["Script error", /^Non-Error/],
  ignoreTransactions: ["/healthcheck"],
  // denyUrls / allowUrls match stack frame URLs — primarily useful for web;
  // in React Native these can filter native frames but are rarely needed.
  // denyUrls: ["chrome-extension://", /extensions\//i],
  // allowUrls: ["https://myapp.com"],
  maxBreadcrumbs: 100,
  maxValueLength: 250,        // max length of string values in events

  // ── Normalization ─────────────────────────────────────────────────
  normalizeDepth: 3,          // depth to normalize context objects
  normalizeMaxBreadth: 1000,  // max number of object properties

  // ── Hooks ─────────────────────────────────────────────────────────
  beforeSend(event, hint) {
    // JS-layer events only. Return null to drop.
    return event;
  },
  beforeSendTransaction(event) {
    return event;
  },
  beforeBreadcrumb(breadcrumb, hint) {
    return breadcrumb; // return null to drop
  },

  // ── Attachments ───────────────────────────────────────────────────
  attachStacktrace: true,          // stack traces on captureMessage calls
  attachScreenshot: false,         // auto-screenshot on error (v4.11.0+)
  attachViewHierarchy: false,      // native view hierarchy JSON on error
  sendDefaultPii: false,           // allow integrations to send PII

  // ── Transport ─────────────────────────────────────────────────────
  maxCacheItems: 30,               // max envelopes cached offline
  shutdownTimeout: 2000,           // ms to wait for queue drain on shutdown

  // ── Sessions ──────────────────────────────────────────────────────
  autoSessionTracking: true,
  sessionTrackingIntervalMillis: 30000,

  // ── Performance / Tracing ─────────────────────────────────────────
  tracesSampleRate: 0.2,
  tracesSampler: ({ name, attributes, parentSampled }) => {
    if (name.includes("healthcheck")) return 0;
    if (typeof parentSampled === "boolean") return parentSampled;
    return 0.2;
  },
  tracePropagationTargets: ["localhost", /^https:\/\/api\.myapp\.com/],
  enableAutoPerformanceTracing: true,

  // ── Native / Hybrid ───────────────────────────────────────────────
  enableNative: true,
  enableNativeCrashHandling: true,
  autoInitializeNativeSdk: true,
  enableNdkScopeSync: true,            // sync Java scope to NDK (Android)
  enableTombstone: true,               // Android 12+ ApplicationExitInfo (default: false)
  attachThreads: false,                // all threads on Android events
  enableNativeNagger: true,            // warn if native init fails
  enableWatchdogTerminationTracking: true, // iOS OOM tracking

  // ── ANR / App Hang ────────────────────────────────────────────────
  enableAppHangTracking: true,         // Apple platforms only
  appHangTimeoutInterval: 2,           // Apple platforms only, seconds

  // ── HTTP Client ───────────────────────────────────────────────────
  enableCaptureFailedRequests: false,  // auto-capture HTTP errors (v5.3.0+)

  // ── Callbacks ─────────────────────────────────────────────────────
  onReady: () => console.log("Sentry native SDKs initialized"),
  onNativeLog: ({ level, component, message }) => {
    // Forward native SDK logs to JS console (debug: true required)
    // Use consoleSandbox to prevent breadcrumb feedback loops
  },

  // ── Integrations ──────────────────────────────────────────────────
  integrations: [
    Sentry.feedbackIntegration({
      styles: { submitButton: { backgroundColor: "#6a1b9a" } },
    }),
    Sentry.httpClientIntegration(),
  ],
  defaultIntegrations: true,  // false disables all built-in integrations
});
```

* * *

## 20. Quick Reference Cheatsheet

```typescript
import * as Sentry from "@sentry/react-native";

// ── Init & Wrap ────────────────────────────────────────────────────
Sentry.init({ dsn: "...", release: "...", environment: "production" });
export default Sentry.wrap(App);  // required for touch breadcrumbs + feedback widget

// ── Capture ───────────────────────────────────────────────────────
Sentry.captureException(new Error("oh no"));
Sentry.captureMessage("Something happened", "warning");
Sentry.captureEvent({ message: "raw event", level: "info" });

// ── Identity & Context ────────────────────────────────────────────
Sentry.setUser({ id: "42", email: "user@example.com" });
Sentry.setTag("version", "3.2.1");
Sentry.setContext("order", { id: "ORD-99", total: 59.99 });

// ── Scopes ────────────────────────────────────────────────────────
Sentry.withScope((scope) => {
  scope.setTag("temp", "value");
  Sentry.captureException(err);
});
Sentry.getGlobalScope().setTag("app", "mobile");
Sentry.getCurrentScope().clear();

// ── Breadcrumbs ───────────────────────────────────────────────────
Sentry.addBreadcrumb({ category: "auth", message: "Login", level: "info" });

// ── Error Boundaries ──────────────────────────────────────────────
<Sentry.ErrorBoundary
  fallback={({ error, resetError }) => (
    <View><Text>{error.toString()}</Text><Button onPress={resetError} title="Retry" /></View>
  )}
  beforeCapture={(scope) => scope.setTag("section", "main")}
>
  <App />
</Sentry.ErrorBoundary>

// ── Event Processor ───────────────────────────────────────────────
Sentry.addEventProcessor((event) => { event.extra = { foo: "bar" }; return event; });
```

* * *

## 21. Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing in Sentry | Check DSN is correct; set `debug: true` to see SDK logs; verify `enabled: true`; check for `beforeSend` returning `null` |
| Native crashes not reported | Ensure `enableNative: true` and `enableNativeCrashHandling: true`; check that native SDKs initialized (look for `onReady` callback firing) |
| ANR/hang events not appearing | Android ANR is always on; for iOS, verify `enableAppHangTracking: true` and try lowering `appHangTimeoutInterval` |
| `Sentry.wrap` not working | Confirm it wraps the **root component** registered with `AppRegistry` (not an inner component) |
| `showFeedbackWidget()` crashes | App must be wrapped with `Sentry.wrap(App)`; ensure Fabric (new arch) requires RN ≥ 0.71 |
| Screenshots are blank | Screenshot capture may be blocked on certain Android versions; ensure `attachScreenshot: true` |
| `beforeSend` not filtering native crashes | `beforeSend` only filters JS-layer events; native crashes bypass it — use `enableNativeCrashHandling: false` to disable native crash capture entirely |
| Duplicate events appearing | Check for multiple `Sentry.init()` calls; `Dedupe` integration handles sequential duplicates but not concurrent ones |
| Too many breadcrumbs / events | Reduce `maxBreadcrumbs`; use `beforeBreadcrumb` to filter; use `sampleRate` to reduce event volume |
| HTTP errors not captured | Add `enableCaptureFailedRequests: true` (v5.3.0+) or configure `httpClientIntegration()` |
| Missing stack frames (minified) | Upload source maps via Sentry CLI or the Metro plugin; check `dist` and `release` match the build |
| `setContext` data not appearing | Verify key `"type"` is not used (reserved); check `normalizeDepth` isn’t truncating nested data |
| Event payload rejected with 413 | Attachment or context too large; use `stateTransformer` in Redux enhancer; limit attachment sizes |
| Offline events not sent | Events are sent on next app launch (Android) or next event fire (iOS); check `maxCacheItems` isn’t set too low |
