import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/controllers/providers.dart';
import '../../core/models/models.dart';
import '../session/session_format.dart';

/// Aggregate stats across a list of sessions (pure, testable).
class AnalyticsAggregate {
  const AnalyticsAggregate({
    required this.sessionCount,
    required this.totalDistanceM,
    required this.bestTopSpeedMs,
  });

  final int sessionCount;
  final double totalDistanceM;
  final double bestTopSpeedMs;

  /// Computes aggregates over sessions that have a summary.
  factory AnalyticsAggregate.from(List<Session> sessions) {
    var count = 0;
    var distance = 0.0;
    var best = 0.0;
    for (final s in sessions) {
      final summary = s.summary;
      if (summary == null) continue;
      count++;
      distance += summary.distanceM;
      if (summary.topSpeedMs > best) best = summary.topSpeedMs;
    }
    return AnalyticsAggregate(
      sessionCount: count,
      totalDistanceM: distance,
      bestTopSpeedMs: best,
    );
  }
}

/// Analytics screen: aggregate stats for the active vehicle plus per-session
/// cards with expandable speed-over-time charts and a top-speed bar chart.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  /// Marker used by tests to verify navigation.
  static const Key markerKey = Key('analytics-screen');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = ref.watch(settingsControllerProvider.select((s) => s.unit));
    final activeVehicleId = ref.watch(
      vehiclesProvider.select((s) => s.activeVehicleId),
    );
    final storage = ref.watch(storageServiceProvider);

    return SafeArea(
      key: markerKey,
      child: activeVehicleId == null
          ? Center(
              child: Text('No vehicle selected',
                  style: theme.textTheme.bodyMedium),
            )
          : FutureBuilder<List<Session>>(
              future: storage.sessionsForVehicle(activeVehicleId, limit: 50),
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? const <Session>[];
                if (sessions.isEmpty) {
                  return Center(
                    child: Text('No sessions yet',
                        style: theme.textTheme.bodyMedium),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _AggregateHeader(sessions: sessions, unit: unit),
                    const SizedBox(height: 16),
                    _TopSpeedChart(sessions: sessions, unit: unit),
                    const SizedBox(height: 16),
                    Text(
                      'Sessions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final session in sessions)
                      _SessionCard(session: session, unit: unit),
                  ],
                );
              },
            ),
    );
  }
}

/// Aggregate stats across all sessions of the active vehicle.
class _AggregateHeader extends StatelessWidget {
  const _AggregateHeader({required this.sessions, required this.unit});

  final List<Session> sessions;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final aggregate = AnalyticsAggregate.from(sessions);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _AggStat(label: 'Sessions', value: '${aggregate.sessionCount}'),
            _AggStat(
              label: 'Distance',
              value: distanceLabel(aggregate.totalDistanceM, unit),
            ),
            _AggStat(
              label: 'Best',
              value: '${trimZero(convertSpeed(ms: aggregate.bestTopSpeedMs, unit: unit))} '
                  '${unitLabel(unit)}',
            ),
          ],
        ),
      ),
    );
  }
}

class _AggStat extends StatelessWidget {
  const _AggStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

/// Bar chart of the top speed of the most recent sessions (oldest → newest).
class _TopSpeedChart extends StatelessWidget {
  const _TopSpeedChart({required this.sessions, required this.unit});

  final List<Session> sessions;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Newest first in the list; chart left→right oldest→newest.
    final recent = sessions.take(10).toList().reversed.toList();
    final speeds = [
      for (final s in recent)
        convertSpeed(ms: s.summary?.topSpeedMs ?? 0, unit: unit),
    ];
    final maxSpeed = speeds.isEmpty
        ? 1.0
        : speeds.reduce((a, b) => a > b ? a : b) * 1.2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Top speed by session (${unitLabel(unit)})',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  maxY: maxSpeed <= 0 ? 1 : maxSpeed,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barGroups: [
                    for (var i = 0; i < speeds.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: speeds[i],
                            color: theme.colorScheme.primary,
                            width: 10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One session: header row always visible; the speed-over-time chart expands
/// on tap (loaded from the session's track points).
class _SessionCard extends ConsumerStatefulWidget {
  const _SessionCard({required this.session, required this.unit});

  final Session session;
  final SpeedUnit unit;

  @override
  ConsumerState<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<_SessionCard> {
  bool _expanded = false;
  List<TrackPoint>? _points;
  bool _loading = false;

  Future<void> _toggle() async {
    setState(() => _expanded = !_expanded);
    if (_expanded && _points == null && !_loading) {
      setState(() => _loading = true);
      final points =
          await ref.read(storageServiceProvider).trackPoints(widget.session.id);
      if (mounted) setState(() => _points = points);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.unit;
    final session = widget.session;
    final summary = session.summary;
    final targetText = switch (session.target) {
      DistanceTarget(:final meters) => distanceLabel(meters, unit),
      DurationTarget(:final minutes) => '$minutes min',
    };

    return Card(
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      targetText,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (summary != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _MiniStat(
                      label: 'Top',
                      value: '${trimZero(convertSpeed(ms: summary.topSpeedMs, unit: unit))} ${unitLabel(unit)}',
                    ),
                    _MiniStat(
                      label: 'Avg',
                      value: '${trimZero(convertSpeed(ms: summary.avgSpeedMs, unit: unit))} ${unitLabel(unit)}',
                    ),
                    _MiniStat(
                      label: 'Dist',
                      value: distanceLabel(summary.distanceM, unit),
                    ),
                    _MiniStat(
                      label: 'Time',
                      value: elapsedLabel(summary.elapsedMs),
                    ),
                  ],
                ),
              ],
              if (_expanded) ...[
                const SizedBox(height: 16),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  _SpeedChart(points: _points ?? const [], unit: unit),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Speed-over-time line chart for one session's track points.
class _SpeedChart extends StatelessWidget {
  const _SpeedChart({required this.points, required this.unit});

  final List<TrackPoint> points;
  final SpeedUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return Text(
        'Not enough data for a chart',
        style: theme.textTheme.bodySmall,
      );
    }
    final start = points.first.timestampMs;
    final spots = [
      for (final p in points)
        FlSpot(
          (p.timestampMs - start) / 1000.0, // seconds since start
          convertSpeed(ms: p.speedMs, unit: unit),
        ),
    ];
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2;

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY,
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: theme.colorScheme.primary,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
