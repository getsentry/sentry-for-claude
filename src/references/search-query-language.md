# Search Query Language

Sentry’s `key:value` search grammar.
It’s the **shared vocabulary** for every query surface — the Issues stream, Explore,
Dashboards, alert/monitor conditions, and the MCP tools.
Authoring a good query (and reading one back) is the same skill everywhere, so the
grammar lives here once.

> The web UI auto-completes these as you type.
> You need the raw syntax for the API, saved queries, alerts, and dashboards.
> The MCP accepts it *or* natural language, but rewrites both — see
> [Through the MCP](#through-the-mcp).

## Grammar

A query is a space-separated list of **tokens**. Each token is either a `key:value` pair
or a single piece of **raw text** (matched against the event title/message with a
CONTAINS match).

```
is:unresolved user.username:"Jane Doe" server:web-8 example error
```

That’s four tokens: `is:unresolved`, `user.username:"Jane Doe"`, `server:web-8` (a
custom tag), and the raw search `example error`.

### Rules

- **Quote values with spaces:** `user.username:"Jane Doe"`.
- **Implicit `AND`:** space-separated tokens are intersected (all must match).
- **Negation:** prefix with `!` to exclude — `!user.email:test@example.com`,
  `!message:"*Timeout"`.
- **Comparison operators** on numbers/durations/dates: `>`, `<`, `>=`, `<=`, placed
  after the `:` for numeric/duration fields (an exact `:` match rarely exists):
  - `transaction.duration:>5s`
  - `count_dead_clicks:<=10`
  - `event.timestamp:>2023-09-28T00:00:00-07:00` (Issues; elsewhere the key is
    `timestamp`)
- **Value lists** (OR on one key): `release:[12.0, 13.0]` ≡
  `release:12.0 OR release:13.0`. Wildcards work inside a list.
  Not allowed with `is:` — a list desugars to `OR`, which the Issues search rejects.
- **Wildcards:** `*` matches any characters — `browser:"Safari 11*"`,
  `!message:"*Timeout"`.
- **`has:`** — field/tag exists regardless of value: `has:user`. Negate as `!has:`.
- **`is:`** — issue **state** (see catalogs below), on both the Issues stream and the
  errors dataset; not usable with value lists.
- **Explicit tag syntax** when a tag name collides with a reserved key:
  `tags[project_id]:value`.

### `AND` / `OR` / parentheses

`OR`, `AND`, and grouping `()` are available in **Discover, Dashboards, and Monitors**
(not the basic Issues search):

```
browser:Chrome OR browser:Opera
release:13.0 AND (transaction.duration:>2s OR http.status_code:500)
```

- `AND` binds tighter than `OR`: `x AND y OR z` ≡ `(x AND y) OR z`. Use parens to
  override.
- `AND` may join a non-aggregate with an aggregate; **`OR` may not** mix the two.
  `user.username:jane OR count():>100` is invalid.

### Aggregate conditions (functions)

On aggregating surfaces (Discover/Dashboards), function keys filter on computed values.
The function still needs a value/filter even when it takes no parameter:

```
count():>100
count_unique(user):>=20
p95(transaction.duration):>500ms
failure_rate():>0.05
epm():>12
count_if(transaction.duration,greater,1000):>5
```

### Relative time / age

`age:` (and `firstSeen`/`lastSeen`) use Unix-find-style offsets — suffixes
`m`/`h`/`d`/`w`:

- `age:-24h` — created in the last 24 hours.
- `age:+12h` — older than 12 hours.
- `age:+12h age:-24h` — created between 12 and 24 hours ago.

> The MCP doesn’t know `age:` and rewrites it to `firstSeen:`, flipping `+` to `-` —
> which silently reverses “older than”.
> Use `firstSeen:` / `lastSeen:` directly there.

* * *

## Searchable properties by dataset

Search terms only validate against the **dataset** you’re querying — a span key won’t
work in Issues, etc.
The catalogs below are the common keys per dataset.
(Any **custom tag** your SDK sets is also searchable as a key; use `tags[name]:value` if
the name collides with a reserved one.)

### Issues (the Issues stream)

State & triage: `is:` (`unresolved`, `resolved`, `archived`, `assigned`, `unassigned`,
`for_review`, `linked`, `unlinked`), `assigned`, `assigned_or_suggested`, `bookmarks`
(values: an email, `me`, `none`, `my_teams`, `#team-name`).

Identity & grouping: `issue` (short code, e.g. `SENTRY-ABC`), `issue.category` (`error`,
`performance`, `frontend`, `outage`), `issue.type` (e.g.
`performance_n_plus_one_db_queries`), `title`, `message`, `culprit`, `location`.

Counts & age: `timesSeen` (= `count()`), `age`, `firstSeen`, `lastSeen`,
`event.timestamp`.

Release/version: `release`, `firstRelease` (supports `latest`), `release.version`,
`release.build`, `release.package`, `release.stage` (`adopted`/`low`/`replaced`),
`dist`.

Error shape: `error.handled`, `error.unhandled`, `error.type`, `error.value`,
`error.mechanism`, `error.main_thread`, `level`, `event.type`.

Stack: `stack.filename`, `stack.function`, `stack.module`, `stack.package`,
`stack.abs_path`.

Request/user/device/geo: `http.method`, `http.status_code`, `http.url`, `http.referer`,
`user.id`, `user.email`, `user.username`, `user.ip`, `device.*`, `os.*`, `geo.city`,
`geo.country_code`, `geo.region`, `platform.name`, `sdk.name`, `sdk.version`.

Other: `project`, `project.id`, `transaction`, `trace`, `flags["my_flag"]:true` /
`flags["my_flag"]:false` (boolean feature-flag evaluations from SDK evaluation tracking
— see concepts/feature-flags.md), `has`.

### Events (Discover, error + transaction events)

> The MCP has no transaction-events dataset (`errors`, `logs`, `spans`, `metrics`,
> `profiles`, `replays`) — query transactions as `spans` with `is_transaction:true`.

Everything in Issues that’s event-level, plus **aggregate functions**: `count()`,
`count_unique(field)`, `count_if(column,operator,value)`,
`count_miserable(field,threshold)`, `count_web_vitals(vital,threshold)`, `avg(field)`,
`min`/`max`/`sum(field)`, `percentile(field,level)`, `pXY(duration field)` (e.g. `p95`),
`apdex(threshold)`, `failure_count()`, `failure_rate()`, `user_misery(number)`,
`last_seen()`, `epm()`, `eps()`.

Transaction/perf: `transaction`, `transaction.duration`, `transaction.op`,
`transaction.status`, `measurements.lcp` / `.fcp` / `.fid` / `.cls` / `.ttfb` (web
vitals), `measurements.app_start_cold` / `.app_start_warm`, `measurements.frames_*`,
`measurements.stall_*`, `spans.db` / `.http` / `.browser` / `.resource` / `.ui`.

Trace linking: `trace`, `trace.span`, `trace.parent_span`. Time bucketing:
`timestamp.to_hour`, `timestamp.to_day`. Plus `environment`, `device.class`, full
`stack.*` (incl. `stack.lineno`, `stack.colno`, `stack.in_app`), `user.display`.

### Spans (Trace / Span Explorer)

`span.op` / `op`, `span.description` / `description`, `span.duration` / `duration`,
`self_time`, `module`, `group`, `action`, `domain`, `system`, `status`, `status_code`,
`trace.status`, `transaction`, `transaction.op`, `transaction.method`, `cache.hit`,
`file_extension`, `resource.render_blocking_status`, `http.response_content_length` /
`.decoded_response_content_length` / `.response_transfer_size`,
`messaging.destination.name`, `messaging.message.id`, `release`, `environment`,
`browser.name`, `os.name`, `device.class`, `platform`, `sdk.name`, `sdk.version`,
`user.id` / `.email` / `.username`.

### Logs

Logs search on the log `message`, `severity` (`level` is the errors/issues key),
`timestamp`, the trace it belongs to (`trace`), and any **structured attributes** you
attached (searched as keys).
Plus the common context keys (`release`, `environment`, `project`).

### Session Replay

Counts/quality: `count_errors`, `count_dead_clicks`, `count_rage_clicks`, `count_urls`,
`count_segments`, `count_traces`, `activity`, `duration`.

Clicks: `click.tag`, `click.id`, `click.class`, `click.role`, `click.label`,
`click.textContent`, `click.title`, `click.testid`, `click.component_name`,
`click.selector`, `click.alt`, `dead.selector`, `rage.selector`.

Session/identity: `id`, `replay_type`, `url`, `screen`, `trace`, `error_ids`,
`is_archived`, `seen_by_me`, `level`, `dist`, `release`, `platform`, `browser.name`,
`browser.version`, `os.name`, `os.version`, `device.*`, `user.id` / `.email` /
`.username` / `.ip`, `user.geo.city` / `.country_code` / `.region` / `.subdivision`,
`sdk.name`, `sdk.version`, `project_id`.

### User Feedback

`is`, `assigned`, `id`, `level`, `message`, `url`, `transaction`, `timestamp`,
`environment`, `browser.name`, `os.name`, `device.brand` / `.family` / `.model_id` /
`.name`, `dist`, `user.id` / `.email` / `.ip` / `.username`, `sdk.name`, `sdk.version`.

### Releases

`release`, `release.version`, `release.build`, `release.package`, `release.stage`
(`adopted` / `low` / `replaced`). Pick the newest with `release:latest`.

* * *

## Where this language is used

- **Reading data** — issue search and event/Discover queries locate and slice data with
  this grammar; natural-language questions are translated into it.
- **Authoring monitors & dashboards** — alerts, metric monitors, and dashboards are
  authored as saved queries in this grammar.

## Through the MCP

`search_events` and `search_issues` accept either natural language or this grammar, but
there is no raw query path — both run your input through an LLM that rewrites fields to
fit the target dataset.
**What you write is not necessarily what runs**, it isn’t reproducible between calls,
and a rewrite into invalid syntax surfaces as a confusing API error rather than a
rejection of your query.

So read back what executed: `search_events` always prints an `## Executed Search` block,
and `search_issues` prints nothing unless you pass `includeExplanation: true`. Both
tools also take a `period` argument that intersects with any time filter in the query
rather than overriding it — `search_issues` defaults to 30 days.

## Pitfalls

- A key from the wrong dataset fails loudly in the UI/API, but **silently through the
  MCP** — either substituted or run as-is for **zero results with no error**. An empty
  result set isn’t evidence of no data; check `## Executed Search`.
- Using `:` instead of a comparison operator on a numeric/duration/date field.
- Expecting `OR`/`AND` in the basic Issues search (only Discover/Dashboards/Monitors).
