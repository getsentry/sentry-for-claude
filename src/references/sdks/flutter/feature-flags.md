# Feature Flags — Flutter / Dart

Track feature-flag evaluations (Sentry Dart/Flutter SDK ≥ 9.0.0).

Docs: [Feature Flags](https://docs.sentry.io/platforms/dart/feature-flags/) ·
[Issue Details → Feature Flags](https://docs.sentry.io/product/issues/issue-details/feature-flags/)

**When:** the app uses Firebase Remote Config or any manual boolean flags.

## Basic setup

### Firebase Remote Config

```bash
flutter pub add sentry_firebase_remote_config
```

Follow
[Firebase Remote Config](https://docs.sentry.io/platforms/dart/integrations/firebase-remote-config/)
and the package row in `./ecosystem-integrations.md`.

### Manual API

```dart
Sentry.addFeatureFlag("feature_flag_a", true);
```

Re-using the same name overwrites the previous value.

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

Evaluate/record a flag, capture an exception, confirm Feature Flag on the event.

## Do not

Do not treat ecosystem “feature flag tracking” as optional trivia — when Remote Config
or flag usage is detected, propose this setup and change tracking together.
