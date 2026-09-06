# Integration Reference — Sentry Android SDK

### Built-in (Auto-Enabled)

These integrations activate automatically when `SentryAndroid.init()` is called:

| Integration | What it does |
| --- | --- |
| `UncaughtExceptionHandlerIntegration` | Captures all uncaught Java/Kotlin exceptions |
| `AnrIntegration` | ANR detection via watchdog thread (5s) + ApplicationExitInfo (API 30+) |
| `NdkIntegration` | Native (C/C++) crash capture via `sentry-native` |
| `ActivityLifecycleIntegration` | Auto-instruments Activity create/resume/pause for TTID/TTFD |
| `AppStartMetrics` | Measures cold/warm/hot app start time |
| `NetworkBreadcrumbsIntegration` | Records connectivity changes as breadcrumbs |
| `SystemEventsBreadcrumbsIntegration` | Records battery, screen on/off, etc. |
| `AppLifecycleIntegration` | Records foreground/background transitions |
| `UserInteractionIntegration` | Breadcrumbs for taps, swipes, input events |
| `CurrentActivityIntegration` | Tracks active Activity for context |

### Optional Integrations

Add the artifact to your `dependencies {}` block (versions managed by BOM):

| Integration | Artifact | When to add |
| --- | --- | --- |
| **Timber** | `io.sentry:sentry-android-timber` | App uses Timber for logging |
| **Fragment** | `io.sentry:sentry-android-fragment` | App uses Jetpack Fragments (lifecycle tracing) |
| **Compose** | `io.sentry:sentry-compose-android` | App uses Jetpack Compose (navigation + masking) |
| **Navigation** | `io.sentry:sentry-android-navigation` | App uses Jetpack Navigation Component |
| **OkHttp** | `io.sentry:sentry-okhttp` | App uses OkHttp or Retrofit |
| **Room/SQLite** | `io.sentry:sentry-android-sqlite` | App uses Room or raw SQLite |
| **Apollo 3** | `io.sentry:sentry-apollo-3` | App uses Apollo GraphQL v3 |
| **Apollo 4** | `io.sentry:sentry-apollo-4` | App uses Apollo GraphQL v4 |
| **Kotlin Extensions** | `io.sentry:sentry-kotlin-extensions` | Kotlin coroutines context propagation |
| **Ktor Client** | `io.sentry:sentry-ktor-client` | App uses Ktor HTTP client |
| **LaunchDarkly** | `io.sentry:sentry-launchdarkly-android` | App uses LaunchDarkly — see [`feature-flags.md`](./feature-flags.md) |

### Gradle Plugin Bytecode Instrumentation

The plugin can inject instrumentation automatically (no source changes):

| Feature | Instruments | Enable via |
| --- | --- | --- |
| `DATABASE` | Room DAO, SupportSQLiteOpenHelper | `tracingInstrumentation.features` |
| `FILE_IO` | FileInputStream, FileOutputStream | `tracingInstrumentation.features` |
| `OKHTTP` | OkHttpClient.Builder automatically | `tracingInstrumentation.features` |
| `COMPOSE` | NavHostController auto-instrumentation | `tracingInstrumentation.features` |
| `LOGCAT` | `android.util.Log` capturing | `tracingInstrumentation.features` |
