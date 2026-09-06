# Feature Flags — PHP

Track feature-flag evaluations on Sentry events (SDK ≥ 4.18.1).

Docs: [Feature Flags](https://docs.sentry.io/platforms/php/feature-flags/) ·
[Issue Details → Feature Flags](https://docs.sentry.io/product/issues/issue-details/feature-flags/)

**When:** any PHP app that evaluates flags; on Laravel, prefer Pennant auto-tracking
when `laravel/pennant` is installed.

**Value type:** **boolean** only.

## Basic setup

### Generic API

```php
\Sentry\addFeatureFlag('test-flag', false);

\Sentry\captureException(new \RuntimeException('Something went wrong!'));
```

Up to 100 evaluations per event; the most recent 100 are kept.

### Laravel Pennant

When `laravel/pennant` is present, `PennantIntegration` records Pennant checks
automatically (no extra config):

```php
use Laravel\Pennant\Feature;

// Recorded as feature flag evaluations on subsequent Sentry events
$value = Feature::active('new-onboarding');
```

See also `./laravel.md` for Laravel-wide setup.
Still enable **change tracking** in Sentry for the provider that owns the flag
definitions (Pennant may be backed by a third-party provider or app logic — use the
generic webhook when there is no hosted provider).

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

Evaluate a flag, capture an error, confirm the Feature Flag section on the event.

## Do not

Do not document flags only as tags or log lines — use `addFeatureFlag` / Pennant
integration so suspect-flag and `flags[name]` search work.
