# Feature Flags — Browser JavaScript

Track feature-flag evaluations on Sentry error and transaction events, and pair them
with provider **change tracking** so rollouts show up as suspect flags on Issue Details.

Docs: [Feature Flags](https://docs.sentry.io/platforms/javascript/feature-flags/) ·
product overview:
[Issue Details → Feature Flags](https://docs.sentry.io/product/issues/issue-details/feature-flags/)

**When to set this up:** the app already evaluates flags (LaunchDarkly, OpenFeature,
Statsig, Unleash, Flagsmith, home-grown, …). Propose it during setup when those
dependencies or calls are detected — do not add a flag system from scratch.

**Value type:** evaluation tracking records **boolean** results.
Do not substitute `setTag`, breadcrumbs, or `setContext("feature_flags", …)` — those
skip the Feature Flags UI and `flags[name]` search.

## Basic setup

Browser / package-based installs.
CDN Loader may not expose every integration — prefer npm/yarn when enabling flags.

### Generic integration

Manual tracking via `featureFlagsIntegration` (`@sentry/*` ≥ 8.43.0):

```typescript
import * as Sentry from "@sentry/browser";

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  integrations: [Sentry.featureFlagsIntegration()],
});

const flags = Sentry.getClient()?.getIntegrationByName("FeatureFlags");
// TypeScript: getIntegrationByName<Sentry.FeatureFlagsIntegration>("FeatureFlags")
if (flags) {
  flags.addFeatureFlag("checkout-v2", true);
}

Sentry.captureException(new Error("Something went wrong!"));
```

Calling `addFeatureFlag` again with the same name overwrites the previous value.
Only **boolean** values are recorded.

## Provider integrations

Prefer a provider integration when the app already uses that SDK — it records
evaluations automatically on boolean flag reads:

| Provider | Integration | Docs |
| --- | --- | --- |
| LaunchDarkly | `launchDarklyIntegration` + `buildLaunchDarklyFlagUsedHandler` | [LaunchDarkly](https://docs.sentry.io/platforms/javascript/configuration/integrations/launchdarkly/) |
| OpenFeature | `openFeatureIntegration` + `OpenFeatureIntegrationHook` | [OpenFeature](https://docs.sentry.io/platforms/javascript/configuration/integrations/openfeature/) |
| Statsig | `statsigIntegration` | [Statsig](https://docs.sentry.io/platforms/javascript/configuration/integrations/statsig/) |
| Unleash | `unleashIntegration` | [Unleash](https://docs.sentry.io/platforms/javascript/configuration/integrations/unleash/) |

Import names live on the same `@sentry/browser` package as the rest of the SDK.

## Change tracking

Evaluation tracking alone shows which flags were on for an event.
**Change tracking** (provider → Sentry webhook) is what lets Sentry correlate definition
changes with error spikes and mark suspect flags.
Configure it in Sentry / your provider — not in app code:

- [Flagsmith](https://docs.sentry.io/integrations/feature-flag/flagsmith/#change-tracking)
- [LaunchDarkly](https://docs.sentry.io/integrations/feature-flag/launchdarkly/#change-tracking)
- [Statsig](https://docs.sentry.io/integrations/feature-flag/statsig/#change-tracking)
- [Unleash](https://docs.sentry.io/integrations/feature-flag/unleash/#change-tracking)
- [Generic](https://docs.sentry.io/integrations/feature-flag/generic/#change-tracking)

After wiring evaluation tracking, tell the user to register the matching webhook so
Issue Details can connect rollouts to failures.

## Verification

1. Evaluate at least one boolean flag (provider or `addFeatureFlag`).
2. Capture a test error on the same request/session.
3. Open the event in Sentry → **Feature Flag** section; confirm the flag name and
   `true`/`false` value.
4. Optionally search Issues with `flags["your-flag"]:true`.

## Do not

- Do not demo flags as tags, breadcrumbs, or generic context objects.
- Do not claim non-boolean variants are stored in `contexts.flags` — they are not, with
  the current API.
