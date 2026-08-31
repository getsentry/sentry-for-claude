# Error Monitoring — Flutter SDK Reference

> **Minimum SDK version:** `sentry_flutter` ≥ 7.0.0 (all features), ≥ 9.14.0 (tombstone,
> trace sync) **Platforms:** All (Android, iOS, macOS, Linux, Windows, Web —
> platform-specific caveats noted)

## What’s Auto-Captured

When `SentryFlutter.init()` runs, the SDK installs these handlers automatically:

| Handler | Captures | Platforms |
| --- | --- | --- |
| `FlutterError.onError` | Widget build errors, rendering errors, gesture errors | All |
| `PlatformDispatcher.instance.onError` | Uncaught Dart async errors (root zone) | All (Flutter ≥ 3.3) |
| Android SDK (bundled) | Java/Kotlin JVM exceptions, NDK native crashes | Android |
| iOS/macOS SDK (bundled) | ObjC `NSException`, Swift errors, POSIX signals, Mach exceptions | iOS, macOS |
| `WidgetsBindingObserver` | App lifecycle breadcrumbs | Linux, Windows, Web (no native SDK) |

Silent framework errors (`FlutterErrorDetails.silent == true`) are excluded unless you
opt in:

```dart
options.reportSilentFlutterErrors = true;
```

* * *

## Manual Capture APIs

### Capture Exception

Always pass `stackTrace` — without it Sentry can’t show the correct call stack:

```dart
import 'package:sentry/sentry.dart';

try {
  await riskyOperation();
} catch (e, stackTrace) {
  await Sentry.captureException(e, stackTrace: stackTrace);
}
```

With a one-off local scope (doesn’t affect subsequent events):

```dart
await Sentry.captureException(
  e,
  stackTrace: stackTrace,
  withScope: (scope) {
    scope.setTag('checkout.step', 'payment');
    scope.setTag('step', 'payment');
    scope.level = SentryLevel.fatal;
    scope.setExtra('orderId', orderId);
  },
);
```

### Capture Message

```dart
await Sentry.captureMessage(
  'Rate limit threshold exceeded',
  level: SentryLevel.warning,
);

// Available levels:
// SentryLevel.debug | info | warning | error | fatal
```

### Capture User Feedback

```dart
final eventId = await Sentry.captureException(e, stackTrace: st);

await Sentry.captureFeedback(
  SentryFeedback(
    message: 'App froze after uploading the photo.',
    contactEmail: 'user@example.com',
    name: 'Jane Doe',
    associatedEventId: eventId,
  ),
);
```

* * *

## Scope — Enrich All Events

### Global Scope (persists across events)

```dart
import 'package:sentry/sentry.dart';

// Set user on login
Sentry.configureScope((scope) => scope.setUser(SentryUser(
  id: 'user-123',
  username: 'jdoe',
  email: 'jane@example.com',
  name: 'Jane Doe',
  data: {'subscription_tier': 'pro'},
)));

// Clear user on logout
Sentry.configureScope((scope) => scope.setUser(null));

// Tags — indexed, searchable (key max 32 chars, value max 200 chars)
Sentry.configureScope((scope) {
  scope.setTag('app.flavor', 'enterprise');
  scope.setTag('locale', 'pt-BR');
});

// Contexts — non-searchable structured data (visible in Sentry UI)
Sentry.configureScope((scope) => scope.setContexts('cart', {
  'items_count': 3,
  'total_usd': 149.99,
}));

// Attributes (SDK ≥9.9.0) — apply to logs, metrics, and spans too
Sentry.setAttributes({'user_tier': SentryAttribute.string('premium')});
Sentry.removeAttribute('user_tier');
```

### Scope Sync to Native (Android/iOS)

When `options.enableScopeSync = true` (default), these methods sync to the native SDK
layer so native crash reports include your Dart context:

- `scope.setUser()` / `scope.setContexts()` / `scope.setTag()` / `scope.setExtra()`
- `scope.addBreadcrumb()` / `scope.clearBreadcrumbs()`

* * *

## Breadcrumbs

Manual breadcrumbs build an audit trail leading to each error:

```dart
Sentry.addBreadcrumb(Breadcrumb(
  message: 'User tapped checkout button',
  category: 'ui.action',
  type: 'user',
  level: SentryLevel.info,
  data: {'screen': 'CartScreen', 'cart_total': 149.99},
));
```

Filter or modify breadcrumbs before storage:

```dart
options.beforeBreadcrumb = (breadcrumb, hint) {
  // Drop noisy analytics calls
  if (breadcrumb.data?['url']?.contains('analytics') == true) {
    return null; // null = drop
  }
  // Strip auth headers from HTTP breadcrumbs
  if (breadcrumb.type == 'http') {
    final data = Map<String, dynamic>.from(breadcrumb.data ?? {})
      ..remove('Authorization');
    return breadcrumb.copyWith(data: data);
  }
  return breadcrumb;
};
```

Increase capacity if needed (default: 100):

```dart
options.maxBreadcrumbs = 150;
```

* * *

## Event Filtering

Drop or modify events before they’re sent:

```dart
options.beforeSend = (event, hint) async {
  // Drop database connection errors (too noisy)
  if (event.throwable is DatabaseConnectionException) return null;

  // Group similar payment failures
  if (event.throwable is PaymentException) {
    event.fingerprint = ['payment-failure'];
  }

  // Strip server name for privacy
  event.serverName = '';
  return event;
};
```

> ⚠️ `beforeSend` intercepts **Dart-layer events only**. Native crashes from Android NDK
> or iOS bypass it.

Error sampling (drop a fraction of errors — not recommended unless volume is very high):

```dart
options.sampleRate = 0.5; // send only 50% of errors
```

* * *

## Isolate Error Capture

Errors in non-root Dart isolates aren’t automatically captured.
Forward them explicitly:

```dart
import 'dart:isolate';
import 'package:sentry/sentry.dart';

final isolate = await Isolate.spawn(myIsolateEntry, someData);
isolate.addSentryErrorListener(); // forwards uncaught errors to Sentry
```

> ⚠️ Isolate errors are NOT captured on Web (no Isolate API in browser).

* * *

## Attachments

Automatically attach screenshots and widget hierarchy to error events:

```dart
options.attachScreenshot = true;          // screenshot at time of error
options.screenshotQuality = ScreenshotQuality.high; // full/high/medium/low
options.attachViewHierarchy = true;       // JSON widget tree snapshot
```

Requires `SentryWidget(child: MyApp())` as the app root.
Not available on Web.

Attach files manually via scope:

```dart
import 'package:sentry/sentry_io.dart';

final attachment = IoSentryAttachment.fromPath('/path/to/debug.log');
Sentry.configureScope((scope) => scope.addAttachment(attachment));
```

* * *

## Android Native Crash Options

```dart
// Android 12+ tombstone crash info via ApplicationExitInfo (SDK ≥9.14.0, opt-in)
options.enableTombstone = true;

// Sync Java/Kotlin scope to NDK
options.enableNdkScopeSync = true; // default: true

// Attach all threads to crash report
options.attachThreads = true; // default: false

// ANR detection
options.anrEnabled = true;             // default: true
options.anrTimeoutInterval = 5000;     // ms; increase if too many false positives
```

* * *

## iOS/macOS Native Crash Options

```dart
// Watchdog termination (OOM kill) tracking
options.enableWatchdogTerminationTracking = true; // default: true

// Native HTTP failures independent of Dart client (SDK ≥9.11.0)
options.captureNativeFailedRequests = true;
```

* * *

## Release Health

Session tracking is on by default — gives you crash-free user and session metrics in the
Sentry dashboard:

```dart
// Disable if not needed
options.enableAutoSessionTracking = false;

// Tune session expiry (how long in background before a new session starts)
options.autoSessionTrackingInterval = const Duration(seconds: 60); // default: 30s
```

Release is auto-set on iOS/Android as `"packageName@versionName+versionCode"`. Override
if needed:

```dart
options.release = 'my-app@2.1.0+105';
```

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing in Sentry | Set `options.debug = true`, check Flutter console for SDK errors; verify DSN |
| Stack traces unreadable | Build with `--obfuscate --split-debug-info` and upload with `sentry_dart_plugin` |
| Native crashes not captured | Confirm `enableNativeCrashHandling: true`; test in release mode (not debug) |
| `beforeSend` not firing for native crashes | Expected — `beforeSend` only intercepts Dart-layer events |
| Silent Flutter errors missed | Set `options.reportSilentFlutterErrors = true` |
| Isolate errors not captured | Call `isolate.addSentryErrorListener()` on each spawned isolate |
| Attachments missing from events | Confirm `SentryWidget(child: MyApp())` is the root widget |
| ANR false positives on slow devices | Increase `anrTimeoutInterval` above 5000ms |
| Events missing user/tag context | Set context before error occurs via `Sentry.configureScope()`; native crashes read scope at crash time |
| Too many events in dashboard | Lower `sampleRate` (last resort) or use `beforeSend` to drop low-value errors |
