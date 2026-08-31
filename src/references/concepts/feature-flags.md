# Feature flags — What & Why

Feature flags are **context on other signals**, not a signal of their own.
When a flag is evaluated in your app, Sentry can record that evaluation and attach it to
errors, messages, and spans so Issue Details can answer: *which flags were on for this
user/request when it broke?*

Sentry’s feature-flag product has two halves.
Together they give the full picture of how a rollout affected application health:

| Half | Where it runs | What you get |
| --- | --- | --- |
| **Evaluation tracking** | Customer app, via the Sentry SDK | Recent flag evaluations on error/message events (`contexts.flags`) and on active spans (`flag.evaluation.<name>`). Searchable with `flags[name]:true` / `false`. Suspect-flag highlighting on Issue Details. |
| **Change tracking** | Sentry + your flag provider (webhook) | Audit log of flag definition changes (create/update/delete). Change markers on the issue event chart. Correlation of a rollout with a spike — requires evaluation tracking so Sentry knows which flags the failing code actually saw. |

Product docs:
[Feature Flags on Issue Details](https://docs.sentry.io/product/issues/issue-details/feature-flags/).
Both halves are currently in open beta.

## Why instrument this

Without evaluation tracking, a bad rollout looks like “errors went up after deploy” with
no link to the flag that gated the change.
With both halves:

- every error shows the flags evaluated leading up to it (up to 100 unique names, most
  recent wins);
- active spans can carry up to 10 evaluations as `flag.evaluation.<name>`;
- change-tracking webhooks let Sentry mark a flag as **suspect** when a definition
  change lines up with new errors;
- Issues Search can filter on `flags["my-flag"]:true` / `false`.

**Recommend evaluation tracking whenever the codebase already uses a feature-flag SDK or
framework** (LaunchDarkly, OpenFeature, Statsig, Unleash, Flagsmith, Laravel Pennant,
Firebase Remote Config, home-grown toggles, …). Don’t bolt flags onto a greenfield app
that has no flag system — there’s nothing to evaluate.

Always pair the proposal with change tracking: evaluation tracking alone shows *what was
on*; change tracking shows *when the definition moved*. Point the user at the provider
webhook setup inside Sentry (Settings → Feature Flags / the provider integration docs) —
that half is configured in Sentry, not in app code.

## Evaluation value types

The SDK evaluation API records a **boolean** result per flag name
(`add_feature_flag(name, bool)` / provider integrations that forward boolean
evaluations).
Non-boolean provider values are outside the current evaluation-tracking API
— do not invent a workaround that stuffs variants into tags, breadcrumbs, or
`setContext("feature_flags", …)`. Those paths bypass the Feature Flags UI, suspect-flag
logic, and `flags[…]` search.

Boolean is the supported evaluation type today per the
[SDK feature-flag integration spec](https://develop.sentry.dev/sdk/foundations/client/integrations/feature-flags/)
and public platform docs.
If the app’s important flags are multi-variant (string/number payloads), still wire
boolean gates you do have, enable change tracking for the provider, and say clearly that
non-boolean evaluation values are not represented in the flags context yet.

## Do not confuse with

| Wrong pattern | Why it’s wrong | Do this instead |
| --- | --- | --- |
| `setTag("feature_flag", …)` / `setTag("feature.x", …)` | Tags are generic indexable pairs; they do **not** populate the Feature Flags UI, suspect flags, or `flags[name]` search. | SDK feature-flag API or provider integration. |
| `setContext("feature_flags", {…})` | Free-form context is not the flags schema. | Same as above. |
| Breadcrumb `category: "feature-flag"` | Breadcrumbs are a timeline, not evaluation tracking. | Same as above. |
| Logging “flag X served” as the only record | Useful narrative, but not structured flag context. | Optional log **plus** evaluation tracking. |

## Platform support (evaluation tracking)

Wire evaluation tracking only on SDKs that document it:

| Docs platform | SDK reference slug(s) in this repo |
| --- | --- |
| [Android](https://docs.sentry.io/platforms/android/feature-flags/) | `android` |
| [Apple](https://docs.sentry.io/platforms/apple/feature-flags/) | `cocoa` |
| [Dart](https://docs.sentry.io/platforms/dart/feature-flags/) | `flutter` |
| [Java](https://docs.sentry.io/platforms/java/feature-flags/) | no dedicated Java tree here — use Android when the app is Android; otherwise point at the Java docs |
| [JavaScript](https://docs.sentry.io/platforms/javascript/feature-flags/) | `browser`, `node`, `react`, `nextjs`, `nestjs`, `svelte`, `cloudflare`, `react-router-framework`, `tanstack-start` |
| [PHP](https://docs.sentry.io/platforms/php/feature-flags/) | `php` (includes Laravel Pennant) |
| [Python](https://docs.sentry.io/platforms/python/feature-flags/) | `python` |
| [React Native](https://docs.sentry.io/platforms/react-native/feature-flags/) | `react-native` |

Per-platform HOW (provider integrations + generic API) lives in
`sdks/<slug>/feature-flags.md`. Open that file after you detect a flag system; don’t
read it “just in case.”

## Change tracking (provider webhooks)

Configured in Sentry / the flag provider, not in the app SDK:

- [Flagsmith](https://docs.sentry.io/integrations/feature-flag/flagsmith/#change-tracking)
- [LaunchDarkly](https://docs.sentry.io/integrations/feature-flag/launchdarkly/#change-tracking)
- [Statsig](https://docs.sentry.io/integrations/feature-flag/statsig/#change-tracking)
- [Unleash](https://docs.sentry.io/integrations/feature-flag/unleash/#change-tracking)
- [Generic](https://docs.sentry.io/integrations/feature-flag/generic/#change-tracking)

After evaluation tracking is in the app, tell the user that registering the matching
webhook is what unlocks suspect-flag correlation on Issue Details.

## Related

- [`errors.md`](errors.md) — flags show up on issue/error events.
- [`tracing.md`](tracing.md) — span attributes `flag.evaluation.<name>`.
- [`search-query-language.md`](../search-query-language.md) — `flags["my_flag"]:true`.
