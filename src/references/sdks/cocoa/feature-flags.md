# Feature Flags — Apple (Cocoa)

Track feature-flag evaluations (Sentry Apple SDK ≥ 9.22.0).

Docs: [Feature Flags](https://docs.sentry.io/platforms/apple/feature-flags/) ·
[Issue Details → Feature Flags](https://docs.sentry.io/product/issues/issue-details/feature-flags/)

**When:** the app evaluates boolean feature flags (any provider or in-house).

**Value type:** **boolean** only.

## Basic setup

```swift
import Sentry

SentrySDK.addFeatureFlag(name: "test-flag", result: false)
SentrySDK.capture(error: error)
```

```objc
#import <SentryObjC/SentryObjC.h>

[SentryObjCSDK addFeatureFlagWithName:@"test-flag" result:NO];
[SentryObjCSDK captureError:error];
```

Also available on a custom hub and via capture scope callbacks.
Use `scope.clearFeatureFlags()` on logout / identity change.

Scope keeps up to 100 latest unique evaluations; active spans record up to 10 as
`flag.evaluation.<name>`.

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

Add a flag, capture an error, confirm the Feature Flag section.

## Do not

Do not replace this API with tags or breadcrumbs labeled “feature flag.”
