# Jilake Speedo

Flutter Web PWA: a racing-style GPS speedometer with vehicle profiles, session-based trip stats, and a manual route timeline. Runs in any modern browser (Android Chrome first, iOS Safari supported), installable as an app, works offline, local-first data — no accounts, no server.

## Stack

- Flutter 3.44.8 / Dart 3.12.2 (web target only in v1)
- flutter_riverpod (state), flutter_map + latlong2 (map), sembast + sembast_web (IndexedDB storage), wakelock_plus, package:web (JS interop for Geolocation)
- Map tiles: CARTO `dark_all` (free, no key, attribution required)

## Commands

```powershell
flutter test              # full test suite (103 tests)
flutter analyze           # must be clean before committing
flutter build web         # production build -> build/web
flutter run -d chrome     # local dev (geolocation needs https or localhost)
```

## Architecture

Service seams behind interfaces (swappable per platform later — Android native is the future path):
- `LocationService` → `WebLocationService` (JS bridge to `navigator.geolocation.watchPosition`; native `coords.speed` authoritative, haversine-delta fallback smoothed)
- `StorageService` → `IdbStorageService` (IndexedDB via sembast; per-row decode guarded against corrupt rows)
- `WakeLockService` (ref-counted hold/release; session + timeline can hold concurrently)

Core logic is pure Dart (no Flutter imports) in `lib/core/`: models, `SpeedSmoother`, `SessionEngine`, `StopDetector`, unit conversions. UI in `lib/features/`: speedo (CustomPainter gauge + vehicle switcher), session (targets + summaries), timeline (map + recording), settings (units, vehicle manager, GPX export, install instructions). App shell: `IndexedStack` + `NavigationBar`, dark racing theme.

Key constants (plan Global Constraints): gauge default 240 km/h; GPS accuracy > 50 m = weak signal / excluded from recording; stop detection = 25 m radius for > 3 min; session distance = cumulative travel, not displacement.

## Conventions

- `flutter analyze` clean + tests pass before every commit
- TDD: failing test first, then implement
- Local-first: all data IndexedDB on device; storage failures never crash a live session (wake lock still released, summary still shown)
- Services behind interfaces; pure-Dart core logic stays Flutter-free
- Never commit to `main` directly — feature branches + PR (see workflow below)

## Git workflow

- `main` = always deployable. Work on `feature/*` branches, merge via PR.
- Worktrees for parallel work live in `.worktrees/` (git-ignored).
- Deployable artifact is `build/web` (static files; needs HTTPS hosting for geolocation).
- Releases tagged `v*.*.*`.

### Release rule (ALWAYS, after every merge to main)

After every merge to `main`, automatically:
1. Bump `version:` in `pubspec.yaml` — **minor** (`1.0.1`→`1.1.0`) for features,
   **patch** (`1.0.1`→`1.0.2`) for fixes/polish, **major** (`1.x`→`2.0.0`) for
   breaking/landmark changes; always increment the `+N` build number.
2. Run `tool\release.ps1` (NOT plain `flutter build web`) — it injects
   `APP_VERSION` from pubspec so the running build matches the server's
   `version.json` and the update badge behaves correctly.
3. Commit the version bump and push.

The user deploys `build/web` manually. Never deploy a plain
`flutter build web` (APP_VERSION defaults to `dev` → the badge shows forever).

## Notes

- `.worktrees/jilake-speedo-v1` holds uncommitted "update checker" WIP (preserved intentionally — not part of v0.1.0).
- Design spec: `docs/superpowers/specs/2026-10-08-jilake-speedo-design.md`; implementation plan: `docs/superpowers/plans/2026-10-08-jilake-speedo.md`.
