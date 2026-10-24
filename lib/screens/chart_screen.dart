import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/bank_entry.dart';
import '../models/receipt.dart';
import '../services/app_settings.dart';
import '../services/bank_reconcile.dart';
import '../services/bank_store.dart';
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
  List<BankEntry> _bank = [];
  int _carryCash = 0;
  int _carryBank = 0;
  bool _loading = true;
  final _currency = NumberFormat('#,##0', 'ja_JP');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ReceiptStore.loadAll();
    final bank = await BankStore.loadAll();
    final carry = await AppSettings.getCarry();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _bank = bank;
      _carryCash = carry.cash;
      _carryBank = carry.bank;
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
    // 口座の出納の月も含める（最新の残高が合計の残高と一致するように）
    for (final b in _bank) {
      final m = DateTime(b.date.year, b.date.month);
      if (first == null || m.isBefore(first)) first = m;
      if (last == null || m.isAfter(last)) last = m;
    }
    final months = <DateTime>[];
    var cur = first!;
    while (!cur.isAfter(last!)) {
      months.add(cur);
      cur = DateTime(cur.year, cur.month + 1);
    }
    final values = [for (final m in months) (income[m] ?? 0, expense[m] ?? 0)];
    // 残高（合計の残高）: 各月末時点の 繰越（現金＋口座等）＋ 口座の出納 ± 現金の増減
    // ホームの「合計の残高」と同じ計算
    final balances = <int>[];
    for (final m in months) {
      final next = DateTime(m.year, m.month + 1);
      final bal = BankReconcile.balances(
        carryCash: _carryCash,
        carryBank: _carryBank,
        bankEntries: _bank.where((b) => b.date.isBefore(next)).toList(),
        receipts: _entries.where((r) => r.date.isBefore(next)).toList(),
      );
      balances.add(bal.bank + bal.cashOnHand);
    }

    const colWidth = 56.0;
    const chartHeight = 180.0;
    final (axisHi, axisLo) = _axisRange(values, balances);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _legend('収入', Colors.green.shade600),
            _legend('支出', Colors.red.shade500),
            _legend('残高（合計）', Colors.indigo),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 縦軸の数字（横にスクロールしても見えたままにする）
            _YAxis(
              hi: axisHi,
              lo: axisLo,
              chartHeight: chartHeight,
              fmt: _currency,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true, // 直近の月を見やすいよう右端から表示
                child: SizedBox(
                  width: colWidth * months.length + 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8), // 縦軸の数字の上端と位置を合わせる
                      SizedBox(
                        height: chartHeight + 28,
                        child: CustomPaint(
                          painter: _MonthlyBarPainter(
                            values: values,
                            balances: balances,
                            incomeColor: Colors.green.shade600,
                            expenseColor: Colors.red.shade500,
                            balanceColor: Colors.indigo,
                            gridColor: Colors.grey.shade300,
                            labelStyle: const TextStyle(
                              fontSize: 11,
                              color: Colors.black87,
                            ),
                            monthLabels: [
                              for (final m in months) '${m.month}月',
                            ],
                            colWidth: colWidth,
                            chartHeight: chartHeight,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (final b in balances)
                            SizedBox(
                              width: colWidth,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _currency.format(b),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: b < 0
                                        ? Colors.red.shade700
                                        : Colors.indigo,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '↑ 残高（合計）',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
  final List<(int, int)> values;
  final List<int> balances;
  final Color incomeColor;
  final Color expenseColor;
  final Color balanceColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final List<String> monthLabels;
  final double colWidth;
  final double chartHeight;

  _MonthlyBarPainter({
    required this.values,
    required this.balances,
    required this.incomeColor,
    required this.expenseColor,
    required this.balanceColor,
    required this.gridColor,
    required this.labelStyle,
    required this.monthLabels,
    required this.colWidth,
    required this.chartHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final (hi, lo) = _axisRange(values, balances);
    final range = (hi - lo).toDouble();
    double yOf(num v) => chartHeight * (hi - v) / range;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final inc = Paint()..color = incomeColor;
    final exp = Paint()..color = expenseColor;
    final line = Paint()
      ..color = balanceColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final dot = Paint()..color = balanceColor;

    // 目盛り線（最大・0・最小）
    for (final v in <num>{hi, 0, lo}) {
      final y = yOf(v);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final baseline = yOf(0);

    final barWidth = colWidth * 0.32;
    final centers = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x0 = i * colWidth + 4;
      final (income, expense) = values[i];
      if (income > 0) {
        canvas.drawRect(
          Rect.fromLTRB(
            x0 + colWidth * 0.1,
            yOf(income),
            x0 + colWidth * 0.1 + barWidth,
            baseline,
          ),
          inc,
        );
      }
      if (expense > 0) {
        canvas.drawRect(
          Rect.fromLTRB(
            x0 + colWidth * 0.1 + barWidth + 2,
            yOf(expense),
            x0 + colWidth * 0.1 + barWidth * 2 + 2,
            baseline,
          ),
          exp,
        );
      }
      centers.add(Offset(x0 + colWidth / 2, yOf(balances[i])));
      final label = TextPainter(
        text: TextSpan(text: monthLabels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(x0 + (colWidth - label.width) / 2, chartHeight + 6),
      );
    }

    // 残高の折れ線と点
    if (centers.length > 1) {
      final path = Path()..moveTo(centers.first.dx, centers.first.dy);
      for (final c in centers.skip(1)) {
        path.lineTo(c.dx, c.dy);
      }
      canvas.drawPath(path, line);
    }
    for (final c in centers) {
      canvas.drawCircle(c, 3, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyBarPainter old) =>
      old.values != values || old.balances != balances;
}

/// 縦軸の範囲（最大・最小）。残高が負になる場合に備えて下端も取る
(int, int) _axisRange(List<(int, int)> values, List<int> balances) {
  var hi = 0;
  var lo = 0;
  for (final v in values) {
    if (v.$1 > hi) hi = v.$1;
    if (v.$2 > hi) hi = v.$2;
  }
  for (final b in balances) {
    if (b > hi) hi = b;
    if (b < lo) lo = b;
  }
  if (hi == lo) hi = lo + 1;
  return (hi, lo);
}

/// 縦軸の目盛りの数字（最大・0・最小。横線と同じ位置）
class _YAxis extends StatelessWidget {
  final int hi;
  final int lo;
  final double chartHeight;
  final NumberFormat fmt;

  const _YAxis({
    required this.hi,
    required this.lo,
    required this.chartHeight,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final range = (hi - lo).toDouble();
    final ticks = <int>{hi, 0, lo}.toList()..sort((a, b) => b.compareTo(a));
    return SizedBox(
      width: 60,
      height: 8 + chartHeight + 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final v in ticks)
            Positioned(
              top: 8 + chartHeight * (hi - v) / range - 7,
              left: 0,
              right: 6,
              height: 14,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    fmt.format(v),
                    style: const TextStyle(fontSize: 10, color: Colors.black87),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
