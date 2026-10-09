import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/controllers/session_engine.dart';
import '../../core/models/models.dart';
import '../session/session_controller.dart';
import '../session/session_format.dart';

/// Distance presets in the display unit (km for km/h, miles for mph).
const List<double> _distancePresets = [0.5, 1, 2, 5, 10];

/// Duration presets in minutes.
const List<int> _durationPresets = [1, 3, 5, 10, 30];

/// Markers (exported for tests).
const Key sessionBarConfigKey = Key('session-bar-config');
const Key sessionBarLiveKey = Key('session-bar-live');
const Key sessionBarSummaryKey = Key('session-bar-summary');

/// Collapsible session control for the Speedo screen.
///
/// Idle: mode selector + preset + Start. Running: live progress + Stop.
/// Finished: a compact summary that can be dismissed.
class SessionBar extends ConsumerStatefulWidget {
  const SessionBar({super.key});

  @override
  ConsumerState<SessionBar> createState() => _SessionBarState();
}

class _SessionBarState extends ConsumerState<SessionBar> {
  bool _durationMode = false;
  int _index = 2; // distance: 2 km/mi, duration: 5 min

  void _setMode({required bool duration}) => setState(() {
        _durationMode = duration;
        _index = 2;
      });

  SessionTarget _target(SpeedUnit unit) {
    if (_durationMode) {
      return DurationTarget(_durationPresets[_index]);
    }
    final preset = _distancePresets[_index];
    final meters = unit == SpeedUnit.kmh ? preset * 1000 : preset * 1609.344;
    return DistanceTarget(meters);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final session = ref.watch(sessionControllerProvider);
    final live = session.live;
    final running = live != null && !live.finished;
    final showSummary = session.lastSummary != null && !running;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: running
              ? _LiveRow(key: sessionBarLiveKey, live: live)
              : showSummary
                  ? _SummaryRow(
                      key: sessionBarSummaryKey,
                      onDismiss: () => ref
                          .read(sessionControllerProvider.notifier)
                          .clearSummary(),
                    )
                  : _ConfigRow(
                      key: sessionBarConfigKey,
                      theme: theme,
                      durationMode: _durationMode,
                      index: _index,
                      unit: unit,
                      onMode: _setMode,
                      onIndex: (i) => setState(() => _index = i),
                      onStart: () => ref
                          .read(sessionControllerProvider.notifier)
                          .start(_target(unit)),
                    ),
        ),
      ),
    );
  }
}

/// Idle row: mode toggle, preset chips, and Start.
class _ConfigRow extends StatelessWidget {
  const _ConfigRow({
    super.key,
    required this.theme,
    required this.durationMode,
    required this.index,
    required this.unit,
    required this.onMode,
    required this.onIndex,
    required this.onStart,
  });

  final ThemeData theme;
  final bool durationMode;
  final int index;
  final SpeedUnit unit;
  final void Function({required bool duration}) onMode;
  final ValueChanged<int> onIndex;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final presets = durationMode
        ? _durationPresets.map((m) => '$m').toList()
        : _distancePresets.map(trimZero).toList();
    final suffix =
        durationMode ? 'min' : (unit == SpeedUnit.kmh ? 'km' : 'mi');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Distance')),
                  ButtonSegment(value: true, label: Text('Duration')),
                ],
                selected: {durationMode},
                onSelectionChanged: (s) => onMode(duration: s.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          children: [
            for (var i = 0; i < presets.length; i++)
              ChoiceChip(
                label: Text('${presets[i]} $suffix'),
                selected: index == i,
                onSelected: (_) => onIndex(i),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow),
          label: Text('Start ${presets[index]} $suffix'),
        ),
      ],
    );
  }
}

/// Running row: live progress + Stop.
class _LiveRow extends ConsumerStatefulWidget {
  const _LiveRow({super.key, required this.live});

  final SessionState live;

  @override
  ConsumerState<_LiveRow> createState() => _LiveRowState();
}

class _LiveRowState extends ConsumerState<_LiveRow> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  void _syncTicker() {
    final wantsTicker = !widget.live.finished &&
        widget.live.target is DurationTarget;
    if (wantsTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!wantsTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final live = widget.live;
    _syncTicker();

    final progressLabel = switch (live.target) {
      DistanceTarget(:final meters) =>
        '${distanceLabel(live.cumulativeDistanceM, unit)} / '
            '${distanceLabel(meters, unit)}',
      DurationTarget(:final minutes) => () {
          final label = elapsedLabelAt(
            live.startedAtMs,
            DateTime.now().millisecondsSinceEpoch,
            minutes * 60000,
          );
          return '$label / $minutes min';
        }(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(
          value: ref.watch(sessionControllerProvider).progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(progressLabel, style: theme.textTheme.titleMedium),
            Text(
              'Top ${convertSpeed(ms: live.topSpeedMs, unit: unit).round()} '
              '${unitLabel(unit)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => ref.read(sessionControllerProvider.notifier).stop(),
          icon: const Icon(Icons.stop),
          label: const Text('Stop'),
        ),
      ],
    );
  }
}

/// Compact finished-session summary with a dismiss action.
class _SummaryRow extends ConsumerWidget {
  const _SummaryRow({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final session = ref.watch(sessionControllerProvider);
    final summary = session.lastSummary!;
    final target = session.lastTarget;
    final speedUnit = unitLabel(unit);
    final top = trimZero(convertSpeed(ms: summary.topSpeedMs, unit: unit));
    final avg = trimZero(convertSpeed(ms: summary.avgSpeedMs, unit: unit));

    final List<(String, String)> rows;
    if (target is DistanceTarget) {
      rows = [
        ('Top speed', '$top $speedUnit'),
        ('Avg speed', '$avg $speedUnit'),
        ('Elapsed', elapsedLabel(summary.elapsedMs)),
      ];
    } else {
      rows = [
        ('Distance', distanceLabel(summary.distanceM, unit)),
        ('Top speed', '$top $speedUnit'),
        ('Avg speed', '$avg $speedUnit'),
        ('Elapsed', elapsedLabel(summary.elapsedMs)),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.flag, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Session summary',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                Text(
                  value,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
