import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';
import 'session_controller.dart';

/// Distance presets in the display unit (km for km/h, miles for mph).
const List<double> _distancePresets = [0.5, 1, 2, 5, 10];

/// Duration presets in minutes.
const List<int> _durationPresets = [1, 3, 5, 10, 30];

/// Label for a distance amount in the display unit (`1 km`, `0.5 mi`).
String distanceLabel(double meters, SpeedUnit unit) {
  final value = convertDistance(meters: meters, unit: unit);
  final suffix = unit == SpeedUnit.kmh ? 'km' : 'mi';
  return '${_trimZero(value)} $suffix';
}

/// Label for an elapsed duration (`m:ss` under an hour, `h:mm:ss` above).
String elapsedLabel(int ms) {
  final totalSeconds = ms ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

String _trimZero(double value) {
  final fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// Marker on the summary card (exported for tests).
const Key sessionSummaryKey = Key('session-summary');

/// Marker on the live progress section (exported for tests).
const Key sessionLiveKey = Key('session-live');

/// Session screen: target configuration, live progress toward the target,
/// the summary card of the last session, and the recent-session history.
class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('session-screen');

  /// Marker for the target configuration section.
  static const Key configKey = Key('session-config');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final live = session.live;
    final running = live != null && !live.finished;
    // Summary shows once a session has ended (completed: live is the frozen
    // state; stopped: live is null) and stays visible until a new run.
    final showSummary = session.lastSummary != null && !running;

    return SafeArea(
      key: markerKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (running)
            const _LiveSection(key: sessionLiveKey)
          else
            _ConfigSection(key: configKey),
          if (showSummary)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: _SummaryCard(key: sessionSummaryKey),
            ),
          const SizedBox(height: 24),
          const _HistorySection(),
        ],
      ),
    );
  }
}

/// Target configuration: mode selector, preset stepper, start button.
class _ConfigSection extends ConsumerStatefulWidget {
  const _ConfigSection({super.key});

  @override
  ConsumerState<_ConfigSection> createState() => _ConfigSectionState();
}

class _ConfigSectionState extends ConsumerState<_ConfigSection> {
  bool _durationMode = false;
  int _index = 2; // distance: 2 km/mi, duration: 5 min

  void _setMode({required bool duration}) => setState(() {
        _durationMode = duration;
        _index = 2;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final presets = _durationMode
        ? _durationPresets.map((m) => '$m').toList()
        : _distancePresets.map(_trimZero).toList();
    final suffix = _durationMode
        ? 'min'
        : (unit == SpeedUnit.kmh ? 'km' : 'mi');

    SessionTarget target() {
      if (_durationMode) {
        return DurationTarget(_durationPresets[_index]);
      }
      final preset = _distancePresets[_index];
      final meters = unit == SpeedUnit.kmh ? preset * 1000 : preset * 1609.344;
      return DistanceTarget(meters);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Distance')),
            ButtonSegment(value: true, label: Text('Duration')),
          ],
          selected: {_durationMode},
          onSelectionChanged: (selection) => _setMode(duration: selection.first),
        ),
        const SizedBox(height: 16),
        Text(
          _durationMode ? 'Ride for' : 'Ride at least',
          style: theme.textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        // Preset stepper: every option stays on screen (greyed out when not
        // selected) so the available choices are visible at a glance.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (var i = 0; i < presets.length; i++)
              ChoiceChip(
                label: Text(presets[i]),
                selected: _index == i,
                onSelected: (_) => setState(() => _index = i),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${presets[_index]} $suffix',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () =>
              ref.read(sessionControllerProvider.notifier).start(target()),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }
}

/// Live session: circular progress toward the target plus current stats.
class _LiveSection extends ConsumerWidget {
  const _LiveSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final session = ref.watch(sessionControllerProvider);
    // Render straight from the live (mutable) SessionState — never cache.
    final live = session.live!;
    final target = live.target;

    final currentSpeed =
        live.speedSamples.isEmpty ? 0.0 : live.speedSamples.last;
    final speedText =
        convertSpeed(ms: currentSpeed, unit: unit).round().toString();
    final progressLabel = switch (target) {
      DistanceTarget(:final meters) =>
        '${distanceLabel(live.cumulativeDistanceM, unit)} / ${distanceLabel(meters, unit)}',
      DurationTarget(:final minutes) => () {
          final budgetMs = minutes * 60000;
          final elapsedMs =
              (session.progress * budgetMs).round().clamp(0, budgetMs);
          return '${elapsedLabel(elapsedMs)} / $minutes min';
        }(),
    };

    return Column(
      children: [
        SizedBox(
          height: 220,
          width: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: session.progress,
                  strokeWidth: 10,
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    speedText,
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  Text(
                    unitLabel(unit),
                    style: theme.textTheme.labelLarge?.copyWith(
                      letterSpacing: 2,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          progressLabel,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Top ${convertSpeed(ms: live.topSpeedMs, unit: unit).round()} '
          '${unitLabel(unit)}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(sessionControllerProvider.notifier).stop(),
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        ),
      ],
    );
  }
}

/// Summary of the last ended session, unit-aware.
///
/// Distance mode leads with top/avg speed and elapsed time (the distance is
/// the configured target); duration mode leads with the covered distance
/// plus the speeds.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final session = ref.watch(sessionControllerProvider);
    final summary = session.lastSummary!;
    final target = session.live?.target;
    final speedUnit = unitLabel(unit);
    // Whole speeds show as integers (`72 km/h`), fractions keep one decimal.
    final top = _trimZero(convertSpeed(ms: summary.topSpeedMs, unit: unit));
    final avg = _trimZero(convertSpeed(ms: summary.avgSpeedMs, unit: unit));

    final List<Widget> rows;
    if (target is DistanceTarget) {
      rows = [
        _StatRow(label: 'Top speed', value: '$top $speedUnit'),
        _StatRow(label: 'Avg speed', value: '$avg $speedUnit'),
        _StatRow(label: 'Elapsed', value: elapsedLabel(summary.elapsedMs)),
        _StatRow(label: 'Distance', value: distanceLabel(target.meters, unit)),
      ];
    } else {
      rows = [
        _StatRow(
          label: 'Distance',
          value: distanceLabel(summary.distanceM, unit),
        ),
        _StatRow(label: 'Top speed', value: '$top $speedUnit'),
        _StatRow(label: 'Avg speed', value: '$avg $speedUnit'),
        _StatRow(label: 'Elapsed', value: elapsedLabel(summary.elapsedMs)),
      ];
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Session summary',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Last 10 sessions for the active vehicle.
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final activeVehicleId = ref.watch(
      vehiclesProvider.select((s) => s.activeVehicleId),
    );
    final storage = ref.watch(storageServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'History',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        if (activeVehicleId == null)
          Text('No vehicle selected', style: theme.textTheme.bodyMedium)
        else
          FutureBuilder<List<Session>>(
            future: storage.sessionsForVehicle(activeVehicleId, limit: 10),
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? const <Session>[];
              if (sessions.isEmpty) {
                return Text('No sessions yet', style: theme.textTheme.bodyMedium);
              }
              return Column(
                children: [
                  for (final session in sessions)
                    _HistoryTile(session: session, unit: unit),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.session, required this.unit});

  final Session session;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetText = switch (session.target) {
      DistanceTarget(:final meters) => distanceLabel(meters, unit),
      DurationTarget(:final minutes) => '$minutes min',
    };
    final statusText = switch (session.status) {
      SessionStatus.completed => 'done',
      SessionStatus.stopped => 'stopped',
      SessionStatus.running => 'running',
    };
    final summary = session.summary;
    final summaryText = summary == null
        ? null
        : '${distanceLabel(summary.distanceM, unit)} · '
            '${elapsedLabel(summary.elapsedMs)}';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('$targetText · $statusText'),
      subtitle: summaryText == null
          ? null
          : Text(summaryText, style: theme.textTheme.bodySmall),
    );
  }
}
