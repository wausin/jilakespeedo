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

  @override
  void initState() {
    super.initState();
    _loadDays();
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

    return Scaffold(
      key: TimelineScreen.markerKey,
      body: Column(
        children: [
          _DayChips(
            days: _days,
            activeDay: timeline.activeDay,
            onSelected: (day) async {
              await ref
                  .read(timelineControllerProvider.notifier)
                  .selectDay(day);
            },
          ),
          Expanded(
            child: TimelineMap(
              segments: segments,
              gaugeMaxMs: gaugeMaxMs,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: timeline.recording
            ? Theme.of(context).colorScheme.error
            : null,
        onPressed: () async {
          await ref.read(timelineControllerProvider.notifier).toggleRecording();
          await _loadDays();
        },
        child: Icon(timeline.recording ? Icons.stop : Icons.fiber_manual_record),
      ),
    );
  }
}

/// Horizontal list of recorded days as selectable chips.
class _DayChips extends StatelessWidget {
  const _DayChips({
    required this.days,
    required this.activeDay,
    required this.onSelected,
  });

  final List<DateTime> days;
  final DateTime? activeDay;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox(
        height: 56,
        child: Center(child: Text('No recorded days yet')),
      );
    }
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = days[index];
          final selected = activeDay != null &&
              day.year == activeDay!.year &&
              day.month == activeDay!.month &&
              day.day == activeDay!.day;
          return ChoiceChip(
            label: Text('${day.year}-${_two(day.month)}-${_two(day.day)}'),
            selected: selected,
            onSelected: (_) => onSelected(day),
          );
        },
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
