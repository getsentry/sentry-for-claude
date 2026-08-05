# Monitors → Issues → Alerts — The Model

Sentry separates **what you detect** from **what you do about it**, in three stages —
**Monitors** detect, **Issues** are the unit you triage, and **Alerts** respond:

- A **Monitor** decides *when* a signal becomes an **issue**.
- An **Issue** is the unit you triage — a grouped, stateful object (status, priority,
  assignee, history).
- An **Alert** decides *what to do* once an issue matches its conditions — notify Slack,
  page someone, open a ticket, hit a webhook.

Monitors detect; Alerts respond.
They’re configured independently: one alert can watch many monitors/projects, and one
monitor can feed several alerts.

## Naming — the product and the API disagree

The API kept the engine’s original vocabulary while the product settled on this one.
Every mismatch below shows up in something you will read — a URL, a response body, an
API reference page, an older doc — so learn them before touching the API:

- **A Monitor is a `detector` in the API.** The endpoints are
  `/organizations/{org}/detectors/`, and every monitor type is one: `metric_issue`,
  `uptime_domain_failure`, `monitor_check_in_failure` (cron), `preprod_size_analysis`
  (mobile builds), plus the auto-created `error` and `issue_stream`. The API reference
  files these pages under “Monitors & Alerts” while every URL in them says `detectors`.
- **`/organizations/{org}/monitors/` is the legacy Crons API — don’t use it.** It is the
  path you would guess from the word “monitor,” it predates this model, and it reaches
  cron monitors alone.
  Those same cron monitors are detectors, so `/detectors/` manages them along with every
  other type.
- **An Alert is a `workflow` in the API** — `/organizations/{org}/workflows/`, named for
  the workflow engine that evaluates it.
- **“Metric alert” means Metric Monitor.** Older docs and integrations use the old name
  for the detection stage; treat them as the same thing.
  The rename isn’t fully settled across the product.

## Monitors — when a signal becomes an issue

- **Default monitors** — auto-created per project: the **Issue Stream Monitor** and
  **Error Monitor** (the error-detection / grouping pipeline).
  Nothing to set up; worth knowing they’re “monitors” in this model.
- **Custom monitors:**
  - **Metric Monitor** — a threshold on errors / spans / logs / releases / Application
    Metrics; the threshold can be **fixed**, a **percentage change** vs.
    a prior window, or **dynamic anomaly detection**. Often created straight from a
    saved Discover or Metrics-Explorer query.
  - **Cron Monitor** — a scheduled-job watch via check-ins ([`crons.md`](crons.md)).
  - **Uptime Monitor** — periodic HTTP checks against a URL.
  - **Mobile Builds Monitor** — app-size thresholds across iOS/Android builds.

**Monitor config also sets issue attributes at creation** — priority, auto-resolve, and
assignee (ownership rules can override the assignee).
The monitor decides not just *that* something becomes an issue but *how important* it is
and *who owns it*.

## Alerts — acting on issues

An alert is **sources → triggers → filters → actions**:

- **Sources** — which projects/monitors it watches.
- **Triggers** — which issue-state changes fire it (new, regression, reappearance,
  resolved); triggers are OR’d.
- **Filters** — conditions the issue/event must match before actions run (priority,
  frequency, tags, assignment, age); filter groups can be ANY or ALL. **If an issue
  exists but no alert fired, a filter is usually why.**
- **Actions** — Slack, email, PagerDuty, Discord, Jira, webhook, …

## When to reach for what

- *“Tell me in Slack when a new issue shows up”* → an **Alert** (the default error
  monitor already makes the issues).
- *“Alert when error rate / latency / a metric crosses a line”* → a **Metric Monitor**,
  then an alert.
- *“My nightly job didn’t run”* → a **Cron Monitor**. *“Is my endpoint up?”* → an
  **Uptime Monitor**.

## Coverage honesty

Alerts and **every custom monitor type** are creatable and editable end-to-end through
Sentry’s workflow-engine API — metric, uptime, cron, and mobile builds monitors are all
detectors there.
Only the metric payload has an API reference page, so building the other
three means mirroring the shape of an existing monitor of that type; the accepted types
also depend on what is enabled for the organization.

Two things the API alone doesn’t finish.
A **Cron Monitor** is inert until the job sends check-ins, which is instrumentation work
— and because the SDKs upsert a monitor from the `monitor_config` they send with a
check-in, a cron monitor can be defined entirely from code, keeping the schedule in
version control beside the job it describes.
**Uptime** and **Cron** monitors also consume a seat, so on an org with none free they
are created **disabled** rather than rejected.

**Uptime monitors are the exception to reaching for the API at all** — the MCP creates,
updates and deletes them directly (`create_uptime_monitor` and friends), which needs no
auth token and no hand-built payload.
For everything else the MCP is read-only: it inspects alert rules (`find_alert_rules`,
`get_alert_rule`), cron monitors and their check-ins (`find_monitors`,
`get_monitor_details`), and uptime check results (`get_uptime_monitor_details`) — useful
for verifying after creation, but with no create or update path.
Note that the alert-rule tools return **legacy** rule IDs, which are not detector or
workflow IDs.

## Related

- [`crons.md`](crons.md)
- [`metrics.md`](metrics.md)
- [`releases.md`](releases.md)
- [`search-query-language.md`](../search-query-language.md)
