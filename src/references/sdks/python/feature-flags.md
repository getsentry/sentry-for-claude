# Feature Flags — Python

Track feature-flag evaluations on Sentry error and transaction events, and enable
provider change tracking so rollouts correlate with errors.

Docs: [Feature Flags](https://docs.sentry.io/platforms/python/feature-flags/) ·
[Issue Details → Feature Flags](https://docs.sentry.io/product/issues/issue-details/feature-flags/)

**When:** the project already uses LaunchDarkly, OpenFeature, Statsig, Unleash, or a
custom flag helper. Detect those imports/dependencies and propose this setup.

**Value type:** **boolean** evaluations only on the generic API and current
integrations.

## Basic setup

### Provider integrations

Add the matching integration to `sentry_sdk.init(integrations=[…])`:

| Provider | Integration | Docs |
| --- | --- | --- |
| LaunchDarkly | `LaunchDarklyIntegration()` | [docs](https://docs.sentry.io/platforms/python/integrations/launchdarkly/) |
| OpenFeature | `OpenFeatureIntegration()` | [docs](https://docs.sentry.io/platforms/python/integrations/openfeature/) |
| Statsig | `StatsigIntegration()` | [docs](https://docs.sentry.io/platforms/python/integrations/statsig/) |
| Unleash | `UnleashIntegration()` | [docs](https://docs.sentry.io/platforms/python/integrations/unleash/) |

Example (LaunchDarkly):

```python
import sentry_sdk
from sentry_sdk.integrations.launchdarkly import LaunchDarklyIntegration

sentry_sdk.init(
    dsn="___DSN___",
    integrations=[
        LaunchDarklyIntegration(),
    ],
)
```

Boolean evaluations made through the provider SDK are then recorded automatically.

### Generic API

For unsupported or in-house flag systems:

```python
import sentry_sdk
from sentry_sdk.feature_flags import add_feature_flag

add_feature_flag("test-flag", False)  # boolean only

sentry_sdk.capture_exception(Exception("Something went wrong!"))
```

Evaluations are held in memory and attached on error and transaction events (latest
value per flag name; capped).

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

1. Evaluate a boolean flag (or call `add_feature_flag`).
2. `capture_exception` / trigger a real error on that request.
3. Confirm the flag on the event’s Feature Flag section.
4. Optional: Issues search `flags["test-flag"]:false`.

## Do not

Do not use `set_tag("feature.flag", …)` or breadcrumbs to “represent” feature flags for
Sentry’s Feature Flags product.
