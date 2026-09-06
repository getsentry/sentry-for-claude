# Choosing a signal

Sentry captures several distinct **signals**. They are not interchangeable.
Picking the right one is the single most important instrumentation decision, and the
wrong one is the most common waste of quota.
Decide by the question you are trying to answer.

| You want to know… | Reach for | Why |
| --- | --- | --- |
| *Something broke — what, where, and why?* | **Error** | An exception/crash with a stack trace, grouped into an issue. The default, always-on signal. |
| *Why is this slow? What’s the chain of calls? Did the request flow through the system as expected?* | **Span / trace** | Timing and structure of a request across services (distributed tracing). Powers performance-issue detection (N+1, slow DB). |
| *What happened leading up to this?* | **Log** | A searchable, structured, trace-connected record of discrete events. Narrative context, not timing. |
| *How many / how much / what’s the trend over time?* | **Metric** | An aggregate number (counter / gauge / distribution) for a KPI you watch and alert on. |
| *Which exact function/line is burning CPU?* | **Profile** | Code-level sampling under a traced transaction. Requires tracing on. |
| *What did the user actually see and do?* | **Session Replay** | A video-like reproduction of a frontend/mobile session around an error or UX problem. |
| *What does the user think went wrong?* | **User Feedback** | A qualitative report from a human, linked to the surrounding context. |
| *Did my scheduled job run on time?* | **Cron monitor** | Check-ins that detect missed, late, or failed recurring jobs. |

Most of these signals carry the same **trace ID**, so once one surfaces a problem you
can pivot to the others in the same request — the trace is the connective tissue that
ties errors, spans, logs, replays, and metrics together for debugging.

## Comparisons

- **Error vs. log.** An exception your code can’t handle is an **error** (capture it as
  one — it groups into an issue and gets a stack trace).
  A noteworthy thing that happened but isn’t a failure is a **log**. Don’t log-spam
  things that should be errors; don’t capture routine events as errors and pollute the
  issue stream.
- **Log vs. span.** A log answers *what happened*; a span answers *how long it took and
  what it called*. If you find yourself logging start/end timestamps to measure
  duration, you want a span instead.
- **Span vs. metric.** A span is one sampled instance of an operation (great for “show me
  a slow request”). An **Application Metric** is a numeric measurement aggregated over
  all occurrences at query time (great for “alert when p95 latency exceeds 500ms”) and,
  unlike a traditional metric, can carry high-cardinality attributes.
- **Metric vs. counting events.** Don’t emit a custom metric for something Sentry already
  derives from errors/spans (issue counts, throughput, latency percentiles, crash-free
  rate). Reserve custom metrics for **business/operational KPIs** Sentry can’t see —
  `checkout.failed`, `queue.depth`, `cache.hit_ratio`.
- **Profile rides on tracing.** Profiling is not a standalone signal — it samples
  *inside* traced transactions.
  Tracing must be on first.

## What to instrument where

- **Errors:** everywhere, always.
  This is the baseline and the first thing to get working.
- **Tracing:** the request **boundaries** first — incoming HTTP, outbound HTTP, DB /
  cache / queue. Auto-instrumentation covers most of these once tracing is on.
  Add custom spans only for meaningful business operations.
- **Logging:** a few high-signal events per request with structured attributes — not a
  firehose.
- **Metrics:** a small, deliberate set of KPIs that map to a real decision or alert.
- **Replay:** frontend (and mobile) only; high sampling on errors, low on normal
  sessions.
- **Crons:** every scheduled job whose silent failure would hurt.
- **Feature flags:** whenever the app already evaluates flags — wire evaluation tracking
  (and point at change tracking).
  Skip if there is no flag system.

When the user is unsure, ask what question they’re trying to answer and map it with the
table above. When they say “set it up properly” / “you pick the defaults,” lean on the
recommended baseline: **errors + tracing at a modest sample rate + releases + source
maps**, then add logs/replay/profiling as the use case warrants.

## Cross-cutting concepts (not signals)

These shape how the signals above behave and how you act on them — each has its own
reference:

- **Feature flags** — evaluation tracking in the SDK plus change tracking via your
  provider webhook. Not a substitute for errors/traces; context that explains whether a
  rollout caused them.
  See [`feature-flags.md`](feature-flags.md).
- **Releases** — tie every event to a deployed version.
  Unlocks regression detection, crash-free rates, suspect commits, and
  resolve-in-next-release.
- **Monitors → Issues → Alerts** — Sentry’s detection-and-response model.
  *Monitors* decide when a signal becomes an **issue**; *Alerts* act on issues.
- **Data scrubbing / PII** — what’s sensitive, and the defense-in-depth model for
  keeping it out.
- **Volume & cost** — what to keep vs.
  drop, and where to sample.
- **Search query language** — the `key:value` grammar shared by every query surface.
