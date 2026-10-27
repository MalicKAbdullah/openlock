# Startup and unlock performance

How OpenLock gets from tap to a usable home screen, and the rules that keep
it fast. The suite-wide background (secure storage costs, `CachedSecureStorage`
and its threat model) is in secure-suite-core's `docs/PERFORMANCE.md`.

## The path

1. **`main()` → first frame.** One `CachedSecureStorage.load` (a single
   `readAll`) and the session resolve (PIN set?, fingerprint on?, recovery
   offer due?) — memory reads after the bulk read. The first frame is already
   the unlock screen.
2. **First frame → fingerprint prompt.** The unlock screen prompts from its
   first post-frame callback; the biometric flag is already known.
   Meanwhile `main()` starts the home data: installed apps (metadata only),
   the encrypted config, and the intruder log.
3. **Fingerprint → home.** `markUnlocked` is synchronous: it reads nothing,
   flips the session and the router shows home. The header, hero and settings
   tiles never wait for the app list; the app rows show same-height skeletons
   until it arrives (normally it already has, during the prompt).
4. **Icons.** Each built row asks for its icon. Requests from one frame go to
   native as one `getAppIcons` call, which renders missing icons into
   `cacheDir/app_icons/<package>@<versionCode>.png` (stale versions of that
   package are deleted) and returns file paths. `Image.file` decodes at
   40 logical px × device pixel ratio, off the UI thread.

### Secure storage

OpenLock qualifies for `CachedSecureStorage`:

- **Sole writer.** Only Dart code writes its flutter_secure_storage keys
  (`OpenLockKeys`, the update auto-check flag). The native `ConfigStore` uses
  its own EncryptedSharedPreferences file (`openlock_enforcement`); no Kotlin
  code opens flutter_secure_storage's file.
- **No gesture-released value.** The fingerprint is a convenience gate, not a
  key release; the config key is random (not PIN-derived) and is needed to
  read the config whenever the app runs.

### Native side

- `getInstalledApps`, `getAppIcons` run on a two-thread executor;
  `pushConfig` and the intruder-log calls on a serial one (so pushes apply in
  order). Replies are posted back to the main thread.
- `ConfigStore` is one process-wide instance (`ConfigStore.get`), created on
  first use: the monitor service, the lock overlay and the plugin share one
  EncryptedSharedPreferences build. The parsed config is cached and replaced
  by `saveConfig`, the only writer.

## Measured (Dart)

`flutter test test/perf/app_list_benchmark_test.dart`, Apple M-series,
`flutter test` JIT, 200 apps, mean of 20–200 runs after a warm-up.

| What | Main isolate, base64 icons | Now |
| --- | --- | --- |
| `getInstalledApps` reply size | 2 103 KiB (6–10 KB PNG per app, base64) | 15 KiB (metadata) |
| Reply decode on the UI isolate (codec + base64) | 5.3–5.5 ms | 0.11–0.12 ms |
| Filter + sort, empty query | 0.11–0.12 ms (lower-casing per comparison) | 0.05–0.06 ms (keys lower-cased once) |
| Re-reading the list on a picker rebuild | full filter + sort | 0.01 ms (memoized provider) |

Home first frame (1080×2400 @3x, debug JIT, includes building the whole
screen): 37–41 ms with the apps loaded, 40–44 ms with them still loading —
the header is drawn either way.

## Estimated (native, no device available)

Mid-range Android phone; confirm with `adb logcat -s OpenLockPerf` (debug
builds log the installed-apps call and every icon batch with cache
hits/misses) and `openlock.startup` lines (`flutter run --profile`).

| Step | Before | Now |
| --- | --- | --- |
| Installed apps, 200 launcher apps | 0.6–1.5 s on the **main thread** (load + draw + PNG-encode + base64 every icon), then 20–30 ms of decoding on the UI isolate, all before home shows anything | 60–150 ms on a background thread (label + version per app), started while the prompt is up |
| Icons, first launch | (included above) | ~3–6 ms per icon on a background thread, only for rows on screen |
| Icons, later launches | (included above) | file-exists check per row; decode at display size |
| Secure-storage reads before the prompt | hasPin, cooldown, biometric flag: 3 serial initialisations (40–150 ms each) | 1 `readAll` before the first frame |
| Fingerprint → home | recovery-offer reads (2 initialisations, 80–300 ms) + config load + app list | one frame |
| Lock overlay launch | EncryptedSharedPreferences build on the main thread (30–100 ms) + JSON parse per accessor | none when the monitor service is running (it holds the store) |
