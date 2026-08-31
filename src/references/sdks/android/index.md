# Sentry Android SDK

Opinionated wizard that scans your Android project and guides you through complete
Sentry setup — error monitoring, tracing, profiling, session replay, logging, and more.

> **Note:** SDK versions and APIs below reflect current Sentry docs at time of writing
> (`io.sentry:sentry-android:8.33.0`, Gradle plugin `6.1.0`). Always verify against
> [docs.sentry.io/platforms/android/](https://docs.sentry.io/platforms/android/) before
> implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect project structure and build system
ls build.gradle build.gradle.kts settings.gradle settings.gradle.kts 2>/dev/null

# Check AGP version and existing Sentry
grep -r '"com.android.application"' build.gradle* app/build.gradle* 2>/dev/null | head -3
grep -ri sentry build.gradle* app/build.gradle* 2>/dev/null | head -10

# Check app-level build file (Groovy vs KTS)
ls app/build.gradle app/build.gradle.kts 2>/dev/null

# Detect Gradle version catalog (libs.versions.toml) — modern AGP projects
ls gradle/libs.versions.toml 2>/dev/null

# Check for existing Sentry entries in the version catalog
grep -iE 'sentry|io\.sentry' gradle/libs.versions.toml 2>/dev/null | head -10

# Check if build files reference the catalog (alias/libs.* usage)
grep -E 'alias\(libs\.|libs\.[a-zA-Z]' build.gradle build.gradle.kts app/build.gradle app/build.gradle.kts 2>/dev/null | head -5

# Detect Kotlin vs Java
find app/src/main -name "*.kt" 2>/dev/null | head -3
find app/src/main -name "*.java" 2>/dev/null | head -3

# Check minSdk, targetSdk
grep -E 'minSdk|targetSdk|compileSdk|minSdkVersion|targetSdkVersion' app/build.gradle app/build.gradle.kts 2>/dev/null | head -6

# Detect Jetpack Compose
grep -E 'compose|androidx.compose' app/build.gradle app/build.gradle.kts 2>/dev/null | head -5

# Detect OkHttp (popular HTTP client — has dedicated integration)
grep -E 'okhttp|retrofit' app/build.gradle app/build.gradle.kts 2>/dev/null | head -3

# Detect Room or SQLite
grep -E 'androidx.room|androidx.sqlite' app/build.gradle app/build.gradle.kts 2>/dev/null | head -3

# Detect Timber (logging library)
grep -E 'timber' app/build.gradle app/build.gradle.kts 2>/dev/null | head -3

# Detect Jetpack Navigation
grep -E 'androidx.navigation' app/build.gradle app/build.gradle.kts 2>/dev/null | head -3

# Detect Apollo (GraphQL)
grep -E 'apollo' app/build.gradle app/build.gradle.kts 2>/dev/null | head -3

# Check existing Sentry initialization
grep -r "SentryAndroid.init\|io.sentry.Sentry" app/src/ 2>/dev/null | head -5

# Check Application class
find app/src/main -name "*.kt" -o -name "*.java" 2>/dev/null | xargs grep -l "Application()" 2>/dev/null | head -3

# Adjacent backend (for cross-linking)
ls ../backend ../server ../api 2>/dev/null
find .. -maxdepth 2 \( -name "go.mod" -o -name "requirements.txt" -o -name "Gemfile" \) 2>/dev/null | grep -v node_modules | head -5
```

**What to determine:**

| Question | Impact |
| --- | --- |
| `build.gradle.kts` present? | Use Kotlin DSL syntax in all examples |
| `gradle/libs.versions.toml` present? | Add Sentry to the version catalog; reference via `libs.*` in build files |
| Catalog already has `sentry` entries? | Reuse the existing version ref; don’t duplicate or hardcode versions |
| `minSdk < 26`? | Note Session Replay requires API 26+ — silent no-op below that |
| Compose detected? | Recommend `sentry-compose-android` and Compose-specific masking |
| OkHttp present? | Recommend `sentry-okhttp` interceptor or Gradle plugin bytecode auto-instrumentation |
| Room/SQLite present? | Recommend `sentry-android-sqlite` or plugin bytecode instrumentation |
| Timber present? | Recommend `sentry-android-timber` integration |
| Jetpack Navigation? | Recommend `sentry-android-navigation` for screen tracking |
| Already has `SentryAndroid.init()`? | Skip install, jump to feature config |
| Application subclass exists? | That’s where `SentryAndroid.init()` goes |

* * *

## Phase 2: Recommend

Present a concrete recommendation based on what you found.
Don’t ask open-ended questions — lead with a proposal:

**Recommended (core coverage — always set up these):**
- ✅ **Error Monitoring** — captures uncaught exceptions, ANRs, and native NDK crashes
  automatically
- ✅ **Tracing** — auto-instruments Activity lifecycle, app start, HTTP requests, and
  database queries
- ✅ **Session Replay** — records screen captures and user interactions for debugging
  (API 26+)

**Optional (enhanced observability):**
- ⚡ **Profiling** — continuous UI profiling (recommended) or transaction-based sampling
- ⚡ **Logging** — structured logs via `Sentry.logger()`, with optional Timber bridge
- ⚡ **User Feedback** — collect user-submitted bug reports from inside the app

**Recommendation logic:**

| Feature | Recommend when … |
| --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline for any Android app |
| Tracing | **Always for Android** — app start time, Activity lifecycle, network latency matter |
| Session Replay | User-facing production app on API 26+; visual debugging of user issues |
| Profiling | Performance-sensitive apps, startup time investigations, production perf analysis |
| Logging | App uses structured logging or you want log-to-trace correlation in Sentry |
| User Feedback | Beta or customer-facing app where you want user-submitted bug reports |

Propose: *“For your [Kotlin / Java] Android app (minSdk X), I recommend setting up Error
Monitoring + Tracing + Session Replay.
Want me to also add Profiling and Logging?”*

* * *

## Phase 3: Guide

### Determine Your Setup Path

| Project type | Recommended setup | Complexity |
| --- | --- | --- |
| New project, no existing Sentry | Gradle plugin (recommended) | Low — plugin handles most config |
| Existing project, no Sentry | Gradle plugin or manual init | Medium — add dependency + Application class |
| Manual full control | `SentryAndroid.init()` in Application | Medium — explicit config, most flexible |

### Option 1: Wizard (Recommended)

> **You need to run this yourself** — the wizard opens a browser for login and requires
> interactive input that the agent can’t handle.
> Copy-paste into your terminal:
> 
> ```
> npx @sentry/wizard@latest -i android
> ```
> 
> It handles login, org/project selection, Gradle plugin setup, dependency installation,
> DSN configuration, and ProGuard/R8 mapping upload.
> 
> **Once it finishes, come back and skip to [Verification](#verification).**

If the user skips the wizard, proceed with Option 2 (Manual Setup) below.

* * *

### Option 2: Manual Setup

#### Using a Gradle Version Catalog (`gradle/libs.versions.toml`)

If Phase 1 detected `gradle/libs.versions.toml`, add Sentry to the catalog **first**,
then reference it from your build files.
This keeps versions centralized and matches modern AGP project conventions.

**Step 1 — Add entries to `gradle/libs.versions.toml`**

```toml
[versions]
sentry = "8.33.0"
sentryGradlePlugin = "6.1.0"

[libraries]
sentry-android = { module = "io.sentry:sentry-android", version.ref = "sentry" }
sentry-bom = { module = "io.sentry:sentry-bom", version.ref = "sentry" }
# Optional integrations — add only the ones your project uses:
sentry-android-timber = { module = "io.sentry:sentry-android-timber" }
sentry-android-fragment = { module = "io.sentry:sentry-android-fragment" }
sentry-compose-android = { module = "io.sentry:sentry-compose-android" }
sentry-android-navigation = { module = "io.sentry:sentry-android-navigation" }
sentry-okhttp = { module = "io.sentry:sentry-okhttp" }
sentry-android-sqlite = { module = "io.sentry:sentry-android-sqlite" }
sentry-kotlin-extensions = { module = "io.sentry:sentry-kotlin-extensions" }

[plugins]
sentry-android-gradle = { id = "io.sentry.android.gradle", version.ref = "sentryGradlePlugin" }
```

> **Note:** Optional integration entries omit `version.ref` — their versions come from
> the BOM at resolution time.
> Only `sentry-bom` needs the version ref.
> If the catalog already defines a `sentry` version, reuse it instead of adding a
> duplicate entry.

**Step 2 — Reference the catalog from `build.gradle[.kts]`**

Project-level `build.gradle.kts`:
```kotlin
plugins {
    alias(libs.plugins.sentry.android.gradle) apply false
}
```

App-level `app/build.gradle.kts`:
```kotlin
plugins {
    id("com.android.application")
    alias(libs.plugins.sentry.android.gradle)
}

dependencies {
    implementation(platform(libs.sentry.bom))
    implementation(libs.sentry.android)
    // implementation(libs.sentry.okhttp)
    // implementation(libs.sentry.compose.android)
}
```

Groovy DSL (`app/build.gradle`) equivalent:
```groovy
plugins {
    id "com.android.application"
    alias libs.plugins.sentry.android.gradle
}

dependencies {
    implementation platform(libs.sentry.bom)
    implementation libs.sentry.android
}
```

Then continue with the `sentry {}` configuration block from Path A, Step 2 below.
The rest of the setup (Application class init, manifest registration, verification) is
identical.

* * *

#### Path A: Gradle Plugin (Recommended)

The Sentry Gradle plugin is the easiest setup path.
It:
- Uploads ProGuard/R8 mapping files automatically on release builds
- Injects source context into stack frames
- Optionally instruments OkHttp, Room/SQLite, File I/O, Compose navigation, and
  `android.util.Log` via bytecode transforms (zero source changes)

**Step 1 — Add the plugin to `build.gradle[.kts]` (project-level)**

Groovy DSL (`build.gradle`):
```groovy
plugins {
    id "io.sentry.android.gradle" version "6.1.0" apply false
}
```

Kotlin DSL (`build.gradle.kts`):
```kotlin
plugins {
    id("io.sentry.android.gradle") version "6.1.0" apply false
}
```

**Step 2 — Apply plugin + add dependencies in `app/build.gradle[.kts]`**

Groovy DSL:
```groovy
plugins {
    id "com.android.application"
    id "io.sentry.android.gradle"
}

android {
    // ...
}

dependencies {
    // Use BOM for consistent versions across sentry modules
    implementation platform("io.sentry:sentry-bom:8.33.0")
    implementation "io.sentry:sentry-android"

    // Optional integrations (add what's relevant):
    // implementation "io.sentry:sentry-android-timber"     // Timber bridge
    // implementation "io.sentry:sentry-android-fragment"   // Fragment lifecycle tracing
    // implementation "io.sentry:sentry-compose-android"    // Jetpack Compose support
    // implementation "io.sentry:sentry-android-navigation"  // Jetpack Navigation
    // implementation "io.sentry:sentry-okhttp"             // OkHttp interceptor
    // implementation "io.sentry:sentry-android-sqlite"     // Room/SQLite tracing
    // implementation "io.sentry:sentry-kotlin-extensions"  // Coroutine context propagation
}

sentry {
    org = "YOUR_ORG_SLUG"
    projectName = "YOUR_PROJECT_SLUG"
    authToken = System.getenv("SENTRY_AUTH_TOKEN")

    // Enable auto-instrumentation via bytecode transforms (no source changes needed)
    tracingInstrumentation {
        enabled = true
        features = [InstrumentationFeature.DATABASE, InstrumentationFeature.FILE_IO,
                    InstrumentationFeature.OKHTTP, InstrumentationFeature.COMPOSE]
    }

    // Upload ProGuard mapping and source context on release
    autoUploadProguardMapping = true
    includeSourceContext = true
}
```

Kotlin DSL (`app/build.gradle.kts`):
```kotlin
plugins {
    id("com.android.application")
    id("io.sentry.android.gradle")
}

dependencies {
    implementation(platform("io.sentry:sentry-bom:8.33.0"))
    implementation("io.sentry:sentry-android")

    // Optional integrations:
    // implementation("io.sentry:sentry-android-timber")
    // implementation("io.sentry:sentry-android-fragment")
    // implementation("io.sentry:sentry-compose-android")
    // implementation("io.sentry:sentry-android-navigation")
    // implementation("io.sentry:sentry-okhttp")
    // implementation("io.sentry:sentry-android-sqlite")
    // implementation("io.sentry:sentry-kotlin-extensions")
}

sentry {
    org = "YOUR_ORG_SLUG"
    projectName = "YOUR_PROJECT_SLUG"
    authToken = System.getenv("SENTRY_AUTH_TOKEN")

    tracingInstrumentation {
        enabled = true
        features = setOf(
            InstrumentationFeature.DATABASE,
            InstrumentationFeature.FILE_IO,
            InstrumentationFeature.OKHTTP,
            InstrumentationFeature.COMPOSE,
        )
    }

    autoUploadProguardMapping = true
    includeSourceContext = true
}
```

**Step 3 — Initialize Sentry in your Application class**

If you don’t have an Application subclass, create one:

```kotlin
// MyApplication.kt
import android.app.Application
import io.sentry.SentryLevel
import io.sentry.android.core.SentryAndroid
import io.sentry.android.replay.SentryReplayOptions

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        SentryAndroid.init(this) { options ->
            options.dsn = "YOUR_SENTRY_DSN"

            // Tracing — lower to 0.1–0.2 in high-traffic production
            options.tracesSampleRate = 1.0

            // Profiling — use continuous UI profiling (recommended, SDK ≥ 8.7.0)
            options.profileSessionSampleRate = 1.0

            // Session Replay (API 26+ only; silent no-op below API 26)
            options.sessionReplay.sessionSampleRate = 0.1    // 10% of all sessions
            options.sessionReplay.onErrorSampleRate = 1.0    // 100% on error

            // Structured logging
            options.logs.isEnabled = true

            // Environment
            options.environment = BuildConfig.BUILD_TYPE
        }
    }
}
```

Java equivalent:
```java
// MyApplication.java
import android.app.Application;
import io.sentry.android.core.SentryAndroid;

public class MyApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();

        SentryAndroid.init(this, options -> {
            options.setDsn("YOUR_SENTRY_DSN");
            options.setTracesSampleRate(1.0);
            options.setProfileSessionSampleRate(1.0);
            options.getSessionReplay().setSessionSampleRate(0.1);
            options.getSessionReplay().setOnErrorSampleRate(1.0);
            options.getLogs().setEnabled(true);
            options.setEnvironment(BuildConfig.BUILD_TYPE);
        });
    }
}
```

**Step 4 — Register Application in `AndroidManifest.xml`**

```xml
<application
    android:name=".MyApplication"
    ... >
```

* * *

#### Path B: Manual Setup (No Gradle Plugin)

Use this if you can’t use the Gradle plugin (e.g., non-standard build setups).

**Step 1 — Add dependency in `app/build.gradle[.kts]`**

```kotlin
dependencies {
    implementation(platform("io.sentry:sentry-bom:8.33.0"))
    implementation("io.sentry:sentry-android")
}
```

**Step 2 — Initialize in Application class** (same as Path A, Step 3)

**Step 3 — Configure ProGuard/R8 manually**

The Sentry SDK ships a ProGuard rules file automatically.
For manual mapping upload, install `sentry-cli` and add to your CI:

```bash
sentry-cli releases files "my-app@1.0.0+42" upload-proguard \
  --org YOUR_ORG --project YOUR_PROJECT \
  app/build/outputs/mapping/release/mapping.txt
```

* * *

### Quick Reference: Full-Featured `SentryAndroid.init()`

```kotlin
SentryAndroid.init(this) { options ->
    options.dsn = "YOUR_SENTRY_DSN"

    // Environment and release
    options.environment = BuildConfig.BUILD_TYPE     // "debug", "release", etc.
    options.release = "${BuildConfig.APPLICATION_ID}@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"

    // Tracing — sample 100% in dev, lower to 10–20% in production
    options.tracesSampleRate = 1.0

    // Continuous UI profiling (recommended over transaction-based)
    options.profileSessionSampleRate = 1.0

    // Session Replay (API 26+; silent no-op on API 21–25)
    options.sessionReplay.sessionSampleRate = 0.1
    options.sessionReplay.onErrorSampleRate = 1.0
    options.sessionReplay.maskAllText = true         // mask text for privacy
    options.sessionReplay.maskAllImages = true       // mask images for privacy

    // Structured logging
    options.logs.isEnabled = true

    // Error enrichment
    options.isAttachScreenshot = true                // capture screenshot on error
    options.isAttachViewHierarchy = true             // attach view hierarchy JSON

    // ANR detection (5s default; watchdog + ApplicationExitInfo API 30+)
    options.isAnrEnabled = true

    // NDK native crash handling (enabled by default)
    options.isEnableNdk = true

    // Send PII: IP address, user data
    options.sendDefaultPii = true

    // Trace propagation (backend distributed tracing)
    options.tracePropagationTargets = listOf("api.yourapp.com", ".*\\.yourapp\\.com")

    // Verbose logging — disable in production
    options.isDebug = BuildConfig.DEBUG
}
```

* * *

### For Each Agreed Feature

Walk through features one at a time.
Load the reference file for each, follow its steps, then verify before moving on:

| Feature | Reference | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing & Performance | `./tracing.md` | Always for Android (Activity lifecycle, network) |
| Profiling | `./profiling.md` | Performance-sensitive production apps |
| Session Replay | `./session-replay.md` | User-facing apps (API 26+) |
| Logging | `./logging.md` | Structured logging / log-to-trace correlation |
| Metrics | `./metrics.md` | Custom metric tracking (SDK ≥ 8.30.0) |
| Crons | `./crons.md` | Scheduled jobs, WorkManager check-ins |
| Integration Reference | `./integrations.md` | Built-in, optional, and Gradle bytecode integrations |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Core `SentryOptions` (via `SentryAndroid.init`)

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `String` | — | **Required.** Project DSN; SDK silently disabled if empty |
| `environment` | `String` | — | e.g., `"production"`, `"staging"`. Env: `SENTRY_ENVIRONMENT` |
| `release` | `String` | — | App version, e.g., `"my-app@1.0.0+42"`. Env: `SENTRY_RELEASE` |
| `dist` | `String` | — | Build variant / distribution identifier |
| `sendDefaultPii` | `Boolean` | `false` | Include PII: IP address, user data |
| `sampleRate` | `Double` | `1.0` | Error event sampling (0.0–1.0) |
| `maxBreadcrumbs` | `Int` | `100` | Max breadcrumbs per event |
| `isAttachStacktrace` | `Boolean` | `true` | Auto-attach stack traces to message events |
| `isAttachScreenshot` | `Boolean` | `false` | Capture screenshot on error |
| `isAttachViewHierarchy` | `Boolean` | `false` | Attach JSON view hierarchy as attachment |
| `isDebug` | `Boolean` | `false` | Verbose SDK output. **Never use in production** |
| `isEnabled` | `Boolean` | `true` | Disable SDK entirely (e.g., for testing) |
| `beforeSend` | `SentryOptions.BeforeSendCallback` | — | Modify or drop error events before sending |
| `beforeBreadcrumb` | `SentryOptions.BeforeBreadcrumbCallback` | — | Filter breadcrumbs before storage |

### Tracing Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `tracesSampleRate` | `Double` | `0.0` | Transaction sample rate (0–1). Use `1.0` in dev |
| `tracesSampler` | `TracesSamplerCallback` | — | Per-transaction sampling; overrides `tracesSampleRate` |
| `tracePropagationTargets` | `List<String>` | `[".*"]` | Hosts/URLs to receive `sentry-trace` and `baggage` headers |
| `isEnableAutoActivityLifecycleTracing` | `Boolean` | `true` | Auto-instrument Activity lifecycle |
| `isEnableTimeToFullDisplayTracing` | `Boolean` | `false` | TTFD spans (requires `Sentry.reportFullyDisplayed()`) |
| `isEnableUserInteractionTracing` | `Boolean` | `false` | Auto-instrument user gestures as transactions |

### Profiling Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `profileSessionSampleRate` | `Double` | `0.0` | Continuous profiling sample rate (SDK ≥ 8.7.0, API 22+) |
| `profilesSampleRate` | `Double` | `0.0` | Legacy transaction profiling rate (mutually exclusive with continuous) |
| `isProfilingStartOnAppStart` | `Boolean` | `false` | Auto-start profiling session on app launch |

### ANR Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `isAnrEnabled` | `Boolean` | `true` | Enable ANR watchdog thread |
| `anrTimeoutIntervalMillis` | `Long` | `5000` | Milliseconds before reporting ANR |
| `isAnrReportInDebug` | `Boolean` | `false` | Report ANRs in debug builds (noisy in debugger) |

### NDK Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `isEnableNdk` | `Boolean` | `true` | Enable native crash capture via sentry-native |
| `isEnableScopeSync` | `Boolean` | `true` | Sync Java scope (user, tags) to NDK layer |
| `isEnableTombstoneFetchJob` | `Boolean` | `true` | Fetch NDK tombstone files for enrichment |

### Session Replay Options (`options.sessionReplay`)

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `sessionSampleRate` | `Double` | `0.0` | Fraction of all sessions to record |
| `onErrorSampleRate` | `Double` | `0.0` | Fraction of error sessions to record |
| `maskAllText` | `Boolean` | `true` | Mask all text in replays |
| `maskAllImages` | `Boolean` | `true` | Mask all images in replays |
| `quality` | `SentryReplayQuality` | `MEDIUM` | Video quality: `LOW`, `MEDIUM`, `HIGH` |

### Logging Options (`options.logs`)

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `isEnabled` | `Boolean` | `false` | Enable `Sentry.logger()` API (SDK ≥ 8.12.0) |
| `setBeforeSend` | `BeforeSendLogCallback` | — | Filter/modify log entries before sending |

### Environment Variables

| Variable | Purpose | Notes |
| --- | --- | --- |
| `SENTRY_DSN` | Data Source Name | Set in CI; SDK reads from environment at init |
| `SENTRY_AUTH_TOKEN` | Upload ProGuard mappings and source context | **Never commit — use CI/CD secrets** |
| `SENTRY_ORG` | Organization slug | Used by Gradle plugin `sentry.org` |
| `SENTRY_PROJECT` | Project slug | Used by Gradle plugin `sentry.projectName` |
| `SENTRY_RELEASE` | Release identifier | Falls back from `options.release` |
| `SENTRY_ENVIRONMENT` | Environment name | Falls back from `options.environment` |

You can also configure DSN and many options via `AndroidManifest.xml` meta-data:

```xml
<application>
    <meta-data android:name="io.sentry.dsn" android:value="YOUR_DSN" />
    <meta-data android:name="io.sentry.traces-sample-rate" android:value="1.0" />
    <meta-data android:name="io.sentry.environment" android:value="production" />
    <meta-data android:name="io.sentry.anr.enable" android:value="true" />
    <meta-data android:name="io.sentry.attach-screenshot" android:value="true" />
    <meta-data android:name="io.sentry.attach-view-hierarchy" android:value="true" />
</application>
```

> ⚠️ Manifest meta-data is a convenient alternative but does **not** support the full
> option set. For complex configuration (session replay, profiling, hooks), use
> `SentryAndroid.init()`.

* * *

## Verification

After setup, verify Sentry is receiving events:

**Test error capture:**
```kotlin
// In an Activity or Fragment
try {
    throw RuntimeException("Sentry Android SDK test")
} catch (e: Exception) {
    Sentry.captureException(e)
}
```

**Test tracing:**
```kotlin
val transaction = Sentry.startTransaction("test-task", "task")
val span = transaction.startChild("test-span", "description")
span.finish()
transaction.finish()
```

**Test structured logging (SDK ≥ 8.12.0):**
```kotlin
Sentry.logger().info("Sentry logging test")
Sentry.logger().error("Error log test", Exception("test error"))
```

**Check the Sentry dashboard:**
- **Issues** → your test exception should appear within seconds
- **Traces** → look for `test-task` transaction with child span
- **Replays** → session recording visible after app interaction (requires API 26+)
- **Logs** → structured log entries visible under Logs tab

If nothing appears:
1. Set `options.isDebug = true` — SDK logs to Logcat
2. Verify DSN is correct and matches your Sentry project
3. Check that your `Application` class is registered in `AndroidManifest.xml` as
   `android:name`
4. Confirm the device/emulator has internet connectivity
5. For NDK crashes, ensure `isEnableNdk = true` (default) and build with NDK support

* * *

## Phase 4: Cross-Link

After completing Android setup, check for a backend or web frontend missing Sentry
coverage:

```bash
# Adjacent backend directories
ls ../backend ../server ../api 2>/dev/null
cat ../go.mod 2>/dev/null | head -3
cat ../requirements.txt ../pyproject.toml 2>/dev/null | head -5
cat ../Gemfile 2>/dev/null | head -3
ls ../backend/package.json ../server/package.json 2>/dev/null

# iOS counterpart app
ls ../ios ../YourApp-iOS 2>/dev/null
find .. -maxdepth 3 -name "*.xcodeproj" 2>/dev/null | head -3
```

If a backend or related platform exists without Sentry, suggest the matching skill:

| Detected | Suggest skill |
| --- | --- |
| Go backend (`go.mod`) | [`go`](../go/index.md) |
| Python backend (`requirements.txt`, `pyproject.toml`) | [`python`](../python/index.md) |
| Ruby backend (`Gemfile`) | [`ruby`](../ruby/index.md) |
| Node.js backend | `@sentry/node` — see [docs.sentry.io/platforms/javascript/guides/express/](https://docs.sentry.io/platforms/javascript/guides/express/) |
| iOS app (`.xcodeproj`) | [`cocoa`](../cocoa/index.md) |
| React Native (`package.json` with `react-native`) | [`react-native`](../react-native/index.md) |
| React / Next.js web | [`react`](../react/index.md) or [`nextjs`](../nextjs/index.md) |

**Distributed tracing setup** — if the backend skill is added, configure
`tracePropagationTargets` in Android to propagate trace context to your API:

```kotlin
options.tracePropagationTargets = listOf(
    "api.yourapp.com",
    ".*\\.yourapp\\.com"
)
```

This links mobile transactions to backend traces in the Sentry waterfall view.

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing in Sentry | Set `isDebug = true`, check Logcat for SDK errors; verify DSN is correct and matches your project |
| `SentryAndroid.init()` not called | Confirm `android:name=".MyApplication"` is set in `AndroidManifest.xml`; Application class not abstract |
| Gradle plugin not found | Add the plugin to project-level `build.gradle.kts` first, then `apply false`; verify version `6.1.0` |
| ProGuard mapping not uploading | Set `SENTRY_AUTH_TOKEN` env var; ensure `autoUploadProguardMapping = true` in `sentry {}` block |
| NDK crashes not captured | Verify `isEnableNdk = true` (default); ensure project has NDK configured in `android.ndkVersion` |
| ANR reported in debugger | Set `isAnrReportInDebug = false` (default); ANR watchdog fires when debugger pauses threads |
| Session replay not recording | Requires API 26+; verify `sessionSampleRate > 0` or `onErrorSampleRate > 0`; check Logcat for replay errors |
| Session replay shows blank screen | PixelCopy (default) requires hardware acceleration; try `SentryReplayOptions.screenshotQuality = CANVAS` |
| Replay masking misaligned | Views with `translationX/Y` or `clipToPadding=false` can offset masks; report to [github.com/getsentry/sentry-java](https://github.com/getsentry/sentry-java) |
| `beforeSend` not firing | `beforeSend` only intercepts managed (Java/Kotlin) events; NDK native crashes bypass it |
| OkHttp spans not appearing | Add `SentryOkHttpInterceptor` to your `OkHttpClient`, or use Gradle plugin `OKHTTP` bytecode instrumentation |
| Spans not attached to transaction | Ensure `TransactionOptions().setBindToScope(true)` when starting transaction; child spans look for scope root |
| Tracing not recording | Verify `tracesSampleRate > 0`; Activity instrumentation requires `isEnableAutoActivityLifecycleTracing = true` (default) |
| Continuous profiling not working | SDK ≥ 8.7.0 required; API 22+ required; set `profileSessionSampleRate > 0`; don’t also set `profilesSampleRate` |
| Both profiling modes set | `profilesSampleRate` and `profileSessionSampleRate` are mutually exclusive — use only one |
| TTFD spans missing | Set `isEnableTimeToFullDisplayTracing = true` and call `Sentry.reportFullyDisplayed()` when screen is ready |
| Kotlin coroutine scope lost | Add `sentry-kotlin-extensions` dependency; use `Sentry.cloneMainContext()` to propagate trace context |
| Release build stack traces unreadable | ProGuard mapping not uploaded; confirm Gradle plugin `autoUploadProguardMapping = true` and auth token set |
| Source context not showing in Sentry | Enable `includeSourceContext = true` in `sentry {}` block (Gradle plugin required) |
| BOM version conflict | Use `implementation(platform("io.sentry:sentry-bom:8.33.0"))` and omit versions from all other `io.sentry:*` entries |
| Version catalog alias unresolved | After editing `gradle/libs.versions.toml`, sync Gradle; alias names use `-` in TOML and `.` in build files (e.g., `sentry-android` → `libs.sentry.android`) |
| Duplicate Sentry version in catalog | Reuse the existing `[versions] sentry = "..."` entry; don’t add a second key, and don’t hardcode the version in `build.gradle` when the catalog is in use |
| `SENTRY_AUTH_TOKEN` exposed | Auth token is build-time only — never pass it to `SentryAndroid.init()` or embed in the APK |
