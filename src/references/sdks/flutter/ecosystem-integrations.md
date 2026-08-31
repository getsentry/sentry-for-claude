# Ecosystem Integrations — Sentry Flutter SDK

Add these packages alongside `sentry_flutter` for deeper instrumentation:

### HTTP Clients

**Standard `http` package** — built into `sentry_flutter`, no extra install:

```dart
import 'package:sentry/sentry.dart';

// Wrap your http client
final client = SentryHttpClient(
  captureFailedRequests: true,
  failedRequestStatusCodes: [SentryStatusCode.range(400, 599)],
);
try {
  final response = await client.get(Uri.parse('https://api.example.com/users'));
} finally {
  client.close();
}
```

**Dio** — install `sentry_dio`:

```bash
flutter pub add sentry_dio
```

```dart
import 'package:dio/dio.dart';
import 'package:sentry_dio/sentry_dio.dart';

final dio = Dio();
// Add your interceptors first, THEN addSentry() last
dio.addSentry(
  captureFailedRequests: true,
  failedRequestStatusCodes: [SentryStatusCode.range(400, 599)],
);
```

### Databases

| Package | Install | Setup |
| --- | --- | --- |
| `sentry_sqflite` | `flutter pub add sentry_sqflite` | `databaseFactory = SentrySqfliteDatabaseFactory();` |
| `sentry_drift` | `flutter pub add sentry_drift` | `.interceptWith(SentryQueryInterceptor(databaseName: 'db'))` |
| `sentry_hive` | `flutter pub add sentry_hive` | Use `SentryHive` instead of `Hive` |
| `sentry_isar` | `flutter pub add sentry_isar` | Use `SentryIsar.open()` instead of `Isar.open()` |

### Other

| Package | Install | Purpose |
| --- | --- | --- |
| `sentry_logging` | `flutter pub add sentry_logging` | Dart `logging` package → Sentry breadcrumbs/events |
| `sentry_link` | `flutter pub add sentry_link` | GraphQL (gql, graphql_flutter, ferry) tracing |
| `sentry_supabase` | `flutter pub add sentry_supabase` | Supabase query tracing (SDK ≥9.9.0) |
| `sentry_firebase_remote_config` | `flutter pub add sentry_firebase_remote_config` | Feature flag evaluation tracking — see [`feature-flags.md`](./feature-flags.md) |
| `sentry_file` | `flutter pub add sentry_file` | File I/O tracing via `.sentryTrace()` extension |

### State Management Patterns

No official packages — wire Sentry via observer APIs:

| Framework | Hook point | Pattern |
| --- | --- | --- |
| **BLoC/Cubit** | `BlocObserver.onError` | `Sentry.captureException(error, stackTrace: stackTrace)` inside `onError`; set `Bloc.observer = SentryBlocObserver()` before init |
| **Riverpod** | `ProviderObserver.providerDidFail` | Fires for `FutureProvider`/`StreamProvider` failures; wrap app with `ProviderScope(observers: [SentryProviderObserver()])` |
| **Provider/ChangeNotifier** | `try/catch` in `notifyListeners` callers | Manually call `Sentry.captureException(e, stackTrace: stack)` in catch blocks |
| **GetX** | `GetMaterialApp.onError` | `GetMaterialApp(onError: (details) => Sentry.captureException(...))` |
