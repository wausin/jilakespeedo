import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/controllers/providers.dart';
import 'core/controllers/update_controller.dart';
import 'core/services/location_service.dart';
import 'core/services/reloader_stub.dart'
    if (dart.library.js_interop) 'core/services/reloader_web.dart';
import 'features/session/session_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/speedo/speedo_screen.dart';
import 'features/timeline/timeline_screen.dart';
import 'features/update/update_badge.dart';

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
  Timer? _updateTimer;
  late final WakeLockService _wakeLock;

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
    // The speedo is the always-visible riding screen: hold the wake lock
    // while it is the active tab so the phone does not dim/lock mid-ride.
    // Capture the service now: ref is not usable from dispose().
    _wakeLock = ref.read(wakeLockServiceProvider);
    unawaited(_wakeLock.hold());
    // Check for a newer deployed build on start, then periodically.
    unawaited(
      startUpdateChecks(
        ref.read(updateCheckerProvider),
        (available) {
          if (!mounted) return;
          ref.read(updateAvailableProvider.notifier).state = available;
        },
      ).then((timer) => _updateTimer = timer),
    );
    // The speedo vehicle switcher's manage affordances open the Settings
    // screen with the vehicles section scrolled into view.
    SpeedoScreen.onManageVehicles = () {
      setState(() => _index = 3);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = SettingsScreen.vehiclesSectionKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            alignment: 0.1,
          );
        }
      });
    };
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    // Release the speedo hold if it is still held (speedo active at dispose).
    if (_index == 0) {
      unawaited(_wakeLock.release());
    }
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    if (index == _index) return;
    // Hold while the speedo tab is active, release when leaving it. The
    // ref-counted service means session/timeline holds are unaffected.
    if (_index == 0) {
      unawaited(_wakeLock.release());
    } else if (index == 0) {
      unawaited(_wakeLock.hold());
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(locationStatusProvider).value;
    final denied = status == LocationStatus.permissionDenied;
    final updateAvailable = ref.watch(updateAvailableProvider);

    return Scaffold(
      body: denied
          ? _PermissionDeniedScreen(
              key: AppShell.permissionDeniedKey,
              onRetry: () => ref.read(locationServiceProvider).start(),
            )
          : Stack(
              children: [
                IndexedStack(index: _index, children: _screens),
                if (updateAvailable)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 8,
                    right: 12,
                    child: UpdateBadge(onTap: reloadApp),
                  ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.speed),
            label: 'Speedo',
          ),
          const NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            label: 'Session',
          ),
          const NavigationDestination(
            icon: Icon(Icons.route),
            label: 'Timeline',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: updateAvailable,
              smallSize: 8,
              child: const Icon(Icons.settings_outlined),
            ),
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
