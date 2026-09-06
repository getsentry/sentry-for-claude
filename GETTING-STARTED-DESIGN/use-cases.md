# Use cases

> Part of the [`/sentry-get-started` design](./index.md). User stories for how people use Sentry
> *agentically* — what they ask for, and how we expect the agent to reach for skills
> ([proposed-skills.md](./proposed-skills.md)) and their reference files to deliver it.
>
> These are hand-written for now. Eventually each becomes an **eval spec**. This file is just the
> table of contents — titles only; we'll flesh out the per-story expectations next.

Each story will eventually describe: the user's ask, which skill(s) the agent loads, which
`references/` files it reads, the MCP calls it makes, and what "done" looks like.

---

## First-time setup

- First-time user sets up error monitoring end-to-end (the flagship journey)
- User has no Sentry account yet (signup + MCP-connect handoff)
- User connects the Sentry MCP for the first time

## Adding a signal

- Adding logging to part of a project
- Adding tracing
- Adding performance profiling
- Adding session replay (frontend)
- Adding user feedback
- Adding cron monitoring for a scheduled job
- Adding custom metrics
- Instrumenting an LLM / AI app (AI monitoring)
- "Set up Sentry properly" — full recommended setup with sensible defaults

## Improving / hardening the setup

- Fixing source maps (unreadable JS/TS stack traces)
- Fixing native/mobile symbolication (debug symbols)
- Setting up releases with suspect commits & deploy tracking
- Setting up code mappings / stack-trace linking
- Scrubbing PII out of events
- Reducing event volume / managing quota & cost
- Diagnosing why events aren't arriving (filtered / rate-limited / dropped)
- Upgrading the SDK across a major version
- Migrating to span streaming / setting up an OpenTelemetry pipeline
- Configuring Seer automation & handoff to the coding agent

## Monitors & alerts

- Getting notified in Slack when a new issue appears (alert rule)
- Setting up a metric monitor (threshold / percentage / anomaly)
- Setting up uptime monitoring for an endpoint
- Setting up a crash-rate / release-health monitor
- Building a dashboard to watch a service
- Routing issues to the right team (ownership rules / CODEOWNERS)

## Using & reading Sentry data

- Finding a Sentry error for a specific problem
- Debugging a known Sentry error
- Resolving a Sentry issue by shipping a fix (`Fixes SENTRY-123`)
- Receiving a Seer root-cause / autofix handoff
- Triaging the issue stream (resolve / archive / assign, in bulk)
- Finding a trace for a potential performance problem
- Investigating a spike or regression (what changed?)
- Reading logs to debug an error
- Reading a profile / flame graph for a slow function
- Reading a replay for a frontend bug
- Asking a natural-language question about the environment (`/seer`)

## Understanding concepts

- Deciding which signal to use (error vs span vs log vs metric)
- Learning Sentry's search query syntax for a query

---

## Parking lot (capabilities we've flagged but not yet in scope)

- Reviewing / resolving Sentry + Seer PR bot comments
- Enabling Sentry's AI code review for a repo
- Syncing issues to an external tracker (Jira / Linear / GitHub Issues)
- Visual regression review (Snapshots) via MCP
- Mobile build size analysis & build distribution
