import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import 'timeline_controller.dart';
import 'timeline_map.dart';

/// Timeline screen: a dark map of the selected day's route with a record
/// toggle (FAB, red while recording) and a horizontal list of recorded days.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('timeline-screen');

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  List<DateTime> _days = const [];
  bool _offline = false;
  StreamSubscription<bool>? _offlineSub;
  final GlobalKey<TimelineMapState> _mapKey = GlobalKey<TimelineMapState>();

  @override
  void initState() {
    super.initState();
    _loadDays();
    final connectivity = ref.read(connectivityServiceProvider);
    _offline = connectivity.isOffline;
    _offlineSub = connectivity.offlineStream.listen((offline) {
      if (mounted) setState(() => _offline = offline);
    });
  }

  @override
  void dispose() {
    _offlineSub?.cancel();
    super.dispose();
  }

  Future<void> _loadDays() async {
    final days = await ref.read(storageServiceProvider).timelineDays();
    if (!mounted) return;
    setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineControllerProvider);
    final gaugeMaxKmh = ref.watch(vehiclesProvider).activeVehicle?.gaugeMaxKmh ??
        240.0;
    final gaugeMaxMs = gaugeMaxKmh / 3.6;
    final current = ref.watch(currentPositionProvider).value;

    // Surface a record-start failure (e.g. location stream errored) and
    // clear it so the snackbar shows once.
    final error = timeline.error;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
        ref.read(timelineControllerProvider.notifier).clearError();
      });
    }

    // While recording, show the live recording; otherwise show the selected
    // day's stored segments.
    final segments = timeline.recording
        ? timeline.liveSegments
        : [
            for (final entry in timeline.dayEntries) ...entry.segments,
          ];
    // Identity for auto-fit: the live recording, or the selected day.
    final fitKey = timeline.recording
        ? 'live'
        : (timeline.activeDay?.toIso8601String() ?? 'none');

    return Scaffold(
      key: TimelineScreen.markerKey,
      body: Stack(
        children: [
          TimelineMap(
            key: _mapKey,
            segments: segments,
            gaugeMaxMs: gaugeMaxMs,
            currentPosition: current,
            fitKey: fitKey,
          ),
          // Floating date selector (top): pick a recorded day, or clear.
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: _DateSelector(
              days: _days,
              activeDay: timeline.activeDay,
              onSelected: (day) =>
                  ref.read(timelineControllerProvider.notifier).selectDay(day),
              onCleared: () =>
                  ref.read(timelineControllerProvider.notifier).clearDay(),
            ),
          ),
          // Zoom + / - buttons.
          Positioned(
            right: 12,
            bottom: 84,
            child: Column(
              children: [
                _MapButton(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onPressed: () => _mapKey.currentState?.zoomIn(),
                ),
                const SizedBox(height: 8),
                _MapButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onPressed: () => _mapKey.currentState?.zoomOut(),
                ),
              ],
            ),
          ),
          // Center on me.
          Positioned(
            right: 12,
            bottom: 24,
            child: _MapButton(
              icon: Icons.my_location,
              tooltip: 'Center on my location',
              onPressed: current == null
                  ? null
                  : () => _mapKey.currentState?.centerOnCurrent(),
            ),
          ),
          if (_offline)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 16, color: Colors.amber),
                      SizedBox(width: 6),
                      Text(
                        'Offline — tiles may not load',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: timeline.recording
            ? Theme.of(context).colorScheme.error
            : null,
        onPressed: () async {
          await ref.read(timelineControllerProvider.notifier).toggleRecording();
          await _loadDays();
          // After stop, make sure the just-recorded day is shown.
          if (mounted) setState(() {});
        },
        icon: Icon(timeline.recording ? Icons.stop : Icons.fiber_manual_record),
        label: Text(timeline.recording ? 'Stop' : 'Record'),
      ),
    );
  }
}

/// Small square map control button.
class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, size: 20, color: Colors.white),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

/// Floating date selector: a dropdown of recorded days plus a clear action.
class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.days,
    required this.activeDay,
    required this.onSelected,
    required this.onCleared,
  });

  final List<DateTime> days;
  final DateTime? activeDay;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onCleared;

  static String _label(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.calendar_today, size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activeDay == null ? null : _label(activeDay!),
                hint: const Text(
                  'No date',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                dropdownColor: const Color(0xFF15151A),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                items: [
                  for (final d in days)
                    DropdownMenuItem(value: _label(d), child: Text(_label(d))),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final d = days.firstWhere((e) => _label(e) == v);
                  onSelected(d);
                },
              ),
            ),
            if (activeDay != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 16, color: Colors.white70),
                tooltip: 'Clear date',
                visualDensity: VisualDensity.compact,
                onPressed: onCleared,
              ),
          ],
        ),
      ),
    );
  }
}
