# Sentry Flutter SDK

Opinionated wizard that scans your Flutter or Dart project and guides you through
complete Sentry setup — error monitoring, tracing, session replay, logging, profiling,
and ecosystem integrations.

> **Note:** SDK versions and APIs below reflect `sentry_flutter` ≥9.14.0 (current
> stable, February 2026). Always verify against
> [docs.sentry.io/platforms/flutter/](https://docs.sentry.io/platforms/flutter/) before
> implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect Flutter project type and existing Sentry
cat pubspec.yaml | grep -E '(sentry|flutter|dart)'

# Check SDK version
cat pubspec.yaml | grep -A2 'environment:'

# Check for existing Sentry initialization
grep -r "SentryFlutter.init\|Sentry.init" lib/ 2>/dev/null | head -5

# Detect navigation library
grep -E '(go_router|auto_route|get:|beamer|routemaster)' pubspec.yaml

# Detect HTTP client
grep -E '(dio:|http:|chopper:)' pubspec.yaml

# Detect database packages
grep -E '(sqflite|drift|hive|isar|floor)' pubspec.yaml

# Detect state management (for integration patterns)
grep -E '(flutter_bloc|riverpod|provider:|get:)' pubspec.yaml

# Detect GraphQL
grep -E '(graphql|ferry|gql)' pubspec.yaml

# Detect Firebase
grep -E '(firebase_core|supabase)' pubspec.yaml

# Detect backend for cross-link
ls ../backend/ ../server/ ../api/ 2>/dev/null
find .. -maxdepth 3 \( -name "go.mod" -o -name "requirements.txt" -o -name "Gemfile" -o -name "*.csproj" \) 2>/dev/null | grep -v flutter | head -10

# Detect platform targets
ls android/ ios/ macos/ linux/ windows/ web/ 2>/dev/null
```

**What to determine:**

| Question | Impact |
| --- | --- |
| `sentry_flutter` already in `pubspec.yaml`? | Skip install, jump to feature config |
| Dart SDK `>=3.5`? | Required for `sentry_flutter` ≥9.0.0 |
| `go_router` or `auto_route` present? | Use `SentryNavigatorObserver` — specific patterns apply |
| `dio` present? | Recommend `sentry_dio` integration |
| `sqflite`, `drift`, `hive`, `isar` present? | Recommend matching `sentry_*` DB package |
| Has `android/` and `ios/` directories? | Full mobile feature set available |
| Has `web/` directory only? | Session Replay and Profiling unavailable |
| Has `macos/` directory? | Profiling available (alpha) |
| Backend directory detected? | Trigger Phase 4 cross-link |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Don’t ask open-ended questions — lead with a proposal:

**Recommended (core coverage — always set up these):**
- ✅ **Error Monitoring** — captures Dart exceptions, Flutter framework errors, and
  native crashes (iOS + Android)
- ✅ **Tracing** — auto-instruments navigation, app start, network requests, and UI
  interactions
- ✅ **Session Replay** — captures widget tree screenshots for debugging (iOS + Android
  only)

**Optional (enhanced observability):**
- ⚡ **Profiling** — CPU profiling; iOS and macOS only (alpha)
- ⚡ **Logging** — structured logs via `Sentry.logger.*` and `sentry_logging` integration
- ⚡ **Metrics** — counters, gauges, distributions (SDK ≥9.11.0)

**Platform limitations — be upfront:**

| Feature | Platforms | Notes |
| --- | --- | --- |
| Session Replay | iOS, Android | Not available on macOS, Linux, Windows, Web |
| Profiling | iOS, macOS | Alpha status; not available on Android, Linux, Windows, Web |
| Native crashes | iOS, Android, macOS | NDK/signal handling; Linux/Windows/Web: Dart exceptions only |
| App Start metrics | iOS, Android | Not available on desktop/web |
| Slow/frozen frames | iOS, Android, macOS | Not available on Linux, Windows, Web |
| Crons | N/A | **Not available** in the Flutter/Dart SDK |

Propose: *“For your Flutter app targeting iOS/Android, I recommend Error Monitoring +
Tracing + Session Replay.
Want me to also add Logging and Profiling (iOS/macOS alpha)?”*

* * *

## Phase 3: Guide

### Determine Your Setup Path

| Project type | Recommended setup |
| --- | --- |
| Any Flutter app | Wizard CLI (handles pubspec, init, symbol upload) |
| Manual preferred | Path B below — `pubspec.yaml` + `main.dart` |
| Dart-only (CLI, server) | Path C below — pure `sentry` package |

* * *

### Path A: Wizard CLI (Recommended)

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```bash
> brew install getsentry/tools/sentry-wizard && sentry-wizard -i flutter
> ```
> 
> It handles org/project selection, adds `sentry_flutter` to `pubspec.yaml`, updates
> `main.dart`, configures `sentry_dart_plugin` for debug symbol upload, and adds build
> scripts. Here’s what it creates/modifies:
> 
| File | Action | Purpose |
| --- | --- | --- |
| `pubspec.yaml` | Adds `sentry_flutter` dependency and `sentry:` config block | SDK + symbol upload config |
| `lib/main.dart` | Wraps `main()` with `SentryFlutter.init()` | SDK initialization |
| `android/app/build.gradle` | Adds Proguard config reference | Android obfuscation support |
| `.sentryclirc` | Auth token and org/project config | Symbol upload credentials |
> 
> **Once it finishes, come back and skip to [Verification](#verification).**

If the user skips the wizard, proceed with Path B (Manual Setup) below.

* * *

### Path B: Manual — Flutter App

**Step 1 — Install**

```bash
flutter pub add sentry_flutter
```

Or add to `pubspec.yaml` manually:

```yaml
dependencies:
  flutter:
    sdk: flutter
  sentry_flutter: ^9.14.0
```

Then run:

```bash
flutter pub get
```

**Step 2 — Initialize Sentry in `lib/main.dart`**

```dart
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'YOUR_SENTRY_DSN';
      options.sendDefaultPii = true;

      // Tracing
      options.tracesSampleRate = 1.0; // lower to 0.1–0.2 in production

      // Profiling (iOS and macOS only — alpha)
      options.profilesSampleRate = 1.0;

      // Session Replay (iOS and Android only)
      options.replay.sessionSampleRate = 0.1;
      options.replay.onErrorSampleRate = 1.0;

      // Structured Logging (SDK ≥9.5.0)
      options.enableLogs = true;

      options.environment = const bool.fromEnvironment('dart.vm.product')
          ? 'production'
          : 'development';
    },
    // REQUIRED: wrap root widget to enable screenshots, replay, user interaction tracing
    appRunner: () => runApp(SentryWidget(child: MyApp())),
  );
}
```

**Step 3 — Add Navigation Observer**

Add `SentryNavigatorObserver` to your `MaterialApp` or `CupertinoApp`:

```dart
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [
        SentryNavigatorObserver(),
      ],
      // Always name your routes for Sentry to track them
      routes: {
        '/': (context) => HomeScreen(),
        '/profile': (context) => ProfileScreen(),
      },
    );
  }
}
```

For **GoRouter**:

```dart
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

final GoRouter router = GoRouter(
  observers: [SentryNavigatorObserver()],
  routes: [
    GoRoute(
      path: '/',
      name: 'home', // name is REQUIRED for Sentry route tracking
      builder: (context, state) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'profile/:id',
          name: 'profile', // name is REQUIRED
          builder: (context, state) => ProfileScreen(
            id: state.pathParameters['id']!,
          ),
        ),
      ],
    ),
  ],
);
```

**Step 4 — Configure Debug Symbol Upload**

Readable stack traces in Sentry require uploading debug symbols when building with
`--obfuscate`.

Add to `pubspec.yaml`:

```yaml
dev_dependencies:
  sentry_dart_plugin: ^3.2.1

sentry:
  project: YOUR_PROJECT_SLUG
  org: YOUR_ORG_SLUG
  auth_token: YOUR_AUTH_TOKEN  # prefer SENTRY_AUTH_TOKEN env var instead
  upload_debug_symbols: true
  upload_sources: true
  upload_source_maps: true     # for Web
```

Build and upload:

```bash
# Android
flutter build apk \
  --release \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --extra-gen-snapshot-options=--save-obfuscation-map=build/app/obfuscation.map.json
dart run sentry_dart_plugin

# iOS
flutter build ipa \
  --release \
  --obfuscate \
  --split-debug-info=build/debug-info \
  --extra-gen-snapshot-options=--save-obfuscation-map=build/app/obfuscation.map.json
dart run sentry_dart_plugin

# Web
flutter build web --release --source-maps
dart run sentry_dart_plugin
```

* * *

### Path C: Manual — Dart-Only (CLI / Server)

```yaml
# pubspec.yaml
dependencies:
  sentry: ^9.14.0
```

```dart
import 'package:sentry/sentry.dart';

Future<void> main() async {
  await Sentry.init(
    (options) {
      options.dsn = 'YOUR_SENTRY_DSN';
      options.tracesSampleRate = 1.0;
      options.enableLogs = true;
    },
    appRunner: myApp,
  );
}
```

* * *

### Quick Reference: Full-Featured `SentryFlutter.init()`

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'YOUR_SENTRY_DSN';
      options.sendDefaultPii = true;

      // Environment — detect release builds via dart.vm.product
      options.environment = const bool.fromEnvironment('dart.vm.product')
          ? 'production'
          : 'development';

      // Release is auto-set on iOS/Android as "packageName@version+build"
      // Override if needed:
      // options.release = 'my-app@1.0.0+42';

      // Error sampling — reduce to drop a fraction of errors in high-volume production
      options.sampleRate = 1.0;

      // Tracing — lower to 0.1–0.2 in high-traffic production
      options.tracesSampleRate = 1.0;

      // Profiling — iOS and macOS only (alpha); relative to tracesSampleRate
      options.profilesSampleRate = 1.0;

      // Session Replay — iOS and Android only (SDK ≥9.0.0)
      options.replay.sessionSampleRate = 0.1;   // record 10% of all sessions
      options.replay.onErrorSampleRate = 1.0;   // always record error sessions

      // Privacy defaults — all text and images masked
      options.privacy.maskAllText = true;
      options.privacy.maskAllImages = true;

      // Structured logging (SDK ≥9.5.0)
      options.enableLogs = true;

      // Attachments
      options.attachScreenshot = true;          // screenshot on error
      options.attachViewHierarchy = true;       // widget tree on error

      // HTTP client
      options.captureFailedRequests = true;     // auto-capture HTTP errors
      options.maxRequestBodySize = MaxRequestBodySize.small;

      // Android specifics
      options.anrEnabled = true;                // ANR detection
      options.enableNdkScopeSync = true;        // sync scope to native
      options.enableTombstone = false;          // Android 12+ tombstone (opt-in)

      // Navigation (Time to Full Display — opt-in)
      options.enableTimeToFullDisplayTracing = true;
    },
    appRunner: () => runApp(SentryWidget(child: MyApp())),
  );
}
```

* * *

### Navigation: Time to Full Display (TTFD)

TTID (Time to Initial Display) is always enabled.
TTFD is opt-in:

```dart
// Enable in options:
options.enableTimeToFullDisplayTracing = true;
```

Then report when your screen has loaded its data:

```dart
// Option 1: Widget wrapper (marks TTFD when child first renders)
SentryDisplayWidget(child: MyWidget())

// Option 2: Manual API call (after async data loads)
await _loadData();
SentryFlutter.currentDisplay()?.reportFullyDisplayed();
```

* * *

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file for each, follow its steps, then verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing & Performance | `./tracing.md` | Always — navigation, HTTP, DB spans |
| Session Replay | `./session-replay.md` | iOS/Android user-facing apps |
| Profiling | `./profiling.md` | iOS/macOS performance-sensitive apps |
| Logging | `./logging.md` | Structured logging / log-trace correlation |
| Metrics | `./metrics.md` | Custom business metrics |
| Ecosystem Integrations | `./ecosystem-integrations.md` | HTTP clients, databases, GraphQL, state management |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Core `SentryFlutter.init()` Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `string` | — | **Required.** Project DSN. Env: `SENTRY_DSN` via `--dart-define` |
| `environment` | `string` | — | e.g., `"production"`, `"staging"`. Env: `SENTRY_ENVIRONMENT` |
| `release` | `string` | Auto on iOS/Android | `"packageName@version+build"`. Env: `SENTRY_RELEASE` |
| `dist` | `string` | — | Distribution identifier; max 64 chars. Env: `SENTRY_DIST` |
| `sendDefaultPii` | `bool` | `false` | Include PII: IP address, user labels, widget text in replay |
| `sampleRate` | `double` | `1.0` | Error event sampling (0.0–1.0) |
| `maxBreadcrumbs` | `int` | `100` | Max breadcrumbs per event |
| `attachStacktrace` | `bool` | `true` | Auto-attach stack traces to messages |
| `attachScreenshot` | `bool` | `false` | Capture screenshot on error (mobile/desktop only) |
| `screenshotQuality` | enum | `high` | Screenshot quality: `full`, `high`, `medium`, `low` |
| `attachViewHierarchy` | `bool` | `false` | Attach JSON widget tree as attachment on error |
| `debug` | `bool` | `true` in debug | Verbose SDK output. **Never force `true` in production** |
| `diagnosticLevel` | enum | `warning` | Log verbosity: `debug`, `info`, `warning`, `error`, `fatal` |
| `enabled` | `bool` | `true` | Disable SDK entirely (e.g., for testing) |
| `maxCacheItems` | `int` | `30` | Max offline-cached envelopes (not supported on Web) |
| `sendClientReports` | `bool` | `true` | Send SDK health reports (dropped events, etc.) |
| `reportPackages` | `bool` | `true` | Report `pubspec.yaml` dependency list |
| `reportSilentFlutterErrors` | `bool` | `false` | Capture `FlutterErrorDetails.silent` errors |
| `idleTimeout` | `Duration` | `3000ms` | Auto-finish idle user interaction transactions |

### Tracing Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `tracesSampleRate` | `double` | — | Transaction sample rate (0–1). Enable by setting >0 |
| `tracesSampler` | `function` | — | Per-transaction sampling; overrides `tracesSampleRate` |
| `tracePropagationTargets` | `List` | — | URLs to attach `sentry-trace` + `baggage` headers |
| `propagateTraceparent` | `bool` | `false` | Also send W3C `traceparent` header (SDK ≥9.7.0) |
| `enableTimeToFullDisplayTracing` | `bool` | `false` | Opt-in TTFD tracking per screen |
| `enableAutoPerformanceTracing` | `bool` | `true` | Auto-enable performance monitoring |
| `enableUserInteractionTracing` | `bool` | `true` | Create transactions for tap/click/long-press events |
| `enableUserInteractionBreadcrumbs` | `bool` | `true` | Breadcrumbs for every tracked user interaction |

### Profiling Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `profilesSampleRate` | `double` | — | Profiling rate relative to `tracesSampleRate`. **iOS/macOS only** |

### Native / Mobile Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `autoInitializeNativeSdk` | `bool` | `true` | Auto-initialize native Android/iOS SDK layer |
| `enableNativeCrashHandling` | `bool` | `true` | Capture native crashes (NDK, signal, Mach exception) |
| `enableNdkScopeSync` | `bool` | `true` | Sync Dart scope to Android NDK |
| `enableScopeSync` | `bool` | `true` | Sync scope data to native SDKs |
| `anrEnabled` | `bool` | `true` | ANR detection (Android) |
| `anrTimeoutInterval` | `int` | `5000` | ANR timeout in milliseconds (Android) |
| `enableWatchdogTerminationTracking` | `bool` | `true` | OOM kill tracking (iOS) |
| `enableTombstone` | `bool` | `false` | Android 12+ native crash info via `ApplicationExitInfo` |
| `attachThreads` | `bool` | `false` | Attach all threads on crash (Android) |
| `captureNativeFailedRequests` | `bool` | — | Native HTTP error capture, independent of Dart client (iOS/macOS, v9.11.0+) |
| `enableAutoNativeAppStart` | `bool` | `true` | App start timing instrumentation (iOS/Android) |
| `enableFramesTracking` | `bool` | `true` | Slow/frozen frame monitoring (iOS/Android/macOS) |
| `proguardUuid` | `string` | — | Proguard UUID for Android obfuscation mapping |

### Session & Release Health Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `enableAutoSessionTracking` | `bool` | `true` | Session tracking for crash-free user/session metrics |
| `autoSessionTrackingInterval` | `Duration` | `30s` | Background inactivity before session ends |

### Replay Options (`options.replay`)

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `replay.sessionSampleRate` | `double` | `0.0` | Fraction of all sessions recorded |
| `replay.onErrorSampleRate` | `double` | `0.0` | Fraction of error sessions recorded |

### Replay Privacy Options (`options.privacy`)

| Option / Method | Default | Purpose |
| --- | --- | --- |
| `privacy.maskAllText` | `true` | Mask all text widget content |
| `privacy.maskAllImages` | `true` | Mask all image widgets |
| `privacy.maskAssetImages` | `true` | Mask images from root asset bundle |
| `privacy.mask<T>()` | — | Mask a specific widget type and all subclasses |
| `privacy.unmask<T>()` | — | Unmask a specific widget type |
| `privacy.maskCallback<T>()` | — | Custom masking decision per widget instance |

### HTTP Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `captureFailedRequests` | `bool` | `true` (Flutter) | Auto-capture HTTP errors |
| `maxRequestBodySize` | enum | `never` | Body capture: `never`, `small`, `medium`, `always` |
| `failedRequestStatusCodes` | `List` | `[500–599]` | Status codes treated as failures |
| `failedRequestTargets` | `List` | `['.*']` | URL patterns to monitor |

### Hook Options

| Option | Type | Purpose |
| --- | --- | --- |
| `beforeSend` | `(SentryEvent, Hint) → SentryEvent?` | Modify or drop error events. Return `null` to drop |
| `beforeSendTransaction` | `(SentryEvent) → SentryEvent?` | Modify or drop transaction events |
| `beforeBreadcrumb` | `(Breadcrumb, Hint) → Breadcrumb?` | Process breadcrumbs before storage |
| `beforeSendLog` | `(SentryLog) → SentryLog?` | Filter structured logs before sending |

### Environment Variables

Pass via `--dart-define` at build time:

| Variable | Purpose | Notes |
| --- | --- | --- |
| `SENTRY_DSN` | Data Source Name | Falls back from `options.dsn` |
| `SENTRY_ENVIRONMENT` | Deployment environment | Falls back from `options.environment` |
| `SENTRY_RELEASE` | Release identifier | Falls back from `options.release` |
| `SENTRY_DIST` | Build distribution | Falls back from `options.dist` |
| `SENTRY_AUTH_TOKEN` | Upload debug symbols | **Never embed in app — build tool only** |
| `SENTRY_ORG` | Organization slug | Used by `sentry_dart_plugin` |
| `SENTRY_PROJECT` | Project slug | Used by `sentry_dart_plugin` |

Usage:

```bash
flutter build apk --release \
  --dart-define=SENTRY_DSN=https://xxx@sentry.io/123 \
  --dart-define=SENTRY_ENVIRONMENT=production
```

Then in code:

```dart
options.dsn = const String.fromEnvironment('SENTRY_DSN');
options.environment = const String.fromEnvironment('SENTRY_ENVIRONMENT', defaultValue: 'development');
```

### Production Settings

Lower sample rates and harden config before shipping:

```dart
Future<void> main() async {
  final isProduction = const bool.fromEnvironment('dart.vm.product');

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.environment = isProduction ? 'production' : 'development';

      // Trace 10% of transactions in high-traffic production
      options.tracesSampleRate = isProduction ? 0.1 : 1.0;

      // Profile 100% of traced transactions (profiling is always a subset)
      options.profilesSampleRate = 1.0;

      // Replay all error sessions, sample 5% of normal sessions
      options.replay.onErrorSampleRate = 1.0;
      options.replay.sessionSampleRate = isProduction ? 0.05 : 1.0;

      // Disable debug logging in production
      options.debug = !isProduction;
    },
    appRunner: () => runApp(SentryWidget(child: MyApp())),
  );
}
```

### Default Auto-Enabled Integrations

These are active with no extra config when you call `SentryFlutter.init()`:

| Integration | What it does |
| --- | --- |
| `FlutterErrorIntegration` | Captures `FlutterError.onError` framework errors |
| `RunZonedGuardedIntegration` | Catches unhandled Dart exceptions in runZonedGuarded |
| `NativeAppStartIntegration` | App start timing (iOS/Android) |
| `FramesTrackingIntegration` | Slow/frozen frames (iOS/Android/macOS) |
| `NativeUserInteractionIntegration` | User interaction breadcrumbs from native layer |
| `UserInteractionIntegration` | Dart-layer tap/click transactions (requires `SentryWidget`) |
| `DeviceContextIntegration` | Device model, OS version, screen resolution |
| `AppContextIntegration` | App version, build number, bundle ID |
| `ConnectivityIntegration` | Network connectivity change breadcrumbs |
| `HttpClientIntegration` | Auto-instrument Dart `http` requests |
| `SdkIntegration` | SDK metadata tagging |
| `ReleaseIntegration` | Auto-set release on iOS/Android from package info |

* * *

## Verification

After setup, test that Sentry is receiving events:

```dart
// Add a test button somewhere visible during development:
ElevatedButton(
  onPressed: () {
    throw Exception('Sentry test error!');
  },
  child: const Text('Test Sentry Error'),
)

// Or capture manually:
ElevatedButton(
  onPressed: () {
    Sentry.captureMessage('Sentry test message', level: SentryLevel.info);
  },
  child: const Text('Test Sentry Message'),
)

// Test structured logging:
ElevatedButton(
  onPressed: () {
    Sentry.logger.info('Test log from Flutter app');
  },
  child: const Text('Test Sentry Log'),
)
```

**Check the Sentry dashboard:**
- **Issues** → test error should appear within seconds
- **Traces** → look for a navigation transaction with child spans
- **Replays** → session recording visible after app interaction (iOS/Android only)
- **Logs** → structured log entries if `enableLogs: true`

> ⚠️ **Platform limitations in debug mode:**
> - Native crashes, session replay, slow/frozen frames, and app start metrics only fully
>   work in release builds on iOS/Android
> - Run `flutter run --release` or use a real device/emulator to test native features
> - Debug mode uses the Dart VM with JIT compilation — some native integrations behave
>   differently

* * *

## Phase 4: Cross-Link

After completing Flutter setup, check for a backend missing Sentry coverage:

```bash
# Adjacent backend directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod 2>/dev/null | head -3
cat ../requirements.txt ../pyproject.toml 2>/dev/null | head -3
cat ../Gemfile 2>/dev/null | head -3
ls ../backend/package.json ../server/package.json 2>/dev/null
```

If a backend exists without Sentry, suggest the matching skill:

| Detected | Suggest skill |
| --- | --- |
| Go backend (`go.mod`) | [`go`](../go/index.md) |
| Python backend (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby backend (`Gemfile`) | [`ruby`](../ruby/index.md) |
| Node.js backend | [`node`](../node/index.md) |
| .NET backend (`*.csproj`) | [`dotnet`](../dotnet/index.md) |
| React / Next.js web | [`react`](../react/index.md) / [`nextjs`](../nextjs/index.md) |

**Distributed tracing** — if a backend skill is added, configure
`tracePropagationTargets` in Flutter to propagate trace context to your API:

```dart
options.tracePropagationTargets = ['api.myapp.com', 'localhost'];
options.propagateTraceparent = true; // also send W3C traceparent header
```

This links mobile transactions to backend traces in the Sentry waterfall view.

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing in Sentry | Set `options.debug = true` — SDK logs to Flutter console; verify DSN is correct |
| `SentryFlutter.init` throws | Ensure `main()` is `async` and you `await SentryFlutter.init(...)` |
| Stack traces unreadable in Sentry | Upload debug symbols with `sentry_dart_plugin`; build with `--obfuscate --split-debug-info` |
| Stack traces missing on Web | Build with `--source-maps` and run `dart run sentry_dart_plugin` to upload |
| Native crashes not captured | Confirm `enableNativeCrashHandling: true`; test in release mode, not debug |
| Session replay not recording | iOS/Android only; confirm `SentryWidget` wraps root; check `replay.onErrorSampleRate` |
| Replay shows blank screens | Confirm `SentryWidget(child: MyApp())` is outermost widget; not inside navigator |
| Profiling not working | iOS and macOS only (alpha); confirm `tracesSampleRate > 0` is set first |
| Navigation not tracked | Add `SentryNavigatorObserver()` to `navigatorObservers`; name all routes |
| GoRouter routes unnamed | Add `name:` to all `GoRoute` entries — unnamed routes are tracked as `null` |
| TTFD never reports | Call `SentryFlutter.currentDisplay()?.reportFullyDisplayed()` after data loads, or wrap with `SentryDisplayWidget` |
| `sentry_dart_plugin` auth error | Set `SENTRY_AUTH_TOKEN` env var instead of hardcoding in `pubspec.yaml` |
| Android ProGuard mapping missing | Ensure `--extra-gen-snapshot-options=--save-obfuscation-map=...` flag is set |
| iOS dSYM not uploaded | `sentry_dart_plugin` handles this; check `upload_debug_symbols: true` in `pubspec.yaml` `sentry:` block |
| `pub get` fails: Dart SDK too old | `sentry_flutter` ≥9.0.0 requires Dart ≥3.5.0; run `flutter upgrade` |
| Hot restart crashes on Android debug | Known issue (fixed in SDK ≥9.9.0); upgrade if on older version |
| ANR detection too aggressive | Increase `anrTimeoutInterval` (default: 5000ms) |
| Too many transactions in dashboard | Lower `tracesSampleRate` to `0.1` or use `tracesSampler` to drop health checks |
| `beforeSend` not firing for native crashes | Expected — `beforeSend` intercepts only Dart-layer events; native crashes bypass it |
| Crons not available | The Flutter/Dart SDK does not support Sentry Crons; use a server-side SDK instead |
| `SentryWidget` warning in tests | Wrap test widget with `SentryFlutter.init()` in `setUpAll`, or use `enabled: false` |
| Firebase Remote Config: Linux/Windows | `sentry_firebase_remote_config` not supported on Linux/Windows (Firebase limitation) |
| Isar tracing on Web | `sentry_isar` does NOT support Web (Isar does not support Web) |
