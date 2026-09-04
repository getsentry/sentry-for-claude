# Cron / Scheduled-Job Monitoring — What & Why

Monitoring for recurring jobs — cron jobs, scheduled tasks, queue workers.
Sentry watches for runs that are **missed**, **late**, **timed out**, or **failed** and
turns those into issues.
It works via **check-ins**: the job reports `in_progress` when it starts and
`ok`/`error` when it finishes; a run that never checks in (or checks in late) is flagged
against the monitor’s schedule.

Reach for it where **silent failure is dangerous** — a nightly billing run, a data sync,
a backup — and “it didn’t run” is as bad as “it crashed.”

## Why a cron issue often isn’t where you’d look

- **A “missed” issue frequently isn’t in the job code.** Missed means no check-in
  arrived in the expected window — commonly the **scheduler** (misconfigured, skipped,
  never started the job), a **network** problem (outbound firewall, flaky connection),
  or a timeout. Don’t assume the job body threw.
- **The real exception is a separate error event on the same trace.** If the SDK is
  configured, errors thrown during the run are captured as normal error events and tied
  back to the check-in through the run’s trace — follow the trace from the cron issue to
  find them.
- **Issue creation is threshold-gated,** not per-failure: `failure_issue_threshold` (N
  consecutive failures before an issue opens) and `recovery_threshold` (N consecutive
  OKs before it resolves).
  A single failure may not create an issue.
- **Absence of alerts ≠ healthy.** A monitor broken for weeks gets auto-muted — it stops
  producing issues and notifications while billing continues.
  A silent monitor may be muted, not passing.

## Setup essentials

- **Monitor config is data** (server-side): the schedule (crontab — 5-field only — or
  interval), the **`timezone`**, **`checkin_margin`** (how late counts as missed), and
  **`max_runtime`** (how long counts as hung).
  Set the last two to the job’s real timing — tight enough to catch a hang, loose enough
  to avoid false alarms.
- **Check-ins are code** (SDK-side).
  Paths: the SDK **`withMonitor` / decorator** wrapper (cleanest when an SDK is present
  — sends both start and outcome), an **HTTP check-in** (any language, ideal for shell
  crontabs), or **`sentry-cli`** wrapping a shell command.
  Wrap the **whole job** so both success and failure report; a bare heartbeat (single
  `ok`/`error`) detects *missed* but not *`max_runtime`* timeouts.
- **Use a stable, descriptive slug** (`nightly-invoice-sync`, not `job-1`) — it’s the
  check-in key, so slug churn on every deploy orphans monitors.
- **Two ways to declare the config.** The SDKs take a `monitor_config` alongside the
  check-in and upsert the monitor from it, which keeps the schedule in version control
  next to the job it describes — usually the one to prefer while instrumenting.
  Otherwise create the monitor through the detectors API ([`monitors.md`](monitors.md)),
  never the legacy `/organizations/{org}/monitors/` one.
  Either way the monitor stays silent until check-ins arrive.

## Related

- [`monitors.md`](monitors.md) — a cron monitor is one kind of Monitor that creates
  issues.
