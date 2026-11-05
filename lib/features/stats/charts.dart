import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../data/db/app_database.dart';
import '../../domain/stats.dart';

/// Подписи осей и сетка — приглушённые, чтобы не спорить с данными.
TextStyle _axisStyle(BuildContext context) => Theme.of(context).textTheme.labelSmall!.copyWith(
  color: Theme.of(context).colorScheme.onSurfaceVariant,
);

FlGridData _grid(BuildContext context) => FlGridData(
  drawVerticalLine: false,
  getDrawingHorizontalLine: (_) => FlLine(
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
    strokeWidth: 1,
  ),
);

/// Красивый шаг для оси: 1, 2, 5 × 10ⁿ.
double _niceInterval(double max, {int ticks = 4}) {
  if (max <= 0) return 1;
  final raw = max / ticks;
  final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 5, 10]) {
    if (raw <= m * p) return m * p;
  }
  return 10 * p;
}

/// Кружок-цвет для легенды.
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Кольцевая диаграмма долей категорий, итог — в центре.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.slices,
    required this.colorOf,
    required this.centerLabel,
    required this.centerValue,
  });

  final List<CategorySlice> slices;
  final Color Function(CategorySlice) colorOf;
  final String centerLabel;
  final String centerValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 72,
              startDegreeOffset: -90,
              pieTouchData: PieTouchData(enabled: false),
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: math.max(s.amount.toDouble(), 0.0001),
                    color: colorOf(s),
                    radius: 30,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 80),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(centerLabel, style: _axisStyle(context)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(centerValue, style: theme.textTheme.titleLarge),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Доходы и расходы по месяцам: две группы столбцов, одна ось.
class MonthlyBars extends StatelessWidget {
  const MonthlyBars({super.key, required this.points, required this.base});

  final List<MonthPoint> points;
  final Currency base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final f = Money.factor(base.decimals).toDouble();
    final maxY = points.fold(0.0, (m, p) => math.max(m, math.max(p.income, p.expense) / f));
    final interval = _niceInterval(maxY);
    final withYear = points.first.month.year != points.last.month.year;
    final barWidth = points.length > 8 ? 7.0 : 12.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 16,
          children: [
            _LegendItem(color: colors.chartIncome, label: 'Доходы'),
            _LegendItem(color: colors.chartExpense, label: 'Расходы'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: interval * (maxY / interval).ceil().clamp(1, 1000),
              gridData: _grid(context).copyWith(horizontalInterval: interval),
              borderData: FlBorderData(show: false),
              alignment: BarChartAlignment.spaceAround,
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 56,
                    interval: interval,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(formatCompact(v), style: _axisStyle(context), softWrap: false),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        formatMonthAxis(points[v.toInt()].month,
                            withYear: withYear && points[v.toInt()].month.month == 1),
                        style: _axisStyle(context),
                      ),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, gi, rod, ri) {
                    final p = points[group.x];
                    final value = ri == 0 ? p.income : p.expense;
                    return BarTooltipItem(
                      '${formatMonthFull(p.month)}\n'
                      '${ri == 0 ? 'Доходы' : 'Расходы'}: ${base.format(value)}',
                      TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      _rod(points[i].income / f, colors.chartIncome, barWidth),
                      _rod(points[i].expense / f, colors.chartExpense, barWidth),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  BarChartRodData _rod(double y, Color color, double width) => BarChartRodData(
    toY: y,
    color: color,
    width: width,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
  );
}

/// Капитал на конец месяца — линия.
class CapitalLine extends StatelessWidget {
  const CapitalLine({super.key, required this.points, required this.base});

  final List<CapitalPoint> points;
  final Currency base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final f = Money.factor(base.decimals).toDouble();
    final values = [for (final p in points) p.amount / f];
    var minY = values.reduce(math.min);
    var maxY = values.reduce(math.max);
    // Если капитал меняется мало, ось начинается не с нуля — иначе линия плоская.
    final narrow = minY > 0 && (maxY - minY) < maxY * 0.5;
    if (!narrow) minY = math.min(0, minY);
    if (maxY == minY) {
      maxY += 1;
      minY = math.max(0, minY - 1);
    }
    final interval = _niceInterval(maxY - minY);
    minY = (minY / interval).floor() * interval;
    maxY = (maxY / interval).ceil() * interval;
    final withYear = points.first.month.year != points.last.month.year;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: (points.length - 1).toDouble().clamp(1, double.infinity),
          gridData: _grid(context).copyWith(horizontalInterval: interval),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: interval,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(formatCompact(v), style: _axisStyle(context), softWrap: false),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: points.length > 7 ? 2 : 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length || v != i.toDouble()) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      formatMonthAxis(points[i].month, withYear: withYear && points[i].month.month == 1),
                      style: _axisStyle(context),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              maxContentWidth: 200,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${formatMonthFull(points[s.x.toInt()].month)}\n'
                    '${base.format(points[s.x.toInt()].amount)}',
                    TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
              color: color,
              barWidth: 2,
              dotData: FlDotData(
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 4,
                  color: color,
                  strokeWidth: 2,
                  strokeColor: theme.colorScheme.surfaceContainerLow,
                ),
              ),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [LegendDot(color: color), Text(label, style: Theme.of(context).textTheme.bodySmall)],
  );
}

/// Прогноз капитала по дням — линия; ниже нуля область подсвечивается.
class ForecastLine extends StatelessWidget {
  const ForecastLine({super.key, required this.days, required this.values, required this.base});

  final List<DateTime> days;

  /// Капитал на каждый день (в минимальных единицах).
  final List<int> values;
  final Currency base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final f = Money.factor(base.decimals).toDouble();
    final ys = [for (final v in values) v / f];
    var minY = ys.reduce(math.min);
    var maxY = ys.reduce(math.max);
    // Ось с нуля, только если колебания большие или денег может не хватить —
    // иначе линия получается плоской.
    if (minY <= 0 || (maxY - minY) >= maxY * 0.5) {
      minY = math.min(0, minY);
      maxY = math.max(0, maxY);
    } else {
      final pad = math.max((maxY - minY) * 0.2, maxY * 0.02);
      minY -= pad;
      maxY += pad;
    }
    if (maxY == minY) maxY = minY + 1;
    final interval = _niceInterval(maxY - minY);
    minY = (minY / interval).floor() * interval;
    maxY = (maxY / interval).ceil() * interval;
    final step = days.length > 40 ? 21 : 7;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          gridData: _grid(context).copyWith(horizontalInterval: interval),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            if (minY < 0)
              HorizontalLine(y: 0, color: theme.colorScheme.error.withValues(alpha: 0.6), strokeWidth: 1),
          ]),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                interval: interval,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(formatCompact(v), style: _axisStyle(context), softWrap: false),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: step.toDouble(),
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length || v != i.toDouble() || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(formatShortDate(days[i], today: days[i]), style: _axisStyle(context), softWrap: false),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              maxContentWidth: 200,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${formatShortDate(days[s.x.toInt()])}\n${base.format(values[s.x.toInt()])}',
                    TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
              isStepLineChart: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
            ),
          ],
        ),
      ),
    );
  }
}
