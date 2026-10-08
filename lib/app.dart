import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/controllers/providers.dart';
import 'core/services/location_service.dart';
import 'features/session/session_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/speedo/speedo_screen.dart';
import 'features/timeline/timeline_screen.dart';

/// Root widget: dark racing-red theme hosting the navigation shell.
class JilakeSpeedoApp extends StatelessWidget {
  const JilakeSpeedoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jilake Speedo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF3B30),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

/// Navigation shell: [IndexedStack] + [NavigationBar] with 4 destinations.
///
/// Listens to the location status stream; on permission-denied the body is
/// replaced with a friendly full-screen explaining how to re-enable site
/// location, with a retry button.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  /// Marker for the permission-denied full-screen.
  static const Key permissionDeniedKey = Key('permission-denied-screen');

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const List<Widget> _screens = [
    SpeedoScreen(),
    SessionScreen(),
    TimelineScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    ref.read(locationServiceProvider).start();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(locationStatusProvider).value;
    final denied = status == LocationStatus.permissionDenied;

    return Scaffold(
      body: denied
          ? _PermissionDeniedScreen(
              key: AppShell.permissionDeniedKey,
              onRetry: () => ref.read(locationServiceProvider).start(),
            )
          : IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed),
            label: 'Speedo',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            label: 'Session',
          ),
          NavigationDestination(
            icon: Icon(Icons.route),
            label: 'Timeline',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Friendly full-screen shown when geolocation permission is denied,
/// with re-enable instructions per browser and a retry button.
class _PermissionDeniedScreen extends StatelessWidget {
  const _PermissionDeniedScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Location permission denied',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Jilake Speedo needs your location to measure speed.\n\n'
              'To re-enable:\n'
              '• Android Chrome: tap the lock icon in the address bar → '
              'Permissions → Location → Allow.\n'
              '• iOS Safari: Settings → Safari → Location → Allow.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
