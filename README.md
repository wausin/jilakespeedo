# Jilake Speedo

A racing-style GPS speedometer for the browser. Install it as an app on your phone, and it keeps working with no signal — no accounts, no server, all data stays on your device.

## Features

- **Speedo gauge** — large dark racing-style dial with vehicle profiles (car, bike, etc.), switchable on the fly
- **Session stats** — per-ride distance, duration, top and average speed, with distance targets
- **Route timeline** — record rides, replay them on a dark map, automatic stop detection (25 m radius for 3+ min)
- **Vehicle manager** — custom vehicles with unit preferences (km/h / mph)
- **GPX export** — take your recorded routes anywhere
- **Local-first** — everything stored in IndexedDB on your device; works offline once installed
- **Keeps screen awake** while riding, with an offline indicator

## Install as an app

- **Android Chrome**: menu → *Add to Home screen*
- **iOS Safari**: Share → *Add to Home Screen*

Geolocation requires HTTPS (or `localhost` in development).

## Development

```powershell
flutter run -d chrome     # local dev
flutter test              # run test suite
flutter analyze           # must be clean before committing
flutter build web         # production build -> build/web
```

Deploy `build/web` to any static HTTPS host.

## Tech

- Flutter 3.44 / Dart 3.12, web target
- `flutter_riverpod` for state
- `flutter_map` + CARTO `dark_all` tiles (free, no key, attribution required)
- `sembast_web` for IndexedDB storage
- `wakelock_plus` to keep the screen on
- `package:web` for Geolocation JS interop

## Project layout

- `lib/core/` — pure Dart logic: models, session engine, stop detection, speed smoothing, unit conversion
- `lib/core/services/` — platform seams: location (Geolocation bridge), storage (IndexedDB), wake lock
- `lib/features/` — UI: speedo, session, timeline, settings

## Workflow

`main` is always deployable. Work on `feature/*` branches and merge via PR. Releases are tagged `v*.*.*`.

Design spec and implementation plan live in `docs/superpowers/`.
