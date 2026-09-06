# Metrics — Sentry Cocoa SDK

> Minimum SDK: `sentry-cocoa` v9.27.0+. Swift only.
> Objective-C metrics API is not currently available.
> Metrics are enabled by default.

Use metrics for aggregate counters, gauges, and distributions that should not create
Sentry issues. Do not duplicate automatic tracing, app hangs, MetricKit diagnostics, or
error events.

## Configuration

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `beforeSendMetric` | `((SentryMetric) -> SentryMetric?)?` | `nil` | Filter or mutate metrics before send. Return `nil` to drop. |

## Code Examples

### Basic setup

Metrics are enabled by default.
Call the `SentrySDK.metrics` API to record them.

### Counter

Counters track discrete occurrences.
`count` does not accept a unit.

```swift
SentrySDK.metrics.count(key: "button.click")

SentrySDK.metrics.count(
    key: "link.created",
    value: 1,
    attributes: [
        "source": "share_extension",
        "is_favorite": false
    ]
)
```

### Gauge

Gauges track current state.

```swift
SentrySDK.metrics.gauge(
    key: "queue.depth",
    value: 42,
    attributes: ["queue": "sync"]
)
```

### Distribution

Distributions track measured values where percentiles are useful.

```swift
SentrySDK.metrics.distribution(
    key: "qr.render.duration",
    value: 187.5,
    unit: .millisecond,
    attributes: [
        "cache_hit": true,
        "image_size": "1024"
    ]
)
```

### beforeSendMetric

```swift
SentrySDK.start { options in
    options.dsn = "___PUBLIC_DSN___"
    options.beforeSendMetric = { metric in
        var metric = metric

        if case let .boolean(drop)? = metric.attributes["drop_me"], drop {
            return nil
        }

        metric.attributes["processed"] = .boolean(true)
        metric.attributes["app_area"] = .string("links")
        return metric
    }
}
```

## Attribute Types

Metric attributes use `SentryAttributeValue` at the capture API and
`SentryAttributeContent` inside `beforeSendMetric`.

Supported capture values:
- Scalar: `String`, `Bool`, `Int`, `Double`, `Float`
- Arrays: `[String]`, `[Bool]`, `[Int]`, `[Double]`, `[Float]`
- Sets: `Set<String>`, `Set<Bool>`, `Set<Int>`, `Set<Double>`, `Set<Float>` (SDK 9.13+)

Use stable, low-cardinality attributes.
Avoid URLs, IDs, user-entered names, or unbounded strings unless they are intentionally
scrubbed and useful for grouping.

## Best Practices

- Use metrics for aggregate product and app-health signals, not exceptions or stack
  traces.
- Keep metric names lowercase and dot-delimited, such as `link.created` or
  `network.reachability.changed`.
- Prefer distributions for durations and sizes, gauges for current state, and counters
  for occurrences.
- Avoid metrics that duplicate automatic spans, failed request events, app hangs,
  watchdog terminations, or MetricKit diagnostics.
- Use `beforeSendMetric` to drop metrics that do not meet the app’s policy or volume
  requirements.

## Troubleshooting

| Issue | Solution |
| --- | --- |
| `enableMetrics` compile error | Removed in SDK 9.27.0. Metrics are enabled by default. |
| Metric not sent | Verify `SentrySDK.start` ran and that `beforeSendMetric` is not dropping the metric |
| Count with `unit` fails | `count` has no `unit` parameter; use `gauge` or `distribution` if units are needed |
| Objective-C compile issue | Metrics are Swift-only |
| Too many unique series | Reduce high-cardinality attributes and metric names |
