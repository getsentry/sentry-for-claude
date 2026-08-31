# Error Monitoring & Crash Reporting — Sentry Android SDK

> **Minimum SDK:** `io.sentry:sentry-android` ≥ 7.0.0 (≥ 8.0.0 recommended) **NDK
> support:** `io.sentry:sentry-android-ndk` (included in `sentry-android` BOM)
> **Languages:** Kotlin and Java — all examples in Kotlin with Java equivalents where
> they differ

Android error monitoring covers three crash layers: **Java/Kotlin exceptions** (JVM),
**ANR (Application Not Responding)** events, and **native C/C++ crashes** via NDK. All
three are handled automatically after initialization.

* * *

## Table of Contents

1. [Core Capture APIs](#1-core-capture-apis)
2. [Automatic Crash Handling](#2-automatic-crash-handling)
3. [ANR Detection](#3-anr-detection)
4. [NDK / Native Crash Capture](#4-ndk--native-crash-capture)
5. [Scope Management](#5-scope-management)
6. [Context Enrichment — Tags, User, Breadcrumbs](#6-context-enrichment--tags-user-breadcrumbs)
7. [Event Filtering — beforeSend, beforeBreadcrumb](#7-event-filtering--beforesend-beforebreadcrumb)
8. [Fingerprinting & Grouping](#8-fingerprinting--grouping)
9. [Attachments — Screenshots & View Hierarchy](#9-attachments--screenshots--view-hierarchy)
10. [Release Health & Sessions](#10-release-health--sessions)
11. [Configuration Reference](#11-configuration-reference)
12. [Troubleshooting](#12-troubleshooting)

* * *

## 1. Core Capture APIs

All methods are static on `io.sentry.Sentry`. Returns a `SentryId` that can be
referenced for user feedback.

### `Sentry.captureException()`

```kotlin
import io.sentry.Sentry
import io.sentry.SentryLevel

// Basic capture
try {
    aMethodThatMightFail()
} catch (e: Exception) {
    Sentry.captureException(e)
}

// With local scope (applies only to this event)
try {
    processPayment(order)
} catch (e: Exception) {
    Sentry.captureException(e) { scope ->
        scope.setTag("component", "payment")
        scope.setLevel(SentryLevel.FATAL)
        scope.setTransaction("CheckoutFlow")
    }
}
```

Java equivalent:
```java
Sentry.captureException(e, scope -> {
    scope.setTag("component", "payment");
    scope.setLevel(SentryLevel.FATAL);
});
```

### `Sentry.captureMessage()`

```kotlin
// Default level is INFO
Sentry.captureMessage("User completed onboarding")

// Explicit level: DEBUG | INFO | WARNING | ERROR | FATAL
Sentry.captureMessage("Payment provider unreachable", SentryLevel.WARNING)
Sentry.captureMessage("Database connection pool exhausted", SentryLevel.FATAL)
```

### `Sentry.captureEvent()`

For fully constructed `SentryEvent` objects — advanced use cases:

```kotlin
import io.sentry.SentryEvent
import io.sentry.protocol.Message

val event = SentryEvent()
event.level = SentryLevel.WARNING
val msg = Message()
msg.message = "Custom structured event"
event.message = msg
event.setTag("build_type", BuildConfig.BUILD_TYPE)
Sentry.captureEvent(event)
```

### `Sentry.captureUserFeedback()`

```kotlin
import io.sentry.UserFeedback

val feedback = UserFeedback(Sentry.lastEventId)
feedback.name = "Jane Smith"
feedback.email = "jane@example.com"
feedback.comments = "The app froze when I tapped the submit button."
Sentry.captureUserFeedback(feedback)
```

### Error Levels

| Level | Android use case |
| --- | --- |
| `FATAL` | App crash, unrecoverable state |
| `ERROR` | Feature broken, user action failed |
| `WARNING` | Degraded state, non-critical failure |
| `INFO` | Informational, notable events |
| `DEBUG` | Development diagnostics |

* * *

## 2. Automatic Crash Handling

The SDK installs `UncaughtExceptionHandlerIntegration` at init time, which wraps
`Thread.defaultUncaughtExceptionHandler`.

### How it works

```
Unhandled exception thrown
       │
       ▼
UncaughtExceptionHandlerIntegration.uncaughtException()
   ├── wraps throwable in ExceptionMechanismException (mechanism: "AppExitReason")
   ├── creates SentryEvent at FATAL level
   ├── captures event and BLOCKS until flushed to disk
   └── calls original defaultUncaughtExceptionHandler (re-throws to Android runtime)
```

Crashes are persisted to disk immediately and transmitted on the **next app launch**.
This ensures crash data is never lost even when the process dies.

### Startup crash handling

If the app crashes within ~2 seconds of SDK init, `SentryAndroid.init()` blocks for up
to 5 seconds to flush the crash before the process exits:

```kotlin
SentryAndroid.init(this) { options ->
    options.startupCrashFlushTimeoutMillis = 5_000L // default: 5 s
}
```

### Disable uncaught exception handler

```kotlin
options.isEnableUncaughtExceptionHandler = false
```

* * *

## 3. ANR Detection

ANR (Application Not Responding) events fire when the main thread is blocked for more
than 5 seconds.

### How it works

`AnrIntegration` runs a watchdog thread (`ANRWatchDog`) that posts a `Runnable` to the
main `Looper` every 500 ms.
If the main thread hasn’t processed the runnable within `anrTimeoutIntervalMillis`, an
ANR event is reported.

```
ANRWatchDog (background thread)
  ├── Posts Runnable to MainLooper every 500 ms
  └── If (now - lastResponseTime) > anrTimeoutIntervalMillis
      → Captures ANR event with mechanism type "ANR"
      → Background ANRs use mechanism "anr_background"
```

### Configuration

```kotlin
SentryAndroid.init(this) { options ->
    options.isAnrEnabled = true                // default: true
    options.anrTimeoutIntervalMillis = 5_000L  // default: 5000 ms
    options.isAnrReportInDebug = false         // default: false (suppress during development)
    options.isAttachAnrThreadDump = true       // attach thread dump as text attachment
}
```

Via `AndroidManifest.xml`:
```xml
<meta-data android:name="io.sentry.anr.enable" android:value="true" />
<meta-data android:name="io.sentry.anr.timeout-interval-millis" android:value="5000" />
<meta-data android:name="io.sentry.anr.report-debug" android:value="false" />
```

### ANR v2 — ApplicationExitInfo (Android 11+)

On API 30+, the SDK reads `ActivityManager.getHistoricalProcessExitReasons()` to report
ANRs from the previous app run that the watchdog couldn’t capture in real-time:

```kotlin
options.isReportHistoricalAnrs = true  // default: false — report previous-run ANRs
```

* * *

## 4. NDK / Native Crash Capture

Native crashes (SIGSEGV, SIGABRT, C++ exceptions) are captured by `sentry-android-ndk`,
which wraps the `sentry-native` C SDK.

### Dependency

```kotlin
// build.gradle.kts — included automatically with the BOM
dependencies {
    implementation(platform("io.sentry:sentry-bom:8.33.0"))
    implementation("io.sentry:sentry-android")    // includes ndk
}
```

### How it works

1. `SentryNdk.init()` loads native libs on a background thread (2 s timeout)
2. Registers native signal handlers via `sentry-native`
3. On crash: writes crash report to disk
4. On next app launch: `sentry-android-core` reads and transmits the report

### NDK Scope Sync

Java scope changes (user, tags, breadcrumbs) are propagated to the native layer so NDK
crashes include the same context as Java events:

```kotlin
options.isEnableScopeSync = true // default: true
```

### Native tombstones (Android 11+)

```kotlin
options.isTombstoneEnabled = true // report native tombstones via ApplicationExitInfo
```

Via manifest:
```xml
<meta-data android:name="io.sentry.tombstone.enable" android:value="true" />
```

### Disable NDK

```kotlin
options.isEnableNdk = false
```

* * *

## 5. Scope Management

Sentry uses a three-layer scope hierarchy.
Data merges in order: **Global → Isolation → Current** (current takes precedence for
single-value fields).

| Scope | Lifespan | How to access |
| --- | --- | --- |
| **Global** | Entire app lifetime | `Sentry.configureScope(ScopeType.GLOBAL) { }` |
| **Isolation** | Per-request/session | `Sentry.configureScope { }` (default) |
| **Current** | Block-level | `Sentry.withScope { }` |

### `Sentry.configureScope()` — persist across events

```kotlin
import io.sentry.Sentry
import io.sentry.protocol.User

// Set data for all subsequent events in this session
Sentry.configureScope { scope ->
    scope.setTag("app.variant", BuildConfig.FLAVOR)

    val user = User().apply {
        id = "42"
        email = "jane@example.com"
        username = "jane_doe"
    }
    scope.setUser(user)
}

// Clear user on logout
Sentry.configureScope { scope ->
    scope.setUser(null)
}
```

### `Sentry.withScope()` — temporary, discarded after block

```kotlin
// Tags/context here do NOT affect events outside this block
Sentry.withScope { scope ->
    scope.setTag("transaction_id", orderId)
    scope.setLevel(SentryLevel.WARNING)
    Sentry.captureMessage("Order processing failed")
}
// scope is discarded — subsequent events are unaffected
```

### `Sentry.pushScope()` — try-with-resources (Java)

```java
try (ISentryLifecycleToken ignored = Sentry.pushScope()) {
    Sentry.configureScope(scope -> scope.setTag("local", "value"));
    Sentry.captureMessage("Event with local tag");
} // scope is automatically popped
```

### Shorthand static methods

```kotlin
Sentry.setUser(user)                        // → configureScope { scope.setUser(user) }
Sentry.setTag("key", "value")               // → configureScope { scope.setTag(...) }
Sentry.removeTag("key")
Sentry.setExtra("key", "value")             // deprecated — use setContexts
Sentry.setFingerprint(listOf("my-key"))
Sentry.setTransaction("CheckoutFlow")
```

* * *

## 6. Context Enrichment — Tags, User, Breadcrumbs

### Tags — indexed and searchable

Tags are key/value string pairs indexed in Sentry, enabling full-text search and
filtering.

**Constraints:** key ≤ 32 chars; value ≤ 200 chars; no newlines in values.

```kotlin
Sentry.configureScope { scope ->
    scope.setTag("app.variant", "google-play")
    scope.setTag("checkout.step", "payment")
    scope.setTag("subscription.tier", "premium")
}

// Or static shorthand
Sentry.setTag("server.region", "eu-west-1")
```

### User identity

```kotlin
import io.sentry.protocol.User

val user = User().apply {
    id = "12345"
    username = "jane_doe"
    email = "jane@example.com"
    ipAddress = "{{auto}}"  // Sentry resolves from request
    data = mapOf(
        "subscription" to "premium",
        "region" to "eu"
    )
}
Sentry.setUser(user)

// Clear on logout
Sentry.setUser(null)
```

### Custom contexts (structured, non-searchable)

```kotlin
// Use for rich structured data; use tags for searchable data
Sentry.configureScope { scope ->
    scope.setContexts("order", mapOf(
        "id" to "ORD-9821",
        "total" to 129.99,
        "item_count" to 3
    ))
    scope.setContexts("device_capability", mapOf(
        "has_nfc" to true,
        "ram_gb" to 4
    ))
}
```

> **Note:** The key `"type"` is reserved — don’t use it as a context key.

### Breadcrumbs — event trail

Breadcrumbs buffer until the next event is captured.
They do not create Sentry issues on their own.

```kotlin
import io.sentry.Breadcrumb
import io.sentry.SentryLevel

// Manual breadcrumb
val breadcrumb = Breadcrumb().apply {
    category = "auth"
    message = "User authenticated: ${user.email}"
    level = SentryLevel.INFO
    type = "user"
    setData("method", "biometric")
}
Sentry.addBreadcrumb(breadcrumb)

// Simple string
Sentry.addBreadcrumb("Tapped checkout button")

// String with category
Sentry.addBreadcrumb("Database query completed", "db")
```

**Breadcrumb fields:**

| Field | Type | Description |
| --- | --- | --- |
| `message` | `String` | Human-readable description |
| `category` | `String` | Dot-separated origin (e.g., `ui.click`, `http`, `auth`) |
| `level` | `SentryLevel` | `DEBUG`, `INFO`, `WARNING`, `ERROR`, `FATAL` |
| `type` | `String` | `default`, `http`, `navigation`, `user`, `error` |
| `data` | `Map<String, Any>` | Arbitrary additional metadata |

### Automatic breadcrumbs (Android-specific)

The SDK automatically collects these breadcrumbs — all enabled by default:

| Source | Category | What it records |
| --- | --- | --- |
| Activity lifecycle | `ui.lifecycle` | Created, started, resumed, paused, stopped, destroyed |
| App foreground/background | `app.lifecycle` | Foreground, background transitions |
| System events | `device.*` | Battery, screen on/off, network, locale, timezone changes |
| Network connectivity | `network.event` | Connected, disconnected, type changes |
| User interactions | `ui.click` | Touch events on views (if enabled) |
| OkHttp requests | `http` | URL, method, status code (with `SentryOkHttpInterceptor`) |

Disable individual sources:

```kotlin
options.isEnableActivityLifecycleBreadcrumbs = false
options.isEnableAppLifecycleBreadcrumbs = false
options.isEnableSystemEventBreadcrumbs = false
options.isEnableNetworkEventBreadcrumbs = false
options.enableAllAutoBreadcrumbs(false) // disable all at once
```

Via manifest:
```xml
<meta-data android:name="io.sentry.breadcrumbs.activity-lifecycle" android:value="false" />
<meta-data android:name="io.sentry.breadcrumbs.app-lifecycle" android:value="false" />
<meta-data android:name="io.sentry.breadcrumbs.system-events" android:value="false" />
<meta-data android:name="io.sentry.breadcrumbs.network-events" android:value="false" />
```

**Max breadcrumbs** (default: 100):

```kotlin
options.maxBreadcrumbs = 50
```

* * *

## 7. Event Filtering — `beforeSend`, `beforeBreadcrumb`

### `beforeSend` — filter/mutate error events

Called immediately before an error event is transmitted.
Return `null` to drop.

> **Important:** `beforeSend` only applies to Java/Kotlin events.
> Native NDK crashes bypass this hook entirely.

```kotlin
SentryAndroid.init(this) { options ->
    options.beforeSend = SentryOptions.BeforeSendCallback { event, hint ->
        // Drop events from test/CI environments
        if (event.environment == "test") return@BeforeSendCallback null

        // Fingerprint based on throwable type
        if (event.throwable is SQLiteException) {
            event.fingerprints = listOf("database-error")
        }

        // Scrub PII before sending
        event.user?.email = null

        // Attach build metadata
        event.setTag("build_number", BuildConfig.VERSION_CODE.toString())

        event
    }
}
```

Java equivalent:
```java
options.setBeforeSend((event, hint) -> {
    if ("test".equals(event.getEnvironment())) return null;
    return event;
});
```

### `beforeSendTransaction` — filter performance transactions

```kotlin
options.beforeSendTransaction = SentryOptions.BeforeSendTransactionCallback { tx, hint ->
    // Drop health check transactions
    if (tx.transaction == "/health") return@BeforeSendTransactionCallback null
    tx
}
```

### `beforeBreadcrumb` — filter/mutate breadcrumbs

```kotlin
options.beforeBreadcrumb = SentryOptions.BeforeBreadcrumbCallback { breadcrumb, hint ->
    // Drop noisy logger breadcrumbs
    if (breadcrumb.category == "com.third_party.SpammyLib") return@BeforeBreadcrumbCallback null

    // Scrub sensitive URLs
    breadcrumb.data?.let { data ->
        (data["url"] as? String)?.let { url ->
            data["url"] = url.replace(Regex("token=[^&]*"), "token=REDACTED")
        }
    }

    breadcrumb
}
```

### `ignoreErrors` (ignored exception types)

```kotlin
options.addIgnoredError("android.os.NetworkOnMainThreadException")
options.addIgnoredError("java.net.UnknownHostException")
```

* * *

## 8. Fingerprinting & Grouping

Fingerprinting controls how Sentry groups events into issues.
Default grouping is by stack trace.

### SDK-level fingerprinting

```kotlin
// Static fingerprint via scope (all matching events → one issue)
Sentry.configureScope { scope ->
    scope.setFingerprint(listOf("database-connection-error"))
}
Sentry.setFingerprint(listOf("database-connection-error"))

// Dynamic fingerprinting in beforeSend
options.beforeSend = SentryOptions.BeforeSendCallback { event, hint ->
    when (event.throwable) {
        is SQLiteException -> event.fingerprints = listOf("db-error", "sqlite")
        is IOException -> event.fingerprints = listOf("io-error", "{{ default }}")
    }
    event
}

// Per-capture fingerprint
Sentry.captureException(e) { scope ->
    scope.setFingerprint(listOf("payment-gateway-error", "stripe"))
}
```

### Fingerprint variables

| Variable | Resolves to |
| --- | --- |
| `{{ default }}` | Sentry’s default stack-trace hash |
| `{{ error.type }}` | Exception class name |
| `{{ error.value }}` | Exception message |
| `{{ transaction }}` | Current transaction name |
| `{{ level }}` | Event severity |

### Server-side rules (Sentry project settings)

```
# Group all DB errors together
error.type:SQLiteException -> database-error
error.type:IOException     -> io-error, {{ transaction }}
```

* * *

## 9. Attachments — Screenshots & View Hierarchy

### Screenshots

Captures a PNG of the current UI when an error occurs.
**Disabled by default** (may contain PII).

```kotlin
options.isAttachScreenshot = true
```

Via manifest:
```xml
<meta-data android:name="io.sentry.attach-screenshot" android:value="true" />
```

Fine-grained control (SDK ≥ 6.24.0):

```kotlin
options.setBeforeScreenshotCaptureCallback { event, hint, debounce ->
    // Always capture for crashes; respect debounce for other events
    if (event.isCrashed) return@setBeforeScreenshotCaptureCallback true
    if (debounce) return@setBeforeScreenshotCaptureCallback false
    event.level == SentryLevel.FATAL
}
```

### View hierarchy

Captures a JSON representation of the Android view tree when an error occurs.

```kotlin
options.isAttachViewHierarchy = true
```

Via manifest:
```xml
<meta-data android:name="io.sentry.attach-view-hierarchy" android:value="true" />
```

Fine-grained control:

```kotlin
options.setBeforeViewHierarchyCaptureCallback { event, hint, debounce ->
    if (event.isCrashed) true
    else if (debounce) false
    else event.level == SentryLevel.FATAL
}
```

> **Debounce:** View hierarchy is captured at most once every 2 seconds (max 3 times per
> window) to prevent overhead during rapid error cascades.

### Jetpack Compose node names

Add the Sentry Kotlin Compiler Plugin to include composable function names in view
hierarchy JSON:

```kotlin
// build.gradle.kts
plugins {
    id("io.sentry.kotlin.compiler.gradle") version "6.1.0"
}
```

### Manual file attachments

```kotlin
Sentry.captureException(e) { scope ->
    scope.addAttachment(Attachment(
        logContents.toByteArray(),
        "debug.log",
        "text/plain"
    ))
    scope.addAttachment(Attachment(
        File(context.filesDir, "config.json")
    ))
}
```

* * *

## 10. Release Health & Sessions

Session tracking enables crash-free rate metrics per release version.

```kotlin
SentryAndroid.init(this) { options ->
    options.release = "${BuildConfig.APPLICATION_ID}@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"
    options.isEnableAutoSessionTracking = true          // default: true
    options.sessionTrackingIntervalMillis = 30_000L     // default: 30 s background threshold
}
```

Sessions are sent automatically.
No additional API calls required.

A session ends when the app goes to the background for longer than
`sessionTrackingIntervalMillis`. Each session maps to a release, so Sentry can compute:
- **Crash-free session rate** — % of sessions without a fatal crash
- **Crash-free user rate** — % of users without a crash per release

* * *

## 11. Configuration Reference

### `SentryAndroid.init()` — common options

```kotlin
SentryAndroid.init(this) { options ->
    // ── Core ──────────────────────────────────────────────────────────────
    options.dsn = "https://publicKey@o0.ingest.sentry.io/0"
    options.environment = "production"
    options.release = "com.myapp@1.2.3+456"
    options.dist = "456"                        // build number
    options.isDebug = false

    // ── Sampling ─────────────────────────────────────────────────────────
    options.sampleRate = 1.0                    // error event sample rate (0.0–1.0)

    // ── Crash handling ────────────────────────────────────────────────────
    options.isEnableUncaughtExceptionHandler = true   // default
    options.startupCrashFlushTimeoutMillis = 5_000L

    // ── ANR ──────────────────────────────────────────────────────────────
    options.isAnrEnabled = true
    options.anrTimeoutIntervalMillis = 5_000L
    options.isAnrReportInDebug = false
    options.isAttachAnrThreadDump = false
    options.isReportHistoricalAnrs = false       // Android 11+

    // ── NDK ──────────────────────────────────────────────────────────────
    options.isEnableNdk = true
    options.isEnableScopeSync = true
    options.isTombstoneEnabled = false           // Android 11+

    // ── Enrichment ────────────────────────────────────────────────────────
    options.isAttachScreenshot = false           // PII risk — disabled by default
    options.isAttachViewHierarchy = false
    options.isAttachThreads = false              // all thread dumps on every event
    options.isAttachStacktrace = true            // stack traces on captureMessage

    // ── Breadcrumbs ───────────────────────────────────────────────────────
    options.maxBreadcrumbs = 100
    options.isEnableActivityLifecycleBreadcrumbs = true
    options.isEnableAppLifecycleBreadcrumbs = true
    options.isEnableSystemEventBreadcrumbs = true
    options.isEnableNetworkEventBreadcrumbs = true

    // ── Filtering ────────────────────────────────────────────────────────
    options.beforeSend = SentryOptions.BeforeSendCallback { event, _ -> event }
    options.beforeBreadcrumb = SentryOptions.BeforeBreadcrumbCallback { crumb, _ -> crumb }

    // ── Sessions ─────────────────────────────────────────────────────────
    options.isEnableAutoSessionTracking = true
    options.sessionTrackingIntervalMillis = 30_000L
}
```

### `AndroidManifest.xml` — key meta-data entries

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `io.sentry.dsn` | String | — | DSN (required for auto-init) |
| `io.sentry.environment` | String | — | Environment name |
| `io.sentry.release` | String | — | Release version string |
| `io.sentry.debug` | Boolean | `false` | Enable SDK debug logging |
| `io.sentry.sample-rate` | Float | — | Error event sample rate |
| `io.sentry.enabled` | Boolean | `true` | Master on/off switch |
| `io.sentry.auto-init` | Boolean | `true` | Auto-init via ContentProvider |
| `io.sentry.anr.enable` | Boolean | `true` | ANR watchdog |
| `io.sentry.anr.timeout-interval-millis` | Integer | `5000` | ANR threshold |
| `io.sentry.anr.report-debug` | Boolean | `false` | Report ANR during debug |
| `io.sentry.ndk.enable` | Boolean | `true` | NDK crash capture |
| `io.sentry.ndk.scope-sync.enable` | Boolean | `true` | NDK scope sync |
| `io.sentry.attach-screenshot` | Boolean | `false` | Screenshot on error |
| `io.sentry.attach-view-hierarchy` | Boolean | `false` | View hierarchy on error |
| `io.sentry.breadcrumbs.activity-lifecycle` | Boolean | `true` | Activity breadcrumbs |
| `io.sentry.breadcrumbs.app-lifecycle` | Boolean | `true` | App lifecycle breadcrumbs |
| `io.sentry.breadcrumbs.system-events` | Boolean | `true` | System event breadcrumbs |
| `io.sentry.breadcrumbs.network-events` | Boolean | `true` | Network breadcrumbs |

* * *

## 12. Troubleshooting

| Issue | Cause | Solution |
| --- | --- | --- |
| Events not appearing in Sentry | DSN incorrect or SDK not initialized | Verify DSN; set `options.isDebug = true`; check Logcat for `[Sentry]` output |
| Crash events missing | UncaughtExceptionHandler disabled | Ensure `isEnableUncaughtExceptionHandler = true`; check for competing crash handlers (Firebase, Crashlytics) |
| NDK crashes not reported | NDK module not included or `isEnableNdk = false` | Add `sentry-android-ndk` dependency; confirm `isEnableNdk = true` |
| ANR events missing in release builds | On Android 11+ the SDK uses ANR v2 (`ApplicationExitInfo`), which reports ANRs on the **next app launch** rather than in real time, and by default reports only the most recent ANR | Verify `isAnrEnabled = true`, relaunch the app so the SDK can read `ApplicationExitInfo`, and set `isReportHistoricalAnrs = true` to also report older ANRs from the exit-reasons history |
| `beforeSend` not filtering native crashes | `beforeSend` only applies to JVM events | NDK crashes bypass `beforeSend`; to suppress NDK entirely: `isEnableNdk = false` |
| Screenshots are blank or black | Activity window not attached at crash time | Best-effort capture; ensure crash occurs with an active `Activity` |
| View hierarchy missing composable names | Sentry Kotlin Compiler Plugin not added | Add `io.sentry.kotlin.compiler.gradle` plugin to `build.gradle.kts` |
| Duplicate events | Multiple `SentryAndroid.init()` calls | Call `init()` once in `Application.onCreate()` only |
| ANR not firing in debug session | Debugger pauses the main thread, which blocks the watchdog | `isAnrReportInDebug` defaults to `false`; this is expected behavior |
| Session tracking not working | `release` not set | `isEnableAutoSessionTracking` requires a non-null `release` to be meaningful |
| `captureException` returns zero-ID | SDK not initialized or `enabled = false` | Verify `SentryAndroid.init()` was called in `Application.onCreate()` before the crash |
| Historical ANRs not reported | Feature not enabled | Set `isReportHistoricalAnrs = true`; requires Android 11+ (API 30) |
| Tags or user missing from NDK crashes | Scope sync disabled | Ensure `isEnableScopeSync = true` (default) |
| Events rejected with HTTP 413 | Payload too large | Reduce attachment sizes; avoid large context objects; limit `maxBreadcrumbs` |
