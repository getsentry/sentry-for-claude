# Sentry React Native SDK

Opinionated wizard that scans your React Native or Expo project and guides you through
complete Sentry setup — error monitoring, tracing, profiling, session replay, logging,
and more.

> **Note:** SDK versions and APIs below reflect current Sentry docs at time of writing
> (`@sentry/react-native` ≥6.0.0, minimum recommended ≥8.0.0). Always verify against
> [docs.sentry.io/platforms/react-native/](https://docs.sentry.io/platforms/react-native/)
> before implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect project type and existing Sentry
cat package.json | grep -E '"(react-native|expo|@expo|@sentry/react-native|sentry-expo)"'

# Distinguish Expo managed vs bare vs vanilla RN
ls app.json app.config.js app.config.ts 2>/dev/null
cat app.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('Expo managed' if 'expo' in d else 'Bare/Vanilla')" 2>/dev/null

# Check Expo SDK version (important: Expo SDK 50+ required for @sentry/react-native)
cat package.json | grep '"expo"'

# Detect navigation library
grep -E '"(@react-navigation/native|react-native-navigation)"' package.json

# Detect state management (Redux → breadcrumb integration available)
grep -E '"(redux|@reduxjs/toolkit|zustand|mobx)"' package.json

# Check for existing Sentry initialization
grep -r "Sentry.init" src/ app/ App.tsx App.js _layout.tsx 2>/dev/null | head -5

# Detect Hermes (affects source map handling)
cat android/app/build.gradle 2>/dev/null | grep -i hermes
cat ios/Podfile 2>/dev/null | grep -i hermes

# Detect Expo Router
ls app/_layout.tsx app/_layout.js 2>/dev/null

# Detect backend for cross-link
ls backend/ server/ api/ 2>/dev/null
find . -maxdepth 3 \( -name "go.mod" -o -name "requirements.txt" -o -name "Gemfile" -o -name "package.json" \) 2>/dev/null | grep -v node_modules | head -10
```

**What to determine:**

| Question | Impact |
| --- | --- |
| `expo` in `package.json`? | Expo path (config plugin + `getSentryExpoConfig`) vs bare/vanilla RN path |
| Expo SDK ≥50? | `@sentry/react-native` directly; older = `sentry-expo` (legacy, do not use) |
| `app.json` has `"expo"` key? | Managed Expo — wizard is simplest; config plugin handles all native config |
| `app/_layout.tsx` present? | Expo Router project — init goes in `_layout.tsx` |
| `@sentry/react-native` already in `package.json`? | Skip install, jump to feature config |
| `@react-navigation/native` present? | Recommend `reactNavigationIntegration` for screen tracking |
| `react-native-navigation` present? | Recommend `reactNativeNavigationIntegration` (Wix) |
| Backend directory detected? | Trigger Phase 4 cross-link |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Don’t ask open-ended questions — lead with a proposal:

**Recommended (core coverage — always set up these):**
- ✅ **Error Monitoring** — captures JS exceptions, native crashes (iOS + Android), ANRs,
  and app hangs
- ✅ **Tracing** — mobile performance is critical; auto-instruments navigation, app
  start, network requests
- ✅ **Session Replay** — mobile replay captures screenshots and touch events for
  debugging user issues

**Optional (enhanced observability):**
- ⚡ **Profiling** — CPU profiling on iOS (JS profiling cross-platform); low overhead in
  production
- ⚡ **Logging** — structured logs via `Sentry.logger.*`; links to traces for full
  context
- ⚡ **User Feedback** — collect user-submitted bug reports directly from your app

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline for any mobile app |
| Tracing | **Always for mobile** — app start, navigation, and network latency matter |
| Session Replay | User-facing production app; debug user-reported issues visually |
| Profiling | Performance-sensitive screens, startup time concerns, or production perf investigations |
| Logging | App uses structured logging, or you want log-to-trace correlation in Sentry |
| User Feedback | Beta or customer-facing app where you want user-submitted bug reports |

Propose: *“For your [Expo managed / bare RN] app, I recommend setting up Error
Monitoring + Tracing + Session Replay.
Want me to also add Profiling and Logging?”*

* * *

## Phase 3: Guide

### Determine Your Setup Path

| Project type | Recommended setup | Complexity |
| --- | --- | --- |
| Expo managed (SDK 50+) | Wizard CLI or manual with config plugin | Low — wizard does everything |
| Expo bare (SDK 50+) | Wizard CLI recommended | Medium — handles iOS/Android config |
| Vanilla React Native (0.69+) | Wizard CLI recommended | Medium — handles Xcode + Gradle |
| Expo SDK <50 | Use `sentry-expo` (legacy) | See [legacy docs](https://docs.sentry.io/platforms/react-native/manual-setup/expo/) |

* * *

### Path A: Wizard CLI (Recommended for all project types)

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```
> npx @sentry/wizard@latest -i reactNative
> ```
> 
> It handles login, org/project selection, SDK installation, native config, source map
> upload, and `Sentry.init()`. Here’s what it creates/modifies:
> 
| File | Action | Purpose |
| --- | --- | --- |
| `package.json` | Installs `@sentry/react-native` | Core SDK |
| `metro.config.js` | Adds `@sentry/react-native/metro` serializer | Source map generation |
| `app.json` | Adds `@sentry/react-native/expo` plugin (Expo only) | Config plugin for native builds |
| `App.tsx` / `_layout.tsx` | Adds `Sentry.init()` and `Sentry.wrap()` | SDK initialization |
| `ios/sentry.properties` | Stores org/project/token | iOS source map + dSYM upload |
| `android/sentry.properties` | Stores org/project/token | Android source map upload |
| `android/app/build.gradle` | Adds Sentry Gradle plugin | Android source maps + proguard |
| `ios/[AppName].xcodeproj` | Wraps “Bundle RN” build phase + adds dSYM upload | iOS symbol upload |
| `.env.local` | `SENTRY_AUTH_TOKEN` | Auth token (add to `.gitignore`) |
> 
> **Once it finishes, come back and skip to [Verification](#verification).**

If the user skips the wizard, proceed with Path B or C (Manual Setup) below based on
their project type.

* * *

### Path B: Manual — Expo Managed (SDK 50+)

**Step 1 — Install**

```bash
npx expo install @sentry/react-native
```

**Step 2 — `metro.config.js`**

```javascript
const { getSentryExpoConfig } = require("@sentry/react-native/metro");
const config = getSentryExpoConfig(__dirname, {
  // Auto-wrap Expo Router ErrorBoundary exports at build time (SDK ≥8.17.0)
  autoWrapExpoRouterErrorBoundary: true,
});
module.exports = config;
```

If `metro.config.js` doesn’t exist yet:
```bash
npx expo customize metro.config.js
# Then replace contents with the above
```

**Metro config options:**

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `autoWrapExpoRouterErrorBoundary` | `boolean` | `false` | Automatically wrap `export { ErrorBoundary } from 'expo-router'` with Sentry at build time (SDK ≥8.17.0). Captures errors that hit per-route ErrorBoundaries without manual wrapping |
| `annotateReactComponents` | `boolean` | `false` | Inject component names for better error context |
| `includeWebReplay` | `boolean` | `true` | Include web replay bundle (set `false` for native-only apps) |
| `includeWebFeedback` | `boolean` | `true` | Include web feedback bundle (set `false` for native-only apps) |
| `enableSourceContextInDevelopment` | `boolean` | `true` | Enable source context in dev builds |

**Step 3 — `app.json` — Add Expo config plugin**

```json
{
  "expo": {
    "plugins": [
      [
        "@sentry/react-native/expo",
        {
          "url": "https://sentry.io/",
          "project": "YOUR_PROJECT_SLUG",
          "organization": "YOUR_ORG_SLUG",
          "disableAutoUpload": false
        }
      ]
    ]
  }
}
```

> **Note:** Set `SENTRY_AUTH_TOKEN` as an environment variable for native builds — never
> commit it to version control.

**Plugin options:**

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `url` | `string` | `"https://sentry.io/"` | Sentry instance URL |
| `project` | `string` | — | Project slug |
| `organization` | `string` | — | Organization slug |
| `disableAutoUpload` | `boolean` | `false` | Skip source map + dSYM upload during local builds (SDK ≥8.13.0) |

**Step 4 — Initialize Sentry**

For **Expo Router** (`app/_layout.tsx`):

```typescript
import { Stack } from "expo-router";
import { isRunningInExpoGo } from "expo";
import * as Sentry from "@sentry/react-native";

Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN ?? "YOUR_SENTRY_DSN",
  sendDefaultPii: true,

  // Tracing
  tracesSampleRate: 1.0, // lower to 0.1–0.2 in production

  // Profiling
  profilesSampleRate: 1.0,

  // Session Replay
  replaysOnErrorSampleRate: 1.0,
  replaysSessionSampleRate: 0.1,

  // Logging (SDK ≥7.0.0)
  enableLogs: true,

  // Session Replay
  integrations: [
    Sentry.mobileReplayIntegration(),
  ],

  enableNativeFramesTracking: !isRunningInExpoGo(), // slow/frozen frames

  environment: __DEV__ ? "development" : "production",
});

function RootLayout() {
  return <Stack />;
}

export default Sentry.wrap(RootLayout);
```

> **Note:** Expo Router automatically handles navigation tracking.
> The `Sentry.NavigationContainer` wrapper is not needed for Expo Router projects —
> navigation spans are captured automatically.

**Expo Router ErrorBoundary Setup (SDK ≥8.16.0)**

Expo Router’s per-route `ErrorBoundary` swallows render errors by default — Sentry won’t
see them unless you explicitly capture them.
Two options:

1. **Auto-wrap (recommended, SDK ≥8.17.0)** — Enable
   `autoWrapExpoRouterErrorBoundary: true` in `metro.config.js` (shown above).
   The Babel plugin rewrites `export { ErrorBoundary } from 'expo-router'` automatically
   in all route files.

2. **Manual wrap** — Wrap the boundary yourself in each route file:

   ```typescript
   // app/_layout.tsx (or any route file)
   import { ErrorBoundary as ExpoErrorBoundary } from 'expo-router';
   import * as Sentry from '@sentry/react-native';

   export const ErrorBoundary = Sentry.wrapExpoRouterErrorBoundary(ExpoErrorBoundary);
   ```

Both methods capture errors that hit the boundary with route context (`route.name`,
`route.path`, `route.params`), tag the active navigation span as errored, and emit a
breadcrumb. Concrete paths/params respect `sendDefaultPii`.

For **standard Expo** (`App.tsx`):

```typescript
import { isRunningInExpoGo } from "expo";
import * as Sentry from "@sentry/react-native";

Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN ?? "YOUR_SENTRY_DSN",
  sendDefaultPii: true,
  tracesSampleRate: 1.0,
  profilesSampleRate: 1.0,
  replaysOnErrorSampleRate: 1.0,
  replaysSessionSampleRate: 0.1,
  enableLogs: true,
  integrations: [
    Sentry.mobileReplayIntegration(),
  ],
  enableNativeFramesTracking: !isRunningInExpoGo(),
  environment: __DEV__ ? "development" : "production",
});

function App() {
  return (
    <Sentry.NavigationContainer>
      {/* your navigation here */}
    </Sentry.NavigationContainer>
  );
}

export default Sentry.wrap(App);
```

* * *

### Path C: Manual — Bare React Native (0.69+)

**Step 1 — Install**

```bash
npm install @sentry/react-native --save
cd ios && pod install
```

**Step 2 — `metro.config.js`**

```javascript
const { getDefaultConfig } = require("@react-native/metro-config");
const { withSentryConfig } = require("@sentry/react-native/metro");

const config = getDefaultConfig(__dirname);
module.exports = withSentryConfig(config, {
  // Set to false to exclude @sentry-internal/replay from the native bundle (web only).
  // includeWebReplay: true,
  // Set to false to exclude @sentry-internal/feedback from the native bundle (web only).
  // includeWebFeedback: true,
  // Auto-wrap Expo Router ErrorBoundary exports at build time (SDK ≥8.17.0, Expo Router only)
  // autoWrapExpoRouterErrorBoundary: true,
});
```

**Step 3 — iOS: Modify Xcode build phase**

Open `ios/[AppName].xcodeproj` in Xcode.
Find the **“Bundle React Native code and images”** build phase and replace the script
content with:

```bash
# RN 0.81.1+
set -e
WITH_ENVIRONMENT="../node_modules/react-native/scripts/xcode/with-environment.sh"
SENTRY_XCODE="../node_modules/@sentry/react-native/scripts/sentry-xcode.sh"
/bin/sh -c "$WITH_ENVIRONMENT $SENTRY_XCODE"
```

**Step 4 — iOS: Add “Upload Debug Symbols to Sentry” build phase**

Add a new **Run Script** build phase in Xcode (after the bundle phase):

```bash
/bin/sh ../node_modules/@sentry/react-native/scripts/sentry-xcode-debug-files.sh
```

**Step 5 — iOS: `ios/sentry.properties`**

```properties
defaults.url=https://sentry.io/
defaults.org=YOUR_ORG_SLUG
defaults.project=YOUR_PROJECT_SLUG
auth.token=YOUR_ORG_AUTH_TOKEN
```

**Step 6 — Android: `android/app/build.gradle`**

Add before the `android {}` block:

```groovy
apply from: "../../node_modules/@sentry/react-native/sentry.gradle.kts"
```

> **Note:** SDK ≥8.13.0 uses `sentry.gradle.kts` (Kotlin DSL). For older SDKs, use
> `sentry.gradle` (Groovy).
> Both are backward-compatible.

**Step 7 — Android: `android/sentry.properties`**

```properties
defaults.url=https://sentry.io/
defaults.org=YOUR_ORG_SLUG
defaults.project=YOUR_PROJECT_SLUG
auth.token=YOUR_ORG_AUTH_TOKEN
```

**Step 8 — Initialize Sentry (`App.tsx` or entry point)**

```typescript
import * as Sentry from "@sentry/react-native";

Sentry.init({
  dsn: "YOUR_SENTRY_DSN",
  sendDefaultPii: true,
  tracesSampleRate: 1.0,
  profilesSampleRate: 1.0,
  replaysOnErrorSampleRate: 1.0,
  replaysSessionSampleRate: 0.1,
  enableLogs: true,
  integrations: [
    Sentry.mobileReplayIntegration(),
  ],
  enableNativeFramesTracking: true,
  environment: __DEV__ ? "development" : "production",
});

function App() {
  return (
    <Sentry.NavigationContainer>
      {/* your navigation here */}
    </Sentry.NavigationContainer>
  );
}

export default Sentry.wrap(App);
```

* * *

### Quick Reference: Full-Featured `Sentry.init()`

This is the recommended starting configuration with all features enabled:

```typescript
import * as Sentry from "@sentry/react-native";

Sentry.init({
  dsn: "YOUR_SENTRY_DSN",
  sendDefaultPii: true,

  // Tracing — lower to 0.1–0.2 in high-traffic production
  tracesSampleRate: 1.0,

  // Profiling — runs on a subset of traced transactions
  profilesSampleRate: 1.0,

  // Session Replay — always capture on error, sample 10% of all sessions
  replaysOnErrorSampleRate: 1.0,
  replaysSessionSampleRate: 0.1,

  // Logging — enable Sentry.logger.* API
  enableLogs: true,

  // Integrations — mobile replay is opt-in
  integrations: [
    Sentry.mobileReplayIntegration({
      maskAllText: true,   // masks text by default for privacy
      maskAllImages: true,
    }),
  ],

  // Native frames tracking (disable in Expo Go)
  enableNativeFramesTracking: true,

  // Environment
  environment: __DEV__ ? "development" : "production",

  // Release — set from CI or build system
  // release: "my-app@1.0.0+1",
  // dist: "1",
});

// REQUIRED: Wrap root component to capture React render errors
export default Sentry.wrap(App);
```

### App Start Accuracy — `Sentry.appLoaded()` (SDK ≥8.x)

If your app does significant async work after the root component mounts (e.g., fetching
config, waiting for auth), call `Sentry.appLoaded()` once that work is complete.
This signals the true end of app startup to Sentry and produces more accurate app start
duration measurements.

```typescript
// Call after async initialization is complete, e.g., in a useEffect or after a loading screen:
useEffect(() => {
  fetchConfig().then(() => {
    Sentry.appLoaded();  // marks the end of the app startup phase
  });
}, []);
```

If you don’t call `Sentry.appLoaded()`, the SDK estimates the app start end
automatically.

* * *

### Navigation Setup — React Navigation (v5+)

**Recommended: Use `Sentry.NavigationContainer` wrapper (SDK ≥8.13.0)**

Drop-in replacement for `NavigationContainer` that automatically wires up navigation
tracking:

```typescript
import * as Sentry from "@sentry/react-native";

// Replace NavigationContainer with Sentry.NavigationContainer
<Sentry.NavigationContainer>
  <Stack.Navigator>
    {/* your screens */}
  </Stack.Navigator>
</Sentry.NavigationContainer>
```

That’s it! The wrapper automatically:
- Creates the `reactNavigationIntegration`
- Registers the navigation container ref
- Captures breadcrumbs for navigation events (SDK ≥8.13.0)
- Tracks Time to Initial Display (TTID) per screen

**Alternative: Manual setup (for SDK <8.13.0 or custom config)**

```typescript
import { reactNavigationIntegration } from "@sentry/react-native";
import { NavigationContainer, createNavigationContainerRef } from "@react-navigation/native";

const navigationIntegration = reactNavigationIntegration({
  enableTimeToInitialDisplay: true,   // track TTID per screen
  routeChangeTimeoutMs: 1_000,        // max wait for route change to settle
  ignoreEmptyBackNavigationTransactions: true,
});

// Add to Sentry.init integrations array
Sentry.init({
  integrations: [navigationIntegration],
  // ...
});

// In your component:
const navigationRef = createNavigationContainerRef();

<NavigationContainer
  ref={navigationRef}
  onReady={() => {
    navigationIntegration.registerNavigationContainer(navigationRef);
  }}
>
```

### Navigation Setup — Wix React Native Navigation

```typescript
import * as Sentry from "@sentry/react-native";
import { Navigation } from "react-native-navigation";

Sentry.init({
  integrations: [Sentry.reactNativeNavigationIntegration({ navigation: Navigation })],
  // ...
});
```

* * *

### Wrap Your Root Component

Always wrap your root component — this enables React error boundaries and ensures
crashes at the component tree level are captured:

```typescript
export default Sentry.wrap(App);
```

* * *

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file for each, follow its steps, then verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing & Performance | `./tracing.md` | Always for mobile (app start, navigation, network) |
| Profiling | `./profiling.md` | Performance-sensitive production apps |
| Session Replay | `./session-replay.md` | User-facing apps |
| Logging | `./logging.md` | Structured logging / log-to-trace correlation |
| User Feedback | `./user-feedback.md` | Collecting user-submitted reports |
| Expo Config Plugin | `./expo-config-plugin.md` | Configuring the `@sentry/react-native/expo` plugin |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Core `Sentry.init()` Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `string` | — | **Required.** Project DSN; SDK disabled if empty. Env: `SENTRY_DSN` |
| `environment` | `string` | — | e.g., `"production"`, `"staging"`. Env: `SENTRY_ENVIRONMENT` |
| `release` | `string` | — | App version, e.g., `"my-app@1.0.0+42"`. Env: `SENTRY_RELEASE` |
| `dist` | `string` | — | Build number / variant identifier (max 64 chars). Env: `SENTRY_DIST` |
| `sendDefaultPii` | `boolean` | `false` | Include PII: IP address, cookies, user data |
| `sampleRate` | `number` | `1.0` | Error event sampling (0.0–1.0) |
| `maxBreadcrumbs` | `number` | `100` | Max breadcrumbs per event |
| `attachStacktrace` | `boolean` | `true` | Auto-attach stack traces to messages |
| `attachScreenshot` | `boolean` | `false` | Capture screenshot on error (SDK ≥4.11.0) |
| `screenshot` | `object` | — | Fine-grained screenshot masking; only effective when `attachScreenshot: true`. See **Screenshot Masking Options** below |
| `attachViewHierarchy` | `boolean` | `false` | Attach JSON view hierarchy as attachment |
| `debug` | `boolean` | `false` | Verbose SDK output. **Never use in production** |
| `enabled` | `boolean` | `true` | Disable SDK entirely (e.g., for testing) |
| `ignoreErrors` | `string[] \| RegExp[]` | — | Drop errors matching these patterns |
| `ignoreTransactions` | `string[] \| RegExp[]` | — | Drop transactions matching these patterns |
| `maxCacheItems` | `number` | `30` | Max offline-cached envelopes |
| `defaultIntegrations` | `boolean` | `true` | Set `false` to disable all default integrations |
| `integrations` | `array \| function` | — | Add or filter integrations |

#### Screenshot Masking Options

Passed as the `screenshot` key inside `Sentry.init()` when `attachScreenshot: true`:

```typescript
Sentry.init({
  attachScreenshot: true,
  screenshot: {
    maskAllText: true,       // default: true — mask all text nodes
    maskAllImages: true,     // default: true — mask all images
    maskedViewClasses: ['com.mapbox.maps.MapView'],    // always mask these native view classes
    unmaskedViewClasses: ['com.example.SafeView'],     // always show these native view classes
  },
});
```

| Sub-option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `maskAllText` | `boolean` | `true` | Mask all text nodes in the screenshot |
| `maskAllImages` | `boolean` | `true` | Mask all images in the screenshot |
| `maskedViewClasses` | `string[]` | `[]` | Native view class names to always mask (Android/iOS) |
| `unmaskedViewClasses` | `string[]` | `[]` | Native view class names to always show (Android/iOS) |

### Tracing Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `tracesSampleRate` | `number` | `0` | Transaction sample rate (0–1). Use `1.0` in dev |
| `tracesSampler` | `function` | — | Per-transaction sampling; overrides `tracesSampleRate` |
| `tracePropagationTargets` | `(string \| RegExp)[]` | `[/.*/]` | Which API URLs receive distributed tracing headers |
| `profilesSampleRate` | `number` | `0` | Profiling sample rate (applied to traced transactions) |

### Native / Mobile Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `enableNative` | `boolean` | `true` | Set `false` for JS-only (no native SDK) |
| `enableNativeCrashHandling` | `boolean` | `true` | Capture native hard crashes (iOS/Android) |
| `enableNativeFramesTracking` | `boolean` | — | Slow/frozen frames tracking. **Disable in Expo Go** |
| `enableWatchdogTerminationTracking` | `boolean` | `true` | OOM kill detection (iOS) |
| `enableAppHangTracking` | `boolean` | `true` | App hang detection (iOS, tvOS, macOS) |
| `appHangTimeoutInterval` | `number` | `2` | Seconds before classifying as app hang (iOS) |
| `enableAutoPerformanceTracing` | `boolean` | `true` | Auto performance instrumentation |
| `enableNdkScopeSync` | `boolean` | `true` | Java→NDK scope sync (Android) |
| `attachThreads` | `boolean` | `false` | Auto-attach all threads on crash (Android) |
| `attachAllThreads` | `boolean` | `false` | Attach full stack traces for all threads to every captured event (iOS only, requires Cocoa SDK ≥9.9.0) |
| `autoInitializeNativeSdk` | `boolean` | `true` | Set `false` for manual native init |
| `onReady` | `function` | — | Callback after native SDKs initialize |
| `enableTurboModuleTracking` | `boolean` | `false` | **Experimental.** Install native TurboModule perf logger for crash attribution and per-module spans. RN 0.75+ New Architecture only; no-op on Old Architecture (SDK ≥8.17.0) |

### Session & Release Health Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `autoSessionTracking` | `boolean` | `true` | Session tracking (crash-free users/sessions) |
| `sessionTrackingIntervalMillis` | `number` | `30000` | ms of background before session ends |

### Replay Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `replaysSessionSampleRate` | `number` | `0` | Fraction of all sessions recorded |
| `replaysOnErrorSampleRate` | `number` | `0` | Fraction of error sessions recorded |

### Logging Options (SDK ≥7.0.0)

| Option | Type | Purpose |
| --- | --- | --- |
| `enableLogs` | `boolean` | Enable `Sentry.logger.*` API |
| `enableAutoConsoleLogs` | `boolean` | Auto-capture `console.*` calls when `enableLogs: true`. Set `false` to use only manual `Sentry.logger.*` (SDK ≥8.14.0, default: `true`) |
| `beforeSendLog` | `function` | Filter/modify logs before sending |
| `logsOrigin` | `'native' \| 'js' \| 'all'` | Filter log source (SDK ≥7.7.0) |

### Hook Options

| Option | Type | Purpose |
| --- | --- | --- |
| `beforeSend` | `(event, hint) => event \| null` | Modify/drop JS error events. ⚠️ Does NOT apply to native crashes |
| `beforeSendTransaction` | `(event) => event \| null` | Modify/drop transaction events |
| `beforeBreadcrumb` | `(breadcrumb, hint) => breadcrumb \| null` | Process breadcrumbs before storage |
| `onNativeLog` | `(log: { level, component, message }) => void` | Intercept native SDK log messages and forward to JS console. Only fires when `debug: true` |

### Environment Variables

| Variable | Purpose | Notes |
| --- | --- | --- |
| `SENTRY_DSN` | Data Source Name | Falls back from `dsn` option |
| `SENTRY_AUTH_TOKEN` | Upload source maps and dSYMs | **Never commit — use CI secrets** |
| `SENTRY_ORG` | Organization slug | Used by wizard and build plugins |
| `SENTRY_PROJECT` | Project slug | Used by wizard and build plugins |
| `SENTRY_RELEASE` | Release identifier | Falls back from `release` option |
| `SENTRY_DIST` | Distribution identifier | Falls back from `dist` option |
| `SENTRY_ENVIRONMENT` | Environment name | Falls back from `environment` option |
| `SENTRY_DISABLE_AUTO_UPLOAD` | Skip source map upload | Set `true` during local builds |
| `EXPO_PUBLIC_SENTRY_DSN` | Expo public env var for DSN | Safe to embed in client bundle |
| `SENTRY_EAS_BUILD_CAPTURE_SUCCESS` | EAS build hook: capture successful builds | Set `true` in EAS secrets |
| `SENTRY_EAS_BUILD_TAGS` | EAS build hook: additional tags JSON | e.g., `{"team":"mobile"}` |

### Default Integrations (Auto-Enabled)

These integrations are enabled automatically — no config needed:

| Integration | What it does |
| --- | --- |
| `ReactNativeErrorHandlers` | Catches unhandled JS exceptions and promise rejections |
| `Release` | Attaches release/dist to all events |
| `Breadcrumbs` | Records console logs, HTTP requests, user gestures as breadcrumbs |
| `HttpClient` | Adds HTTP request/response breadcrumbs |
| `DeviceContext` | Attaches device/OS/battery info to events |
| `AppContext` | Attaches app version, bundle ID, and memory info |
| `CultureContext` | Attaches locale and timezone |
| `Screenshot` | Captures screenshot on error (when `attachScreenshot: true`) |
| `ViewHierarchy` | Attaches view hierarchy (when `attachViewHierarchy: true`) |
| `NativeLinkedErrors` | Links JS errors to their native crash counterparts |
| `TurboModuleContext` | Tracks TurboModule calls in crash-time context; attributes native crashes to the high-level RN module + method (e.g., `RNSentry.captureEnvelope`) |

### Opt-In Integrations

| Integration | How to enable |
| --- | --- |
| `mobileReplayIntegration()` | Add to `integrations` array |
| `reactNavigationIntegration()` | Add to `integrations` array |
| `reactNativeNavigationIntegration()` | Add to `integrations` array (Wix only) |
| `feedbackIntegration()` | Add to `integrations` array (user feedback widget; supports `enableShakeToReport` for native shake detection) |
| `deeplinkIntegration()` | Add to `integrations` array (auto-captures deep link URLs as breadcrumbs; opt-in) |
| `turboModuleContextIntegration()` | **Default** — tracks `RNSentry` TurboModule automatically. Optionally configure with `{ modules: [...] }` to track custom TurboModules |

### Tracking Custom TurboModules

The `TurboModuleContext` integration is enabled by default and automatically tracks the
built-in `RNSentry` TurboModule.
To track your own custom TurboModules, configure the integration explicitly:

```typescript
import * as Sentry from "@sentry/react-native";
import { NativeModules } from "react-native";

Sentry.init({
  dsn: "YOUR_DSN",
  integrations: [
    Sentry.turboModuleContextIntegration({
      modules: [
        {
          name: "MyCustomModule",
          module: NativeModules.MyCustomModule,
          // Optional: skip specific methods to avoid tracking overhead
          skipMethods: ["addListener", "removeListeners"],
        },
      ],
    }),
  ],
});
```

When a native crash occurs inside a tracked TurboModule method call, the crash report
will include `contexts.turbo_module` with the module name and method, making it easier
to identify the exact RN API call that triggered the crash.

### Rage Tap Detection (TouchEventBoundary)

`TouchEventBoundary` (wraps your app root) includes built-in rage tap detection.
When a user taps the same element 3+ times within 1 second, a `ui.multiClick` breadcrumb
is emitted and shown on the replay timeline.
Configure via props:

```tsx
<Sentry.TouchEventBoundary
  enableRageTapDetection={true}   // default: true — set false to disable
  rageTapThreshold={3}            // taps required to trigger (default: 3)
  rageTapTimeWindow={1000}        // detection window in ms (default: 1000)
>
  <App />
</Sentry.TouchEventBoundary>
```

### Production Settings

Lower sample rates and harden config before shipping to production:

```typescript
Sentry.init({
  dsn: process.env.EXPO_PUBLIC_SENTRY_DSN,
  environment: __DEV__ ? "development" : "production",

  // Trace 10–20% of transactions in high-traffic production
  tracesSampleRate: __DEV__ ? 1.0 : 0.1,

  // Profile 100% of traced transactions (profiling is always a subset of tracing)
  profilesSampleRate: 1.0,

  // Replay all error sessions, sample 5% of normal sessions
  replaysOnErrorSampleRate: 1.0,
  replaysSessionSampleRate: __DEV__ ? 1.0 : 0.05,

  // Set release and dist for accurate source map lookup
  release: "my-app@" + Application.nativeApplicationVersion,
  dist: String(Application.nativeBuildVersion),

  // Disable debug logging in production
  debug: __DEV__,
});
```

* * *

### Source Maps & Debug Symbols

Source maps and debug symbols are what transform minified stack traces into readable
ones. When set up correctly, Sentry shows you the exact line of your source code that
threw. The React Native-specific upload mechanics are below.

#### How Uploads Work

| Platform | What’s uploaded | When |
| --- | --- | --- |
| **iOS** (JS) | Source maps (`.map` files) | During Xcode build |
| **iOS** (Native) | dSYM bundles | During Xcode archive / Xcode Cloud |
| **Android** (JS) | Source maps + Hermes `.hbc.map` | During Gradle build |
| **Android** (Native) | Proguard mapping + NDK `.so` files | During Gradle build |

#### Expo: Automatic Upload

The `@sentry/react-native/expo` config plugin automatically sets up upload hooks for
native builds. Source maps are uploaded during `eas build` and `expo run:ios/android`
(release).

```bash
SENTRY_AUTH_TOKEN=sntrys_... npx expo run:ios --configuration Release
```

#### Manual Upload (bare RN)

If you need to manually upload source maps:

```bash
npx sentry-cli sourcemaps upload \
  --org YOUR_ORG \
  --project YOUR_PROJECT \
  --release "my-app@1.0.0+1" \
  ./dist
```

* * *

### EAS Build Hooks

Monitor your Expo Application Services (EAS) builds in Sentry.
The SDK ships three binary hooks — `sentry-eas-build-on-complete`,
`sentry-eas-build-on-error`, and `sentry-eas-build-on-success` — that capture build
events as Sentry errors or messages.

**Step 1 — Register the hook in `package.json`**

```json
{
  "scripts": {
    "eas-build-on-complete": "sentry-eas-build-on-complete"
  }
}
```

Use `eas-build-on-complete` to capture both failures and (optionally) successes in one
hook. Alternatively use `eas-build-on-error` or `eas-build-on-success` separately if you
want independent control.

**Step 2 — Set `SENTRY_DSN` in your EAS secrets**

```bash
eas secret:create --name SENTRY_DSN --value "https://...@sentry.io/..."
```

The hook reads `SENTRY_DSN` from the build environment — it does not share the same
`.env` as your app.

**Optional environment variables:**

| Variable | Purpose |
| --- | --- |
| `SENTRY_EAS_BUILD_CAPTURE_SUCCESS` | Set `true` to also capture successful builds (default: errors only) |
| `SENTRY_EAS_BUILD_TAGS` | JSON object of additional tags, e.g., `{"team":"mobile","channel":"production"}` |
| `SENTRY_EAS_BUILD_ERROR_MESSAGE` | Custom error message for failed builds |
| `SENTRY_EAS_BUILD_SUCCESS_MESSAGE` | Custom message for successful builds |

> **How it works:** The hook script is an EAS
> [npm lifecycle hook](https://docs.expo.dev/build-reference/npm-hooks/). EAS calls
> `package.json` scripts matching `eas-build-on-*` at the end of the build process.
> The script loads env from `@expo/env`, `.env`, or `.env.sentry-build-plugin` — without
> overwriting EAS secrets already in the environment.

* * *

## Verification

After setup, test that Sentry is receiving events:

```typescript
// Quick test — throws and Sentry.wrap(App) catches it
<Button
  title="Test Sentry Error"
  onPress={() => {
    throw new Error("My first Sentry error!");
  }}
/>

// Or capture manually
<Button
  title="Test Sentry Message"
  onPress={() => {
    Sentry.captureMessage("Sentry test message", "info");
  }}
/>
```

**Check the Sentry dashboard:**
- **Issues** → your test error should appear within seconds
- **Traces** → look for a “main” transaction with child spans
- **Replays** → session recording visible after app interaction (native build only — not
  Expo Go)
- **Logs** → structured log entries if `enableLogs: true`

> ⚠️ **Expo Go limitation:** Native crashes, session replay, slow/frozen frames, TTID,
> and TTFD only work in native builds (`eas build` or `expo run`). Expo Go runs in a
> JS-only mode. Set `enableNativeFramesTracking: !isRunningInExpoGo()` to avoid warnings.

If nothing appears:
1. Set `debug: true` — SDK logs to Metro console
2. Verify DSN is correct and the Sentry project exists
3. Ensure `Sentry.wrap(App)` is applied to the root component
4. For native crashes, build a release build (crashes in debug mode may not forward)

* * *

## Phase 4: Cross-Link

After completing React Native setup, check for a backend or web frontend missing Sentry
coverage:

```bash
# Adjacent backend directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod 2>/dev/null | head -3
cat ../requirements.txt ../pyproject.toml 2>/dev/null | head -3
cat ../Gemfile 2>/dev/null | head -3
ls ../backend/package.json ../server/package.json 2>/dev/null

# Web frontend in same or sibling repo
ls ../web ../frontend ../dashboard 2>/dev/null
cat ../web/package.json ../frontend/package.json 2>/dev/null | grep -E '"react"|"svelte"|"next"'

# Check for OpenTelemetry (for distributed tracing interop)
grep -r "opentelemetry" ../backend/go.mod ../server/requirements.txt 2>/dev/null
```

If a backend or web frontend exists without Sentry, suggest the matching skill:

| Detected | Suggest skill |
| --- | --- |
| Go backend (`go.mod`) | [`go`](../go/index.md) |
| Python backend (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby backend (`Gemfile`) | [`ruby`](../ruby/index.md) |
| Node.js backend (Express, Fastify, etc.) | `@sentry/node` — see [docs.sentry.io/platforms/javascript/guides/express/](https://docs.sentry.io/platforms/javascript/guides/express/) |
| React / Next.js web | [`react`](../react/index.md) |
| Svelte / SvelteKit web | [`svelte`](../svelte/index.md) |

**Distributed tracing setup** — if the backend skill is added, configure
`tracePropagationTargets` in React Native to propagate trace context to your API:

```typescript
Sentry.init({
  tracePropagationTargets: [
    "localhost",
    /^https:\/\/api\.yourapp\.com/,
  ],
  // ...
});
```

This links mobile transactions to backend traces in the Sentry waterfall view.

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing in Sentry | Set `debug: true`, check Metro/Xcode console for SDK errors; verify DSN is correct |
| `pod install` fails | Run `cd ios && pod install --repo-update`; check CocoaPods version |
| iOS build fails with Sentry script | Verify the “Bundle React Native code and images” script was replaced (not appended to) |
| Android build fails after adding `sentry.gradle.kts` | Ensure `apply from` line is before the `android {}` block in `build.gradle`; use `sentry.gradle` for SDK <8.13.0 |
| Android Gradle 8+ compatibility issue | Use `sentry-android-gradle-plugin` ≥4.0.0; check `sentry.gradle` version in your SDK |
| Source maps not uploading | Verify `sentry.properties` has a valid `auth.token`; check build logs for `sentry-cli` output |
| Source maps not resolving in Sentry | Confirm `release` and `dist` in `Sentry.init()` match the uploaded bundle metadata |
| Hermes source maps not working | Hermes emits `.hbc.map` — the Gradle plugin handles this automatically; verify `sentry.gradle` is applied |
| Session replay not recording | Must use a native build (not Expo Go); confirm `mobileReplayIntegration()` is in `integrations` |
| Replay shows blank/black screens | Check that `maskAllText`/`maskAllImages` settings match your privacy requirements |
| Slow/frozen frames not tracked | Set `enableNativeFramesTracking: true` and confirm you’re on a native build (not Expo Go) |
| TTID / TTFD not appearing | Requires `enableTimeToInitialDisplay: true` in `reactNavigationIntegration()` on a native build |
| App crashes on startup after adding Sentry | Likely a native initialization error — check Xcode/Logcat logs; try `enableNative: false` to isolate |
| Expo SDK 49 or older | Use `sentry-expo` (legacy package); `@sentry/react-native` requires Expo SDK 50+ |
| `isRunningInExpoGo` import error | Import from `expo` package: `import { isRunningInExpoGo } from "expo"` |
| Node not found during Xcode build | Add `export NODE_BINARY=$(which node)` to the Xcode build phase, or symlink: `ln -s $(which node) /usr/local/bin/node` |
| Expo Go warning about native features | Use `isRunningInExpoGo()` guard: `enableNativeFramesTracking: !isRunningInExpoGo()` |
| `beforeSend` not firing for native crashes | Expected — `beforeSend` only intercepts JS-layer errors; native crashes bypass it |
| Android 15+ (16KB page size) crash | Upgrade to `@sentry/react-native` ≥6.3.0 |
| Too many transactions in dashboard | Lower `tracesSampleRate` to `0.1` or use `tracesSampler` to drop health checks |
| `SENTRY_AUTH_TOKEN` exposed in app bundle | `SENTRY_AUTH_TOKEN` is for build-time upload only — never pass it to `Sentry.init()` |
| EAS Build: Sentry auth token missing | Set `SENTRY_AUTH_TOKEN` as an EAS secret: `eas secret:create --name SENTRY_AUTH_TOKEN` |
