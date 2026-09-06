---
name: sentry-dotnet-sdk
description: Full Sentry SDK setup for .NET. Use when asked to "add Sentry to .NET", "install Sentry for C#", or configure error monitoring, tracing, profiling, logging, or crons for ASP.NET Core, MAUI, WPF, WinForms, Blazor, Azure Functions, or any other .NET application.
license: Apache-2.0
category: sdk-setup
parent: sentry-sdk-setup
disable-model-invocation: true
---

> [All Skills](../../SKILL_TREE.md) > [SDK Setup](../sentry-sdk-setup/SKILL.md) > .NET SDK

# Sentry .NET SDK

Opinionated wizard that scans your .NET project and guides you through complete Sentry setup: error monitoring, distributed tracing, profiling, structured logging, and cron monitoring across all major .NET frameworks.

## Invoke This Skill When

- User asks to "add Sentry to .NET", "set up Sentry in C#", or "install Sentry for ASP.NET Core"
- User wants error monitoring, tracing, profiling, logging, or crons for a .NET app
- User mentions `SentrySdk.Init`, `UseSentry`, `Sentry.AspNetCore`, or `Sentry.Maui`
- User wants to capture unhandled exceptions in WPF, WinForms, MAUI, or Azure Functions
- User asks about `SentryOptions`, `BeforeSend`, `TracesSampleRate`, or symbol upload

> **Note:** SDK version and APIs below reflect `Sentry` NuGet packages ≥6.1.0 (OTLP export requires ≥6.5.0).
> Always verify against [docs.sentry.io/platforms/dotnet/](https://docs.sentry.io/platforms/dotnet/) before implementing.

---

## Phase 1: Detect

Run these commands to understand the project before making any recommendations:

```bash
# Detect framework type — find all .csproj files
find . -name "*.csproj" | head -20

# Detect framework targets
grep -r "TargetFramework\|Project Sdk" --include="*.csproj" .

# Check for existing Sentry packages
grep -r "Sentry" --include="*.csproj" . | grep "PackageReference"

# Check startup files
ls Program.cs src/Program.cs App.xaml.cs MauiProgram.cs 2>/dev/null

# Check for appsettings
ls appsettings.json src/appsettings.json 2>/dev/null

# Check for logging libraries
grep -r "Serilog\|NLog\|log4net" --include="*.csproj" .

# Check for companion frontend
ls ../frontend ../client ../web 2>/dev/null
cat ../package.json 2>/dev/null | grep -E '"next"|"react"|"vue"' | head -3
```

**What to determine:**

| Question | Impact |
|----------|--------|
| Framework type? | Determines correct package and init pattern |
| .NET version? | .NET 8+ recommended; .NET Framework 4.6.2+ supported |
| Sentry already installed? | Skip install, go to feature config |
| Logging library (Serilog, NLog)? | Recommend matching Sentry sink/target |
| Async/hosted app (ASP.NET Core)? | `UseSentry()` on `WebHost`; no `IsGlobalModeEnabled` needed |
| Desktop app (WPF, WinForms, WinUI)? | Must set `IsGlobalModeEnabled = true` |
| Serverless (Azure Functions, Lambda)? | Must set `FlushOnCompletedRequest = true` |
| Frontend directory found? | Trigger Phase 4 cross-link |

**Framework → Package mapping:**

| Detected | Package to install |
|----------|--------------------|
| `Sdk="Microsoft.NET.Sdk.Web"` (ASP.NET Core) | `Sentry.AspNetCore` |
| `App.xaml.cs` with `Application` base | `Sentry` (WPF) |
| `[STAThread]` in `Program.cs` | `Sentry` (WinForms) |
| `MauiProgram.cs` | `Sentry.Maui` |
| `WebAssemblyHostBuilder` | `Sentry.AspNetCore.Blazor.WebAssembly` |
| `FunctionsStartup` | `Sentry.Extensions.Logging` + `Sentry.OpenTelemetry` |
| `HttpApplication` / `Global.asax` | `Sentry.AspNet` |
| Generic host / Worker Service | `Sentry.Extensions.Logging` |

---

## Phase 2: Recommend

Present a concrete recommendation based on what you found. Lead with a proposal — don't ask open-ended questions.

**Recommended (core coverage):**
- ✅ **Error Monitoring** — always; captures unhandled exceptions, structured captures, scope enrichment
- ✅ **Tracing** — always for ASP.NET Core and hosted apps; auto-instruments HTTP requests and EF Core queries
- ✅ **Logging** — recommended for all apps; routes ILogger / Serilog / NLog entries to Sentry as breadcrumbs and events

**Optional (enhanced observability):**
- ⚡ **Profiling** — CPU profiling; recommend for performance-critical services running on .NET 6+
- ⚡ **Metrics** — counters, gauges, distributions linked to traces; recommend for apps that need custom business metrics
- ⚡ **Crons** — detect missed/failed scheduled jobs; recommend when Hangfire, Quartz.NET, or scheduled endpoints detected

**Recommendation logic:**

| Feature | Recommend when... |
|---------|------------------|
| Error Monitoring | **Always** — non-negotiable baseline |
| Tracing | **Always for ASP.NET Core** — request traces, EF Core spans, HttpClient spans are high-value |
| Logging | App uses `ILogger<T>`, Serilog, NLog, or log4net |
| Profiling | Performance-critical service on .NET 6+ |
| Metrics | App needs custom business metrics (request counts, queue depths, response times) |
| Crons | App uses Hangfire, Quartz.NET, or scheduled Azure Functions |

Propose: *"I recommend setting up Error Monitoring + Tracing + Logging. Want me to also add Profiling or Crons?"*

---

## Phase 3: Guide

### Option 1: Wizard (Recommended)

> **You need to run this yourself** — the wizard opens a browser for login and requires interactive input that the agent can't handle. Copy-paste into your terminal:
>
> ```
> npx @sentry/wizard@latest -i dotnet
> ```
>
> It handles login, org/project selection, DSN configuration, and MSBuild symbol upload setup for readable stack traces in production.
>
> **Once it finishes, come back and skip to [Verification](#verification).**

If the user skips the wizard, proceed with Option 2 (Manual Setup) below.

---

### Option 2: Manual Setup

#### Install the right package

```bash
# ASP.NET Core
dotnet add package Sentry.AspNetCore -v 6.1.0

# WPF or WinForms or Console
dotnet add package Sentry -v 6.1.0

# .NET MAUI
dotnet add package Sentry.Maui -v 6.1.0

# Blazor WebAssembly
dotnet add package Sentry.AspNetCore.Blazor.WebAssembly -v 6.1.0

# Azure Functions (Isolated Worker)
dotnet add package Sentry.Extensions.Logging -v 6.1.0
dotnet add package Sentry.OpenTelemetry -v 6.1.0

# Classic ASP.NET (System.Web / .NET Framework)
dotnet add package Sentry.AspNet -v 6.1.0
```

---

#### ASP.NET Core — `Program.cs`

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.WebHost.UseSentry(options =>
{
    options.Dsn = Environment.GetEnvironmentVariable("SENTRY_DSN")
                  ?? "___YOUR_DSN___";
    options.Debug = true;                         // disable in production
    options.SendDefaultPii = true;                // captures user IP, name, email
    options.MaxRequestBodySize = RequestSize.Always;
    options.MinimumBreadcrumbLevel = LogLevel.Debug;
    options.MinimumEventLevel = LogLevel.Warning;
    options.TracesSampleRate = 1.0;               // tune to 0.1–0.2 in production
    options.SetBeforeSend((@event, hint) =>
    {
        @event.ServerName = null;                 // scrub hostname from events
        return @event;
    });
});

var app = builder.Build();
app.Run();
```

**`appsettings.json` (alternative configuration):**

```json
{
  "Sentry": {
    "Dsn": "___YOUR_DSN___",
    "SendDefaultPii": true,
    "MaxRequestBodySize": "Always",
    "MinimumBreadcrumbLevel": "Debug",
    "MinimumEventLevel": "Warning",
    "AttachStacktrace": true,
    "Debug": true,
    "TracesSampleRate": 1.0,
    "Environment": "production",
    "Release": "my-app@1.0.0"
  }
}
```

**Environment variables (double underscore as separator):**

```bash
export Sentry__Dsn="https://examplePublicKey@o0.ingest.sentry.io/0"
export Sentry__TracesSampleRate="0.1"
export Sentry__Environment="staging"
```

---

#### WPF — `App.xaml.cs`

> ⚠️ **Critical:** Initialize in the **constructor**, NOT in `OnStartup()`. The constructor fires earlier, catching more failure modes.

```csharp
using System.Windows;
using Sentry;

public partial class App : Application
{
    public App()
    {
        SentrySdk.Init(options =>
        {
            options.Dsn = "___YOUR_DSN___";
            options.Debug = true;
            options.SendDefaultPii = true;
            options.TracesSampleRate = 1.0;
            options.IsGlobalModeEnabled = true;   // required for all desktop apps
        });

        // Capture WPF UI-thread exceptions before WPF's crash dialog appears
        DispatcherUnhandledException += App_DispatcherUnhandledException;
    }

    private void App_DispatcherUnhandledException(
        object sender,
        System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
    {
        SentrySdk.CaptureException(e.Exception);
        // Set e.Handled = true to prevent crash dialog and keep app running
    }
}
```

---

#### WinForms — `Program.cs`

```csharp
using System;
using System.Windows.Forms;
using Sentry;

static class Program
{
    [STAThread]
    static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // Required: allows Sentry to see unhandled WinForms exceptions
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);

        using (SentrySdk.Init(new SentryOptions
        {
            Dsn = "___YOUR_DSN___",
            Debug = true,
            TracesSampleRate = 1.0,
            IsGlobalModeEnabled = true,           // required for desktop apps
        }))
        {
            Application.Run(new MainForm());
        } // Disposing flushes all pending events
    }
}
```

---

#### .NET MAUI — `MauiProgram.cs`

```csharp
public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();
        builder
            .UseMauiApp<App>()
            .UseSentry(options =>
            {
                options.Dsn = "___YOUR_DSN___";
                options.Debug = true;
                options.SendDefaultPii = true;
                options.TracesSampleRate = 1.0;
                // MAUI-specific: opt-in breadcrumbs (off by default — PII risk)
                options.IncludeTextInBreadcrumbs = false;
                options.IncludeTitleInBreadcrumbs = false;
                options.IncludeBackgroundingStateInBreadcrumbs = false;
            });

        return builder.Build();
    }
}
```

---

#### Blazor WebAssembly — `Program.cs`

```csharp
var builder = WebAssemblyHostBuilder.CreateDefault(args);

builder.UseSentry(options =>
{
    options.Dsn = "___YOUR_DSN___";
    options.Debug = true;
    options.SendDefaultPii = true;
    options.TracesSampleRate = 0.1;
});

// Hook logging pipeline without re-initializing the SDK
builder.Logging.AddSentry(o => o.InitializeSdk = false);

await builder.Build().RunAsync();
```

---

#### Azure Functions (Isolated Worker) — `Program.cs`

> **Recommended:** Install `Sentry.OpenTelemetry.Exporter` (≥6.5.0) for OTLP export. Alternatively, use `Sentry.OpenTelemetry` for the bridge pattern.

```csharp
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Trace;

// Package: Sentry.OpenTelemetry.Exporter
var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureLogging(logging =>
    {
        logging.AddSentry(options =>
        {
            options.Dsn = "___YOUR_DSN___";
            options.Debug = true;
            options.TracesSampleRate = 1.0;
            options.UseOtlp(); // send OTel spans via OTLP (requires 6.5.0+)
        });
    })
    .ConfigureServices(services =>
    {
        services.AddOpenTelemetry().WithTracing(builder =>
        {
            builder
                .AddHttpClientInstrumentation()
                .AddSentryOtlpExporter("___YOUR_DSN___"); // route spans to Sentry OTLP endpoint
        });
    })
    .Build();

await host.RunAsync();
```

---

#### AWS Lambda — `LambdaEntryPoint.cs`

```csharp
public class LambdaEntryPoint : APIGatewayProxyFunction
{
    protected override void Init(IWebHostBuilder builder)
    {
        builder
            .UseSentry(options =>
            {
                options.Dsn = "___YOUR_DSN___";
                options.TracesSampleRate = 1.0;
                options.FlushOnCompletedRequest = true; // REQUIRED for Lambda
            })
            .UseStartup<Startup>();
    }
}
```

---

#### Classic ASP.NET — `Global.asax.cs`

```csharp
public class MvcApplication : HttpApplication
{
    private IDisposable _sentry;

    protected void Application_Start()
    {
        _sentry = SentrySdk.Init(options =>
        {
            options.Dsn = "___YOUR_DSN___";
            options.TracesSampleRate = 1.0;
            options.AddEntityFramework(); // EF6 query breadcrumbs
            options.AddAspNet();          // Classic ASP.NET integration
        });
    }

    protected void Application_Error() => Server.CaptureLastError();

    protected void Application_BeginRequest() => Context.StartSentryTransaction();
    protected void Application_EndRequest() => Context.FinishSentryTransaction();

    protected void Application_End() => _sentry?.Dispose();
}
```

---

### Symbol Upload (Readable Stack Traces)

Without debug symbols, stack traces show only method names — no file names or line numbers. The SDK uploads PDB files (and optionally sources) via MSBuild properties on Release builds:

```xml
<PropertyGroup Condition="'$(Configuration)' == 'Release'">
  <SentryOrg>___ORG_SLUG___</SentryOrg>
  <SentryProject>___PROJECT_SLUG___</SentryProject>
  <SentryUploadSymbols>true</SentryUploadSymbols>
  <SentryUploadSources>true</SentryUploadSources>
  <SentryCreateRelease>true</SentryCreateRelease>
  <SentrySetCommits>true</SentrySetCommits>
</PropertyGroup>
```

Upload needs a `SENTRY_AUTH_TOKEN` set in CI (a secret). For creating the token and the CI wiring, see [`sentry-source-maps`](../sentry-source-maps/SKILL.md). The `SentryCreateRelease` / `SentrySetCommits` properties also create a release with suspect commits — see [`sentry-releases`](../sentry-releases/SKILL.md).

---

### For Each Agreed Feature

Load the corresponding reference file and follow its steps:

| Feature | Reference file | Load when... |
|---------|---------------|-------------|
| Error Monitoring | `references/error-monitoring.md` | Always — `CaptureException`, scopes, enrichment, filtering |
| Tracing | `references/tracing.md` | Server apps, distributed tracing, EF Core spans, custom instrumentation |
| Profiling | `references/profiling.md` | Performance-critical apps on .NET 6+ |
| Logging | `references/logging.md` | `ILogger<T>`, Serilog, NLog, log4net integration |
| Metrics | `references/metrics.md` | Custom counters, gauges, distributions; `EmitCounter`, `EmitGauge`, `EmitDistribution` |
| Crons | `references/crons.md` | Hangfire, Quartz.NET, or scheduled function monitoring |

For each feature: read the reference file, follow its steps exactly, and verify before moving on.

---

## Configuration Reference

### Core `SentryOptions`

| Option | Type | Default | Env Var | Notes |
|--------|------|---------|---------|-------|
| `Dsn` | `string` | — | `SENTRY_DSN` | Required. SDK disabled if unset. |
| `Debug` | `bool` | `false` | — | SDK diagnostic output. Disable in production. |
| `DiagnosticLevel` | `SentryLevel` | `Debug` | — | `Debug`, `Info`, `Warning`, `Error`, `Fatal` |
| `Release` | `string` | auto | `SENTRY_RELEASE` | Auto-detected from assembly version + git SHA |
| `Environment` | `string` | `"production"` | `SENTRY_ENVIRONMENT` | `"debug"` when debugger attached |
| `Dist` | `string` | — | — | Build variant. Max 64 chars. |
| `SampleRate` | `float` | `1.0` | — | Error event sampling rate 0.0–1.0 |
| `TracesSampleRate` | `double` | `0.0` | — | Transaction sampling. Must be `> 0` to enable. |
| `TracesSampler` | `Func<SamplingContext, double>` | — | — | Per-transaction dynamic sampler; overrides `TracesSampleRate` |
| `ProfilesSampleRate` | `double` | `0.0` | — | Fraction of traced transactions to profile. Requires `Sentry.Profiling`. |
| `SendDefaultPii` | `bool` | `false` | — | Include user IP, name, email |
| `AttachStacktrace` | `bool` | `true` | — | Attach stack trace to all messages |
| `MaxBreadcrumbs` | `int` | `100` | — | Max breadcrumbs stored per event |
| `IsGlobalModeEnabled` | `bool` | `false`* | — | *Auto-`true` for MAUI, Blazor WASM. **Must** be `true` for WPF, WinForms, Console. |
| `AutoSessionTracking` | `bool` | `false`* | — | *Auto-`true` for MAUI. Enable for Release Health. |
| `CaptureFailedRequests` | `bool` | `true` | — | Auto-capture HTTP client errors |
| `CacheDirectoryPath` | `string` | — | — | Offline event caching directory |
| `ShutdownTimeout` | `TimeSpan` | — | — | Max wait for event flush on shutdown |
| `HttpProxy` | `string` | — | — | Proxy URL for Sentry requests |
| `EnableBackpressureHandling` | `bool` | `true` | — | Auto-reduce sample rates on delivery failures |
| `TraceIgnoreStatusCodes` | `IList<HttpStatusCodeRange>` | `[]` | — | Drop transactions whose HTTP response status matches any range; e.g., `[404]` or `[(500, 599)]` |
| `StrictTraceContinuation` | `bool` | `false` | — | When `true`, starts a new trace if exactly one side (SDK or incoming `sentry-org_id` baggage) has an org ID. A full mismatch (both present but different) always starts a new trace regardless of this setting. (requires ≥6.6.0) |
| `OrgId` | `string` | auto | — | Organization ID for trace validation; auto-parsed from DSN subdomain (e.g., `o123.ingest.sentry.io` → `"123"`). Recommended to set explicitly for self-hosted Sentry, local Relay, or custom domains (requires ≥6.6.0) |

### ASP.NET Core Extended Options (`SentryAspNetCoreOptions`)

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `MaxRequestBodySize` | `RequestSize` | `None` | `None`, `Small` (~4 KB), `Medium` (~10 KB), `Always` |
| `MinimumBreadcrumbLevel` | `LogLevel` | `Information` | Min log level for breadcrumbs |
| `MinimumEventLevel` | `LogLevel` | `Error` | Min log level to send as Sentry event |
| `CaptureBlockingCalls` | `bool` | `false` | Detect `.Wait()` / `.Result` threadpool starvation |
| `FlushOnCompletedRequest` | `bool` | `false` | **Required for Lambda / serverless** |
| `IncludeActivityData` | `bool` | `false` | Capture `System.Diagnostics.Activity` values |

### MAUI Extended Options (`SentryMauiOptions`)

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `IncludeTextInBreadcrumbs` | `bool` | `false` | Text from `Button`, `Label`, `Entry` elements. ⚠️ PII risk. |
| `IncludeTitleInBreadcrumbs` | `bool` | `false` | Titles from `Window`, `Page` elements. ⚠️ PII risk. |
| `IncludeBackgroundingStateInBreadcrumbs` | `bool` | `false` | `Window.Backgrounding` event state. ⚠️ PII risk. |

### Android Native Options (`SentryOptions.Native`)

Available when targeting Android via MAUI or Xamarin. Access via `options.Native.PropertyName`.

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `TombstoneEnabled` | `bool` | `false` | Enables native crash reporting via tombstones. See [Android Tombstone docs](https://docs.sentry.io/platforms/android/configuration/tombstones/). |
| `ReportHistoricalTombstones` | `bool` | `false` | Reports historical tombstones from previous app runs. Requires `TombstoneEnabled = true`. |

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `SENTRY_DSN` | Project DSN |
| `SENTRY_RELEASE` | App version (e.g. `my-app@1.2.3`) |
| `SENTRY_ENVIRONMENT` | Deployment environment name |
| `SENTRY_AUTH_TOKEN` | MSBuild / `sentry-cli` symbol upload auth token |

**ASP.NET Core:** use double underscore `__` as hierarchy separator:

```bash
export Sentry__Dsn="https://..."
export Sentry__TracesSampleRate="0.1"
```

### MSBuild Symbol Upload Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `SentryOrg` | `string` | — | Sentry organization slug |
| `SentryProject` | `string` | — | Sentry project slug |
| `SentryUploadSymbols` | `bool` | `false` | Upload PDB files for line numbers in stack traces |
| `SentryUploadSources` | `bool` | `false` | Upload source files for source context |
| `SentryCreateRelease` | `bool` | `false` | Auto-create a Sentry release during build |
| `SentrySetCommits` | `bool` | `false` | Associate git commits with the release |
| `SentryUrl` | `string` | — | Self-hosted Sentry URL |

---

## Verification

After wizard or manual setup, add a test throw and remove it after verifying:

```csharp
// ASP.NET Core: add a temporary endpoint
app.MapGet("/sentry-test", () =>
{
    throw new Exception("Sentry test error — delete me");
});

// Or capture explicitly anywhere
SentrySdk.CaptureException(new Exception("Sentry test error — delete me"));
```

Then check your [Sentry Issues dashboard](https://sentry.io/issues/) — the error should appear within ~30 seconds.

**Verification checklist:**

| Check | How |
|-------|-----|
| Exceptions captured | Throw a test exception, verify in Sentry Issues |
| Stack traces readable | Check that file names and line numbers appear |
| Tracing active | Check Performance tab for transactions |
| Logging wired | Log an error via `ILogger`, check it appears as Sentry breadcrumb |
| Symbol upload working | Stack trace shows `Controllers/HomeController.cs:42` not `<unknown>` |

---

## Phase 4: Cross-Link

After completing .NET setup, check for companion frontend projects:

```bash
# Check for frontend in adjacent directories
ls ../frontend ../client ../web ../app 2>/dev/null

# Check for JavaScript framework indicators
cat ../package.json 2>/dev/null | grep -E '"next"|"react"|"vue"|"nuxt"' | head -3
```

If a frontend is found, suggest the matching SDK skill:

| Frontend detected | Suggest skill |
|-------------------|--------------|
| Next.js (`"next"` in `package.json`) | `sentry-nextjs-sdk` |
| React SPA (`"react"` without `"next"`) | `@sentry/react` — see [docs.sentry.io/platforms/javascript/guides/react/](https://docs.sentry.io/platforms/javascript/guides/react/) |
| Vue.js | `@sentry/vue` — see [docs.sentry.io/platforms/javascript/guides/vue/](https://docs.sentry.io/platforms/javascript/guides/vue/) |
| Nuxt | `@sentry/nuxt` — see [docs.sentry.io/platforms/javascript/guides/nuxt/](https://docs.sentry.io/platforms/javascript/guides/nuxt/) |

Connecting frontend and backend with the same Sentry project enables **distributed tracing** — a single trace view spanning browser, .NET server, and any downstream APIs.

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Events not appearing | DSN misconfigured | Set `Debug = true` and check console output for SDK diagnostic messages |
| Stack traces show no file/line | PDB files not uploaded | Add `SentryUploadSymbols=true` to `.csproj`; set `SENTRY_AUTH_TOKEN` in CI |
| WPF/WinForms exceptions missing | `IsGlobalModeEnabled` not set | Set `options.IsGlobalModeEnabled = true` in `SentrySdk.Init()` |
| Lambda/serverless events lost | Container freezes before flush | Set `options.FlushOnCompletedRequest = true` |
| WPF UI-thread exceptions missing | `DispatcherUnhandledException` not wired | Register `App.DispatcherUnhandledException` in constructor (not `OnStartup`) |
| Duplicate HTTP spans in Azure Functions | Both Sentry and OTel instrument HTTP | Set `options.DisableSentryHttpMessageHandler = true` |
| `TracesSampleRate` has no effect | Rate is `0.0` (default) | Set `TracesSampleRate > 0` to enable tracing |
| `appsettings.json` values ignored | Config key format wrong | Use flat key `"Sentry:Dsn"` or env var `Sentry__Dsn` (double underscore) |
| `BeforeSend` drops all events | Hook returns `null` unconditionally | Verify your filter logic; return `null` only for events you want to drop |
| MAUI native crashes not captured | Wrong package | Confirm `Sentry.Maui` is installed (not just `Sentry`) |
