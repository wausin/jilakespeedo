# Jilake Speedo — Design Spec

Date: 2026-10-08
Status: Approved design, pending implementation plan

## 1. Summary

Jilake Speedo is a Flutter Web PWA: a racing-style GPS speedometer with vehicle
profiles, session-based trip statistics, and a manual route timeline. It runs
in any modern browser (Android Chrome first, iOS Safari supported), is
installable as an app, works offline, and stores all data locally on the
device. No accounts, no server, no cost to run.

Primary user: riders/drivers who mount their phone and want a beautiful live
speed display plus per-trip stats and a record of where they went.

## 2. Researched Constraints (verified)

- The browser Geolocation API (`navigator.geolocation.watchPosition`) provides
  a live position stream including `coords.speed` (m/s, GPS Doppler), heading,
  and accuracy. Requires HTTPS and a permission prompt.
- On web, continuous geolocation only works reliably while the app is in the
  foreground (screen on). Android PWAs degrade within minutes in the
  background; iOS stops almost immediately. Therefore route tracking is an
  **active, manually-controlled session** — user switches it ON before riding,
  OFF after. The phone is expected to be mounted/on during recording, held
  awake by a screen wake lock.
- Free maps: CARTO "dark_all" raster tiles (free, no API key, attribution
  required) via `flutter_map`, with standard OSM tiles as fallback. Zero map
  cost. Future premium option if ever needed: MapTiler (free 5k sessions/month,
  then $30/mo).

## 3. Decisions

| Decision | Choice |
| --- | --- |
| Tracking model | Active sessions, manual ON/OFF (no background tracking in v1) |
| Data storage | Local-first, no accounts — IndexedDB on device |
| Tech stack | Flutter Web (matches existing skills, later Android reuse) |
| Platform roadmap | Web PWA first; same codebase can target Android later |
| Architecture | Approach A: thin platform seams, direct JS interop for web GPS |

## 4. Screens

### 4.1 Speedo Screen (home)
- Racing gauge rendered with `CustomPainter` on canvas: dark carbon
  background, glowing needle with spring/eased animation, digital speed
  readout, peak-speed marker. Gauge range adapts to the active vehicle's
  `gaugeMax`.
- Portrait layout: gauge on top, vehicle switcher bar below (bottom).
- Landscape layout: gauge left, stats panel right, vehicle switcher adjusts
  to the layout (side/adjusted position).
- Vehicle switcher: horizontal bar showing the top-3 pinned vehicles; tap to
  switch instantly; long-press opens vehicle manager.
- Weak-signal indicator when GPS accuracy > 50 m.

### 4.2 Session Screen
- Configure a target: **by distance** (e.g. 1 km) or **by duration**
  (e.g. 5 min).
- Live progress display while running.
- On completion the session freezes and a summary card shows:
  - distance target: top speed, average speed, time to reach target.
  - duration target: distance covered, top speed, average speed.
- Sessions saved to history.

### 4.3 Timeline Screen
- Recording switched ON/OFF manually (separate from sessions).
- Map (`flutter_map`) with dark CARTO tiles showing the recorded route as a
  polyline; stops rendered as pins with dwell duration ("stayed 45 min at
  X"-style).
- Day list: pick a day to view its route and segments.

### 4.4 Settings
- Units: km/h ↔ mph (global, converts every screen instantly).
- Vehicle manager: add/edit/delete vehicles (name, type
  bike/motorcycle/car, optional gaugeMax e.g. 240 km/h, pin to top-3).
- Data export: GPX.
- PWA install instructions.

## 5. Architecture

```
UI (screens/widgets)
  SpeedoGauge · VehicleSwitcher · SessionPanel · TimelineMap · Settings
State (Riverpod providers/controllers)
  SpeedoController  ← subscribes to LocationService stream
  SessionController ← consumes same stream
  TimelineController
Services (interfaces, swappable)
  LocationService   → WebLocationService (JS interop: watchPosition
                      → speed, heading, accuracy; delta-based fallback
                      when coords.speed is null)
  StorageService    → IndexedDB (sembast + idb_shim)
  WakeLockService   → wakelock_plus, held while a session or timeline
                      recording is active
```

- Controllers consume a single location stream; the speedo is a live view and
  the session/timeline recorders are sinks over the same data.
- The gauge animates at display frame rate via a repaint stream; the needle
  uses spring easing so it never jitters on sparse updates.

## 6. Data Models

- `Vehicle` — id, name, type (bike | motorcycle | car), gaugeMax (default
  240 km/h), isPinned.
- `Session` — id, vehicleId, target (distance OR duration), startedAt,
  endedAt, status, summary {topSpeed, avgSpeed, distance, elapsed}.
- `TrackPoint` — lat, lng, timestamp, speed, accuracy. Written in batches to
  IndexedDB.
- `TimelineEntry` — day + ordered segments: `RideSegment` (polyline) or
  `StopSegment` (point + dwell duration).

## 7. Core Logic

### Session
Target progress is fed by the location stream; when the target is reached the
session freezes, the summary card is produced, and the record is persisted to
history. Distance-based targets measure cumulative distance traveled (not
displacement).

### Stop detection (timeline)
While recording: a stop is opened when the position stays within ~25 m
(accuracy radius included) for > 3 minutes; the ride segment closes, a stop
segment opens with its start time; movement beyond the radius resumes a new
ride segment. This yields Google-Timeline-like "went here, stayed N minutes"
entries.

### Speed fallback
`coords.speed` is authoritative when non-null. When null (some devices),
speed is computed from consecutive position deltas with smoothing, and the
needle easing absorbs the noise.

## 8. Error Handling

- Permission denied → friendly screen with instructions to re-enable
  location for the site.
- Weak GPS (accuracy > 50 m) → indicator on the gauge; points with poor
  accuracy are downweighted or dropped from recording.
- Browser without Geolocation → unsupported notice.
- Storage write failures → surfaced as a non-blocking banner; in-memory data
  preserved for the live session.

## 9. PWA & Hosting

- Customized manifest + service worker: name "Jilake Speedo", maskable icons,
  dark theme-color, standalone display.
- App shell cached for offline launch; all history data is local, so the app
  is fully functional offline (GPS itself needs no network).
- Hosted on HTTPS — free tier of Firebase Hosting / Netlify / Cloudflare
  Pages.

## 10. Testing

- Unit tests: session target logic (distance and duration variants), stop
  detection, speed fallback computation, unit conversion.
- Widget tests: gauge painter output, vehicle switcher, summary card.
- Manual device testing: real GPS behavior on Android Chrome and iOS Safari,
  PWA install, wake lock during a real ride.

## 11. Out of Scope (v1)

Accounts, cloud sync, always-on background tracking, sharing/social, native
APK. The `LocationService` / `StorageService` seams keep these open for later:
an Android build with true background geolocation is a future step, not a
rewrite.

## 12. Future Considerations

- Android Play Store build from the same codebase (swap in native
  `LocationService` implementation, e.g. background geolocation plugin).
- Optional GPX import, more export formats.
- Optional premium map styling (MapTiler) — not needed for launch.
