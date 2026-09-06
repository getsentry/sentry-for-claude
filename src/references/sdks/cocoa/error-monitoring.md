# Error Monitoring — Sentry Cocoa SDK

> Minimum SDK: `sentry-cocoa` v7.0.0+ Swift Error improvements: v8.7.0+ HTTP client
> error capture: v8.0.0+

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enableCrashHandler` | `Bool` | `true` | Master switch for crash reporting (signal handlers, Mach exceptions, C++) |
| `sampleRate` | `Float` (0.0–1.0) | `1.0` | Percentage of error events sent |
| `attachStacktrace` | `Bool` | `true` | Attach stack traces to all captured messages |
| `attachAllThreads` | `Bool` | `false` | Attach full stack traces for all threads (SDK 9.9+) |
| `maxBreadcrumbs` | `Int` | `100` | Max breadcrumbs per event |
| `enableAppHangTracking` | `Bool` | `true` | Detect main thread unresponsiveness |
| `appHangTimeoutInterval` | `Double` | `2.0` | Seconds before a hang is reported |
| `enableReportNonFullyBlockingAppHangs` | `Bool` | `true` | Include non-fully-blocking hangs where V2 is supported |
| `enableWatchdogTerminationTracking` | `Bool` | `true` | Track OS watchdog kills via heuristics |
| `enableCaptureFailedRequests` | `Bool` | `true` | Auto-capture HTTP client errors as Sentry events |
| `failedRequestStatusCodes` | `[HttpStatusCodeRange]` | `[500–599]` | Status code ranges that trigger error capture |
| `failedRequestTargets` | `[String]` | `[".*"]` | Hosts/regex patterns to monitor for HTTP errors |
| `attachScreenshot` | `Bool` | `false` | Capture screenshot when an error event fires |
| `attachViewHierarchy` | `Bool` | `false` | Capture view hierarchy when an error event fires |
| `sendDefaultPii` | `Bool` | `false` | Include PII (IP address, username) in events |

## Code Examples

### SDK initialization

```swift
import Sentry

SentrySDK.start { options in
    options.dsn = "https://examplePublicKey@o0.ingest.sentry.io/0"
    options.environment = "production"
    options.releaseName = "my-app@2.0.0+123"
    options.enableCrashHandler = true   // default; explicit for clarity
    options.attachScreenshot = true
    options.attachViewHierarchy = true
}
```

### Capture a message

```swift
SentrySDK.capture(message: "Something noteworthy happened")
```

### Capture a Swift Error / NSError

```swift
do {
    try riskyOperation()
} catch {
    SentrySDK.capture(error: error)
}
```

### Capture a custom SentryEvent

```swift
let event = Event(level: .warning)
event.message = SentryMessage(formatted: "Checkout flow aborted")
event.tags = ["feature": "checkout"]
event.extra = ["cart_items": 3]
SentrySDK.capture(event: event)
```

### Swift Error enum — human-readable titles (v8.7.0+)

By default, Swift error enum cases appear as `LoginError - Code: 1`. To get readable
titles, conform to `CustomNSError`:

```swift
enum LoginError: Error {
    case wrongUser(id: String)
    case wrongPassword
}

extension LoginError: CustomNSError {
    var errorUserInfo: [String: Any] {
        [NSDebugDescriptionErrorKey: debugDescription]
    }

    private var debugDescription: String {
        switch self {
        case .wrongUser(let id): return "Wrong user (id: \(id))"
        case .wrongPassword:     return "Wrong password"
        }
    }
}

// Captures "LoginError - Wrong user (id: 12345)" as the issue title
SentrySDK.capture(error: LoginError.wrongUser(id: "12345"))
```

> Use `NSDebugDescriptionErrorKey`, NOT `NSLocalizedDescriptionKey`. Localized strings
> vary by device locale and create duplicate issues.

### Capture with per-event scope

The scope callback receives an isolated copy — changes don’t affect global state:

```swift
SentrySDK.capture(error: error) { scope in
    scope.setTag(value: "payment", key: "checkout.step")
    scope.setContext(value: ["amount": 99.99, "currency": "USD"], key: "payment")
}

SentrySDK.capture(message: "Payment declined") { scope in
    scope.setLevel(.fatal)
    scope.setTag(value: "stripe", key: "payment_provider")
}
```

### App hang detection

```swift
SentrySDK.start { options in
    options.dsn = "___PUBLIC_DSN___"
    options.enableAppHangTracking = true
    options.appHangTimeoutInterval = 2.0    // default; avoid values < 0.1

    // V2 is the default in v9+ where supported; this option controls whether
    // less-actionable non-fully-blocking hangs are reported.
    options.enableReportNonFullyBlockingAppHangs = true
}

// Pause tracking during expected blocking operations (e.g., permission dialogs)
SentrySDK.pauseAppHangTracking()
// ... system dialog ...
SentrySDK.resumeAppHangTracking()
```

V2 exception types:

| Type | Meaning |
| --- | --- |
| `App Hang Fully Blocked` | Main thread completely frozen |
| `App Hang Non Fully Blocked` | App stuck but still renders some frames |
| `Fatal App Hang Fully Blocked` | Force-quit / watchdog kill during full block |
| `Fatal App Hang Non Fully Blocked` | Force-quit / watchdog kill during partial block |

### HTTP client error capture

```swift
SentrySDK.start { options in
    options.dsn = "___PUBLIC_DSN___"
    options.enableCaptureFailedRequests = true

    // Capture 4xx and 5xx
    options.failedRequestStatusCodes = [
        HttpStatusCodeRange(min: 400, max: 599)
    ]

    // Only monitor your own backend
    options.failedRequestTargets = [
        "api.myapp.com",
        ".*\\.myapp\\.com"   // regex supported
    ]
}
```

### Scope management

```swift
// Global scope — persists across all events
SentrySDK.configureScope { scope in
    scope.setTag(value: "premium", key: "subscription")
    scope.setExtra(value: 42, key: "retry_count")

    let user = User()
    user.email = "user@example.com"
    user.userId = "abc123"
    scope.setUser(user)

    scope.setContext(value: [
        "version": "2.1",
        "platform": "ios"
    ], key: "app_info")
}

// Clear a specific value
SentrySDK.configureScope { scope in
    scope.removeTag(key: "subscription")
    scope.setUser(nil)   // clear user on logout
}

// Clear everything
SentrySDK.configureScope { $0.clear() }
```

### Set user identity

```swift
let user = User()
user.userId = "user-abc-123"
user.email = "john.doe@example.com"
user.username = "johndoe"
user.data = ["plan": "premium"]
SentrySDK.setUser(user)

// On logout
SentrySDK.setUser(nil)
```

### Breadcrumbs

```swift
let crumb = Breadcrumb()
crumb.level = .info
crumb.category = "auth"
crumb.type = "user"
crumb.message = "User logged in"
crumb.data = ["method": "oauth", "provider": "google"]
SentrySDK.addBreadcrumb(crumb)
```

Filter breadcrumbs via `beforeBreadcrumb`:

```swift
SentrySDK.start { options in
    options.beforeBreadcrumb = { crumb in
        if crumb.message?.contains("password") == true { return nil }
        return crumb
    }
}
```

### beforeSend hook — filter and modify events

```swift
SentrySDK.start { options in
    options.beforeSend = { event in
        // Drop events from internal testers
        if event.user?.email?.hasSuffix("@mycompany.com") == true {
            return nil
        }
        // Suppress app hang events
        // V1/macOS may use "App Hanging"; V2 uses the more specific values
        // listed above. Inspect event.exceptions?.first?.type in beforeSend.
        if event.exceptions?.first?.type?.contains("App Hang") == true {
            return nil
        }
        // Scrub sensitive data
        event.request?.cookies = nil
        // Add global tag
        event.tags?["processed_by"] = "beforeSend"
        return event
    }
}
```

### Screenshot and view hierarchy attachments

```swift
SentrySDK.start { options in
    options.attachScreenshot = true
    options.screenshot.maskAllText = true        // default: true
    options.screenshot.maskAllImages = true      // default: true
    options.screenshot.maskedViewClasses = [MySecretView.self]
    options.screenshot.unmaskedViewClasses = [MyLogoView.self]

    options.attachViewHierarchy = true
    options.reportAccessibilityIdentifier = true // disable if identifiers contain PII

    // Conditional capture
    options.beforeCaptureScreenshot = { event in event.level == .fatal }
    options.beforeCaptureViewHierarchy = { _ in true }
}
```

### Fingerprinting and custom grouping

```swift
// Per-event fingerprint via scope
SentrySDK.capture(error: error) { scope in
    scope.fingerprint = ["payment-service-timeout", "stripe"]
}

// Pattern-based in beforeSend — extend default grouping
SentrySDK.start { options in
    options.beforeSend = { event in
        if let error = event.error as NSError?,
           error.domain == NSURLErrorDomain,
           let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? String {
            event.fingerprint = ["{{ default }}", url, String(error.code)]
        }
        return event
    }
}

// Aggressive grouping — all SQLite errors → one issue
SentrySDK.start { options in
    options.beforeSend = { event in
        if let error = event.error as NSError?,
           error.domain == NSSQLiteErrorDomain {
            event.fingerprint = ["database-connection-error"]
        }
        return event
    }
}
```

`"{{ default }}"` substitutes Sentry’s standard hash, allowing you to *extend* rather
than fully replace default grouping.

### onLastRunStatusDetermined callback

```swift
SentrySDK.start { options in
    options.dsn = "___PUBLIC_DSN___"
    options.onLastRunStatusDetermined = { status, crashEvent in
        // Called once after init when the previous run's crash status is determined.
        // Keep this minimal — complex logic can cascade into another crash.
        if status == .didCrash {
            UserDefaults.standard.set(true, forKey: "didCrashLastRun")
        }
    }
}
```

## Automatic Crash Reporting

When `enableCrashHandler = true` (default), the SDK installs:

- **Signal handlers** — SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP
- **Mach exception handlers** — low-level kernel exceptions
- **C++ exception handlers** — `std::terminate` interception
- **Objective-C uncaught exception handler** — `NSSetUncaughtExceptionHandler`

> Warning: Always test crash reporting **without a debugger attached**. The debugger
> intercepts signals and prevents the SDK from capturing crashes.

### macOS — uncaught NSException reporting

```swift
SentrySDK.start { options in
    options.dsn = "___PUBLIC_DSN___"
    options.enableUncaughtNSExceptionReporting = true
}
```

### SIGTERM reporting (v8.27.0+)

```swift
options.enableSigtermReporting = true   // report background task timeouts
```

## Scope API Quick Reference

```swift
SentrySDK.configureScope { scope in
    scope.setTag(value: "v2", key: "api_version")
    scope.removeTag(key: "api_version")
    scope.setExtra(value: someObject, key: "debug_info")
    scope.removeExtra(key: "debug_info")
    scope.setContext(value: ["key": "value"], key: "my_context")
    scope.removeContext(key: "my_context")
    scope.setUser(User(userId: "12345"))
    scope.setUser(nil)
    scope.setLevel(.error)
    scope.fingerprint = ["my-group-key"]
    scope.addBreadcrumb(crumb)
    scope.clear()
}
```

## Best Practices

- Set `releaseName` to a consistent value (e.g.,
  `CFBundleShortVersionString + "+" + CFBundleVersion`) for regression tracking between
  deployments
- Use `NSDebugDescriptionErrorKey` — not `NSLocalizedDescriptionKey` — for error user
  info to avoid locale-based duplicate issues
- Use `beforeSend` to strip PII (`event.request?.cookies = nil`) when
  `sendDefaultPii = false`
- Use `onLastRunStatusDetermined` only for lightweight operations (flag writes); heavy
  logic risks a cascading crash
- Disable app hang tracking for **Widgets and Live Activities** to avoid false positives
- Use `initialScope` to set global context before the first event fires

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Crashes not appearing in Sentry | Test without debugger attached; debugger intercepts signals |
| Swift errors show “Code: 1” | Conform to `CustomNSError` and provide `NSDebugDescriptionErrorKey` in `errorUserInfo` |
| Duplicate issues from localization | Use `NSDebugDescriptionErrorKey`, not `NSLocalizedDescriptionKey` |
| App hang events too noisy | Raise `appHangTimeoutInterval`; or filter in `beforeSend` by exception type |
| HTTP errors not captured | Verify `enableCaptureFailedRequests = true` and `failedRequestStatusCodes` covers the status code |
| Screenshots contain PII | Enable `screenshot.maskAllText = true` and `screenshot.maskAllImages = true` (both default) |
| Events missing from `beforeSend` for transactions | `beforeSend` is for error/message events only; use `beforeSendSpan` for spans |
| `onLastRunStatusDetermined` not firing | SDK must be initialized on main thread; check `enableCrashHandler = true` |
