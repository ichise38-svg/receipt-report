import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/receipt.dart';
import '../services/ledger_summary.dart';
import '../services/receipt_store.dart';

/// 収入と支出のグラフ（月別の棒グラフ・区分別の内訳）
class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  List<Receipt> _entries = [];
  bool _loading = true;
  final _currency = NumberFormat('#,##0', 'ja_JP');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ReceiptStore.loadAll();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('収支グラフ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? const Center(child: Text('登録がありません。'))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTotals(),
                  const SizedBox(height: 16),
                  _sectionTitle('月別の収入と支出（円）'),
                  const SizedBox(height: 8),
                  _buildMonthly(),
                  const SizedBox(height: 16),
                  _sectionTitle('区分別の内訳'),
                  const SizedBox(height: 8),
                  _buildBreakdown(),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  );

  Widget _buildTotals() {
    final s = LedgerSummary.from(_entries);
    return Row(
      children: [
        Expanded(child: _totalCard('収入合計', s.income, Colors.green.shade700)),
        const SizedBox(width: 8),
        Expanded(child: _totalCard('支出合計', s.expense, Colors.red.shade700)),
        const SizedBox(width: 8),
        Expanded(
          child: _totalCard(
            '差引',
            s.balance,
            s.balance < 0 ? Colors.red.shade700 : Colors.blueGrey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _totalCard(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥${_currency.format(amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 月ごとの集計（期間内の月を欠けなく並べる）
  Widget _buildMonthly() {
    final income = <DateTime, int>{};
    final expense = <DateTime, int>{};
    DateTime? first;
    DateTime? last;
    for (final r in _entries) {
      final m = DateTime(r.date.year, r.date.month);
      if (first == null || m.isBefore(first)) first = m;
      if (last == null || m.isAfter(last)) last = m;
      if (r.isIncome) {
        income[m] = (income[m] ?? 0) + r.amount;
      } else {
        expense[m] = (expense[m] ?? 0) + r.amount;
      }
    }
    final months = <DateTime>[];
    var cur = first!;
    while (!cur.isAfter(last!)) {
      months.add(cur);
      cur = DateTime(cur.year, cur.month + 1);
    }
    final values = [for (final m in months) (income[m] ?? 0, expense[m] ?? 0)];
    final maxValue = values.fold<int>(
      0,
      (mx, v) => [mx, v.$1, v.$2].reduce((a, b) => a > b ? a : b),
    );

    const colWidth = 56.0;
    const chartHeight = 180.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _legend('収入', Colors.green.shade600),
            const SizedBox(width: 12),
            _legend('支出', Colors.red.shade500),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // 直近の月を見やすいよう右端から表示
          child: SizedBox(
            width: colWidth * months.length + 8,
            height: chartHeight + 28,
            child: CustomPaint(
              painter: _MonthlyBarPainter(
                months: months,
                values: values,
                maxValue: maxValue == 0 ? 1 : maxValue,
                incomeColor: Colors.green.shade600,
                expenseColor: Colors.red.shade500,
                gridColor: Colors.grey.shade300,
                labelStyle: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                ),
                colWidth: colWidth,
                chartHeight: chartHeight,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );

  Widget _buildBreakdown() {
    final s = LedgerSummary.from(_entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _breakdownCard('収入の内訳', s.incomeByCategory, s.income, Colors.green),
        const SizedBox(height: 12),
        _breakdownCard('支出の内訳', s.expenseByCategory, s.expense, Colors.red),
      ],
    );
  }

  Widget _breakdownCard(
    String title,
    Map<String, int> byCategory,
    int total,
    MaterialColor color,
  ) {
    final items = byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Text('データがありません', style: TextStyle(color: Colors.grey))
            else
              for (final e in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(e.key)),
                          Text(
                            '¥${_currency.format(e.value)}（${_percent(e.value, total)}）',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : e.value / total,
                          minHeight: 8,
                          color: color.shade400,
                          backgroundColor: color.shade50,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _percent(int part, int total) {
    if (total <= 0) return '0%';
    return '${(part * 100 / total).toStringAsFixed(1)}%';
  }
}

class _MonthlyBarPainter extends CustomPainter {
  final List<DateTime> months;
  final List<(int, int)> values;
  final int maxValue;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final double colWidth;
  final double chartHeight;

  _MonthlyBarPainter({
    required this.months,
    required this.values,
    required this.maxValue,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
    required this.labelStyle,
    required this.colWidth,
    required this.chartHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final inc = Paint()..color = incomeColor;
    final exp = Paint()..color = expenseColor;

    // 目盛り線（0・1/2・最大）
    for (final frac in [0.0, 0.5, 1.0]) {
      final y = chartHeight - chartHeight * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final barWidth = colWidth * 0.32;
    for (var i = 0; i < months.length; i++) {
      final x0 = i * colWidth + 4;
      final (income, expense) = values[i];
      final incH = chartHeight * income / maxValue;
      final expH = chartHeight * expense / maxValue;
      if (income > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            x0 + colWidth * 0.1,
            chartHeight - incH,
            barWidth,
            incH,
          ),
          inc,
        );
      }
      if (expense > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            x0 + colWidth * 0.1 + barWidth + 2,
            chartHeight - expH,
            barWidth,
            expH,
          ),
          exp,
        );
      }
      final label = TextPainter(
        text: TextSpan(text: '${months[i].month}月', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(x0 + (colWidth - label.width) / 2, chartHeight + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyBarPainter old) =>
      old.values != values || old.maxValue != maxValue;
}
