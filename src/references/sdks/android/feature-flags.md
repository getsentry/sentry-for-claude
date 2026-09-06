# Feature Flags — Android

Track feature-flag evaluations on scope and spans (Sentry Android SDK ≥ 8.42.0).

Docs: [Feature Flags](https://docs.sentry.io/platforms/android/feature-flags/) ·
[Issue Details → Feature Flags](https://docs.sentry.io/product/issues/issue-details/feature-flags/)

**When:** the app uses LaunchDarkly or any custom/boolean flag system.

**Value type:** **boolean** only.

## Basic setup

### LaunchDarkly integration

Add the optional artifact and wire per
[LaunchDarkly](https://docs.sentry.io/platforms/android/integrations/launchdarkly/):

`io.sentry:sentry-launchdarkly-android` (also listed in `./integrations.md`).

### Generic API

```kotlin
import io.sentry.Sentry

Sentry.addFeatureFlag("test-flag", false)
Sentry.captureException(Exception("Something went wrong!"))
```

```java
import io.sentry.Sentry;

Sentry.addFeatureFlag("test-flag", false);
Sentry.captureException(new Exception("Something went wrong!"));
```

Scope behavior (summary):

- Current scope keeps the latest evaluation per flag name (up to 100).
- Active spans/transactions record up to 10 flags as `flag.evaluation.<name>`.
- `scope.clearFeatureFlags()` clears the current scope buffer (not parent scopes or span
  attributes already set).
- Scope-callback additions apply to that capture only; still recorded on an active span.

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

Record a flag, capture an exception, confirm Feature Flag on the event.

## Do not

Do not use `scope.setTag("feature.flag", …)` as feature-flag tracking.
