---
name: sentry-create-monitor
description: Create and edit Sentry monitors and the alerts that act on them — metric monitors with fixed, percentage-change, or anomaly-detection thresholds, uptime monitors, cron monitors, mobile app-size monitors, and alerts that notify Slack, email, PagerDuty, Discord, or open a Jira/GitHub ticket. Use when asked to monitor a metric or an endpoint's uptime, set up an alert or notification, change a threshold, route issues to a channel, or list and disable existing monitors and alerts.
license: Apache-2.0
---
# Create Sentry Monitors and Alerts

Monitors decide when a signal becomes an issue.
Alerts decide what happens once it is one.

**Read [`references/concepts/monitors.md`](references/concepts/monitors.md) first** — it
is the model this skill assumes, and getting the two stages backwards is the most common
way to build something that never fires.

## Never hardcode the payload — read the live schema

The payloads are large, polymorphic, and actively changing: the alert condition catalog
alone is ~20,000 characters, its shapes vary per condition `type`, and new types ship
without notice.

So **before writing any payload, fetch the endpoint’s reference page** and build the
request from what it says.
Any page becomes plain Markdown by appending `.md`:

```bash
curl -sL https://docs.sentry.io/api/monitors.md                                    # index of all 14 endpoints
curl -sL https://docs.sentry.io/api/monitors/create-an-alert-for-an-organization.md
curl -sL https://docs.sentry.io/api/monitors/create-a-monitor-for-a-project.md
```

Those last two are the only pages carrying real payload schema — the `dataSources`
recipes per metric, the detection types, and the condition and action catalogs.
This skill carries the procedure and the traps; the reference carries the fields.

## Prerequisites

- `curl` and `python3` (or `jq`).
- **A user auth token, not an organization auth token.** Create one under User settings
  → Personal Tokens (`sntryu_…`) with `alerts:write`. Org tokens (`sntrys_…`)
  authenticate as an anonymous user, and `GET /detectors/` plus the bulk `PUT`/`DELETE`
  reject anonymous callers outright — while `POST /workflows/` accepts them, so the
  failure looks arbitrary rather than like a bad token.
  A `401` here means the wrong token type; a missing scope is a `403`.
- The org slug and its region host: `us.sentry.io`, `de.sentry.io`, or a self-hosted
  URL. A 404 on a correct-looking path is usually the wrong region.

```bash
API="https://us.sentry.io/api/0/organizations/<org>"
AUTH="Authorization: Bearer $SENTRY_USER_TOKEN"
```

## Endpoint paths

A Monitor is a `detector` in the API and an Alert is a `workflow` — the Naming section
of [`references/concepts/monitors.md`](references/concepts/monitors.md) covers why, and
why `/monitors/` is not the path you want:

| Object | Path |
| --- | --- |
| Monitor (create) | `POST /organizations/{org}/projects/{project}/detectors/` |
| Monitor (list, bulk enable/disable, bulk delete) | `/organizations/{org}/detectors/` |
| Monitor (get, update, delete) | `/organizations/{org}/detectors/{id}/` |
| Alert (list, create, bulk enable/disable, bulk delete) | `/organizations/{org}/workflows/` |
| Alert (get, update, delete) | `/organizations/{org}/workflows/{id}/` |
| Legacy Crons API — do not use | `/organizations/{org}/monitors/` |

This API is in **beta**. Expect fields to move, and re-read the reference page rather
than trusting a payload that worked last month.

### Four undocumented endpoints worth knowing

None appear in the reference, and each replaces a round of guessing:

| Endpoint | Answers |
| --- | --- |
| `GET /detector-types/` | Which monitor types this org can create. Omits `monitor_check_in_failure` even though cron monitors are creatable |
| `GET /available-actions/` | Every action type with its installed integrations **and their services** — the only source for a PagerDuty service or Opsgenie team `targetIdentifier` |
| `POST /test-fire-actions/` | Fires an action against a sample event without saving anything, so a Slack or PagerDuty route can be proven before the alert exists. Body: `{"actions": [...], "projectSlug": "..."}`. Rate limited to 10/min |
| `GET /alert-rule-workflow/?alert_rule_id=` and `GET /alert-rule-detector/?alert_rule_id=` | Maps a **legacy** alert-rule ID to its workflow or detector ID. The MCP’s `find_alert_rules` returns legacy IDs, which 404 against `/detectors/{id}/` |

### Monitor types — all four go through `/detectors/`

The reference documents `metric_issue` alone, which reads as though it is the only
monitor you can create.
It isn’t — the endpoint accepts any type registered with a validator:

| Monitor | `type` | Build it with |
| --- | --- | --- |
| Metric | `metric_issue` | The reference page — `dataSources` (query), `config` (detection type), `conditionGroup` (thresholds) |
| Uptime | `uptime_domain_failure` | **The MCP, not this API** — see Playbook B |
| Cron | `monitor_check_in_failure` | One `dataSources` entry holding the monitor’s `name`/`slug`, `owner`, and cron `config` (schedule, timezone, checkinMargin, maxRuntime, thresholds). The detector `config` is empty |
| Mobile builds | `preprod_size_analysis` | `dataSources` and `config` per its own validator |

## Step 1 — Decide what the user actually needs

Route before building.
The default monitors already exist, so a notification request usually needs **no monitor
at all**:

| The user wants | What to build |
| --- | --- |
| “Tell me in Slack when a new issue appears” | An **alert** only — Playbook A |
| “Notify me when errors spike / latency crosses 800ms / this metric goes anomalous” | A **metric monitor**, then an alert — Playbook B |
| “Is my endpoint up?” | An **uptime monitor** — Playbook B |
| “My nightly job didn’t run” | A **cron monitor** — Playbook B, plus check-ins from code via `sentry-instrument` |
| “Tell me when the app binary grows” | A **mobile builds monitor** — Playbook B |
| “Change the threshold / add a channel / rename it” | An **edit** — Playbook C |
| “Turn this off”, “clean these up” | Playbook D |

Confirm the target project and environment before writing anything.
Use the Sentry MCP (`find_organizations`, `find_projects`) if it is connected.

## Step 2 — Resolve the IDs you will need

Payloads reference users, teams, and integrations by ID, never by name.
`owner` takes the string form `user:<id>` or `team:<id>`; action targets take a bare ID.
Members and teams come from `$API/members/` and `$API/teams/`.

For anything an action needs, use `available-actions` rather than `/integrations/` — it
returns the services within each integration, which `/integrations/` does not:

```bash
curl -s "$API/available-actions/" -H "$AUTH"
```

If an integration the user asked for is absent, stop and tell them — it has to be
installed in Sentry first, and no payload can work around that.

## Playbook A — Create an alert

1. Fetch `create-an-alert-for-an-organization.md` and read the `triggers`,
   `action_filters`, and `config` sections.

2. List the monitors it should watch and note their IDs:

   ```bash
   curl -s "$API/detectors/?project=<project-slug>" -H "$AUTH" | python3 -c "
   import json,sys
   for d in json.load(sys.stdin): print(d['id'], d['type'], repr(d['name']))"
   ```

   For “any new issue in this project”, connect that project’s `error` and
   `issue_stream` monitors.

3. Build the payload: `triggers` for the issue-state changes that fire it,
   `actionFilters` for the conditions that must pass plus the actions to run,
   `detectorIds` for the monitors it watches.

4. Prove the notification route works before committing to it, via `test-fire-actions`
   above. A misrouted Slack channel or PagerDuty service is otherwise invisible until a
   real incident.

5. POST it:

   ```bash
   curl -s -w '\n%{http_code}\n' -X POST "$API/workflows/" \
     -H "$AUTH" -H 'Content-Type: application/json' -d @alert.json
   ```

   Expect `201`. The response contains the alert `id`.

Keep alerts quiet enough to be trusted — filter to what genuinely deserves a
notification, and set `config.frequency` so a noisy issue does not page repeatedly.

## Playbook B — Create a monitor

**For an uptime monitor, use the MCP and skip the rest of this playbook.**
`create_uptime_monitor` takes the url, `intervalSeconds`, `timeoutMs`, method, headers,
thresholds, and owner directly — no token, no payload assembly, and the tool schema
states the legal interval values.
`update_uptime_monitor`, `delete_uptime_monitor`, `find_uptime_monitors`, and
`get_uptime_monitor_details` cover the rest of its lifecycle, the last one returning
recent check results.
Fall back to `/detectors/` with `type: uptime_domain_failure` only if those tools are
absent.

For the other types:

1. Pick the `type` from the table above and get its payload shape — the reference page
   for a metric monitor, or an existing object of that type for cron and mobile builds:

   ```bash
   curl -s "$API/detectors/?query=type:monitor_check_in_failure" -H "$AUTH"
   ```

   **A response is not a request body.** Two fields differ: `dataSources` comes back
   wrapped as `[{id, sourceId, type, queryObj: {…}}]` and the request wants the contents
   of `queryObj` flat (for metric monitors, of `queryObj.snubaQuery`); and `owner` comes
   back as an object but must be sent as `user:<id>` / `team:<id>`.

2. Ground the threshold in real data before choosing it — query current values with
   `search_events` over the MCP, or Discover — then pick the detection type: a fixed
   threshold, a percentage change against a prior window, or dynamic anomaly detection
   when the metric is seasonal or the normal range is unknown.

3. Build `dataSources` (what to watch), `config` (how to detect), and, for metric
   monitors, `conditionGroup`. Three rules the reference does not state:

   - A resolving condition (`conditionResult: 0`) is **required** unless the condition
     is `anomaly_detection`. Omitting it fails with “Resolution condition required”.
   - At most 3 conditions.
   - `conditionResult` accepts only `75` (high), `50` (medium), and `0` (resolved).
     `25` is rejected as “Unsupported condition result”, and the reference’s priority
     table mislabels `50` as low.

4. POST to the **project-scoped** path:

   ```bash
   curl -s -w '\n%{http_code}\n' -X POST "$API/projects/<project>/detectors/" \
     -H "$AUTH" -H 'Content-Type: application/json' -d @monitor.json
   ```

5. Check `enabled` on the response.
   Uptime and cron monitors consume a seat, and on an org with none free they are
   created **disabled** instead of failing.

6. Connect it to an alert, or it will open issues silently.
   Either set `workflowIds` on the monitor or `detectorIds` on the alert — both describe
   the same link. Say which you did.

7. For a cron monitor, wire the check-ins with **`sentry-instrument`**; the monitor
   cannot report anything until the job does.

## Playbook C — Edit a monitor or an alert

**`PUT` merges — it does not replace.** Omitted top-level fields are left alone, so
`PUT {"enabled": false}` on a monitor is safe and complete (a monitor PUT needs neither
`name` nor `type`; an alert PUT requires `name`).

**But every array you send is authoritative.** An `actionFilter`, `action`, or
`condition` that exists on the object and is missing from your array is **deleted** —
`"actionFilters": []` wipes all of them.
To add a channel, echo the existing items **with their `id`s** and append the new one
**without** one.

Two specific traps:

- **Always send `enabled` explicitly on an alert PUT.** It defaults to `true`, so
  omitting it silently re-enables an alert the user just turned off.
- Re-read the response-shape warning in Playbook B before echoing a GET back.

```bash
curl -s "$API/detectors/<id>/" -H "$AUTH"        # read current state
curl -s -w '\n%{http_code}\n' -X PUT "$API/detectors/<id>/" \
  -H "$AUTH" -H 'Content-Type: application/json' -d '{"enabled": false}'
```

Editing a **system-created** monitor — the default `error`, `issue_stream`, and
performance ones — needs `org:write`; `alerts:write` alone will not modify them, though
it is enough to connect one to an alert.

Before overwriting anything a person configured, show the user the diff you intend to
apply. For read-only inspection the MCP needs no token: `find_alert_rules` and
`get_alert_rule` (legacy IDs — map them via `alert-rule-workflow` above),
`find_monitors` and `get_monitor_details` for cron, `find_uptime_monitors` and
`get_uptime_monitor_details` for uptime.

## Playbook D — Enable, disable, delete

Bulk `PUT`/`DELETE` on both collections **require** a filter — at least one of `id`,
`query`, `project`, or `projectSlug` — and 400 without one:

```bash
curl -s -X PUT "$API/detectors/?id=<id>" \
  -H "$AUTH" -H 'Content-Type: application/json' -d '{"enabled": false}'

curl -s -w '\n%{http_code}\n' -X DELETE "$API/workflows/<id>/" -H "$AUTH"
```

A `DELETE` scoped by `project` fails wholesale with a `403`, because every project
contains undeletable system monitors.
Enumerate first and delete by `?id=`. Deletes are soft — objects move to
`PENDING_DELETION` and stop appearing before they are actually gone, so a disappearance
is not proof of deletion.

Deletes are destructive and a filter can match more than you expect.
List the exact objects a filter selects and get the user’s confirmation before issuing
one.

## Wire-format traps

- **`comparison` is polymorphic.** Its shape is dictated by the condition `type` — a
  bare integer for a priority threshold, a bare boolean for a trigger, an object for a
  frequency or tag condition.
  Copy the shape from the reference page for that exact type.
- **`conditionResult` means different things per stage.** On an alert condition it is a
  boolean — set `false` to invert.
  On a monitor’s `conditionGroup` it is the issue priority the threshold opens at, with
  `0` resolving the issue.
- **`triggers.actions` is always `[]`.** Actions live in `actionFilters[].actions`; the
  trigger validator does not declare an `actions` field, so anything you put there is
  dropped silently rather than stored and skipped.
- **`triggers.logicType` must be `any-short`** whenever the group contains a real
  trigger condition. Filter groups additionally accept `all`, `any`, and `none`.
- **`config` on an alert takes `frequency` and nothing else** — any other key 400s.
  `frequency` is any integer ≥ 0, in minutes; the value list on the reference page is
  the UI’s presets, not a constraint.
- **camelCase and snake_case both work** — the serializer converts the whole body
  recursively, so the reference’s snake_case names can be sent verbatim.
  What matters is never sending both spellings of one key (that 400s with “collides
  with”), and that errors always come back camelCased regardless of what you sent.

## Step 3 — Verify

A `201` on a create (or `200` on an update) means the payload parsed, not that it does
what was asked. Read the object back and confirm the conditions and actions match:

```bash
curl -s "$API/workflows/<id>/" -H "$AUTH"
```

**Two ways an alert is silently dead**, neither of which produces an error:

- It only evaluates issues from its **connected detectors**. A workflow with no
  `detectorIds` is org-level and never fires.
- Its `environment`, if set, must match the event’s exactly.
  Leave it `null` to match every environment.

Then surface the UI links: `https://<org>.sentry.io/monitors/` for the list,
`/monitors/<id>/` for one monitor, `/monitors/alerts/<id>/` for one alert.
If the org lacks the new Monitors and Alerts UI, alerts appear under
`https://<org>.sentry.io/alerts/rules/` instead.

For a metric monitor, tell the user it only opens an issue once the threshold is
genuinely crossed — there is no test-fire for detection, so nothing appearing yet is
expected rather than a misconfiguration.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| 401 | Organization auth token — swap it for a user token (see Prerequisites) |
| 403 on a write | Token lacks `alerts:write`, or the target is a system-created monitor needing `org:write` |
| 403 on a bulk delete | The filter matched undeletable system monitors; delete by `?id=` |
| 404 on a valid path | Wrong region host, wrong slug, or a legacy alert-rule ID used as a detector ID |
| 400 “Resolution condition required” | Metric monitor `conditionGroup` has no `conditionResult: 0` |
| 400 “Unsupported condition result” | Priority other than `75`, `50`, `0` |
| 400 “collides with” | The same key sent in both camelCase and snake_case |
| 400 naming a field you sent | Re-read that field on the reference page; check the `comparison` trap |
| 400 on an unrecognized `type` | Not available to this org — `GET /detector-types/` lists what is |
| Update wiped actions or filters | An array you sent omitted existing items; echo them with their `id`s |
| Disabled alert came back on | `enabled` omitted from the PUT; it defaults to `true` |
| Monitor created but disabled | No seat available for an uptime or cron monitor |
| Monitor opens issues, nobody is notified | No alert connected — set `workflowIds` or `detectorIds` |
| Alert exists but never fires | No `detectorIds`, a mismatched `environment`, or a filter excluding everything |
