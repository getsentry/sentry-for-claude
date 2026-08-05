# Sentry for AI

> [!IMPORTANT]
> **This is a skill *source* repository — not something you install directly.** The
> skills here are built from this source into a portable
> [Agent Plugin](https://github.com/getsentry/agent-plugin) and installable
> client-specific plugins for [Claude Code](https://github.com/getsentry/plugin-claude),
> [Cursor](https://github.com/getsentry/plugin-cursor),
> [Codex](https://github.com/getsentry/plugin-codex), and
> [Grok](https://github.com/getsentry/plugin-grok) — install one of those, not this
> repo. They’re also served over HTTP at [skills.sentry.dev](https://skills.sentry.dev)
> for agents to fetch directly.
> In the future we may also publish the skills as a generic, standalone skills
> repository.

Your AI coding assistant already knows how to write code.
This plugin teaches it Sentry — how to set it up, how to find and fix production issues,
and how to get the most out of every feature.

Whether you’re adding Sentry to a new project, debugging a spike in errors, or
configuring alerts, just ask.
The plugin gives your assistant the context it needs to do it right.

Supports the [**Agent Plugins standard**](https://agent-plugins.org/),
[**Claude Code**](https://github.com/getsentry/plugin-claude),
[**Cursor**](https://github.com/getsentry/plugin-cursor),
[**Codex**](https://github.com/getsentry/plugin-codex), and
[**Grok**](https://github.com/getsentry/plugin-grok).

## What You Can Do

**Set up Sentry in any project** — SDK setup wizards that detect your stack, recommend
the right features, and walk through the full installation.
No copy-pasting from docs.

```
Add Sentry to my Next.js app
Set up Sentry in my Rails project
Add error monitoring to my iOS app
```

**Find and fix production issues** — Query your Sentry environment, triage errors, and
fix them in place.

```
What are the top errors in the last 24 hours?
Which issues are affecting the most users?
Fix the recent Sentry errors
```

**Review code with Sentry context** — Automatically resolve bugs that Sentry or Seer
flag in pull request comments.

```
Review PR #118 and fix the Sentry comments
```

**Configure monitoring** — Set up alerts, instrument AI/LLM calls, connect OpenTelemetry
pipelines.

```
Create a Slack alert for new high-priority issues
Monitor my OpenAI calls with Sentry
Set up OTel Collector with Sentry exporter
```

## Distribution

This repository is the single source of truth for all skills, but it is not itself an
installable plugin.
Each assistant needs the plugin in a slightly different shape, so the
per-agent plugins are **built** from it by the build scripts under
`src/plugins/<agent>/build.sh`. CI runs these on every push and deploys each result to
its own **distribution repository**, whose root is exactly that agent’s plugin:

| Agent | Distribution repository |
| --- | --- |
| Agent Plugins 1.0.0 | [`getsentry/agent-plugin`](https://github.com/getsentry/agent-plugin) |
| Claude Code | [`getsentry/plugin-claude`](https://github.com/getsentry/plugin-claude) |
| Cursor | [`getsentry/plugin-cursor`](https://github.com/getsentry/plugin-cursor) |
| Codex | [`getsentry/plugin-codex`](https://github.com/getsentry/plugin-codex) |
| Grok | [`getsentry/plugin-grok`](https://github.com/getsentry/plugin-grok) |

These repositories are generated; do not edit them.
Each one’s README has the install instructions for that agent.

The skill library is also browsable at [skills.sentry.dev](https://skills.sentry.dev)
and available through the [`skills.sh`](https://www.skills.sh/getsentry/sentry-for-ai)
installer.

### Build it yourself

Each `src/plugins/<agent>/build.sh` takes an output directory and writes that agent’s
plugin into it (the Codex build moves the plugin under `plugins/sentry/` and swaps the
skill tree’s `disable-model-invocation` flags for Codex’s `agents/openai.yaml` policy):

```bash
git clone https://github.com/getsentry/sentry-for-ai.git
cd sentry-for-ai
src/plugins/agent-plugin/build.sh /tmp/sentry-agent-plugin
```

To build any target locally, run `src/plugins/<agent>/build.sh <output-dir>`
(`agent-plugin`, `claude`, `cursor`, `codex`, or `grok`).

## Skills

### Core

| Skill | What it does |
| --- | --- |
| `sentry-get-started` | Guided entry point — orients to your current Sentry setup and routes to the right skill |
| `sentry-instrument` | Add Sentry to a project, or wire up any signal — error monitoring, tracing, logging, metrics, profiling, session replay, user feedback, cron check-ins, and AI/LLM monitoring. Detects your platform and pulls the code from the reference library. |
| `sentry-debug-issue` | Find a Sentry issue, pull full context, optionally run Seer root-cause / autofix, apply the fix, and resolve it |

### Feature Setup

| Skill | What it does |
| --- | --- |
| `sentry-otel-exporter-setup` | Configure OTel Collector with the Sentry exporter for multi-project routing |
| `sentry-create-monitor` | Create and edit monitors and the alerts that act on them, against the live API schema |
| `sentry-snapshots-cocoa` | Set up Sentry Snapshots for Apple/Cocoa projects |

### Reference Library

`sentry-instrument` doesn’t hard-code platform steps — it pulls them from a shared
library that the build hydrates into the skill:

- **`src/references/sdks/<platform>/`** — per-platform install and per-signal code, one
  directory per supported platform.
- **`src/references/concepts/`** — per-signal strategy: errors, tracing, logging,
  metrics, profiling, session replay, user feedback, crons, releases, data scrubbing,
  and choosing-a-signal.

> Superseded per-SDK “wizard” skills are frozen under `skills-legacy/`, excluded from
> the plugin build.

## Prerequisites

The plugin configures the [Sentry MCP server](https://mcp.sentry.dev) automatically on
install. No extra setup needed.

Some skills require the [GitHub CLI](https://cli.github.com/):

```bash
brew install gh    # macOS
gh auth login
```

## Contributing

Skills follow the [Agent Skills specification](https://agentskills.io).
Each skill is a directory with a `SKILL.md` file containing YAML frontmatter and
markdown instructions.
A skill can declare the shared references it needs in a `references.yml` manifest; the
build hydrates the matching files from the shared library at `references/` into the
skill so the shipped copy is self-contained.

## License

MIT
