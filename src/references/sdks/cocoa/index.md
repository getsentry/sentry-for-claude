# Sentry Cocoa SDK

Opinionated wizard that scans your Apple project and guides you through complete Sentry
setup.

> **Note:** SDK versions and APIs below reflect Sentry docs at time of writing
> (sentry-cocoa 9.15.0). Always verify against
> [docs.sentry.io/platforms/apple/](https://docs.sentry.io/platforms/apple/) before
> implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Check existing Sentry dependency
grep -rEi "sentry|sentry-cocoa|SentrySPM|SentrySwiftUI" \
  --include="Package.swift" --include="Podfile" --include="Cartfile" \
  --include="Package.resolved" --include="project.pbxproj" . 2>/dev/null | head -20

# Detect UI framework (SwiftUI vs UIKit)
grep -rE "@main|struct .*: App" --include="*.swift" . 2>/dev/null | head -5
grep -rE "AppDelegate|UIApplicationMain|@UIApplicationDelegateAdaptor" --include="*.swift" . 2>/dev/null | head -5

# Detect platform and deployment targets
grep -rE "platforms:|\\.iOS|\\.macOS|\\.tvOS|\\.watchOS|\\.visionOS|IPHONEOS_DEPLOYMENT_TARGET|MACOSX_DEPLOYMENT_TARGET|TVOS_DEPLOYMENT_TARGET|WATCHOS_DEPLOYMENT_TARGET|XROS_DEPLOYMENT_TARGET" \
  --include="Package.swift" --include="project.pbxproj" . 2>/dev/null | head -20
grep -E "platform :ios|platform :osx|platform :tvos|platform :watchos" Podfile 2>/dev/null

# Detect logging
grep -rE "import OSLog|import os\\.log|Logger\\(|CocoaLumberjack|DDLog" --include="*.swift" . 2>/dev/null | head -5

# Detect companion backend
ls ../backend ../server ../api 2>/dev/null
ls ../go.mod ../requirements.txt ../Gemfile ../package.json 2>/dev/null
```

**What to note:**
- Is `sentry-cocoa` already in `Package.swift` or `Podfile`? If yes, skip to Phase 2
  (configure features).
- SwiftUI (`@main App` struct) or UIKit (`AppDelegate`)? Determines init pattern.
- Which Apple platforms?
  (Affects which features are available — see Platform Support Matrix.)
- Existing logging library?
  (Enables structured log capture.)
- SwiftUI tracing import/product?
  `SentrySwiftUI` still exists but is deprecated in SDK 9.4.1+; prefer the main `Sentry`
  module for released binary products.
- Companion backend? (Triggers Phase 4 cross-link for distributed tracing.)

* * *

## Phase 2: Recommend

Based on what you found, present a concrete recommendation.
Don’t ask open-ended questions — lead with a proposal:

**Recommended (core coverage):**
- **Error Monitoring** — always; crash reporting, app hangs, watchdog terminations,
  NSError/Swift errors
- **Tracing** — always for apps; auto-instruments app launch, network, UIViewController,
  file I/O, Core Data
- **Profiling** — production iOS/macOS apps; UI profiling via `configureProfiling`

**Optional (enhanced observability):**
- **Session Replay** — user-facing iOS apps; verify masking on iOS 26+ / Liquid Glass
  builds
- **Logging** — when structured log capture is needed
- **Metrics** — Swift apps needing aggregate counters, gauges, or distributions
- **User Feedback** — apps that want crash/error feedback forms from users

**Not available for Cocoa:**
- Crons — backend only
- AI Monitoring — JS/Python only

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Always for apps** — rich auto-instrumentation out of the box |
| Profiling | iOS/macOS production apps where performance matters (not tvOS/watchOS/visionOS) |
| Session Replay | User-facing iOS apps; tvOS may work but is not officially supported |
| Logging | Existing `os.log` / CocoaLumberjack usage, or structured logs needed |
| Metrics | Aggregate product or health signals that should not create issues; Swift only, SDK 9.12+ |
| User Feedback | Apps wanting in-app bug reports with screenshots |

Propose: *“I recommend Error Monitoring + Tracing + Profiling.
Want me to also add Session Replay and Logging?”*

* * *

## Phase 3: Guide

### Install

**Option 1 — Sentry Wizard (recommended):**

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```
> brew install getsentry/tools/sentry-wizard && sentry-wizard -i ios
> ```
> 
> It handles login, org/project selection, auth token setup, SDK installation,
> AppDelegate updates, and dSYM/debug symbol upload build phases.
> 
> **Once it finishes, come back and skip to [Verification](#verification).**

If the user skips the wizard, proceed with Option 2 (SPM/CocoaPods) and manual setup
below.

**Option 2 — Swift Package Manager:** File → Add Packages → enter:
```
https://github.com/getsentry/sentry-cocoa.git
```

Or in `Package.swift`:
```swift
.package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.15.0"),
```

**SPM Products** — choose **exactly one** per target:

| Product | Use Case |
| --- | --- |
| `Sentry` | **Recommended** — static framework, fast app start; includes SwiftUI APIs in SDK 9.4.1+ |
| `Sentry-Dynamic` | Dynamic framework alternative |
| `SentrySwiftUI` | Legacy/deprecated re-export for SwiftUI APIs; use only when maintaining older setup |
| `Sentry-WithoutUIKitOrAppKit` | watchOS, app extensions, CLI tools (Swift < 6.1) |
| `SentrySPM` + `NoUIFramework` trait | Source build without UIKit/AppKit for CLI/headless targets (**SDK 9.7+ / Swift 6.1+ / Xcode 26.4+** for Xcode UI) |

> Warning: Xcode allows selecting multiple products — choose only one.
> 
> If using `SentrySPM` from source, current source-build projects may import
> `SentrySwift` instead of `Sentry`; verify the module name in the target.
> Released binary products use `import Sentry`.

**Swift 6.1+ trait-based opt-out of UIKit/AppKit** (requires `Package@swift-6.1.swift`
manifest):

```swift
// Package.swift (Swift 6.1+)
.package(
    url: "https://github.com/getsentry/sentry-cocoa",
    from: "9.15.0",
    traits: ["NoUIFramework"]
),

// In your target's dependencies:
.product(name: "SentrySPM", package: "sentry-cocoa")
```

This is the preferred opt-out path for command-line/headless targets on Swift 6.1+. It
compiles the SDK from source so the trait can remove UIKit/AppKit/SwiftUI linkage.
For Swift < 6.1 continue using `Sentry-WithoutUIKitOrAppKit`.

> **Note:** Package traits are visible in the Xcode UI starting with **Xcode 26.4+**. On
> older Xcode versions, traits still work when declared in `Package.swift` but won’t
> appear in the GUI.

**Option 3 — CocoaPods (deprecated; prefer SPM):**
```ruby
platform :ios, '15.0'
use_frameworks!

target 'YourApp' do
  pod 'Sentry', :git => 'https://github.com/getsentry/sentry-cocoa.git', :tag => '9.15.0'
end
```

Sentry plans to stop publishing CocoaPods releases at the end of June 2026; use this
only for existing CocoaPods projects.

> **Known issue (Xcode 14+):** Sandbox `rsync.samba` error → Target Settings → “Enable
> User Script Sandbox” → `NO`.

**Option 4 — SentryObjC (for pure Objective-C/C++ projects):**

For pure Objective-C or Objective-C++ projects that **cannot enable Clang modules**
(e.g., `-fmodules=NO`), use the SentryObjC wrapper SDK. It provides the same
functionality as the main SDK but with pure Objective-C headers that don’t require Swift
module imports.

**SPM:**
```swift
.package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.17.1"),

// In your target's dependencies:
.product(name: "SentryObjC", package: "sentry-cocoa")
```

Or download `SentryObjC-Dynamic.xcframework.zip` from the
[releases page](https://github.com/getsentry/sentry-cocoa/releases).

**Migration from regular Sentry to SentryObjC:**
- Change `#import <Sentry/Sentry.h>` to `#import <SentryObjC/SentryObjC.h>`
- Rename `Sentry`-prefixed types to `SentryObjC` (e.g., `SentrySDK` → `SentryObjCSDK`,
  `SentryOptions` → `SentryObjCOptions`)
- The API surface is otherwise identical

Most users should use the standard `Sentry` product (Option 2). Only use `SentryObjC` if
you have a specific requirement preventing Clang modules.

* * *

### Quick Start — Recommended Init

Full iOS app config enabling the most common features with sensible defaults.
Add before any other code at app startup.

For macOS, watchOS, app extensions, or `NoUIFramework` builds, omit options that are
unavailable for that platform (`sessionReplay`, screenshots/view hierarchy,
user-feedback UI, UIKit tracing, and profiling on tvOS/watchOS/visionOS). Keep the core
`dsn`, environment, error monitoring, tracing, logs, and metrics settings that compile
for the detected target.

**SwiftUI — App entry point:**
```swift
import SwiftUI
import Sentry

@main
struct MyApp: App {
    init() {
        SentrySDK.start { options in
            options.dsn = ProcessInfo.processInfo.environment["SENTRY_DSN"]
                ?? "https://examplePublicKey@o0.ingest.sentry.io/0"
            options.environment = ProcessInfo.processInfo.environment["SENTRY_ENVIRONMENT"]
                ?? "production"
            // releaseName defaults to "<bundle id>@<version>+<build>"; set only if you need a custom release.

            // Error monitoring (on by default — explicit for clarity)
            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.enableReportNonFullyBlockingAppHangs = true
            options.enableWatchdogTerminationTracking = true
            options.attachScreenshot = true
            options.attachViewHierarchy = true
            options.sendDefaultPii = true

            // Tracing
            options.tracesSampleRate = 1.0          // lower to 0.2 in high-traffic production

            // Profiling (SDK 9.0.0+ API)
            options.configureProfiling = {
                $0.sessionSampleRate = 1.0
                $0.lifecycle = .trace
            }

            // Session Replay. Keep production sampling conservative and verify masking on iOS 26+.
            options.sessionReplay.sessionSampleRate = 0.1
            options.sessionReplay.onErrorSampleRate = 1.0

            // Logging (SDK 9.0.0+ top-level; use options.experimental.enableLogs in 8.x)
            options.enableLogs = true

            // Metrics are enabled by default in SDK 9.12+. Set false only to opt out.
            options.enableMetrics = true
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

**UIKit — AppDelegate:**
```swift
import UIKit
import Sentry

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        SentrySDK.start { options in
            options.dsn = ProcessInfo.processInfo.environment["SENTRY_DSN"]
                ?? "https://examplePublicKey@o0.ingest.sentry.io/0"
            options.environment = ProcessInfo.processInfo.environment["SENTRY_ENVIRONMENT"]
                ?? "production"
            // releaseName defaults to "<bundle id>@<version>+<build>"; set only if you need a custom release.

            options.enableCrashHandler = true
            options.enableAppHangTracking = true
            options.enableReportNonFullyBlockingAppHangs = true
            options.enableWatchdogTerminationTracking = true
            options.attachScreenshot = true
            options.attachViewHierarchy = true
            options.sendDefaultPii = true

            options.tracesSampleRate = 1.0

            options.configureProfiling = {
                $0.sessionSampleRate = 1.0
                $0.lifecycle = .trace
            }

            options.sessionReplay.sessionSampleRate = 0.1
            options.sessionReplay.onErrorSampleRate = 1.0

            // Logging (SDK 9.0.0+ top-level; use options.experimental.enableLogs in 8.x)
            options.enableLogs = true

            // Metrics are enabled by default in SDK 9.12+. Set false only to opt out.
            options.enableMetrics = true
        }
        return true
    }
}
```

> Warning: SDK initialization must occur on the **main thread**.

* * *

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file for each, follow its steps, and verify before moving to the
next:

| Feature | Reference file | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing | `./tracing.md` | App launch, network, UIViewController perf |
| Profiling | `./profiling.md` | Production perf-sensitive apps |
| Session Replay | `./session-replay.md` | User-facing iOS apps; tvOS only with caveat |
| Logging | `./logging.md` | Structured log capture needed |
| Metrics | `./metrics.md` | Aggregate counters, gauges, distributions |
| User Feedback | `./user-feedback.md` | In-app bug reporting wanted |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `SentryOptions` Fields

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `String?` | `nil` | SDK disabled if empty; macOS can read `SENTRY_DSN`, other Apple platforms must set explicitly |
| `environment` | `String` | `"production"` | e.g., `"production"` |
| `releaseName` | `String?` | bundle-derived | Defaults to `<bundle id>@<version>+<build>` |
| `debug` | `Bool` | `false` | Verbose SDK output — **disable in production** |
| `sendDefaultPii` | `Bool` | `false` | Include IP, user info from active integrations |
| `enableCrashHandler` | `Bool` | `true` | Master switch for crash reporting |
| `enableAppHangTracking` | `Bool` | `true` | Master switch for app hang tracking |
| `enableReportNonFullyBlockingAppHangs` | `Bool` | `true` | Report non-fully-blocking hangs on supported UI platforms |
| `appHangTimeoutInterval` | `Double` | `2.0` | Seconds before classifying as hang |
| `enableWatchdogTerminationTracking` | `Bool` | `true` | Track watchdog kills (iOS, tvOS, Mac Catalyst) |
| `attachScreenshot` | `Bool` | `false` | Capture screenshot on error |
| `attachViewHierarchy` | `Bool` | `false` | Capture view hierarchy on error |
| `tracesSampleRate` | `NSNumber?` | `nil` | Transaction sample rate (`nil` = tracing disabled); Swift auto-boxes `Double` literals (e.g. `1.0` → `NSNumber`) |
| `tracesSampler` | `Closure` | `nil` | Dynamic per-transaction sampling (overrides rate) |
| `enableAutoPerformanceTracing` | `Bool` | `true` | Master switch for auto-instrumentation |
| `tracePropagationTargets` | `[Any]` | all requests | Strings or `NSRegularExpression` values that receive distributed trace headers |
| `enableCaptureFailedRequests` | `Bool` | `true` | Auto-capture HTTP 5xx errors as events |
| `enableNetworkBreadcrumbs` | `Bool` | `true` | Breadcrumbs for outgoing HTTP requests |
| `add(inAppInclude:)` | Method | bundle executable | Add module prefixes treated as “in-app” code |
| `maxBreadcrumbs` | `Int` | `100` | Max breadcrumbs per event |
| `sampleRate` | `Float` | `1.0` | Error event sample rate |
| `beforeSend` | `Closure` | `nil` | Hook to mutate/drop error events |
| `onLastRunStatusDetermined` | `Closure` | `nil` | Called after SDK determines previous launch crash status |
| `strictTraceContinuation` | `Bool` | `false` | Reject incoming traces from other orgs; validates `sentry-org_id` in baggage headers (sentry-cocoa ≥9.10.0) |
| `orgId` | `String?` | `nil` | Organization ID for strict trace validation; auto-parsed from DSN host (e.g. `o123.ingest.sentry.io` → `"123"`) if not set explicitly |
| `enableLogs` | `Bool` | `false` | Enable structured logs |
| `enableMetrics` | `Bool` | `true` | Enable Swift Metrics API (SDK 9.12+) |

### Environment Variables

| Variable | Maps to | Purpose |
| --- | --- | --- |
| `SENTRY_DSN` | `dsn` | macOS fallback only; set explicitly on iOS/tvOS/watchOS/visionOS |
| `SENTRY_RELEASE` | `releaseName` | Do not assume automatic Cocoa fallback; set explicitly if needed |
| `SENTRY_ENVIRONMENT` | `environment` | Do not assume automatic Cocoa fallback; set explicitly if needed |

### Platform Feature Support Matrix

| Feature | iOS | tvOS | macOS | watchOS | visionOS |
| --- | --- | --- | --- | --- | --- |
| Crash Reporting | Yes | Yes | Yes | No | Yes |
| App Hangs | Yes | Yes | Yes | No | Yes |
| Watchdog Termination | Yes | Yes | No | No | Yes |
| App Start Tracing | Yes | Yes | No | No | Yes |
| UIViewController Tracing | Yes | Yes | No | No | Yes |
| SwiftUI Tracing | Yes | Yes | Yes | No | Yes |
| Network Tracking | Yes | Yes | Yes | No | Yes |
| Profiling | Yes | No | Yes | No | No |
| Session Replay | Yes | Unofficial | No | No | No |
| MetricKit | Yes (15+) | No | Yes (12+) | No | No |
| Metrics API | Yes | Yes | Yes | Verify | Yes |

### Production Settings

Lower sample rates for production to control volume and cost:

```swift
options.tracesSampleRate = 0.2          // 20% of transactions

options.configureProfiling = {
    $0.sessionSampleRate = 0.1          // 10% of sessions
    $0.lifecycle = .trace
}

options.sessionReplay.sessionSampleRate = 0.1   // 10% continuous
options.sessionReplay.onErrorSampleRate = 1.0   // 100% on error (keep high)

options.enableLogs = true
options.enableMetrics = true             // default true in SDK 9.12+
options.debug = false                   // never in production
```

* * *

## Verification

Test that Sentry is receiving events:

```swift
// Trigger a test error event:
SentrySDK.capture(message: "Sentry Cocoa SDK test")

// Or test crash reporting (without debugger — crashes are intercepted by debugger):
// SentrySDK.crash()  // uncomment, run without debugger, relaunch to see crash report
```

Check the Sentry dashboard within a few seconds.
If nothing appears:
1. Set `options.debug = true` — prints SDK internals to Xcode console
2. Verify the DSN is correct and the project exists
3. Ensure initialization is on the **main thread**

* * *

## Phase 4: Cross-Link

After completing Apple setup, check for a companion backend missing Sentry coverage:

```bash
# Detect companion backend
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod 2>/dev/null | head -5
cat ../requirements.txt ../Pipfile 2>/dev/null | head -5
cat ../Gemfile 2>/dev/null | head -5
cat ../package.json 2>/dev/null | grep -E '"name"|"dependencies"' | head -5
```

If a backend is found, configure `tracePropagationTargets` to enable distributed tracing
end-to-end, and suggest the matching skill:

| Backend detected | Suggest skill | Trace header support |
| --- | --- | --- |
| Go (`go.mod`) | [`go`](../go/index.md) | Automatic |
| Python (`requirements.txt`) | [`python`](../python/index.md) | Automatic |
| Ruby (`Gemfile`) | [`ruby`](../ruby/index.md) | Automatic |
| Node.js backend (`package.json`) | [`node`](../node/index.md) | Automatic |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing | Set `debug: true`, verify DSN format, ensure init is on main thread |
| Crashes not captured | **Run without debugger attached** — debugger intercepts signals |
| App hangs not reported | Auto-disabled when debugger attached; check `appHangTimeoutInterval` |
| Session Replay not recording | Verify `sessionSampleRate > 0` or `onErrorSampleRate > 0`; on iOS 26+ verify masking and any manual Liquid Glass gating |
| Tracing data missing | Confirm `tracesSampleRate > 0`; check `enableAutoPerformanceTracing = true` |
| Profiling data missing | Verify `sessionSampleRate > 0` in `configureProfiling`; for `.trace` lifecycle, tracing must be enabled |
| `rsync.samba` build error (CocoaPods) | Target Settings → “Enable User Script Sandbox” → `NO` |
| Multiple SPM products selected | Choose **only one** of `Sentry`, `Sentry-Dynamic`, `SentrySwiftUI`, `Sentry-WithoutUIKitOrAppKit`, or `SentrySPM` (with `NoUIFramework` trait on Swift 6.1+) |
| `inAppExclude` compile error | Removed in SDK 9.0.0 — use `options.add(inAppInclude:)` |
| `enableAppHangTrackingV2` compile error | Removed in SDK 9.0.0 — use `enableAppHangTracking`; V2 behavior is default where supported |
| Watchdog termination not tracked | Requires `enableCrashHandler = true` (it is by default) |
| Network breadcrumbs missing | Requires `enableSwizzling = true` (it is by default) |
| `profilesSampleRate` compile error | Removed in SDK 9.0.0 — use `configureProfiling` closure instead |
