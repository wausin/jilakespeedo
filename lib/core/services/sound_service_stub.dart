import 'sound_service.dart';

/// Stub for non-web platforms (VM tests): audio is a no-op.
SoundService createSoundService() => const _StubSoundService();

class _StubSoundService implements SoundService {
  const _StubSoundService();

  @override
  Future<void> playHitMark({String? url}) async {}
}
