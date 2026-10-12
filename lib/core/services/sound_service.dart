/// Plays the hit-mark celebration sound.
///
/// The default sound is bundled at `web/sounds/hitmark.mp3` (served from the
/// app root). A user-chosen override can be supplied as a data/object URL.
abstract class SoundService {
  /// Plays [url] (or the bundled default when null) once.
  ///
  /// Must be best-effort: a browser may block audio before a user gesture,
  /// and a missing file must never throw into the UI.
  Future<void> playHitMark({String? url});
}
