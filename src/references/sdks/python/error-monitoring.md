# Error Monitoring — Sentry Python SDK

> Minimum SDK: `sentry-sdk` 1.x+ (2.x for `new_scope()`, `get_isolation_scope()`)

## Configuration

Key `sentry_sdk.init()` options for error monitoring:

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `dsn` | `str` | env `SENTRY_DSN` | Data Source Name; SDK disabled if empty |
| `environment` | `str` | `"production"` | Deployment environment tag |
| `release` | `str` | env `SENTRY_RELEASE` | App version string |
| `sample_rate` | `float` | `1.0` | Fraction of error events to send (0.0–1.0) |
| `send_default_pii` | `bool` | `False` | Include IPs, cookies, sessions |
| `attach_stacktrace` | `bool` | `False` | Add stack traces to `capture_message()` |
| `max_breadcrumbs` | `int` | `100` | Max breadcrumbs per event |
| `ignore_errors` | `list` | `[]` | Exception types to never report |
| `before_send` | `callable` | `None` | Mutate or drop error events before sending |
| `before_breadcrumb` | `callable` | `None` | Mutate or drop breadcrumbs |
| `event_scrubber` | `EventScrubber` | `None` | Denylist-based PII scrubber |
| `include_local_variables` | `bool` | `True` | Capture stack-frame local variable values |
| `max_request_body_size` | `str` | `"medium"` | `"never"` / `"small"` / `"medium"` / `"always"` |

## Code Examples

### Basic setup

```python
import sentry_sdk

sentry_sdk.init(
    dsn="https://<key>@<org>.ingest.sentry.io/<project>",
    environment="production",
    release="my-app@1.0.0",
    sample_rate=1.0,
    send_default_pii=False,
    max_breadcrumbs=100,
)
```

### Capturing exceptions and messages

```python
import sentry_sdk

# Capture current exception (inside except block — reads sys.exc_info())
try:
    risky_operation()
except Exception:
    sentry_sdk.capture_exception()

# Capture explicit exception object
try:
    risky_operation()
except Exception as e:
    sentry_sdk.capture_exception(e)
    raise  # re-raise after capturing

# Capture a plain message
sentry_sdk.capture_message("Payment webhook received unexpected payload")
sentry_sdk.capture_message("Rate limit approaching", level="warning")

# Capture a fully manual event
sentry_sdk.capture_event({
    "message": "Billing failure",
    "level": "error",
    "tags": {"payment.method": "stripe"},
    "fingerprint": ["billing-charge-failure"],
})
```

### Automatic capture by framework

Framework integrations are **auto-enabled** when installed — no `integrations=[...]`
needed for most:

```python
# Django — unhandled view exceptions auto-captured
import sentry_sdk
sentry_sdk.init(dsn="...")   # DjangoIntegration auto-enabled

# Flask — unhandled route exceptions auto-captured
from flask import Flask
import sentry_sdk
sentry_sdk.init(dsn="...")   # FlaskIntegration auto-enabled
app = Flask(__name__)

# FastAPI — unhandled endpoint exceptions auto-captured
import sentry_sdk
sentry_sdk.init(dsn="...")   # StarletteIntegration + FastApiIntegration auto-enabled

# Celery — task exceptions auto-captured
import sentry_sdk
sentry_sdk.init(dsn="...")   # CeleryIntegration auto-enabled
```

### Scope management (SDK 2.x)

Three scope layers merge when sending events:

| Scope | Lifetime | Use for |
| --- | --- | --- |
| **Global** | Process lifetime | App-wide tags, server metadata |
| **Isolation** | One request / task | Per-request user, tags |
| **Current** | One span | Per-span metadata |

```python
import sentry_sdk

# Per-request user (isolation scope — fresh per HTTP request with web integrations)
scope = sentry_sdk.get_isolation_scope()
scope.set_user({"id": "user_42", "email": "alice@example.com"})
scope.set_tag("request.id", "req_abc123")

# Temporary forked scope — changes don't leak out
with sentry_sdk.new_scope() as scope:
    scope.set_tag("payment.retry_attempt", "3")
    scope.set_context("charge", {"amount": 9900, "currency": "USD"})
    scope.fingerprint = ["payment-processing-error"]
    sentry_sdk.capture_exception(some_error)
# ← scope reverts here
```

### Context enrichment

```python
import sentry_sdk

# Tags — indexed and searchable; max key 32 chars, value 200 chars
sentry_sdk.set_tag("page.locale", "de-at")
sentry_sdk.set_tags({"checkout.step": "payment", "plan": "enterprise"})

# User identity
sentry_sdk.set_user({
    "id": "user_42",
    "username": "alice_wonder",
    "email": "alice@example.com",
    "ip_address": "{{auto}}",    # Sentry infers from connection
})
sentry_sdk.set_user(None)        # clear user (e.g., on logout)

# Structured context objects (not searchable, visible in event detail)
sentry_sdk.set_context("payment", {
    "provider": "stripe",
    "amount": 9900,
    "currency": "USD",
})

# Breadcrumbs
sentry_sdk.add_breadcrumb(
    type="http",
    category="auth",
    message="User authenticated via OAuth2",
    level="info",
    data={"provider": "google"},
)
```

### `before_send` hook — filtering and scrubbing

```python
import sentry_sdk

def before_send(event, hint):
    exc_info = hint.get("exc_info")

    # Drop non-actionable exceptions
    if exc_info and issubclass(exc_info[0], (KeyboardInterrupt, SystemExit)):
        return None

    # Scrub sensitive HTTP headers
    headers = event.get("request", {}).get("headers", {})
    for h in ("Authorization", "Cookie", "X-Api-Key"):
        if h in headers:
            headers[h] = "[Filtered]"

    # Scrub local variables
    for exc in event.get("exception", {}).get("values", []):
        for frame in exc.get("stacktrace", {}).get("frames", []):
            for key in ("password", "token", "secret"):
                frame.get("vars", {}).pop(key, None)

    # Custom fingerprinting
    if exc_info and isinstance(exc_info[1], TimeoutError):
        event["fingerprint"] = ["network-timeout"]

    return event

sentry_sdk.init(dsn="...", before_send=before_send)
```

### Fingerprinting (custom grouping)

```python
import sentry_sdk

# Static fingerprint via scope
with sentry_sdk.new_scope() as scope:
    scope.fingerprint = ["database-connection-failure"]
    sentry_sdk.capture_exception(db_error)

# Extend default grouping
with sentry_sdk.new_scope() as scope:
    scope.fingerprint = ["{{ default }}", "stripe-payment-failure"]
    sentry_sdk.capture_exception(payment_error)

# Dynamic fingerprint in before_send
def before_send(event, hint):
    exc_info = hint.get("exc_info")
    if exc_info and hasattr(exc_info[1], "status_code"):
        code = exc_info[1].status_code
        if code >= 500:
            event["fingerprint"] = ["http-server-error", str(code)]
    return event
```

### PII scrubbing with EventScrubber

```python
import sentry_sdk
from sentry_sdk.scrubber import EventScrubber, DEFAULT_DENYLIST

sentry_sdk.init(
    dsn="...",
    send_default_pii=False,
    event_scrubber=EventScrubber(
        denylist=DEFAULT_DENYLIST + ["stripe_key", "internal_secret", "ssn"],
        recursive=True,   # deep-scan nested dicts (has performance cost)
    ),
)
```

### Exception Groups (Python 3.11+)

```python
import sentry_sdk

# ExceptionGroup sub-exceptions appear as linked entries in Sentry UI
try:
    raise ExceptionGroup(
        "Batch job failures",
        [ValueError("Bad record #1"), KeyError("Missing field in record #5")],
    )
except* ValueError as eg:
    sentry_sdk.capture_exception(eg)
except* KeyError as eg:
    sentry_sdk.capture_exception(eg)
```

### Advanced: Framework middleware pattern

```python
import sentry_sdk
from flask import Flask

app = Flask(__name__)
sentry_sdk.init(dsn="...")

@app.before_request
def set_sentry_user():
    scope = sentry_sdk.get_isolation_scope()
    user = get_current_user()
    if user:
        scope.set_user({"id": str(user.id), "username": user.username})
        scope.set_tag("user.plan", user.plan)
```

## Best Practices

- Set `send_default_pii=False` (default) — add explicit PII scrubbing via `before_send`
  or `EventScrubber`
- Use `get_isolation_scope()` for per-request data; use `new_scope()` for temporary
  isolated context
- Avoid `set_extra()` (deprecated) — use `set_context()` for structured data
- Prefer `set_tag()` for data you want to filter on; `set_context()` for detail-only
  data
- Use `ignore_errors=[...]` for exceptions you never want reported (e.g.,
  `KeyboardInterrupt`)
- Set `in_app_include=["my_package"]` to correctly mark your frames as in-app in
  tracebacks

## Troubleshooting

| Issue | Solution |
| --- | --- |
| Events not appearing in Sentry | Verify DSN, check `debug=True` output, ensure `sentry_sdk.init()` is called before app startup |
| User/tag data missing from events | Set scope data before the exception occurs; check isolation vs current scope |
| PII appearing in events | Set `send_default_pii=False` and add `EventScrubber` with your denylist |
| `capture_exception()` is a no-op | Must be called inside an `except` block or pass the exception explicitly |
| Breadcrumbs missing | Check `max_breadcrumbs` setting and `before_breadcrumb` hook |
| `push_scope()` / `configure_scope()` errors | Migrate to `new_scope()` / `get_isolation_scope()` (SDK 2.x) |
