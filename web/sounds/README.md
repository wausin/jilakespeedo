Put the hit-mark celebration sound here as `hitmark.mp3`.

It is played on the Speedo screen when your speed crosses the
"Hit-mark speed" set in Settings (default 100 km/h).

- File name must be exactly:  hitmark.mp3
- Format: mp3 (or change `defaultHitMarkUrl` in
  lib/core/services/sound_service_web.dart to match .ogg/.wav)
- Users can override it in the app later via "Choose sound" (not yet wired).

If this file is missing, the app simply stays silent — nothing breaks.
