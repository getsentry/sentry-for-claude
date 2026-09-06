# Sentry PHP SDK

Opinionated wizard that scans your PHP project and guides you through complete Sentry
setup.

> **Note:** SDK versions and APIs below reflect Sentry docs at time of writing
> (sentry/sentry 4.x, sentry/sentry-laravel 4.x, sentry/sentry-symfony 5.x). Always
> verify against [docs.sentry.io/platforms/php/](https://docs.sentry.io/platforms/php/)
> before implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making recommendations:

```bash
# Check existing Sentry
grep -i sentry composer.json composer.lock 2>/dev/null

# Detect framework
cat composer.json | grep -E '"laravel/framework"|"symfony/framework-bundle"|"illuminate/'

# Confirm framework via filesystem markers
ls artisan 2>/dev/null && echo "Laravel detected"
ls bin/console 2>/dev/null && echo "Symfony detected"

# Detect queue systems
grep -E '"laravel/horizon"|"symfony/messenger"' composer.json 2>/dev/null

# Detect AI libraries
grep -E '"(laravel/ai|openai-php|openai/|anthropic|llm)' composer.json 2>/dev/null

# Check for companion frontend
ls frontend/ resources/js/ assets/ 2>/dev/null
cat package.json 2>/dev/null | grep -E '"react"|"svelte"|"vue"|"next"'
```

**What to note:**
- Is `sentry/sentry` (or `-laravel` / `-symfony`) already in `composer.json`? If yes,
  check if the init call exists — may just need feature config.
- Framework detected? **Laravel** (has `artisan` + `laravel/framework` in composer.json),
  **Symfony** (has `bin/console` + `symfony/framework-bundle`), or **plain PHP**.
- Queue system? (Laravel Queue / Horizon, Symfony Messenger need queue worker
  configuration.)
- AI libraries? (`laravel/ai` is auto-instrumented by `sentry/sentry-laravel >= 4.27.0`
  when tracing is enabled; other PHP AI libraries need manual spans.)
- Companion frontend? (Triggers Phase 4 cross-link.)

* * *

## Phase 2: Recommend

Based on what you found, present a concrete proposal.
Don’t ask open-ended questions — lead with a recommendation:

**Always recommended (core coverage):**
- ✅ **Error Monitoring** — captures unhandled exceptions and PHP errors
- ✅ **Logging** — Monolog integration (Laravel/Symfony auto-configure; plain PHP uses
  `MonologHandler`)

**Recommend when detected:**
- ✅ **Tracing** — web framework detected (Laravel/Symfony auto-instrument HTTP, DB,
  Twig/Blade, cache)
- ⚡ **Profiling** — production apps where performance matters (requires `excimer` PHP
  extension, Linux/macOS only)
- ⚡ **Crons** — scheduler patterns detected (Laravel Scheduler, Symfony Scheduler,
  custom cron jobs)
- ⚡ **Metrics** — business KPIs or SLO tracking (uses `TraceMetrics` API)
- ✅ **AI Monitoring** — `laravel/ai` detected in a Laravel app (auto-instrumented in
  `sentry/sentry-laravel >= 4.27.0`)

**Recommendation matrix:**

| Feature | Recommend when … | Reference |
| --- | --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline | `./error-monitoring.md` |
| Tracing | Laravel/Symfony detected, or manual spans needed | `./tracing.md` |
| Profiling | Production + `excimer` extension available | `./profiling.md` |
| Logging | **Always**; Monolog for Laravel/Symfony | `./logging.md` |
| Metrics | Business events or SLO tracking needed | `./metrics.md` |
| Crons | Scheduler or cron patterns detected | `./crons.md` |
| AI Monitoring | `laravel/ai` detected in a Laravel app, or manual PHP AI spans needed | `./ai-monitoring.md` |
| Feature Flags | `laravel/pennant` or other flag evaluations detected | `./feature-flags.md` |

Propose: *“I recommend Error Monitoring + Tracing [+ Logging]. Want Profiling, Crons,
Metrics, or AI Monitoring too?”*

* * *

## Phase 3: Guide

### Install

```bash
# Plain PHP
composer require sentry/sentry "^4.0"

# Laravel
composer require sentry/sentry-laravel "^4.0"

# Laravel with Laravel AI monitoring
composer require sentry/sentry-laravel "^4.27.0"

# Symfony
composer require sentry/sentry-symfony "^5.0"
```

**System requirements:**
- PHP 7.2 or later
- Extensions: `ext-json`, `ext-mbstring`, `ext-curl` (all required)
- `excimer` PECL extension (Linux/macOS only — required for profiling)

### Framework-Specific Initialization

#### Plain PHP

Place `\Sentry\init()` at the top of your entry point (`index.php`, `bootstrap.php`, or
equivalent), before any application code:

```php
<?php

require_once 'vendor/autoload.php';

\Sentry\init([
    'dsn'                  => $_SERVER['SENTRY_DSN'] ?? '',
    'environment'          => $_SERVER['SENTRY_ENVIRONMENT'] ?? 'production',
    'release'              => $_SERVER['SENTRY_RELEASE'] ?? null,
    'send_default_pii'     => true,
    'traces_sample_rate'   => 1.0,
    'profiles_sample_rate' => 1.0,
    'enable_logs'          => true,
]);

// rest of application...
```

#### Laravel

**Step 1 — Register exception handler** in `bootstrap/app.php`:

```php
use Sentry\Laravel\Integration;

return Application::configure(basePath: dirname(__DIR__))
    ->withExceptions(function (Exceptions $exceptions) {
        Integration::handles($exceptions);
    })->create();
```

**Step 2 — Publish config and set DSN:**

```bash
php artisan sentry:publish --dsn=YOUR_DSN
```

This creates `config/sentry.php` and adds `SENTRY_LARAVEL_DSN` to `.env`.

**Step 3 — Configure `.env`:**

```ini
SENTRY_LARAVEL_DSN=https://examplePublicKey@o0.ingest.sentry.io/0
SENTRY_TRACES_SAMPLE_RATE=1.0
SENTRY_PROFILES_SAMPLE_RATE=1.0
```

> For full Laravel configuration options, read `./laravel.md`.

#### Symfony

**Step 1 — Register the bundle** in `config/bundles.php` (auto-done by Symfony Flex):

```php
Sentry\SentryBundle\SentryBundle::class => ['all' => true],
```

**Step 2 — Create `config/packages/sentry.yaml`:**

```yaml
sentry:
    dsn: '%env(SENTRY_DSN)%'
    options:
        environment: '%env(APP_ENV)%'
        release: '%env(SENTRY_RELEASE)%'
        send_default_pii: true
        traces_sample_rate: 1.0
        profiles_sample_rate: 1.0
        enable_logs: true
```

**Step 3 — Set the DSN in `.env`:**

```ini
SENTRY_DSN=https://examplePublicKey@o0.ingest.sentry.io/0
```

> For full Symfony configuration options, read `./symfony.md`.

### Quick Start — Recommended Init (Plain PHP)

Full init enabling the most features with sensible defaults:

```php
\Sentry\init([
    'dsn'                     => $_SERVER['SENTRY_DSN'] ?? '',
    'environment'             => $_SERVER['SENTRY_ENVIRONMENT'] ?? 'production',
    'release'                 => $_SERVER['SENTRY_RELEASE'] ?? null,
    'send_default_pii'        => true,

    // Tracing (lower to 0.1–0.2 in high-traffic production)
    'traces_sample_rate'      => 1.0,

    // Profiling — requires excimer extension (Linux/macOS only)
    'profiles_sample_rate'    => 1.0,

    // Structured logs (sentry/sentry >=4.12.0)
    'enable_logs'             => true,
]);
```

### For Each Agreed Feature

Walk through features one at a time.
Load the reference, follow its steps, verify before moving on:

| Feature | Reference file | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing | `./tracing.md` | HTTP handlers / distributed tracing |
| Profiling | `./profiling.md` | Performance-sensitive production |
| Logging | `./logging.md` | Always; Monolog for Laravel/Symfony |
| Metrics | `./metrics.md` | Business KPIs / SLO tracking |
| Crons | `./crons.md` | Scheduler / cron patterns detected |
| AI Monitoring | `./ai-monitoring.md` | `laravel/ai` detected in Laravel, or manual PHP AI spans needed |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `\Sentry\init()` Options (Plain PHP)

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `string\|bool\|null` | `$_SERVER['SENTRY_DSN']` | SDK disabled if empty or `false` |
| `environment` | `string\|null` | `$_SERVER['SENTRY_ENVIRONMENT']` | e.g., `"staging"` |
| `release` | `string\|null` | `$_SERVER['SENTRY_RELEASE']` | e.g., `"myapp@1.0.0"` |
| `send_default_pii` | `bool` | `false` | Include request headers, cookies, IP |
| `sample_rate` | `float` | `1.0` | Error event sample rate (0.0–1.0) |
| `traces_sample_rate` | `float\|null` | `null` | Transaction sample rate; `null` disables tracing |
| `traces_sampler` | `callable\|null` | `null` | Custom per-transaction sampling (overrides rate) |
| `profiles_sample_rate` | `float\|null` | `null` | Profiling rate relative to traces; requires `excimer` |
| `enable_logs` | `bool` | `false` | Send structured logs to Sentry (>=4.12.0) |
| `max_breadcrumbs` | `int` | `100` | Max breadcrumbs per event |
| `attach_stacktrace` | `bool` | `false` | Stack traces on `captureMessage()` |
| `in_app_include` | `string[]` | `[]` | Path prefixes belonging to your app |
| `in_app_exclude` | `string[]` | `[]` | Path prefixes for third-party code (hidden in traces) |
| `ignore_exceptions` | `string[]` | `[]` | Exception FQCNs to never report |
| `ignore_transactions` | `string[]` | `[]` | Transaction names to never report |
| `error_types` | `int\|null` | `error_reporting()` | PHP error bitmask (e.g., `E_ALL & ~E_NOTICE`) |
| `capture_silenced_errors` | `bool` | `false` | Capture errors suppressed by `@` operator |
| `max_request_body_size` | `string` | `"medium"` | `"none"` / `"small"` / `"medium"` / `"always"` |
| `before_send` | `callable` | identity | `fn(Event $event, ?EventHint $hint): ?Event` — return `null` to drop |
| `before_breadcrumb` | `callable` | identity | `fn(Breadcrumb $b): ?Breadcrumb` — return `null` to discard |
| `trace_propagation_targets` | `string[]\|null` | `null` | Downstream hosts to inject `sentry-trace` headers into; `null` = all, `[]` = none |
| `strict_trace_continuation` | `bool` | `false` | Only continue an incoming distributed trace if the `sentry-org_id` baggage matches the SDK’s org ID; prevents trace contamination from third-party Sentry-instrumented services (>=4.21.0) |
| `debug` | `bool` | `false` | Verbose SDK output (use a PSR-3 `logger` option instead for structured output) |

### Environment Variables

| Variable | Maps to | Notes |
| --- | --- | --- |
| `SENTRY_DSN` | `dsn` | Also `$_SERVER['SENTRY_DSN']` |
| `SENTRY_ENVIRONMENT` | `environment` |  |
| `SENTRY_RELEASE` | `release` | Also reads `$_SERVER['AWS_LAMBDA_FUNCTION_VERSION']` |
| `SENTRY_SPOTLIGHT` | `spotlight` |  |

> **Laravel note:** Uses `SENTRY_LARAVEL_DSN` (falls back to `SENTRY_DSN`). Other
> options follow `SENTRY_TRACES_SAMPLE_RATE`, `SENTRY_PROFILES_SAMPLE_RATE`, etc.

* * *

## Verification

Test that Sentry is receiving events:

```php
// Trigger a real error event — check the Sentry dashboard within seconds
throw new \Exception('Sentry PHP SDK test');
```

Or for a non-crashing check:

```php
\Sentry\captureMessage('Sentry PHP SDK test');
```

**Laravel:**
```bash
php artisan sentry:test
```

If nothing appears:
1. Enable debug output:
   ```php
   \Sentry\init([
       'dsn' => '...',
       'logger' => new \Sentry\Logger\DebugStdOutLogger(),
   ]);
   ```
2. Verify the DSN is correct (format: `https://<key>@o<org>.ingest.sentry.io/<project>`)
3. Check `SENTRY_DSN` (or `SENTRY_LARAVEL_DSN`) env var is set in the running process
4. For queue workers: ensure Sentry is initialized **inside the worker process**, not
   just the web process

* * *

## Phase 4: Cross-Link

After completing PHP setup, check for a companion frontend missing Sentry:

```bash
ls frontend/ resources/js/ assets/ public/ 2>/dev/null
cat package.json frontend/package.json 2>/dev/null \
  | grep -E '"react"|"svelte"|"vue"|"next"|"nuxt"'
```

If a frontend exists without Sentry, suggest the matching skill:

| Frontend detected | Suggest skill |
| --- | --- |
| React / Next.js | [`react`](../react/index.md) |
| Svelte / SvelteKit | [`svelte`](../svelte/index.md) |
| Vue / Nuxt | Use `@sentry/vue` — see [docs.sentry.io/platforms/javascript/guides/vue/](https://docs.sentry.io/platforms/javascript/guides/vue/) |
| Other JS/TS | [`react`](../react/index.md) (covers generic browser JS patterns) |

* * *

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing | Enable `logger` option (`DebugStdOutLogger`), verify DSN, check env vars in the running process |
| Malformed DSN error | Format: `https://<key>@o<org>.ingest.sentry.io/<project>` |
| Laravel exceptions not captured | Ensure `Integration::handles($exceptions)` is in `bootstrap/app.php` |
| Symfony exceptions not captured | Verify `SentryBundle` is registered in `config/bundles.php` |
| No traces appearing | Set `traces_sample_rate` (not `null`); confirm auto-instrumentation is enabled |
| Profiling not working | `excimer` extension required (Linux/macOS only; not available on Windows); requires `traces_sample_rate > 0` |
| `enable_logs` not working | Requires `sentry/sentry >= 4.12.0`, `sentry/sentry-laravel >= 4.15.0`, or `sentry/sentry-symfony >= 5.4.0` |
| Queue worker errors missing | Init Sentry in the worker process itself, not just the web process; for Laravel use `SENTRY_LARAVEL_DSN` in worker `.env` |
| Too many transactions | Lower `traces_sample_rate` or use `traces_sampler` to drop health check routes |
| PII not captured | Set `send_default_pii: true`; for Laravel set `send_default_pii: true` in `config/sentry.php` |
| `@`-suppressed errors missing | Set `capture_silenced_errors: true` |
| Cross-service traces broken | Check `trace_propagation_targets`; ensure downstream services have Sentry installed |
| Trace contamination from third-party services | Set `strict_trace_continuation: true` to only continue traces where the incoming `sentry-org_id` baggage matches your SDK’s org ID (>=4.21.0) |
