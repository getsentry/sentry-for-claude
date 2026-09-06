# Laravel — Sentry SDK Deep Dive

> Package: `sentry/sentry-laravel` · Requires `sentry/sentry ^4.21.0`\
> Laravel versions: `^6.0` through `^12.0` (Lumen supported)

* * *

## Installation & Setup

### Requirements

- PHP `^7.2 | ^8.0`
- Laravel `^6.0`–`^12.0`
- `zend.exception_ignore_args: Off` in `php.ini` (required for stack trace arguments)

### Install

```bash
composer require sentry/sentry-laravel
```

Auto-registration via Laravel Package Discovery — no manual `config/app.php` entry
needed. Two service providers register automatically:

- `Sentry\Laravel\ServiceProvider`
- `Sentry\Laravel\Tracing\ServiceProvider`

### Step 1 — Hook Exception Handler (Laravel 11+)

In `bootstrap/app.php`:

```php
use Sentry\Laravel\Integration;

->withExceptions(function (Exceptions $exceptions) {
    Integration::handles($exceptions);
})
```

For **Laravel 10 and earlier**, add to `app/Exceptions/Handler.php`:

```php
public function register(): void
{
    $this->reportable(function (\Throwable $e) {
        \Sentry\Laravel\Integration::captureUnhandledException($e);
    });
}
```

### Step 2 — Publish Config & Set DSN

```bash
php artisan sentry:publish --dsn=___PUBLIC_DSN___
```

This creates `config/sentry.php` and writes `SENTRY_LARAVEL_DSN=your_dsn` to `.env`.

### Step 3 — Verify

```bash
php artisan sentry:test
```

Or add a test route:

```php
Route::get('/debug-sentry', function () {
    throw new Exception('My first Sentry error!');
});
```

* * *

## Environment Variables

| Variable | Purpose | Notes |
| --- | --- | --- |
| `SENTRY_LARAVEL_DSN` | Primary DSN | Takes priority over `SENTRY_DSN` |
| `SENTRY_DSN` | Generic DSN fallback | Used if `SENTRY_LARAVEL_DSN` not set |
| `SENTRY_RELEASE` | Release version string | Mapped to `release` option |
| `SENTRY_ENVIRONMENT` | Environment name | Falls back to `APP_ENV` if not set |
| `SENTRY_TRACES_SAMPLE_RATE` | Enable/configure tracing | Must be `> 0.0` to enable tracing |
| `SENTRY_PROFILES_SAMPLE_RATE` | Enable profiling | Relative to traces sample rate |
| `SENTRY_ENABLE_LOGS` | Enable structured Sentry Logs | `true` / `false` |
| `SENTRY_SEND_DEFAULT_PII` | Capture PII (IP, etc.) | `true` / `false` |
| `LOG_CHANNEL` | Laravel log channel | e.g., `stack` |
| `LOG_STACK` | Stack channels | e.g., `single,sentry_logs` |
| `LOG_LEVEL` | Log level threshold | e.g., `info` |
| `SENTRY_LOG_LEVEL` | Sentry-specific log level override | Defaults to `LOG_LEVEL` |

* * *

## `config/sentry.php` — Complete Options

### Root Options

| Key | Default | Description |
| --- | --- | --- |
| `dsn` | `env('SENTRY_LARAVEL_DSN', env('SENTRY_DSN'))` | Sentry DSN |
| `release` | `env('SENTRY_RELEASE')` | Release version |
| `environment` | `env('SENTRY_ENVIRONMENT')` | Falls back to `APP_ENV` |
| `sample_rate` | `1.0` | Error event sample rate (0.0–1.0) |
| `traces_sample_rate` | `null` | Transaction sample rate; enables tracing when set |
| `profiles_sample_rate` | `null` | Profile sample rate; relative to traces rate |
| `enable_logs` | `false` | Enable Sentry structured logs |
| `send_default_pii` | `false` | Capture PII (IP, cookies, headers) |
| `ignore_exceptions` | `[]` | Exception FQCNs to suppress |
| `ignore_transactions` | `['/up']` | Transaction names to suppress (health check) |
| `logs_channel_level` | `'debug'` | Min log level for the `sentry` log channel (Laravel-only, not forwarded to core SDK) |

### Breadcrumb Options

All controlled per-feature in the `breadcrumbs` sub-array:

| Key | ENV Variable | Default | What it captures |
| --- | --- | --- | --- |
| `breadcrumbs.logs` | `SENTRY_BREADCRUMBS_LOGS_ENABLED` | `true` | Log message breadcrumbs |
| `breadcrumbs.cache` | `SENTRY_BREADCRUMBS_CACHE_ENABLED` | `true` | Cache operation breadcrumbs |
| `breadcrumbs.livewire` | `SENTRY_BREADCRUMBS_LIVEWIRE_ENABLED` | `true` | Livewire breadcrumbs |
| `breadcrumbs.sql_queries` | `SENTRY_BREADCRUMBS_SQL_QUERIES_ENABLED` | `true` | SQL query breadcrumbs |
| `breadcrumbs.sql_bindings` | `SENTRY_BREADCRUMBS_SQL_BINDINGS_ENABLED` | `false` | Include SQL parameter bindings |
| `breadcrumbs.queue_info` | `SENTRY_BREADCRUMBS_QUEUE_INFO_ENABLED` | `true` | Queue job breadcrumbs |
| `breadcrumbs.command_info` | `SENTRY_BREADCRUMBS_COMMAND_JOBS_ENABLED` | `true` | Artisan command breadcrumbs |
| `breadcrumbs.http_client_requests` | `SENTRY_BREADCRUMBS_HTTP_CLIENT_REQUESTS_ENABLED` | `true` | HTTP client breadcrumbs |
| `breadcrumbs.notifications` | `SENTRY_BREADCRUMBS_NOTIFICATIONS_ENABLED` | `true` | Notification breadcrumbs |

### Tracing Options

| Key | ENV Variable | Default | Description |
| --- | --- | --- | --- |
| `tracing.queue_job_transactions` | `SENTRY_TRACE_QUEUE_ENABLED` | `true` | Queue jobs as root transactions |
| `tracing.queue_jobs` | `SENTRY_TRACE_QUEUE_JOBS_ENABLED` | `true` | Queue jobs as child spans |
| `tracing.sql_queries` | `SENTRY_TRACE_SQL_QUERIES_ENABLED` | `true` | SQL queries as spans |
| `tracing.sql_bindings` | `SENTRY_TRACE_SQL_BINDINGS_ENABLED` | `false` | Include SQL bindings in spans |
| `tracing.sql_origin` | `SENTRY_TRACE_SQL_ORIGIN_ENABLED` | `true` | Track origin of SQL queries |
| `tracing.sql_origin_threshold_ms` | `SENTRY_TRACE_SQL_ORIGIN_THRESHOLD_MS` | `100` | Only track origin above this ms |
| `tracing.views` | `SENTRY_TRACE_VIEWS_ENABLED` | `true` | Blade view rendering spans |
| `tracing.livewire` | `SENTRY_TRACE_LIVEWIRE_ENABLED` | `true` | Livewire component spans |
| `tracing.http_client_requests` | `SENTRY_TRACE_HTTP_CLIENT_REQUESTS_ENABLED` | `true` | HTTP client spans |
| `tracing.cache` | `SENTRY_TRACE_CACHE_ENABLED` | `true` | Cache operation spans |
| `tracing.redis_commands` | `SENTRY_TRACE_REDIS_COMMANDS` | `false` | Redis command spans |
| `tracing.redis_origin` | `SENTRY_TRACE_REDIS_ORIGIN_ENABLED` | `true` | Track Redis command origins |
| `tracing.notifications` | `SENTRY_TRACE_NOTIFICATIONS_ENABLED` | `true` | Notification sending spans |
| `tracing.missing_routes` | `SENTRY_TRACE_MISSING_ROUTES_ENABLED` | `false` | Track 404 routes as transactions |
| `tracing.continue_after_response` | `SENTRY_TRACE_CONTINUE_AFTER_RESPONSE` | `true` | Continue traces after response |
| `tracing.default_integrations` | `SENTRY_TRACE_DEFAULT_INTEGRATIONS_ENABLED` | `true` | Register default tracing integrations |
| `tracing.features.gen_ai` | `SENTRY_TRACE_GEN_AI_ENABLED` | `true` | Capture Laravel AI spans (requires `laravel/ai`, Sentry Laravel >=4.27.0) |
| `tracing.features.gen_ai_invoke_agent` | `SENTRY_TRACE_GEN_AI_INVOKE_AGENT_ENABLED` | `true` | Capture Laravel AI agent invocation spans |
| `tracing.features.gen_ai_chat` | `SENTRY_TRACE_GEN_AI_CHAT_ENABLED` | `true` | Capture Laravel AI chat/provider request spans |
| `tracing.features.gen_ai_execute_tool` | `SENTRY_TRACE_GEN_AI_EXECUTE_TOOL_ENABLED` | `true` | Capture Laravel AI tool execution spans |
| `tracing.features.gen_ai_embeddings` | `SENTRY_TRACE_GEN_AI_EMBEDDINGS_ENABLED` | `true` | Capture Laravel AI embedding spans |

* * *

## Auto-Instrumented Operations

The Laravel SDK auto-instruments the following (via `EventHandler` + feature
integrations):

| Operation | Span Op | Minimum Version |
| --- | --- | --- |
| HTTP request lifecycle | `http.server` | All |
| Database queries | `db.sql.query` | All |
| Database transactions | `db.transaction` | All |
| View rendering (Blade) | `view.render` | All |
| Queue job publishing | `queue.publish` | All |
| Queue job processing | `queue.process` | All |
| Cache operations | (cache spans) | Laravel ≥ v11.11.0 |
| HTTP Client requests | (http.client spans) | Laravel ≥ v8.45.0 |
| Redis operations | (redis spans) | All |
| Notifications | (notification spans) | All |
| Livewire components | (livewire spans) | Requires `livewire/livewire` |
| Lighthouse GraphQL | (graphql spans) | Requires `nuwave/lighthouse` |
| Folio routes | breadcrumb + transaction name | Requires `laravel/folio` |
| Filesystem disk operations | (file spans) | Opt-in, see below |
| Laravel AI agent invocations | `gen_ai.invoke_agent` | `sentry/sentry-laravel` >=4.27.0 + `laravel/ai` |
| Laravel AI chat requests | `gen_ai.chat` | `sentry/sentry-laravel` >=4.27.0 + `laravel/ai` |
| Laravel AI tool executions | `gen_ai.execute_tool` | `sentry/sentry-laravel` >=4.27.0 + `laravel/ai` |
| Laravel AI embeddings | `gen_ai.embeddings` | `sentry/sentry-laravel` >=4.27.0 + `laravel/ai` |

### Laravel AI Instrumentation

Laravel AI instrumentation auto-enables when `laravel/ai` is installed and tracing is
enabled. It captures agent invocations, provider chat requests, tool executions,
embeddings, token usage, provider/model metadata, and conversation IDs.

To capture prompts, responses, tool arguments, tool results, and embeddings input,
explicitly enable PII capture after confirming the application’s privacy requirements:

```ini
SENTRY_SEND_DEFAULT_PII=true
```

For setup and verification steps, read `./ai-monitoring.md`.

### Filesystem Disk Instrumentation (Opt-in)

```php
// config/filesystems.php — wrap ALL disks
'disks' => Sentry\Laravel\Features\Storage\Integration::configureDisks([
    'local' => [
        'driver' => 'local',
        'root' => storage_path('app'),
    ],
    's3' => [
        'driver' => 's3',
        // ...
    ],
], /* enableSpans: */ true, /* enableBreadcrumbs: */ true),

// Or wrap a single disk
's3' => Sentry\Laravel\Features\Storage\Integration::configureDisk('s3', [
    // ... disk config ...
], /* enableSpans: */ true, /* enableBreadcrumbs: */ true),
```

* * *

## Middleware

Three middleware are auto-registered — no manual setup needed:

| Middleware | Purpose |
| --- | --- |
| `SetRequestMiddleware` | Converts and caches PSR-7 request early (prevents upload parsing failures) |
| `SetRequestIpMiddleware` | Sets request IP on Sentry scope |
| `FlushEventsMiddleware` | Flushes pending events in `terminate()` phase after response sent |

The tracing middleware (`Tracing\Middleware`) is auto-prepended via
`$httpKernel->prependMiddleware()` — it runs before all user middleware and records the
full boot time.

**FastCGI behavior:** On FastCGI, the terminate phase runs after the response is sent to
the client, so Sentry upload does not add user-visible latency.
On non-FastCGI (built-in server, RoadRunner), the response is delayed by the Sentry
upload — use a local Relay proxy in that case.

* * *

## Log Channels

Laravel provides two separate Sentry log channel drivers:

### `sentry` channel — Error Events/Breadcrumbs (classic)

Sends log messages as Sentry error events or breadcrumbs.

```php
// config/logging.php
'channels' => [
    'sentry' => [
        'driver'  => 'sentry',
        'level'   => env('LOG_LEVEL', 'error'),
        'bubble'  => true,
    ],
],
```

### `sentry_logs` channel — Structured Sentry Logs (≥ 4.15.0)

Sends structured logs to the Sentry Logs product (not as error events).

```bash
# .env
LOG_CHANNEL=stack
LOG_STACK=single,sentry_logs
SENTRY_ENABLE_LOGS=true
LOG_LEVEL=info
SENTRY_LOG_LEVEL=warning
```

```php
// config/logging.php (required for SDK <= 4.16.0; auto-registered in > 4.16.0)
'sentry_logs' => [
    'driver' => 'sentry_logs',
    'level'  => env('LOG_LEVEL', 'info'),
],
```

```php
// Usage
use Illuminate\Support\Facades\Log;

Log::info('User logged in', ['user_id' => $user->id]);
Log::warning('User {id} failed to login.', ['id' => $user->id]);
Log::error('Something went wrong', ['user_id' => auth()->id(), 'action' => 'update_profile']);

// Send only to Sentry (bypass other channels)
Log::channel('sentry_logs')->error('This goes only to Sentry');
```

**Auto-flush:** When `enable_logs` is `true`, the ServiceProvider registers a
terminating callback that flushes pending logs automatically.

**Troubleshooting Tinker:** `tinker` doesn’t trigger the normal request lifecycle —
flush manually:

```php
\Sentry\logger()->flush();
```

* * *

## Queue Integration

The queue integration is the most complete in any framework.
All of the following is automatic when `traces_sample_rate` is set:

### Distributed Tracing Across Queue

Trace context is automatically injected into job payloads using these keys:

```php
const QUEUE_PAYLOAD_BAGGAGE_DATA      = 'sentry_baggage_data';
const QUEUE_PAYLOAD_TRACE_PARENT_DATA = 'sentry_trace_parent_data';
const QUEUE_PAYLOAD_PUBLISH_TIME      = 'sentry_publish_time';
```

The worker side automatically reads these and calls `continueTrace()` — the queue job
transaction is linked to the originating HTTP request transaction, giving you end-to-end
distributed traces.

### Transaction Attributes

Queue process transactions include OpenTelemetry-aligned attributes:

| Attribute | Description |
| --- | --- |
| `messaging.system` | Queue driver (e.g., `redis`, `sqs`) |
| `messaging.destination.name` | Queue name |
| `messaging.message.id` | Job ID |
| `messaging.message.receive.latency` | Time from dispatch to processing (ms) |

### Config

```php
// config/sentry.php
'tracing' => [
    'queue_job_transactions' => true,  // Full distributed transaction per job
    'queue_jobs'             => true,  // Child spans for jobs within a transaction
],
'breadcrumbs' => [
    'queue_info' => true,  // Job name/queue/attempts breadcrumbs
],
```

* * *

## Cron Monitoring (Scheduled Tasks)

### `sentryMonitor()` Macro

Add to scheduled tasks in `routes/console.php` (Laravel 9+) or `app/Console/Kernel.php`:

```php
use Illuminate\Support\Facades\Schedule;

Schedule::command(SendEmailsCommand::class)
    ->everyHour()
    ->sentryMonitor();
```

With full configuration:

```php
Schedule::command(SendEmailsCommand::class)
    ->everyHour()
    ->sentryMonitor(
        monitorSlug: null,             // Auto-generated if null
        checkInMargin: 5,              // Minutes before check-in is considered missed
        maxRuntime: 15,                // Minutes before in-progress is marked timed out
        failureIssueThreshold: 1,      // Consecutive failures before creating issue
        recoveryThreshold: 1,          // Consecutive successes before resolving issue
        updateMonitorConfig: false,    // Set false to configure only in UI
    );
```

**⚠️ Limitation:** Tasks using `between`, `unlessBetween`, `when`, and `skip` methods
are **not supported**. Use `cron('...')` for the schedule frequency instead.

### Automatic Slug Generation

When no slug is provided:
- Commands: `"scheduled_emails-send"` (from command name)
- Jobs: `"scheduled_send-email-job"` (from reversed class name)

### Automatic Transaction Tracing

`ConsoleSchedulingIntegration` also creates tracing transactions for scheduled tasks
automatically (no additional config beyond `traces_sample_rate`):

- `op: 'console.command.scheduled'`
- `source: TransactionSource::task()`

* * *

## Artisan Commands

| Command | Description |
| --- | --- |
| `php artisan sentry:publish --dsn=DSN` | Publish `config/sentry.php`, write DSN to `.env`, optionally enable PII/tracing, send test event |
| `php artisan sentry:test` | Send a test exception (and optionally a test transaction) to verify configuration |
| `php artisan about` | Displays Sentry version/config info (via `AboutCommandIntegration`) |

* * *

## User Context

```php
\Sentry\configureScope(function (\Sentry\State\Scope $scope): void {
    $scope->setUser([
        'id'    => auth()->user()->id,
        'email' => auth()->user()->email,
    ]);
});
```

Requires `'send_default_pii' => true` in `config/sentry.php`.

* * *

## Closures and Config Caching

`php artisan config:cache` will **fail** if `config/sentry.php` contains PHP closures
(e.g., inline `before_send` callbacks).
Use a static class method callable instead:

```php
// config/sentry.php — safe for config:cache
'before_send'         => [App\Sentry\Callbacks::class, 'beforeSend'],
'before_send_log'     => [App\Sentry\Callbacks::class, 'beforeSendLog'],
'before_send_metric'  => [App\Sentry\Callbacks::class, 'beforeSendMetric'],
'traces_sampler'      => [App\Sentry\Callbacks::class, 'tracesSampler'],
```

```php
// app/Sentry/Callbacks.php
namespace App\Sentry;

use Sentry\Event;
use Sentry\EventHint;

class Callbacks
{
    public static function beforeSend(Event $event, ?EventHint $hint): ?Event
    {
        // return null to drop the event
        return $event;
    }

    public static function tracesSampler(\Sentry\Tracing\SamplingContext $context): float
    {
        return $context->getParentSampled() ? 1.0 : 0.25;
    }
}
```

* * *

## Lumen Support

```php
// bootstrap/app.php
$app->register(Sentry\Laravel\ServiceProvider::class);
```

Lumen does not auto-register service providers via Package Discovery.
No `artisan sentry:publish` — create `config/sentry.php` manually and configure it as a
Lumen config file:

```php
$app->configure('sentry');
```

* * *

## Laravel Octane (Long-Running Server)

When using Laravel Octane (Swoole/RoadRunner/FrankenPHP), requests are handled in
long-lived workers. Sentry scope must be isolated per request:

```php
// The SDK automatically handles this via context isolation
// when the Octane integration is active
```

**⚠️ Important:** If using `withScope()` / `configureScope()` for per-request context,
ensure you’re using `withScope()` (not `configureScope()`) in Octane environments —
`configureScope()` persists across requests in long-running workers.

* * *

## Feature Flags (Laravel Pennant)

**Why:** so Issue Details shows which Pennant flags were active when an error fired, and
— with provider **change tracking** configured in Sentry — so rollouts can be marked as
suspect. Full guide: [`feature-flags.md`](./feature-flags.md).

The `PennantIntegration` auto-records Pennant feature flag evaluations (boolean-style
active checks):

```php
use Laravel\Pennant\Feature;

// Checked features are automatically added as feature flags in Sentry
$active = Feature::active('new-onboarding');
```

No SDK configuration needed — enabled automatically when `laravel/pennant` is installed.
Still set up
[change tracking](https://docs.sentry.io/product/issues/issue-details/feature-flags/#change-tracking)
for the system that owns flag definitions so Sentry can correlate definition changes
with errors.

* * *

## Complete `.env` Reference

```bash
# Required
SENTRY_LARAVEL_DSN=https://examplePublicKey@o0.ingest.sentry.io/0

# Release & environment
SENTRY_RELEASE=1.0.0
SENTRY_ENVIRONMENT=production   # defaults to APP_ENV

# Performance
SENTRY_TRACES_SAMPLE_RATE=0.1   # 10% of transactions
SENTRY_PROFILES_SAMPLE_RATE=0.1 # 10% of traced transactions

# Logging
SENTRY_ENABLE_LOGS=true
LOG_CHANNEL=stack
LOG_STACK=single,sentry_logs
LOG_LEVEL=info
SENTRY_LOG_LEVEL=warning

# Privacy
SENTRY_SEND_DEFAULT_PII=false

# Breadcrumb toggles (all default true)
SENTRY_BREADCRUMBS_SQL_BINDINGS_ENABLED=false
SENTRY_BREADCRUMBS_CACHE_ENABLED=true

# Tracing toggles
SENTRY_TRACE_REDIS_COMMANDS=false
SENTRY_TRACE_MISSING_ROUTES_ENABLED=false
```
