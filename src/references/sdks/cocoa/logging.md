# Logging — Sentry Cocoa SDK

Requires `sentry-cocoa` v9.27.0+. Logs are enabled by default, so no additional
configuration is required.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `beforeSendLog` | `((SentryLog) -> SentryLog?)?` | `nil` | Filter or modify logs before sending. Return `nil` to drop. |

## Code Examples

### All log levels

```swift
import Sentry

let logger = SentrySDK.logger

// Without attributes
logger.trace("Starting database connection")
logger.debug("Cache miss for user")
logger.info("Profile updated successfully")
logger.warn("Rate limit nearly reached")
logger.error("Failed to process payment")
logger.fatal("Database connection pool exhausted")

// With structured attributes
logger.trace("Starting DB connection",    attributes: ["database": "users"])
logger.debug("Cache miss for user",       attributes: ["userId": 123])
logger.info("Profile updated",            attributes: ["profileId": 345])
logger.warn("Rate limit reached",         attributes: ["endpoint": "/api/results/"])
logger.error("Payment failed",            attributes: ["amount": 99.99])
logger.fatal("Connection pool exhausted", attributes: ["activeConnections": 100])
```

Supported Swift attribute value types include `String`, `Bool`, `Int`, `Double`,
`Float`, arrays, and sets; other values are converted to strings.

### Log levels (severity order)

| Level | Method | Typical Use |
| --- | --- | --- |
| 1 — Trace | `logger.trace(...)` | Very fine-grained diagnostic events |
| 2 — Debug | `logger.debug(...)` | Debugging information |
| 3 — Info | `logger.info(...)` | General informational messages |
| 4 — Warn | `logger.warn(...)` | Potentially harmful situations |
| 5 — Error | `logger.error(...)` | Error events; app may continue |
| 6 — Fatal | `logger.fatal(...)` | Severe errors; likely app abort |

### Swift string interpolation as structured attributes

When you use Swift string interpolation in the message, the SDK automatically extracts
the interpolated values as named attributes using the key pattern
`sentry.message.parameter.{index}`:

```swift
let userId = "user_123"
let orderCount = 5

logger.info("User \(userId) placed \(orderCount) orders")

// Sentry receives:
//   message template: "User %s placed %d orders"
//   sentry.message.parameter.0 = "user_123"
//   sentry.message.parameter.1 = 5
```

This preserves the ability to search and filter by the template while retaining the
individual values as queryable attributes.

### beforeSendLog filter hook

```swift
SentrySDK.start { options in
    options.beforeSendLog = { log in
        // Drop trace-level logs
        if log.level == .trace { return nil }

        // Drop debug logs in production
        if log.level == .debug && options.environment == "production" { return nil }

        // Enrich all logs with app version
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            log.attributes["app.version"] = SentryAttribute(string: version)
        }
        return log
    }
}
```

Available on `SentryLog`:
- `log.level` — `SentryLog.Level` (`.trace`, `.debug`, `.info`, `.warn`, `.error`,
  `.fatal`)
- `log.body` — `String`
- `log.timestamp` — `Date`
- `log.attributes` — `[String: SentryAttribute]`

### Automatic default attributes

The SDK automatically attaches the following to every log entry:

- `environment` and `release`
- SDK name and version
- User ID, name, email (if set via `SentrySDK.setUser(...)`)
- Message template and `sentry.message.parameter.*` interpolated values
- Integration origin marker

### Using alongside Apple os.log

`SentrySDK.logger` is a standalone Sentry telemetry system — it is **not** a bridge to
`os.log` / `Logger`. To write to both:

```swift
import OSLog
import Sentry

private let osLog = Logger(subsystem: "com.myapp", category: "network")

func fetchData() {
    osLog.info("Fetching data")                        // → system log / Console.app
    SentrySDK.logger.info("Fetching data",             // → Sentry Logs
                          attributes: ["subsystem": "network"])
}
```

There is no built-in bridge to automatically forward `OSLog` entries to Sentry.

### Full initialization example with logging

```swift
import Sentry

SentrySDK.start { options in
    options.dsn = "___PUBLIC_DSN___"
    options.environment = "production"
    options.beforeSendLog = { log in
        // Drop trace and debug in production
        guard log.level != .trace && log.level != .debug else { return nil }
        return log
    }
}

// Anywhere in your app:
SentrySDK.logger.info("User signed in",
                      attributes: ["userId": currentUser.id, "method": "oauth"])
```

## Known Limitations

- Logs can be **lost in crash scenarios** if the SDK cannot flush the buffer before the
  app terminates — this is a known limitation of the current implementation
- Logs are a **separate pipeline** from error events — they are not attached to
  breadcrumbs or spans automatically
- Attribute values are limited to `String`, `Int`, `Double`, and `Bool` — other types
  must be converted

## Best Practices

- Prefer `logger.error(...)` or `logger.fatal(...)` over `SentrySDK.capture(message:)`
  for application-level log lines — structured logs are easier to search and filter in
  Sentry
- Use structured attributes instead of embedding values in the message string directly;
  attributes are indexed and queryable
- Use Swift string interpolation to let the SDK extract attribute values automatically
- Set `beforeSendLog` to drop `trace` and `debug` in production to reduce noise and
  volume
- Set the user via `SentrySDK.setUser(...)` before logging to automatically correlate
  logs with user identities

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Logs not appearing in Sentry | Verify `SentrySDK.start` ran and that `beforeSendLog` is not dropping the log |
| Logs only partially appearing | Logs may be lost during crashes; this is a known SDK limitation |
| `SentrySDK.logger` not found | Requires v8.55.0+; check SPM/CocoaPods version |
| Attributes not queryable | Prefer `String`, `Bool`, `Int`, `Double`, `Float`, arrays, or sets; convert complex objects to stable strings |
| `beforeSendLog` not called | Ensure you set it during `SentrySDK.start` configuration |
| Too many logs overwhelming Sentry | Use `beforeSendLog` to filter by level; set minimum level for production |
| Logs missing user context | Call `SentrySDK.setUser(...)` before logging to attach user identity automatically |
