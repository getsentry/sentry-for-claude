# First-error setup (one real error, end to end)

The shared spine for getting a brand-new project reporting to Sentry — detect the
platform, provision a project, install the SDK with sane defaults, and confirm a real
error lands.
Any flow that starts from zero runs this; it exists so the sequence lives in
exactly one place.

This file owns the **order**, not the details.
Each step hands off to the reference that owns it — follow that reference, then come
back. Don’t re-derive what those files already cover.

> [!NOTE]
> If “onboarding status updates” has not been defined by the skill that led you here,
> ignore the onboarding notes below.
> They do not apply to this setup.

## Step 1 — Detect the platform

> [!NOTE]
> If you are sending onboarding status updates, this stage is `analyze_project`: inspect
> the application and identify its platform, SDK, and setup needs.
> Report `active` before inspection unless the calling skill already started this stage,
> `waiting` before asking for confirmation, and `completed` once the platform and
> current Sentry setup are understood.
> This stage is unskippable.

Read [`sdks/index.md`](sdks/index.md) for the catalog and detection rules.
Identify the platform from project files (`package.json`, `go.mod`, `requirements.txt`,
`Gemfile`, `*.csproj`, `build.gradle`, `pubspec.yaml`, …), **tell the user what you
found and confirm** — don’t assume from files alone — then open that platform’s
`sdks/<slug>/index.md`, `sdks/<slug>/error-monitoring.md`, and `sdks/<slug>/tracing.md`.

## Step 2 — Provision a project + DSN

> [!NOTE]
> If you are sending onboarding status updates, this stage is `create_project`: select
> an existing Sentry project or create one and obtain its DSN. Report `waiting` before
> requesting creation approval.
> Keep it `active` while selecting or provisioning every planned project, and report
> each validated slug in `update.extra.projectSlugs` as its DSN becomes usable.
> Report `completed` once all planned projects are usable, including all known validated
> slugs. For one existing project, complete it with `update.extra.projectSlugs` and
> `update.eventNote: Project already existed.` Do not complete the stage per project.
> This stage is unskippable.

Follow [`new-project.md`](new-project.md).
Determine via the MCP whether a fitting project already exists; select it and read its
DSN, or create one (propose `create_project` and create on a yes, never silently).
Either way you come back with the DSN to use in `init`.

## Step 3 — Install the SDK with sane defaults

> [!NOTE]
> If you are sending onboarding status updates, this stage is `instrument_app`: install
> and configure the Sentry SDK in the application.
> Report `active` immediately before changing SDK files and `completed` only after
> installation and initialization finish.
> This stage is unskippable.

Following the platform references, install the SDK and write `init` using the DSN from
Step 2. Take the SDK reference’s **recommended default setup** as written — in practice
errors and tracing.
Don’t ask the user which signals to enable, and don’t pare it back to
errors-only; the reference’s default `init` is the best-practice baseline for a new
project.

## Step 4 — Verify end to end

> [!NOTE]
> If you are sending onboarding status updates,
> [`setup-verification.md`](setup-verification.md) covers three unskippable stages:
> 
> - `plan_test_error`: choose a representative test error and plan how to trigger it
>   safely. Report `active` while planning, `waiting` for required input or permission,
>   and `completed` when the path is ready.
> - `send_verification_error`: trigger the planned error in the instrumented
>   application. Report `active` before running it, `waiting` when it cannot yet run, and
>   `completed` once the error is triggered.
> - `receive_verification_error`: wait for Sentry to ingest and return the error.
>   Keep it `active` or `waiting` while checking ingestion.
>   Report each MCP-confirmed issue/group identifier in `update.extra.issueIds`, and
>   report `completed` only after every project being verified has a confirmed result.
>   Never include event IDs.

Close the loop with [`setup-verification.md`](setup-verification.md): run the **real**
application, make it throw a genuine error through its actual init/code path (a
temporary real trigger in the app is fine — never a standalone script that bypasses
init), poll the MCP until the error appears, and **show the user what came back from the
MCP — the issue title, the error message/value, and the direct issue URL — not just the
link**, then confirm it’s verified end to end.
Not done until the real error is seen in Sentry.

## Step 5 — Get it into production — this is the point

> [!NOTE]
> If you are sending onboarding status updates, this stage is `prepare_production`:
> prepare the instrumentation and release configuration for production.
> Report `active` when production work begins, `waiting` before requesting deployment
> approval, and `completed` once configuration is ready or the user chooses a concrete
> next action. This stage is unskippable.
> If deployment is deferred, use a concise note stating the agreed next step.

A verified local error just proves the wiring works; the value is capturing errors from
*real users*. Don’t end on “it works locally.”
**Work with the user to get it into production — advocate for it plainly, but don’t take
deploy actions without their consent:**

- **If you already have context on how this project deploys** — a CI/CD config, a deploy
  script, a Dockerfile/Procfile, a hosting platform (Vercel, Fly, Render, Heroku, …), or
  a deploy section in `AGENTS.md`/`CLAUDE.md` — use it.
  Walk the user through (or offer to make) the changes to ship the Sentry-instrumented
  build, making sure the DSN and the `release`/`environment` values are set in the
  production environment, not just locally.
  [`releases/index.md`](releases/index.md) routes to the per-platform way to set those
  two — do it here rather than leaving events tagged “unknown release”; it is a
  one-option change, and every release feature depends on it.
- **Otherwise**, advocate plainly and ask: getting Sentry into production is the most
  important next step because real user errors are where the payoff is — how do you
  deploy this, and can I help wire it in?

## Step 6 — Make sure production stack traces will be readable

> [!NOTE]
> If you are sending onboarding status updates, this stage is
> `check_stack_trace_quality`: check source maps or debug symbols and confirm stack
> traces are readable.
> Report `active` before inspection and `completed` with `update.runStatus: completed`
> after the checks and accepted work finish.
> If the user declines artifact work, complete the stage once the decision and any
> agreed next step are clear.
> Report `skipped` with `update.runStatus: completed` only when the detected platform
> needs no source-map or debug-artifact work.
> This stage is optional only in that case.

Local frames often look fine while production builds mangle them — minified JavaScript,
stripped native symbols — so an issue from a real user can be unreadable even though the
verified test error wasn’t. This is per-platform: the platform’s `sdks/<slug>/index.md`
("Platform considerations") names what *this* stack needs — e.g. **source maps** for
JavaScript/TypeScript, **debug symbols** (dSYM, ProGuard/R8) for native/mobile.
Frame it proactively, tied to the platform you detected:

> “Now that this is heading to production — since you’re on <platform>, we’ll want
> <source maps / debug symbols / …> so real-user stack traces stay readable.
> Here’s what that takes.”

If the user wants it done now, [`debug-artifacts/index.md`](debug-artifacts/index.md)
routes to the procedure for this platform’s artifact family — you don’t have to hand the
task off. Wiring it into the build here is cheaper than diagnosing an unreadable
production trace later.

Also **scrutinize the verified issue**: pull it with `get_sentry_resource` and check the
frames show actual source (file, line, function), not minified or unsymbolicated noise.
Degraded frames even locally are a strong signal production will be worse.

## What “done” looks like

The SDK is installed with sane defaults (errors + tracing), a **real error produced by
the running app** has been confirmed in Sentry via the MCP (its title, error message,
and issue URL surfaced to the user), **the user has been worked toward getting it into
production** (with their consent — no deploy without it), and **production stack-trace
quality has been addressed** (the per-platform source maps / debug symbols flagged, and
the produced issue’s frames scrutinized).
A local-only setup isn’t the finish line.
