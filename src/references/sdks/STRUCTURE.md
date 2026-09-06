> [!WARNING]
> THIS IS AN INTERNAL DOCUMENT. It is not part of the reference content itself — it
> exists only for the development and maintenance of the SDK references.
> Skip it during normal use.

# `sdks/[sdk]/` structure

This document is the contract every SDK reference tree must follow.
It exists so that all 19 SDKs read the same way and a reader can predict exactly where a
given piece of information lives.
When you add or edit an SDK reference, conform to this — don’t invent a per-SDK shape.

These references are the platform **HOW** — install commands, `Sentry.init()` options,
and the code to wire up each signal.
They are **standalone**: a reference must not reference or link to a skill, nor to
reference docs in another domain (e.g. the `concepts/` strategy docs).
The skill that loads a reference supplies the surrounding WHY and orchestration; the
reference stays focused on the code.
The only links a reference carries are to **sibling files within the SDK tree** and to
**external documentation**.

## Directory layout

Each SDK gets one directory under `sdks/`, named by its **slug** (the `SDK slug` column
in [`index.md`](./index.md) — lowercase, no `sentry-` prefix, no `-sdk` suffix, e.g.
`nextjs`, `react-native`):

```
sdks/[sdk]/
  index.md                  # required — overview, detect, install, init, feature catalog
  error-monitoring.md       # required — every SDK supports it
  tracing.md                # one file per SUPPORTED canonical signal
  logging.md
  profiling.md
  metrics.md
  crons.md
  session-replay.md
  user-feedback.md
  ai-monitoring.md
  <extension>.md            # optional — platform-specific topics (see below)
```

Create a signal file **only if the SDK supports that signal.** Unsupported signals are
not files — they are listed in `index.md`’s catalog table marked as not available (see
below).

## The WHAT vs HOW rule

These references are the **HOW** — install commands, `init` options, and the code to
wire up a signal on this platform.
They are **not** the place for strategy.

- Best practices, when-to-use, sampling philosophy, naming conventions, and pitfalls do
  **not** live here, and the reference does **not** link out to them.
  Omit them — the skill that loads this reference supplies that context.
  If you find yourself writing a paragraph that would be true on every platform, cut it.
- Genuinely platform-specific guidance (e.g. “Celery needs dual-process init”, “ProGuard
  mappings must be uploaded for readable native frames”) *does* belong here — it is HOW,
  not generic strategy.

## What does NOT live here

Some setup is not owned by a platform tree at all — project/DSN provisioning, the
verify/confirm loop, source maps / debug symbols, releases, data scrubbing, and volume
tuning.
Keep these out of the SDK references entirely; do not document or link them here.
Source maps and debug files (dSYM, ProGuard/R8, NDK symbols, Dart obfuscation maps) live
in `references/debug-artifacts/` — the upload procedure and artifact matching are all
there, per family. Releases live in `references/releases/` — naming, the per-platform
`release`/`environment` tag, the CI pipeline, commit association, and suspect commits.
The build-time auth token both groups need is `references/auth-token.md`. The one
exception is the **SDK-side hook** for those topics — the `authToken` line,
`beforeSend`, sample-rate options, the `release` / `environment` `init` options — which
may appear as a normal config option, described in place without a pointer to any other
doc.

## Canonical signals

This is the fixed, ordered set.
Use these exact filenames and section titles.
Order matters: it is the order the catalog table and any walkthrough should follow.

| Order | Signal title | Filename | Notes |
| --- | --- | --- | --- |
| 1 | Error Monitoring | `error-monitoring.md` | Always supported. The baseline. |
| 2 | Tracing & Performance | `tracing.md` |  |
| 3 | Logging | `logging.md` |  |
| 4 | Profiling | `profiling.md` | Requires tracing. |
| 5 | Metrics | `metrics.md` |  |
| 6 | Cron Monitoring | `crons.md` | Check-in code only. |
| 7 | Session Replay | `session-replay.md` | Browser and mobile only. |
| 8 | User Feedback | `user-feedback.md` |  |
| 9 | AI / LLM Monitoring | `ai-monitoring.md` | Platforms with LLM-SDK auto-instrumentation. |

Do not add a canonical signal without updating this table and the catalog in `index.md`.

## Platform-extension files

Topics that aren’t one of the canonical signals but are specific to a platform get their
own file with a descriptive slug, linked from `index.md`. Examples already in the tree:

- `integrations.md` / `ecosystem-integrations.md` (Android, Flutter)
- `feature-flags.md` — evaluation tracking + pointer to change tracking (supported
  platforms only; not a canonical signal)
- `laravel.md`, `symfony.md` (PHP)
- `durable-objects.md` (Cloudflare)
- `react-features.md`, `react-router-framework-features.md`, `tanstackstart-features.md`
- `expo-config-plugin.md` (React Native)
- `migration.md` (Ruby)

Keep these focused. If an extension grows to cover a canonical signal, move that content
into the signal file and cross-link.

## `index.md` format

The front door for an SDK — read first, every time.
Sections, in order:

1. **Title** — `# Sentry <Platform> SDK`

2. **What this SDK applies to** — the scope of the SDK so a reader can confirm it is the
   right one: the runtimes/languages it covers, the frameworks and libraries it
   supports, the package name(s) it ships as, and when to pick a sibling SDK instead
   (e.g. “use `nextjs` for Next.js apps, not this”). A link to the platform’s docs
   (`https://docs.sentry.io/platforms/<...>/`) and a version note belong here.
   **If the SDK has more than one target** (multiple runtimes, platforms, or tooling
   variants — see “Multi-target SDKs”), enumerate them here by name; everything
   downstream refers back to these names.

3. **Confirm & inspect** — two jobs: (a) *confirm this is the right reference* — quick
   checks that the project really matches this SDK, and a pointer to the sibling SDK’s
   `index.md` if it doesn’t (e.g. “found `@nestjs/core` → use `../nestjs/index.md`
   instead”); and (b) *inspect the specifics* that change the setup — framework/variant,
   task queue, AI libs, existing Sentry install, companion frontend/backend — with the
   shell commands to find each and what the finding implies.

4. **Recommend** — a concrete proposal, not open questions: a matrix mapping each
   feature to “recommend when…” and its reference file.
   Write it so it is easy to skip — it must not be a prerequisite for reading an
   individual signal file.

5. **Installation** — how to add the SDK as a project dependency: package name(s), the
   package-manager command(s) for that ecosystem, where the dependency is declared, and
   any framework-specific extras.
   This covers *only* getting the package installed — wiring up `init` is next.

6. **Quick Start `init`** — the recommended initialization snippet with sensible
   defaults and where it must be placed.
   A placeholder DSN (like `___DSN___`) is fine in the reference text.
   This is the minimal-but-good starting point; deeper per-signal config lives in the
   signal files.

7. **Where to initialize** — *where and when* `init` should run for this platform, and
   why placement matters (e.g. “before any other import,” “before the app/server is
   created,” “in each worker process”). Cover the common cases inline; defer deep
   framework-specific placement to that framework’s extension file and link out.

8. **Feature catalog** — the table linking every canonical signal to its file or marking
   it unsupported (see next section).
   The routing hub.

9. **Configuration Reference** — key `init` options and environment variables in a
   table.

10. **Platform considerations** — the things unique to this platform that must be
    handled for Sentry to actually work well — the gotchas obvious to a platform expert
    but easy to miss. Most common are the steps for a *readable* event:

    - **JavaScript/TypeScript** — source maps must be configured or stack traces stay
      minified.
    - **Native / mobile** (Apple, Android, NDK) — debug symbols must be uploaded (dSYM,
      ProGuard/R8 mappings, etc.)
      or frames stay unsymbolicated.

    These are only examples — generalize to whatever this platform needs that others
    don’t (build steps, release/dist matching, runtime quirks, permissions, init
    ordering, packaging/deploy).
    List each with what happens if skipped.
    Don’t omit this section just because a platform “seems straightforward” — if there
    is genuinely nothing, say so.

11. **Cross-link** — companion projects to suggest (e.g. a backend SDK for a frontend
    install), linking the sibling tree’s `index.md`.

12. **Troubleshooting** — a symptom → solution table.

### The feature catalog table

`index.md` lists **all** canonical signals so coverage is explicit.
The `Status` column takes one of three forms:

- **`Supported`** — available on every target this SDK covers; link the signal to its
  file.

- **`Supported — <targets> only`** — available on *some* targets but not all; still link
  to the file, and name the targets that have it.

- **`Not available — <reason>`** — unsupported everywhere; do not link (there is no
  file).

  ## Features

| Signal | Status |
| --- | --- |
| [Error Monitoring](./error-monitoring.md) | Supported |
| [Tracing & Performance](./tracing.md) | Supported |
| [Logging](./logging.md) | Supported |
| [Profiling](./profiling.md) | Supported — iOS, macOS only |
| [Metrics](./metrics.md) | Supported |
| [Session Replay](./session-replay.md) | Supported — iOS, Android only |
| User Feedback | Not available — no widget on this platform |
| Cron Monitoring | Not available — no scheduler runtime |
| AI / LLM Monitoring | Not available — no auto-instrumentation yet |

Use the target names exactly as the SDK enumerates them, so the catalog, the signal
files, and the per-target setup sections all speak the same vocabulary.
List platform-extension files in a separate row group or a short list under the table.

### Multi-target SDKs

Some SDKs cover more than one **target** — multiple runtimes (`node`: Node/Bun/Deno),
platforms (`cocoa`: iOS/macOS/tvOS/watchOS/visionOS), or tooling variants
(`react-native`: Expo-managed / bare / vanilla).
One slug still maps to one `index.md`; the target axis is handled *inside* it.
Two rules:

- **Enumerate targets once**, in *What this SDK applies to*, and reuse those exact names
  everywhere.
- **Tier by how much actually diverges:**
  - *Minor divergence* — same `init`, differing only in install/build/packaging or a few
    placement details. Keep everything in `index.md` and use labeled `### <target>`
    subsections inside the sections that vary.
  - *Major divergence* — a whole distinct setup flow for one target (e.g. React Native’s
    Expo config-plugin path).
    Give that target its own **platform-extension file** and route to it from
    `index.md`; keep the shared path in `index.md` so the common case stays linear.

Per-target *feature availability* is a separate axis covered by the catalog’s
`Supported — <targets> only` status and a signal file’s target-scope line.

## Signal-file format

Every canonical signal file (`tracing.md`, `logging.md`, …) follows the same shape:

1. **Title** — `# <Signal title> — <Platform>` (e.g.
   `# Tracing & Performance — Python`).
2. **Target scope** — *only when the signal is not available on every target.* One line
   right after the title naming where it applies, e.g. “Applies to: iOS, Android.”
   Use the same target names as the catalog.
   Omit when the signal works on all of the SDK’s targets.
3. **Setup** — the minimal config/code to turn the signal on, building on the `index.md`
   `init`.
   - **Single path (the default):** one `## Basic setup` section.
   - **Mutually-exclusive paths:** when a signal can be wired up in genuinely different,
     non-combinable ways (e.g. native tracing vs an OpenTelemetry/OTLP path), drop the
     single `## Basic setup` and lead with a short **“Which path”** selector (HOW-level
     routing only), followed by one `## Setup: <Path>` section per path.
   - When setup differs by target, note the per-target difference here (a short
     `### <target>` subsection or inline note).
4. **Additional sections as needed** — `## Custom spans`, `## Sampling`, framework
   specifics, etc. Only what is platform-specific.
5. **Verification** — `## Verification`. A copy-pasteable snippet that *produces this
   signal* (a span, a log line, a metric, a forced replay) so a reader can confirm it
   lands: the trigger and what to expect in Sentry.
   With multiple setup paths, share one Verification if the produced signal looks the
   same, or give one per path when they differ.

A signal file does **not** open with a cross-skill callout, and does **not** link to
strategy/WHY docs. It starts with the title and gets straight to the HOW.

## Relative links

Reference files live at `sdks/[sdk]/`. The only links allowed are within the SDK tree
and to external docs:

- Sibling signal file in the same SDK → `./<other>.md`
- Sibling SDK tree → `../<other-slug>/index.md`
- External documentation → an absolute `https://…` URL

Do **not** link to skills or to reference docs in another domain (e.g. `concepts/`).
References are standalone; cross-domain navigation is the job of the skill that loads
them.
