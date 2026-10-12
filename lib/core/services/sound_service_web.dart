import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'sound_service.dart';

/// Default bundled hit-mark sound (placed by the user at
/// `web/sounds/hitmark.mp3`, served from the app root).
const String defaultHitMarkUrl = 'sounds/hitmark.mp3';

/// Web [SoundService]: plays an [HTMLAudioElement] once, best-effort.
class WebSoundService implements SoundService {
  web.HTMLAudioElement? _element;

  @override
  Future<void> playHitMark({String? url}) async {
    try {
      final src = url ?? defaultHitMarkUrl;
      final audio = _element ??= web.HTMLAudioElement();
      audio.src = src;
      audio.currentTime = 0;
      audio.volume = 1.0;
      final p = audio.play();
      // play() returns a Promise; swallow rejection (autoplay blocked).
      p.toDart.catchError((Object _) => null);
    } catch (_) {
      // Never let audio break the speedo.
    }
  }
}

/// Factory used by conditional imports (see stub for non-web).
SoundService createSoundService() => WebSoundService();
