# Sentry SDK references

The per-platform HOW — the code for installing Sentry and wiring up each signal.
There is one reference tree per SDK under `sdks/[sdk]/`: an `index.md` (detect, install,
`init`, feature catalog) plus one file per supported signal.
This is the mechanics layer: the actual install commands, `Sentry.init()` options, and
the code to wire up each capability.

## What Sentry can capture

A quick orientation so you know which signal file to open.

| Signal | What it is |
| --- | --- |
| **Error Monitoring** | Unhandled exceptions and crashes, grouped into issues with stack traces, breadcrumbs, and context. The baseline — always set up first. |
| **Tracing & Performance** | Distributed traces and spans across services and requests, showing where time goes and how a request flows end to end. |
| **Profiling** | Function-level CPU/wall-clock samples tied to traces — which lines are slow. Requires tracing. |
| **Logging** | Structured application logs sent to Sentry and correlated with errors and traces. |
| **Metrics** | Counters, gauges, and distributions for operational metrics — request rates, queue depths, cache hit ratios, and other system-health signals. |
| **Cron Monitoring** | Check-in code for scheduled/recurring jobs. |
| **Session Replay** | A video-like reproduction of a user’s session (browser and mobile) leading up to an error. |
| **User Feedback** | A widget or API to collect user-submitted reports, optionally attached to an event. |
| **AI / LLM Monitoring** | Spans, token usage, and tool calls for LLM and agent frameworks (OpenAI, Anthropic, Vercel AI, LangChain, Google GenAI, Laravel AI, Eve, Flue, the Cloudflare Agents SDK, and Workers AI). |

## How the references are structured

Each SDK has a reference tree:

```
sdks/[sdk]/index.md          # overview, detect, install, init, feature catalog
sdks/[sdk]/error-monitoring.md
sdks/[sdk]/tracing.md
sdks/[sdk]/<signal>.md        # one file per supported signal
```

Read `sdks/[sdk]/index.md` **first** — it owns detection, install, the recommended
`init`, and a feature catalog table that links to each signal’s file (and marks
unsupported ones). Then read only the signal files you need.
The exact format both files follow is documented in `STRUCTURE.md`, an internal
authoring contract that is not shipped with the skills.

## Detect the platform first

Detect the platform from project files (`package.json`, `go.mod`, `requirements.txt`,
`Gemfile`, `*.csproj`, `build.gradle`, `pubspec.yaml`, etc.)
using the catalog below, then open that SDK’s `index.md` and follow it.
Each `index.md` carries its own detection logic, prerequisites, and step-by-step
configuration.

### SDK catalog

| Platform | SDK slug | Reference |
| --- | --- | --- |
| Android | `android` | `sdks/android/index.md` |
| browser JavaScript | `browser` | `sdks/browser/index.md` |
| Cloudflare Workers and Pages | `cloudflare` | `sdks/cloudflare/index.md` |
| Apple platforms (iOS, macOS, tvOS, watchOS, visionOS) | `cocoa` | `sdks/cocoa/index.md` |
| .NET | `dotnet` | `sdks/dotnet/index.md` |
| Elixir | `elixir` | `sdks/elixir/index.md` |
| Go | `go` | `sdks/go/index.md` |
| NestJS | `nestjs` | `sdks/nestjs/index.md` |
| Next.js | `nextjs` | `sdks/nextjs/index.md` |
| Node.js, Bun, and Deno | `node` | `sdks/node/index.md` |
| PHP | `php` | `sdks/php/index.md` |
| Python | `python` | `sdks/python/index.md` |
| Flutter and Dart | `flutter` | `sdks/flutter/index.md` |
| React Native and Expo | `react-native` | `sdks/react-native/index.md` |
| React | `react` | `sdks/react/index.md` |
| React Router Framework | `react-router-framework` | `sdks/react-router-framework/index.md` |
| TanStack Start React | `tanstack-start` | `sdks/tanstack-start/index.md` |
| Ruby | `ruby` | `sdks/ruby/index.md` |
| Svelte and SvelteKit | `svelte` | `sdks/svelte/index.md` |

### Platform detection priority

When multiple SDKs could match, prefer the more specific one:

- **Android** (`build.gradle` with android plugin) → `android`
- **Cloudflare** (`wrangler.toml` or `wrangler.jsonc`) → `cloudflare` over `node`
- **NestJS** (`@nestjs/core`) → `nestjs` over `node`
- **Next.js** → `nextjs` over `react` or `node`
- **React Router Framework** (`@sentry/react-router` or `@react-router/*`) →
  `react-router-framework` over `react`
- **TanStack Start React** (`@tanstack/react-start`) → `tanstack-start` over `react`
- **Flutter** (`pubspec.yaml` with `flutter:` dependency or `sentry_flutter`) →
  `flutter`
- **React Native** → `react-native` over `react`
- **PHP** with Laravel or Symfony → `php`
- **Elixir** (`mix.exs` detected) → `elixir`
- **Node.js / Bun / Deno** without a specific framework → `node`
- **Browser JS** (vanilla, jQuery, static sites) → `browser`
- **No match** → direct the user to [Sentry Docs](https://docs.sentry.io/platforms/)

### Quick lookup

| Keywords | SDK slug |
| --- | --- |
| android, kotlin, java, jetpack compose | `android` |
| browser, vanilla js, javascript, jquery, cdn, wordpress, static site | `browser` |
| cloudflare, cloudflare workers, cloudflare pages, wrangler, durable objects, d1 | `cloudflare` |
| ios, macos, swift, cocoa, tvos, watchos, visionos, swiftui, uikit | `cocoa` |
| .net, csharp, c#, asp.net, maui, wpf, winforms, blazor, azure functions | `dotnet` |
| go, golang, gin, echo, fiber | `go` |
| elixir, phoenix, plug, oban | `elixir` |
| nestjs, nest | `nestjs` |
| nextjs, next.js, next | `nextjs` |
| node, nodejs, node.js, bun, deno, express, fastify, koa, hapi | `node` |
| php, laravel, symfony | `php` |
| python, django, flask, fastapi, celery, starlette | `python` |
| flutter, dart, pubspec | `flutter` |
| react native, expo | `react-native` |
| react, react router, tanstack, redux, vite | `react` |
| react-router framework, @sentry/react-router, @react-router/dev | `react-router-framework` |
| tanstack start, @tanstack/react-start | `tanstack-start` |
| ruby, rails, sinatra, sidekiq | `ruby` |
| svelte, sveltekit | `svelte` |
