# Sentry Python SDK

Opinionated wizard that scans your Python project and guides you through complete Sentry
setup.

> **Note:** SDK versions and APIs below reflect Sentry docs at time of writing
> (sentry-sdk 2.x). Always verify against
> [docs.sentry.io/platforms/python/](https://docs.sentry.io/platforms/python/) before
> implementing.

* * *

## Phase 1: Detect

Run these commands to understand the project before making recommendations:

```bash
# Check existing Sentry
grep -i sentry requirements.txt pyproject.toml setup.cfg setup.py 2>/dev/null

# Detect web framework
grep -rE "django|flask|fastapi|starlette|aiohttp|tornado|quart|falcon|sanic|bottle|pyramid" \
  requirements.txt pyproject.toml 2>/dev/null

# Detect task queues
grep -rE "celery|rq|huey|arq|dramatiq" requirements.txt pyproject.toml 2>/dev/null

# Detect logging libraries
grep -E "loguru" requirements.txt pyproject.toml 2>/dev/null

# Detect AI libraries
grep -rE "openai|anthropic|langchain|huggingface|google-genai|pydantic-ai|litellm" \
  requirements.txt pyproject.toml 2>/dev/null

# Detect feature-flag providers
grep -rE "launchdarkly|openfeature|statsig|unleash|flagsmith|ldclient" \
  requirements.txt pyproject.toml 2>/dev/null


# Detect schedulers / crons
grep -rE "celery|apscheduler|schedule|crontab" requirements.txt pyproject.toml 2>/dev/null

# OpenTelemetry tracing — check for SDK + instrumentations
grep -rE "opentelemetry-sdk|opentelemetry-instrumentation|opentelemetry-distro" \
  requirements.txt pyproject.toml 2>/dev/null
grep -rn "TracerProvider\|trace\.get_tracer\|start_as_current_span" \
  --include="*.py" 2>/dev/null | head -5

# Check for companion frontend
ls frontend/ web/ client/ ui/ static/ templates/ 2>/dev/null
```

**What to note:**
- Is `sentry-sdk` already in requirements?
  If yes, check if `sentry_sdk.init()` is present — may just need feature config.
- Which framework? (Determines where to place `sentry_sdk.init()`.)
- Which task queue? (Celery needs dual-process init; RQ needs a settings file.)
- AI libraries? (OpenAI, Anthropic, LangChain are auto-instrumented.)
- OpenTelemetry tracing?
  (Use OTLP path instead of native tracing.)
- Companion frontend? (Triggers Phase 4 cross-link.)

* * *

## Phase 2: Recommend

Based on what you found, present a concrete proposal.
Don’t ask open-ended questions — lead with a recommendation:

**Route from OTel detection:**
- **OTel tracing detected** (`opentelemetry-sdk` / `opentelemetry-distro` in
  requirements, or `TracerProvider` in source) → use OTLP path: `OTLPIntegration()`; do
  **not** set `traces_sample_rate`; Sentry links errors to OTel traces automatically

**Always recommended (core coverage):**
- ✅ **Error Monitoring** — captures unhandled exceptions, supports `ExceptionGroup`
  (Python 3.11+)
- ✅ **Logging** — Python `logging` stdlib auto-captured; enhanced if Loguru detected

**Recommend when detected:**
- ✅ **Tracing** — HTTP framework detected (Django/Flask/FastAPI/etc.)
- ✅ **AI Monitoring** — OpenAI/Anthropic/LangChain/etc.
  detected (auto-instrumented, zero config)
- ⚡ **Profiling** — production apps where performance matters; **not available with OTLP
  path**
- ⚡ **Crons** — Celery Beat, APScheduler, or cron patterns detected
- ⚡ **Metrics** — business KPIs, SLO tracking

**Recommendation matrix:**

| Feature | Recommend when … | Reference |
| --- | --- | --- |
| Error Monitoring | **Always** — non-negotiable baseline | `./error-monitoring.md` |
| OTLP Integration | OTel tracing detected — **replaces** native Tracing | `./tracing.md` |
| Tracing | Django/Flask/FastAPI/AIOHTTP/etc. detected; **skip if OTel tracing detected** | `./tracing.md` |
| Profiling | Production + performance-sensitive workload; **skip if OTel tracing detected** (requires `traces_sample_rate`, incompatible with OTLP) | `./profiling.md` |
| Logging | Always (stdlib); enhanced for Loguru | `./logging.md` |
| Metrics | Business events or SLO tracking needed | `./metrics.md` |
| Crons | Celery Beat, APScheduler, or cron patterns | `./crons.md` |
| AI Monitoring | OpenAI/Anthropic/LangChain/etc. detected | `./ai-monitoring.md` |
| Feature Flags | LaunchDarkly / OpenFeature / Statsig / Unleash / custom flags detected | `./feature-flags.md` |

**OTel tracing detected:** *“I see OpenTelemetry tracing in the project.
I recommend Sentry’s OTLP integration for tracing (via your existing OTel setup) + Error
Monitoring + Sentry Logging [+ Metrics/Crons/AI Monitoring if applicable]. Shall I
proceed?”*

**No OTel:** *“I recommend Error Monitoring + Tracing [+ Logging if applicable]. Want
Profiling, Crons, or AI Monitoring too?”*

* * *

## Phase 3: Guide

### Install

```bash
# Core SDK (always required)
pip install sentry-sdk

# Optional extras (install only what matches detected framework):
pip install "sentry-sdk[django]"
pip install "sentry-sdk[flask]"
pip install "sentry-sdk[fastapi]"
pip install "sentry-sdk[celery]"
pip install "sentry-sdk[aiohttp]"
pip install "sentry-sdk[tornado]"

# Multiple extras:
pip install "sentry-sdk[django,celery]"
```

> Extras are optional — plain `sentry-sdk` works for all frameworks.
> Extras install complementary packages.

### Quick Start — Recommended Init

Full init enabling the most features with sensible defaults.
Place **before** any app/framework code:

```python
import os
import sentry_sdk

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    environment=os.environ.get("SENTRY_ENVIRONMENT", "production"),
    release=os.environ.get("SENTRY_RELEASE"),   # e.g. "myapp@1.0.0"
    send_default_pii=True,

    # Tracing (lower to 0.1–0.2 in high-traffic production)
    traces_sample_rate=1.0,

    # Profiling — continuous, tied to active spans
    profile_session_sample_rate=1.0,
    profile_lifecycle="trace",

    # Structured logs (SDK ≥ 2.35.0)
    enable_logs=True,
)
```

### Where to Initialize Per Framework

| Framework | Where to call `sentry_sdk.init()` | Notes |
| --- | --- | --- |
| **Django** | Top of `settings.py`, before other application imports | No middleware needed — Sentry patches Django internally |
| **Flask** | Before `app = Flask(__name__)` | Must precede app creation |
| **FastAPI** | Before `app = FastAPI()` | `StarletteIntegration` + `FastApiIntegration` auto-enabled together |
| **Starlette** | Before `app = Starlette(...)` | Same auto-integration as FastAPI |
| **AIOHTTP** | Module level, before `web.Application()` |  |
| **Tornado** | Module level, before app setup | No integration class needed |
| **Quart** | Before `app = Quart(__name__)` |  |
| **Falcon** | Module level, before `app = falcon.App()` |  |
| **Pyramid** | Module level, before `config = Configurator()` | WSGI framework |
| **Sanic** | Inside `@app.listener("before_server_start")` | Sanic’s lifecycle requires async init |
| **Celery** | `@signals.celeryd_init.connect` in worker AND in calling process | Dual-process init required |
| **RQ** | `mysettings.py` loaded by worker via `rq worker -c mysettings` |  |
| **ARQ** | Both worker module and enqueuing process |  |

**Django example** (`settings.py`):
```python
import os
import sentry_sdk

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    send_default_pii=True,
    traces_sample_rate=1.0,
    profile_session_sample_rate=1.0,
    profile_lifecycle="trace",
    enable_logs=True,
)

# rest of Django settings...
INSTALLED_APPS = [...]
```

**FastAPI example** (`main.py`):
```python
import os
import sentry_sdk

sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    send_default_pii=True,
    traces_sample_rate=1.0,
    profile_session_sample_rate=1.0,
    profile_lifecycle="trace",
    enable_logs=True,
)

from fastapi import FastAPI
app = FastAPI()
```

### Auto-Enabled vs Explicit Integrations

Most integrations activate automatically when their package is installed — no
`integrations=[...]` needed:

| Auto-enabled | Explicit required |
| --- | --- |
| Django, Flask, FastAPI, Starlette, AIOHTTP, Tornado, Quart, Falcon, Pyramid, Sanic, Bottle | `DramatiqIntegration` |
| Celery, RQ, Huey, ARQ | `GRPCIntegration` |
| SQLAlchemy, Redis, asyncpg, pymongo | `StrawberryIntegration` |
| Requests, HTTPX, httpx2, aiohttp-client | `AsyncioIntegration` |
| OpenAI, Anthropic, LangChain, Pydantic AI, MCP | `OpenAIIntegration` / `AnthropicIntegration` / etc. |
| Python `logging`, Loguru | — |

### For Each Agreed Feature

Walk through features one at a time.
Load the reference, follow its steps, verify before moving on:

| Feature | Reference file | Load when … |
| --- | --- | --- |
| Error Monitoring | `./error-monitoring.md` | Always (baseline) |
| Tracing | `./tracing.md` | HTTP handlers / distributed tracing |
| Profiling | `./profiling.md` | Performance-sensitive production |
| Logging | `./logging.md` | Always; enhanced for Loguru |
| Metrics | `./metrics.md` | Business KPIs / SLO tracking |
| Crons | `./crons.md` | Scheduler / cron patterns detected |
| AI Monitoring | `./ai-monitoring.md` | AI library detected |
| Feature Flags | `./feature-flags.md` | Flag system detected (LaunchDarkly, OpenFeature, Statsig, Unleash, Pennant, Remote Config, …) — also enable change tracking |

For each feature: `Read ./<feature>.md`, follow steps exactly, verify it works.

* * *

## Configuration Reference

### Key `sentry_sdk.init()` Options

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `str` | `None` | SDK disabled if empty; env: `SENTRY_DSN` |
| `environment` | `str` | `"production"` | e.g., `"staging"`; env: `SENTRY_ENVIRONMENT` |
| `release` | `str` | `None` | e.g., `"myapp@1.0.0"`; env: `SENTRY_RELEASE` |
| `send_default_pii` | `bool` | `False` | Include IP, headers, cookies, auth user, query strings (ASGI frameworks) |
| `traces_sample_rate` | `float` | `None` | Transaction sample rate; `None` disables tracing |
| `traces_sampler` | `Callable` | `None` | Custom per-transaction sampling (overrides rate) |
| `profile_session_sample_rate` | `float` | `None` | Continuous profiling session rate |
| `profile_lifecycle` | `str` | `"manual"` | `"trace"` = auto-start profiler with spans |
| `profiles_sample_rate` | `float` | `None` | Transaction-based profiling rate |
| `enable_logs` | `bool` | `False` | Send logs to Sentry (SDK ≥ 2.35.0) |
| `sample_rate` | `float` | `1.0` | Error event sample rate |
| `attach_stacktrace` | `bool` | `False` | Stack traces on `capture_message()` |
| `max_breadcrumbs` | `int` | `100` | Max breadcrumbs per event |
| `debug` | `bool` | `False` | Verbose SDK debug output |
| `before_send` | `Callable` | `None` | Hook to mutate/drop error events |
| `before_send_transaction` | `Callable` | `None` | Hook to mutate/drop transaction events |
| `ignore_errors` | `list` | `[]` | Exception types or regex patterns to suppress |
| `auto_enabling_integrations` | `bool` | `True` | Set `False` to disable all auto-detection |

#### `OTLPIntegration` Options (pass to constructor)

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `setup_otlp_traces_exporter` | `bool` | `True` | Auto-configure OTLP exporter; set `False` if you send to your own Collector |
| `collector_url` | `str` | `None` | OTLP HTTP endpoint of an OTel Collector (e.g., `http://localhost:4318/v1/traces`); when set, spans are sent to the collector instead of directly to Sentry |
| `setup_propagator` | `bool` | `True` | Auto-configure Sentry propagator for distributed tracing |
| `capture_exceptions` | `bool` | `False` | Intercept exceptions recorded via OTel `Span.record_exception` |

### Environment Variables

| Variable | Maps to | Notes |
| --- | --- | --- |
| `SENTRY_DSN` | `dsn` |  |
| `SENTRY_RELEASE` | `release` | Also auto-detected from git SHA, Heroku, CircleCI, CodeBuild, GAE |
| `SENTRY_ENVIRONMENT` | `environment` |  |
| `SENTRY_DEBUG` | `debug` |  |

* * *

## Verification

Test that Sentry is receiving events:

```python
# Trigger a real error event — check dashboard within seconds
division_by_zero = 1 / 0
```

Or for a non-crashing check:
```python
sentry_sdk.capture_message("Sentry Python SDK test")
```

If nothing appears:
1. Set `debug=True` in `sentry_sdk.init()` — prints SDK internals to stdout
2. Verify the DSN is correct
3. Check `SENTRY_DSN` env var is set in the running process
4. For Celery/RQ: ensure init runs in the **worker** process, not just the calling
   process

* * *

## Phase 4: Cross-Link

After completing Python setup, check for a companion frontend missing Sentry:

```bash
ls frontend/ web/ client/ ui/ 2>/dev/null
cat frontend/package.json web/package.json client/package.json 2>/dev/null \
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
| Events not appearing | Set `debug=True`, verify DSN, check env vars in the running process |
| Malformed DSN error | Format: `https://<key>@o<org>.ingest.sentry.io/<project>` |
| Django exceptions not captured | Ensure `sentry_sdk.init()` is at the **top** of `settings.py` before other imports |
| Flask exceptions not captured | Init must happen **before** `app = Flask(__name__)` |
| FastAPI exceptions not captured | Init before `app = FastAPI()`; both `StarletteIntegration` and `FastApiIntegration` auto-enabled |
| ASGI chained exceptions suppressed | By default, Sentry’s ASGI middleware strips exception chains (`raise exc from None`). To preserve chained exceptions, set `_experiments={"suppress_asgi_chained_exceptions": False}` in `sentry_sdk.init()` |
| Celery task errors not captured | Must call `sentry_sdk.init()` in the **worker process** via `celeryd_init` signal |
| Sanic init not working | Init must be inside `@app.listener("before_server_start")`, not module level |
| uWSGI not capturing | Add `--enable-threads --py-call-uwsgi-fork-hooks` to uWSGI command |
| No traces appearing (native) | Verify `traces_sample_rate` is set (not `None`); check that the integration is auto-enabled |
| No traces appearing (OTLP) | Verify `sentry-sdk[opentelemetry-otlp]` is installed; do **not** set `traces_sample_rate` when using `OTLPIntegration` |
| Profiling not starting | Requires `traces_sample_rate > 0` + either `profile_session_sample_rate` or `profiles_sample_rate`; **not compatible with OTLP path** |
| `enable_logs` not working | Requires SDK ≥ 2.35.0; for direct structured logs use `sentry_sdk.logger`; for stdlib bridging use `LoggingIntegration(sentry_logs_level=...)` |
| Too many transactions | Lower `traces_sample_rate` or use `traces_sampler` to drop health checks |
| Cross-request data leaking | Don’t use `get_global_scope()` for per-request data — use `get_isolation_scope()` |
| Query strings not captured (ASGI) | Query strings and client IP in ASGI frameworks (FastAPI, Starlette, etc.) require `send_default_pii=True` |
| RQ worker not reporting | Pass `--sentry-dsn=""` to disable RQ’s own Sentry shortcut; init via settings file instead |
