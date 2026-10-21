import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/receipt.dart';
import '../services/app_settings.dart';
import '../services/excel_export_service.dart';
import '../services/excel_layout.dart';
import '../services/member_store.dart';
import '../services/receipt_store.dart';

/// Excelビューワー：入出力の数値が収支報告書（Excel）のどのセルに入るかを表示する
///
/// 左側は Excel 風のグリッド（A〜G列・行番号）。明細をタップすると、
/// その明細が書き込まれるセルを強調表示し、下部に「どの列に何が入るか」を説明します。
class ExcelViewerScreen extends StatefulWidget {
  const ExcelViewerScreen({super.key});

  @override
  State<ExcelViewerScreen> createState() => _ExcelViewerScreenState();
}

class _ExcelViewerScreenState extends State<ExcelViewerScreen> {
  List<Receipt> _entries = [];
  static const _colWidths = [84.0, 170.0, 96.0, 96.0, 96.0, 96.0, 180.0];
  static const _rowHeight = 36.0;
  static const _rowHeaderWidth = 44.0;

  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _carryCashCtrl = TextEditingController(text: '146353');
  final _carryBankCtrl = TextEditingController(text: '308650');

  bool _loading = true;
  List<LayoutRow> _rows = [];
  String _mainTitle = AppSettings.defaultMainTitle;
  int _participants = 0;
  int? _selectedRow;
  int? _selectedCol;
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _carryCashCtrl.dispose();
    _carryBankCtrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await ReceiptStore.loadAll();
    final members = await MemberStore.loadAll();
    final title = await AppSettings.getMainTitle();
    if (!mounted) return;
    setState(() {
      _mainTitle = title;
      _participants = members.length;
      _loading = false;
      _entries = entries;
    });
    _rebuild(entries);
  }

  void _rebuild(List<Receipt> entries) {
    _entries = entries;
    setState(() {
      _rows = AnnualLayout.build(
        entries: entries.where((r) => !r.deleted).toList(),
        carryCash: _parseYen(_carryCashCtrl),
        carryBank: _parseYen(_carryBankCtrl),
        participants: _participants,
      );
    });
  }

  int _parseYen(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'[,，\s円]'), '')) ?? 0;

  LayoutRow? get _selected {
    final r = _selectedRow;
    if (r == null) return null;
    for (final row in _rows) {
      if (row.row == r) return row;
    }
    return null;
  }

  LayoutCell? _cellAt(int row, int col) {
    for (final r in _rows) {
      if (r.row != row) continue;
      for (final c in r.cells) {
        if (c.col == col) return c;
      }
    }
    return null;
  }

  void _select(int row, int? col) {
    setState(() {
      _selectedRow = row;
      _selectedCol = col;
    });
  }

  String _cellText(LayoutCell? c) {
    if (c == null) return '';
    if (c.amount != null) return _currency.format(c.amount);
    return c.text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excelビューワー'),
        actions: [
          IconButton(
            tooltip: '再計算',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeaderInfo(),
                Expanded(child: _buildGrid()),
                _buildExplain(),
              ],
            ),
    );
  }

  Widget _buildHeaderInfo() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ファイル: ${ExcelExportService.fileNameFor('全体')} ／ シート: 収支報告書',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _carryCashCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '繰越金（現金）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _rebuild(_entries),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _carryBankCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '繰越金（口座等）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _rebuild(_entries),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '左上：$_mainTitle（$_participants名）',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final totalWidth = _rowHeaderWidth + _colWidths.reduce((a, b) => a + b);
    final rowCount = _maxRow() + 1;
    return Scrollbar(
      controller: _vScroll,
      child: SingleChildScrollView(
        controller: _vScroll,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              children: [
                _gridHeader(),
                for (var r = 0; r < rowCount; r++) _gridRow(r),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _maxRow() {
    var max = AnnualLayout.headerRow + 1;
    for (final r in _rows) {
      if (r.row > max) max = r.row;
    }
    return max;
  }

  Widget _gridHeader() {
    return Row(
      children: [
        _box(_rowHeaderWidth, 28, '', header: true),
        for (var c = 0; c < _colWidths.length; c++)
          _box(_colWidths[c], 28, excelColumnName(c), header: true),
      ],
    );
  }

  Widget _gridRow(int r) {
    final isHeaderRow = r == AnnualLayout.headerRow;
    final layout = _rows.where((x) => x.row == r).firstOrNull;
    final rowSelected = _selectedRow == r;
    return Row(
      children: [
        _box(
          _rowHeaderWidth,
          _rowHeight,
          '${r + 1}',
          header: true,
          highlight: rowSelected,
        ),
        for (var c = 0; c < _colWidths.length; c++)
          _cellWidget(r, c, isHeaderRow, layout),
      ],
    );
  }

  Widget _cellWidget(int r, int c, bool isHeaderRow, LayoutRow? layout) {
    final scheme = Theme.of(context).colorScheme;
    String text = '';
    bool isFormula = false;
    bool isCell = false;
    if (isHeaderRow) {
      text = AnnualLayout.headers[c];
      isCell = true;
    } else {
      final cell = _cellAt(r, c);
      if (cell != null) {
        text = _cellText(cell);
        isFormula = cell.isFormula;
        isCell = true;
      }
    }
    final selected = _selectedRow == r && _selectedCol == c;
    final rowSelected = _selectedRow == r;
    Color? bg;
    if (isHeaderRow) {
      bg = const Color(0xFFE3F2FD);
    } else if (selected) {
      bg = scheme.primary.withValues(alpha: 0.35);
    } else if (rowSelected) {
      bg = scheme.primary.withValues(alpha: 0.10);
    }
    final isRight = c == 2 || c == 3 || c == 4 || c == 5;
    return InkWell(
      onTap: isHeaderRow || !isCell ? null : () => _select(r, c),
      child: Container(
        width: _colWidths[c],
        height: _rowHeight,
        alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: selected ? scheme.primary : Colors.grey.shade300,
            width: selected ? 2 : 0.5,
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isHeaderRow ? FontWeight.bold : FontWeight.normal,
            color: isFormula ? Colors.teal.shade700 : null,
          ),
        ),
      ),
    );
  }

  Widget _box(
    double w,
    double h,
    String text, {
    bool header = false,
    bool highlight = false,
  }) {
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
            : (header ? const Color(0xFFF5F5F5) : null),
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildExplain() {
    final scheme = Theme.of(context).colorScheme;
    final row = _selected;
    final String body;
    if (row == null) {
      body = '明細の行（月日・摘要・収入・支出の欄）をタップすると、'
          'その明細がExcelのどのセルに入るかを表示します。';
    } else {
      final col = _selectedCol;
      final cell = col == null ? null : _cellAt(row.row, col);
      final lines = <String>[
        '行 ${row.row + 1}（${row.label}）',
        if (row.receipt != null)
          '登録内容：${row.receipt!.storeName}／'
              '${row.receipt!.isIncome ? '収入' : '支出'}'
              '／¥${_currency.format(row.receipt!.amount)}',
      ];
      if (cell != null) {
        lines.add(
          '選択セル ${cell.address}：${_columnRole(cell.col)}'
          '${cell.amount != null ? '＝ ¥${_currency.format(cell.amount)}' : ''}',
        );
        if (cell.formula != null) {
          lines.add('数式 ${cell.formula}（自動計算。手で入力しなくてよい）');
        }
      } else {
        lines.add('セルをタップすると列の意味を表示します。');
      }
      body = lines.join('\n');
    }
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(body, style: const TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: const [
              _Legend(color: Color(0xFFE3F2FD), label: '見出し'),
              _Legend(color: Color(0xFF80CBC4), label: '数式（自動）'),
            ],
          ),
        ],
      ),
    );
  }

  String _columnRole(int col) {
    switch (col) {
      case 0:
        return 'A列「月日」';
      case 1:
        return 'B列「摘要」（店舗・名目）';
      case 2:
        return 'C列「収入」';
      case 3:
        return 'D列「支出」';
      case 4:
        return 'E列「収支」（収入−支出）';
      case 5:
        return 'F列「残高」（前行の残高＋収支）';
      case 6:
        return 'G列「備考」（カテゴリ／メモ）';
      default:
        return '';
    }
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
