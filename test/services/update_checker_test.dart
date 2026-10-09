import 'package:flutter_test/flutter_test.dart';
import 'package:jilake_speedo/core/controllers/update_controller.dart';
import 'package:jilake_speedo/core/services/update_checker.dart';

/// Fake checker with a configurable server version.
class FakeUpdateChecker extends UpdateChecker {
  FakeUpdateChecker({required this.running, this.server});

  final String running;
  final String? server;

  int fetchCount = 0;

  @override
  String get runningVersion => running;

  @override
  Future<String?> fetchServerVersion() async {
    fetchCount++;
    return server;
  }
}

void main() {
  group('UpdateChecker.isUpdateAvailable', () {
    test('returns false when versions match', () async {
      final checker = FakeUpdateChecker(running: '1.0.0+1', server: '1.0.0+1');
      expect(await checker.isUpdateAvailable(), isFalse);
      expect(checker.fetchCount, 1);
    });

    test('returns true when server version differs', () async {
      final checker = FakeUpdateChecker(running: '1.0.0+1', server: '1.0.0+2');
      expect(await checker.isUpdateAvailable(), isTrue);
    });

    test('returns false when the server cannot be reached', () async {
      final checker = FakeUpdateChecker(running: '1.0.0+1', server: null);
      expect(await checker.isUpdateAvailable(), isFalse);
    });
  });

  group('checkUpdateNow', () {
    test('reports up-to-date with the running version when server matches',
        () async {
      final checker = FakeUpdateChecker(running: '1.0.0+1', server: '1.0.0+1');
      final result = await checkUpdateNow(checker);
      expect(result.available, isFalse);
      expect(result.message, contains('up to date'));
      expect(result.message, contains('1.0.0+1'));
    });

    test('reports an available update naming the server version', () async {
      final checker = FakeUpdateChecker(running: '1.0.0+1', server: '1.0.0+2');
      final result = await checkUpdateNow(checker);
      expect(result.available, isTrue);
      expect(result.message, contains('1.0.0+2'));
    });

    test('reports offline / unreachable without claiming an update', () async {
      final checker = FakeUpdateChecker(running: '1.0.0+1', server: null);
      final result = await checkUpdateNow(checker);
      expect(result.available, isFalse);
      expect(result.message.toLowerCase(), contains('could not'));
    });
  });
}
