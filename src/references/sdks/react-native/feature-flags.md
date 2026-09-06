# Feature Flags — React Native

Track feature-flag evaluations on Sentry error and transaction events.

Docs: [Feature Flags](https://docs.sentry.io/platforms/react-native/feature-flags/) ·
[Issue Details → Feature Flags](https://docs.sentry.io/product/issues/issue-details/feature-flags/)

**When:** the app already evaluates flags.
Propose during setup when a flag SDK or toggle helper is detected.

**Value type:** **boolean** only via the current API. Do not use tags/breadcrumbs/
`setContext` as a substitute for the Feature Flags product.

## Basic setup

Requires `@sentry/react-native` ≥ 7.0.0.

```javascript
import * as Sentry from "@sentry/react-native";

const flagsIntegration = Sentry.featureFlagsIntegration();
flagsIntegration.addFeatureFlag("feature_flag_a", true);

Sentry.init({
  dsn: "___PUBLIC_DSN___",
  integrations: [flagsIntegration],
});
```

You can also call `addFeatureFlag` later, after init, on the same integration instance.
Re-evaluating the same name overwrites the previous boolean.

## Change tracking

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

Capture a test error after recording a flag; confirm it on the event’s Feature Flag
section. Search with `flags["feature_flag_a"]:true` if needed.

## Do not

Do not put active flags into `event.extra`, tags, or a custom context named
`feature_flags` — use `featureFlagsIntegration` so Issue Details and suspect flags work.
