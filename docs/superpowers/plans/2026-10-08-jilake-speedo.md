# Jilake Speedo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter Web PWA GPS speedometer with vehicle profiles, session-based trip stats, and a manual route timeline.

**Architecture:** Riverpod state layer over three service seams (`LocationService`, `StorageService`, `WakeLockService`). A single GPS position stream feeds both the live speedo view and the session/timeline recorders. All data persists to IndexedDB; no server.

**Tech Stack:** Flutter 3.44 / Dart 3.12, flutter_riverpod, flutter_map, sembast + idb_shim, wakelock_plus, package:web (JS interop for Geolocation).

**Spec:** `docs/superpowers/specs/2026-10-08-jilake-speedo-design.md`

## Global Constraints

- App name everywhere (manifest, UI titles): **Jilake Speedo**.
- Speed source: `coords.speed` (m/s) is authoritative when non-null; fallback = smoothed delta of consecutive positions.
- Gauge default max: **240 km/h** (adapted per-vehicle via `gaugeMax`).
- Units: global km/h ↔ mph, stored in settings, converted at display.
- GPS accuracy > **50 m** → weak-signal indicator; points with accuracy > 50 m are excluded from recording.
- Stop detection: movement stays within **~25 m** for **> 3 minutes** → stop segment; movement beyond radius resumes ride segment.
- Session distance targets measure **cumulative distance traveled**, not displacement.
- Maps: CARTO `dark_all` tiles (`https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png`), attribution `&copy; OpenStreetMap contributors &copy; CARTO`. Free, no API key.
- PWA: standalone display, maskable icons, dark theme color, service worker caching app shell.
- Web-only in v1 (no Android target compiled), but services behind interfaces.
- Every task: `flutter analyze` clean, tests pass, then commit.

## Review Focus

- Sparse GPS jitter (speed spikes) → needle uses spring easing and recorded speeds are smoothed, so a single noisy fix does not jump the needle or inflate top speed.
- `coords.speed` = null on some devices → delta fallback with smoothing (harness `FixedFixtures.json` simulates it), no NaN reaches the UI.
- Distance target reached between fixes → session freezes at first fix where cumulative distance ≥ target, summary uses that moment's stats, no double-freeze on later fixes.
- Poor-accuracy fixes during recording → excluded from recorded track, session progress continues from last good fix.
- Large histories (months of TrackPoints) → day-list and map load per-day segments; batched storage writes; no full-table reads on app start.

---

### Task 1: Project scaffold + models

**Files:**
- Create: `flutter create` output (app name `jilake_speedo`), `pubspec.yaml` deps
- Create: `lib/core/models/models.dart` (barrel)
- Create: `lib/core/models/vehicle.dart`, `session.dart`, `track_point.dart`, `timeline_entry.dart`
- Create: `lib/core/models/units.dart` (SpeedUnit enum + conversions)
- Test: `test/models/units_test.dart`, `test/models/vehicle_test.dart`

**Interfaces:**
- Produces: `enum SpeedUnit { kmh, mph }`, `double convertSpeed({required double ms, required SpeedUnit unit})`, `double convertDistance({required double meters, required SpeedUnit unit})`, `String unitLabel(SpeedUnit)`;
  `class Vehicle { String id; String name; VehicleType type; double gaugeMaxKmh; bool isPinned; }`, `enum VehicleType { bike, motorcycle, car }`;
  `class TrackPoint { double lat, lng, speedMs, accuracyM; int timestampMs; }`;
  `sealed class TimelineSegment` with `RideSegment(List<TrackPoint> points)` and `StopSegment(TrackPoint center, int startMs, int endMs)`;
  `class SessionTarget` (`SessionTarget.distance(double meters)` / `SessionTarget.duration(int minutes)`), `class Session { ... summary }` with `SessionSummary { double topSpeedMs, avgSpeedMs, distanceM, elapsedMs; }`.

- [ ] **Step 1: Scaffold**

Run: `flutter create jilake_speedo --platforms web` in repo root, then move contents to repo root (keep `.git`, `docs/`). Add deps to `pubspec.yaml`: `flutter_riverpod`, `flutter_map`, `sembast`, `idb_shim`, `wakelock_plus`, `web` (dev: `flutter_lints`).

Run: `flutter pub get` → resolves clean.

- [ ] **Step 2: Write failing model tests**

`test/models/units_test.dart`: `convertSpeed(ms: 1, unit: kmh) == 3.6`; `convertSpeed(ms: 1, unit: mph) == 2.236936` (approx); `convertDistance(meters: 1000, kmh) == 1.0` km; `unitLabel(mph) == 'mph'`.
`test/models/vehicle_test.dart`: default vehicle `gaugeMaxKmh == 240`, `fromJson/toJson` round-trips.

- [ ] **Step 3: Run tests, verify they fail**

Run: `flutter test test/models`
Expected: FAIL — files don't compile / functions not defined.

- [ ] **Step 4: Implement models + conversions**

Plain Dart classes with `copyWith`, `toJson`/`fromJson` (sembast stores maps). Speed conversions: m/s → km/h `* 3.6`, m/s → mph `* 2.2369362920544`.

- [ ] **Step 5: Run tests, verify pass**

Run: `flutter test test/models && flutter analyze`
Expected: PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: project scaffold and core data models"
```

### Task 2: LocationService (web) + speed smoothing

**Files:**
- Create: `lib/core/services/location_service.dart` (interface + `PositionFix` type)
- Create: `lib/core/services/web_location_service.dart`
- Create: `lib/core/services/speed_smoother.dart`
- Create: `web/js/geolocation_bridge.js` (loaded via index.html `<script src="js/geolocation_bridge.js">`)
- Modify: `web/index.html` (script tag)
- Test: `test/services/speed_smoother_test.dart`

**Interfaces:**
- Consumes: `TrackPoint` (Task 1).
- Produces: `class PositionFix { double lat, lng, speedMs, accuracyM, headingDeg; int timestampMs; bool hasNativeSpeed; }`;
  `abstract class LocationService { Stream<PositionFix> watch(); Future<void> start(); Future<void> stop(); bool get isSupported; }`;
  `WebLocationService` implements it via the JS bridge. `SpeedSmoother.smooth(double newMs, int timestampMs) → double` — exponential smoothing `α = 0.4`, fallback delta speed capped at 75 m/s.

- [ ] **Step 1: Write failing tests for SpeedSmoother**

`test/services/speed_smoother_test.dart`: feeding a spike (0, 0, 40, 0, 0) yields max output < 40 (smoothing damps single spikes); steady input 10 m/s converges within 5 samples to ~10; first sample returns as-is.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/services/speed_smoother_test.dart`
Expected: FAIL — `speed_smoother.dart` doesn't exist.

- [ ] **Step 3: Implement SpeedSmoother**

Exponential moving average with `α = 0.4`; clamp output to [0, 75] m/s.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/services/speed_smoother_test.dart`
Expected: PASS.

- [ ] **Step 5: Implement LocationService interface + JS bridge**

`web/js/geolocation_bridge.js`: exposes `window.jilakeGeo = { start(successCallbackName, errCallbackName, json), stop() }` — wraps `navigator.geolocation.watchPosition` with `enableHighAccuracy: true, maximumAge: 0, timeout: 15000`; calls `window[callbackName](json)` with `{latitude, longitude, speed, accuracy, heading, timestamp}`; `stop()` calls `clearWatch`. Also exposes `jilakeGeo.speedSeen = false` (set true when any non-null speed arrives) — surfaced through `PositionFix.hasNativeSpeed` by checking `coords.speed !== null`.
`WebLocationService` (uses `package:web` + `dart:js_interop`): `start()` calls the bridge, converts JSON → `PositionFix`; `speedMs` uses native speed when non-null, otherwise delta-distance/haversine over previous fix fed through `SpeedSmoother`; `stop()` clears watch. Stream is a broadcast stream.

- [ ] **Step 6: Run analyze + tests, verify pass**

Run: `flutter analyze && flutter test test/services`
Expected: clean, PASS.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: web location service with speed smoothing fallback"
```

### Task 3: StorageService (IndexedDB via sembast)

**Files:**
- Create: `lib/core/services/storage_service.dart` (interface)
- Create: `lib/core/services/idb_storage_service.dart`
- Test: `test/services/idb_storage_service_test.dart`

**Interfaces:**
- Consumes: Task 1 models.
- Produces: `abstract class StorageService { Future<void> init(); Future<List<Vehicle>> vehicles(); Future<void> upsertVehicle(Vehicle); Future<void> deleteVehicle(String id); Future<void> saveSession(Session); Future<List<Session>> sessionsForVehicle(String vehicleId, {int limit}); Future<void> appendTrackPoints(String sessionId, List<TrackPoint> points); Future<List<TrackPoint>> trackPoints(String sessionId); Future<void> upsertTimelineEntry(TimelineEntry); Future<List<TimelineEntry>> timelineEntriesForDay(DateTime day); Future<List<DateTime>> timelineDays(); }`

- [ ] **Step 1: Write failing storage tests**

`test/services/idb_storage_service_test.dart` (uses `sembast` memory factory via `idb_shim`): upsert/fetch vehicles; save session + sessionsForVehicle returns newest-first; appendTrackPoints batched then trackPoints returns in order; timeline entry round-trip with ride+stop segments; delete vehicle removes it.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/services/idb_storage_service_test.dart`
Expected: FAIL — class doesn't exist.

- [ ] **Step 3: Implement IdbStorageService**

Sembast `databaseFactoryWeb` (web) / `databaseFactoryIdb` (test) behind the interface; stores: `vehicles` (key `id`), `sessions` (key `id`), `track_points` (auto-increment key, index on `sessionId`), `timeline_entries` (key `id`). Timeline segments serialized to/from JSON lists.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/services/idb_storage_service_test.dart && flutter analyze`
Expected: PASS, clean.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: IndexedDB storage service"
```

### Task 4: Session engine (target logic)

**Files:**
- Create: `lib/core/controllers/session_engine.dart`
- Test: `test/controllers/session_engine_test.dart`

**Interfaces:**
- Consumes: `PositionFix` (Task 2), `Session`, `SessionTarget`, `SessionSummary` (Task 1).
- Produces: `class SessionEngine { SessionEngine({required double accuracyThresholdM}); void start({required String vehicleId, required SessionTarget target, required int startedAtMs}); SessionState? onFix(PositionFix fix); }` — `SessionState { String vehicleId; SessionTarget target; int startedAtMs; double cumulativeDistanceM; double topSpeedMs; List<double> speedSamples; bool finished; SessionSummary? summary; }`. Distance = haversine sum over included fixes.

- [ ] **Step 1: Write failing tests**

`test/controllers/session_engine_test.dart` with a `fix()` helper:
- distance target 1000 m: fixes at 10 m/s spaced 10 s → finishes exactly when cumulative ≥ 1000; summary `topSpeedMs == 10`, `avgSpeedMs ≈ 10`, `elapsedMs` matches fix count.
- duration target 2 min: fixes for 3 min → finishes at the 2-minute fix; `distanceM` equals sum of deltas.
- accuracy gate: a fix with `accuracyM: 120` does not advance distance and is not sampled for speed (top speed unaffected by a 50 m/s spike on a bad fix).
- late fix after finish → `onFix` returns same finished state, no changes (no double-freeze).

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/controllers/session_engine_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement SessionEngine**

Pure Dart, no Flutter imports. Haversine distance; fixes with `accuracyM > accuracyThresholdM` (default 50) skipped; on target reach: `finished = true`, compute summary (avg = mean of speed samples), freeze. `speedSamples` only good fixes.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/controllers/session_engine_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: session engine with distance/duration targets"
```

### Task 5: Stop detector (timeline)

**Files:**
- Create: `lib/core/controllers/stop_detector.dart`
- Test: `test/controllers/stop_detector_test.dart`

**Interfaces:**
- Consumes: `PositionFix` (Task 2), `TimelineSegment` (Task 1).
- Produces: `class StopDetector { StopDetector({double radiusM = 25, int minStopMs = 180000}); StopDetectorState get state; void onFix(PositionFix fix); void reset(); }` — `StopDetectorState { bool inStop; List<TrackPoint> currentRide; List<TimelineSegment> closedSegments; }`

- [ ] **Step 1: Write failing tests**

`test/controllers/stop_detector_test.dart`:
- moving fixes → `closedSegments` empty, `currentRide` accumulates.
- fixes clustered within 25 m for 4 min → a `StopSegment` with correct start/end, then movement → new ride segment appended to `closedSegments`.
- short pause (2 min, < 3-min threshold) → no stop recorded, points stay in `currentRide`.
- `reset()` clears everything.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/controllers/stop_detector_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement StopDetector**

Track centroid (running mean of positions while stationary); open stop when all fixes within radius for `minStopMs`; close stop when a fix lands beyond radius; ride points between stops buffer into `currentRide`, closed rides go to `closedSegments`.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/controllers/stop_detector_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: stop detector for timeline segments"
```

### Task 6: Riverpod providers + app shell + navigation

**Files:**
- Create: `lib/app.dart` (MaterialApp.router, dark theme, ProviderScope)
- Create: `lib/core/controllers/providers.dart` (service providers, SettingsController, VehicleController)
- Create: `lib/features/speedo/speedo_screen.dart`, `lib/features/session/session_screen.dart`, `lib/features/timeline/timeline_screen.dart`, `lib/features/settings/settings_screen.dart` (placeholder content initially)
- Create: `lib/main.dart` (init storage, run app)
- Test: `test/app_shell_test.dart`

**Interfaces:**
- Consumes: services (Tasks 2–3), models (Task 1).
- Produces: `settingsControllerProvider` (StateNotifier<SettingsState> exposing `SpeedUnit unit`, persisted), `vehiclesProvider` (StateNotifier<VehiclesState> — list, activeVehicleId, `setActive`, `upsert`, `delete`, `pin`), `Provider<LocationService>`, `Provider<StorageService>`, `wakeLockServiceProvider` (wraps `wakelock_plus`: `Future<void> hold()`, `Future<void> release()`; keeps a ref-count so session+timeline can hold concurrently); app router with 4 routes: `/`, `/session`, `/timeline`, `/settings`.

- [ ] **Step 1: Write failing shell test**

`test/app_shell_test.dart`: pump `JilakeSpeedoApp` (with overridden providers: fake LocationService stream controller, in-memory storage). Navigation bar has 4 destinations; tapping navigates to each screen (finds each screen's key marker). Settings unit toggle switches displayed labels km/h → mph.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/app_shell_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement shell, providers, placeholder screens**

go_router not needed — `IndexedStack` + `NavigationBar` (mobile-first). Dark `ColorScheme.fromSeed(seedColor: Color(0xFFFF3B30))` racing red. `SettingsState` persists unit via StorageService (`settings` string store). Vehicles loaded at init; default vehicle created on first run ("My Ride", motorcycle, 240, pinned). Unit changes notify all screens via provider.
Permission-denied handling: `LocationService.watch()` error callback maps `GeolocationPositionError` codes (1 = permission denied) to a `LocationStatus` value; shell listens — on denied, shows a friendly full-screen explaining how to re-enable site location (Android Chrome: lock icon → Permissions; iOS Safari: Settings → Safari → Location), with retry button. Add `test/app_shell_test.dart` case: denied status → friendly screen visible with retry.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/app_shell_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: app shell, navigation, riverpod providers"
```

### Task 7: Speedo gauge + vehicle switcher (Speedo screen)

**Files:**
- Create: `lib/features/speedo/gauge_painter.dart`
- Create: `lib/features/speedo/speedo_controller.dart`
- Create: `lib/features/speedo/vehicle_switcher.dart`
- Modify: `lib/features/speedo/speedo_screen.dart`
- Test: `test/features/speedo/gauge_painter_test.dart`, `test/features/speedo/speedo_controller_test.dart`

**Interfaces:**
- Consumes: `LocationService.watch()` (Task 2), `vehiclesProvider`, `settingsControllerProvider` (Task 6), `SpeedUnit` conversions (Task 1).
- Produces: `SpeedoController extends AutoDisposeNotifier<SpeedoState>` — `SpeedoState { double displaySpeedMs; double peakSpeedMs; bool weakSignal; }`; needle spring animation driven by `AnimationController` (duration 300 ms, `Curves.easeOutCubic`) toward latest target; `GaugePainter(rangeKmh: double, speedFraction: double, peakFraction: double, weakSignal: bool)` painting ticks, digits, peak marker, redline arc (last 10% of range).

- [ ] **Step 1: Write failing tests**

`gauge_painter_test.dart`: `GaugePainter(rangeKmh: 240, speedFraction: 0.5, peakFraction: 0.75, weakSignal: false)` — `shouldRepaint` true when any field differs; painter paints without exception (golden-lite: canvas mock records arc/draw calls > 0).
`speedo_controller_test.dart`: emitting fix at 20 m/s → `displaySpeedMs` approaches 20 (after simulated animation tick), `peakSpeedMs == 20`; fix with accuracy 120 → `weakSignal == true` and display speed unchanged (bad fix ignored); fix with `speedMs: 5` after peak 20 → peak stays 20.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/speedo`
Expected: FAIL.

- [ ] **Step 3: Implement gauge painter, controller, switcher, screen**

Gauge: 270° sweep from 225° to 495° (i.e. start bottom-left), major ticks every 20 km/h (label every 40), minor ticks every 10; digital readout center-bottom; peak marker thin red line at peak angle; weak-signal = amber pulsing dot. Needle: red glowing line with `MaskFilter.blur`. Layout: `OrientationBuilder` — portrait: gauge top / switcher bottom; landscape: gauge left / stats right (`SafeArea` respected). `VehicleSwitcher`: horizontal `ListView` of pinned vehicles (max 3) + trailing "manage" button → `/settings` vehicles section; long-press also opens manager.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/features/speedo && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: racing gauge, speedo controller, vehicle switcher"
```

### Task 8: Session screen (UI + integration)

**Files:**
- Create: `lib/features/session/session_controller.dart`
- Modify: `lib/features/session/session_screen.dart`
- Test: `test/features/session/session_controller_test.dart`, `test/features/session/session_screen_test.dart`

**Interfaces:**
- Consumes: `SessionEngine` (Task 4), `LocationService`, `WakeLockService` (Task 6 provides `wakeLockServiceProvider` wrapping `wakelock_plus`), `StorageService`, `vehiclesProvider`.
- Produces: `SessionController` — `start(target)`, `stop()`; live state = `SessionState` + progress fraction; on finish: persists `Session` + TrackPoints via storage, releases wake lock, exposes `lastSummary`.

- [ ] **Step 1: Write failing tests**

`session_controller_test.dart`: fake location stream; start with distance target 100 m, emit fixes 10 m/s/1 s apart → after 10 s worth of fixes: finished, summary saved to fake storage, wake lock enable/disable called (fake records calls), progress fraction hit 1.0. `stop()` mid-session → session saved with `status: stopped`.
`session_screen_test.dart`: target picker shows distance/duration options; summary card shows top/avg speed + elapsed (distance mode) or distance + speeds (duration mode) with correct unit labels.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/session`
Expected: FAIL.

- [ ] **Step 3: Implement controller + screen**

Config UI: segmented button [Distance | Duration] + numeric stepper (distance: 0.5/1/2/5/10 km or mi; duration: 1/3/5/10/30 min) + Start. Live: circular progress + current stats. Summary card: unit-aware via settings. History list (last 10 sessions for active vehicle) at bottom.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/features/session && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: session screen with targets and summaries"
```

### Task 9: Timeline screen (map + recording)

**Files:**
- Create: `lib/features/timeline/timeline_controller.dart`
- Create: `lib/features/timeline/timeline_map.dart`
- Modify: `lib/features/timeline/timeline_screen.dart`
- Test: `test/features/timeline/timeline_controller_test.dart`, `test/features/timeline/timeline_map_test.dart`

**Interfaces:**
- Consumes: `StopDetector` (Task 5), `LocationService`, `StorageService`, `WakeLockService`, `flutter_map`.
- Produces: `TimelineController` — `toggleRecording()`, state: `{bool recording; List<TimelineSegment> liveSegments; DateTime? activeDay; List<TimelineEntry> dayEntries;}`; persists closed segments + on stop-off flushes current ride. `TimelineMap` widget: `flutter_map` `MapOptions` with CARTO dark `TileLayer` (attribution as Global Constraint), `PolylineLayer` speed-colored, stop markers with dwell label.

- [ ] **Step 1: Write failing tests**

`timeline_controller_test.dart`: toggle ON + fake fixes (moving 5 min) → liveSegments grows, on toggle OFF → `TimelineEntry` persisted to fake storage with correct day; wake lock held while on. Replay of a stored day → `dayEntries` populated.
`timeline_map_test.dart`: widget builds with a fixed segment list without throwing; polyline layer present; attribution text present (finds `OpenStreetMap` text).

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/timeline`
Expected: FAIL.

- [ ] **Step 3: Implement controller, map, screen**

Screen: record toggle (FAB, red when recording), day list (horizontal chips from `timelineDays()`), map fills rest. Polyline color by segment speed: <30% gaugeMax blue → >70% red gradient (lerped). Stop marker: circular pin + "N min" label. Map centers on route bounds via `MapController.fitCamera(CameraFit.bounds(...))` when day selected.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/features/timeline && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: timeline recording screen with dark map"
```

### Task 10: Settings screen + vehicle manager + GPX export

**Files:**
- Create: `lib/features/settings/vehicle_manager_screen.dart`
- Create: `lib/core/services/gpx_exporter.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Test: `test/features/settings/vehicle_manager_test.dart`, `test/services/gpx_exporter_test.dart`

**Interfaces:**
- Consumes: `vehiclesProvider`, `settingsControllerProvider`, `StorageService`, `TrackPoint`/`Session` models.
- Produces: `GpxExporter.gpx({required List<TrackPoint> points, required String vehicleName}) → String`; `GpxExporter.download(String xml, String filename)` (web anchor download). Vehicle manager: list, add/edit form dialog (name, type, gaugeMax, pin), delete with confirm, pin limit 3 (pinning a 4th unpins oldest).

- [ ] **Step 1: Write failing tests**

`gpx_exporter_test.dart`: 3 points → valid GPX 1.1 XML with `<trkpt lat lon>` count 3, `<name>vehicleName</name>`, `<trk><trkseg>` structure, parseable by `xml` package (add dev dep).
`vehicle_manager_test.dart`: pin limit — 3 pinned, pin 4th → oldest pinned becomes unpinned; delete active vehicle → falls back to first remaining.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/features/settings test/services/gpx_exporter_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement manager + exporter + settings UI**

Settings sections: Units toggle; Vehicles (open manager); Export (per session GPX download); About/install instructions (Android Chrome menu → Install app; iOS Safari share → Add to Home Screen).

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/features/settings test/services/gpx_exporter_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: settings, vehicle manager, GPX export"
```

### Task 11: PWA manifest, service worker, icons + polish

**Files:**
- Modify: `web/manifest.json` (name, icons, theme_color `#0E0E10`, background_color, standalone)
- Modify: `web/index.html` (theme-color meta, apple-touch-icon, title)
- Create: `web/icons/` (192/512 maskable PNGs — generated simple dark+red gauge icon)
- Modify: `web/flutter_service_worker.js` behavior via `flutter build web --pwa-strategy=offline-first` build flag; add custom offline fallback page `web/offline.html`
- Test: manual + `test/pwa_test.dart` (parsing manifest assertions)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: installable PWA artifacts.

- [ ] **Step 1: Write failing manifest test**

`test/pwa_test.dart`: reads `web/manifest.json` — name == "Jilake Speedo", display == "standalone", has icons 192 & 512 with `"purpose": "maskable"` entry, theme_color == "#0E0E10"; `web/index.html` contains `<meta name="theme-color" content="#0E0E10">`.

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/pwa_test.dart`
Expected: FAIL (default manifest has "flutter_app" name).

- [ ] **Step 3: Update manifest, icons, index.html, offline page**

Simple generated icon: solid `#0E0E10` rounded square, red needle arc at 60% — via a small Dart script `tool/gen_icons.dart` run once (`dart run tool/gen_icons.dart`, using `image` package, committed output). Build config: default `flutter build web` includes service worker; verify `--pwa-strategy` docs for current flag or keep default SW + ensure `offline.html` referenced.

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/pwa_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 5: Production build smoke test**

Run: `flutter build web` → succeeds; check `build/web/manifest.json`, service worker present, icons copied.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: PWA manifest, icons, offline polish"
```

### Task 12: Final verification pass

**Files:**
- Modify: any file failing checks.

- [ ] **Step 1: Full suite**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 2: Analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: Build**

Run: `flutter build web`
Expected: success, output size reported.

- [ ] **Step 4: Manual test on device (user)**

Serve `build/web` over HTTPS (or `flutter run -d chrome`), verify: permission prompt → gauge moves, unit toggle converts, vehicle switch works portrait+landscape, session completes + summary, timeline records + map renders, install prompt works on Android Chrome.

- [ ] **Step 5: Commit any fixes + final tag**

```bash
git add -A && git commit -m "chore: final verification fixes" && git tag v0.1.0
```
