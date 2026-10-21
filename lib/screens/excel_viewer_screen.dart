import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/receipt.dart';
import '../services/app_settings.dart';
import '../services/event_excel_service.dart';
import '../services/event_report.dart';
import '../services/excel_export_service.dart';
import '../services/excel_layout.dart';
import '../services/member_store.dart';
import '../services/receipt_store.dart';

/// Excelビューワー：入出力の数値が収支報告書（Excel）のどのセルに入るかを表示する
///
/// 左側は Excel 風のグリッド（A〜G列・行番号）。明細をタップすると、
/// その明細が書き込まれるセルを強調表示し、下部に「どの列に何が入るか」を説明します。
class ExcelViewerScreen extends StatefulWidget {
  /// true のときは画面の一部（ホームの入力パネルの下）として表示する。
  /// 外部でデータが変わったら [refreshKey] を変えると再計算する。
  final bool embedded;
  final Object? refreshKey;

  const ExcelViewerScreen({super.key, this.embedded = false, this.refreshKey});

  @override
  State<ExcelViewerScreen> createState() => _ExcelViewerScreenState();
}

enum _ViewMode { annual, event }

class _ExcelViewerScreenState extends State<ExcelViewerScreen> {
  List<Receipt> _entries = [];
  _ViewMode _mode = _ViewMode.annual;
  String? _eventName;
  List<String> _eventNames = [];
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
  // 年間報告の対象期間（既定は今年の 1/1〜12/31 で完結）
  late DateTime _periodFrom = DateTime(DateTime.now().year, 1, 1);
  late DateTime _periodTo = DateTime(DateTime.now().year, 12, 31);
  final _dateFmt = DateFormat('yyyy/MM/dd');
  int? _selectedRow;
  int? _selectedCol;
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();
  // グリッドの拡大率（ピンチ・ボタンで変更）
  double _zoom = 1.0;
  static const _minZoom = 0.5;
  static const _maxZoom = 3.0;
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDist;
  double _pinchStartZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExcelViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) _load();
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
    final names = EventReport.namesOf(entries);
    setState(() {
      _mainTitle = title;
      _participants = members.length;
      _loading = false;
      _entries = entries;
      _eventNames = names;
      _eventName = (_eventName != null && names.contains(_eventName))
          ? _eventName
          : (names.isEmpty ? null : names.first);
    });
    _rebuild(entries);
  }

  void _rebuild(List<Receipt> entries) {
    _entries = entries;
    final live = entries.where((r) => !r.deleted).toList();
    setState(() {
      _selectedRow = null;
      _selectedCol = null;
      _rows = _mode == _ViewMode.annual
          ? AnnualLayout.build(
              entries: live,
              carryCash: _parseYen(_carryCashCtrl),
              carryBank: _parseYen(_carryBankCtrl),
              participants: _participants,
              from: _periodFrom,
              to: _periodTo,
            )
          : (_eventName == null
                ? <LayoutRow>[]
                : EventLayout.build(
                    entries: live,
                    eventName: _eventName!,
                    participants: _participants,
                    mainTitle: _mainTitle,
                  ));
    });
  }

  Future<void> _pickPeriod(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _periodFrom : _periodTo,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ja'),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _periodFrom = picked;
      } else {
        _periodTo = picked;
      }
    });
    _rebuild(_entries);
  }

  void _setMode(_ViewMode m) {
    if (_mode == m) return;
    _mode = m;
    _rebuild(_entries);
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
    if (widget.embedded) {
      return _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeaderInfo(),
                SizedBox(height: 260, child: _buildGrid()),
                _buildExplain(),
              ],
            );
    }
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
    final annual = _mode == _ViewMode.annual;
    final fileName = annual
        ? ExcelExportService.fileNameFor('全体')
        : (_eventName == null
              ? '（イベント未選択）'
              : EventExcelService.fileNameFor(_eventName!));
    final sheetName = annual ? '収支報告書' : '会計報告書';
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_ViewMode>(
            segments: const [
              ButtonSegment(value: _ViewMode.annual, label: Text('年間収支報告書')),
              ButtonSegment(value: _ViewMode.event, label: Text('イベント別報告')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
          const SizedBox(height: 6),
          if (!annual) ...[
            if (_eventNames.isEmpty)
              const Text('イベント名が登録された明細がありません。', style: TextStyle(fontSize: 12))
            else
              DropdownButtonFormField<String>(
                initialValue: _eventName,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'イベント',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final e in _eventNames)
                    DropdownMenuItem(value: e, child: Text(e)),
                ],
                onChanged: (v) {
                  _eventName = v;
                  _rebuild(_entries);
                },
              ),
            const SizedBox(height: 6),
          ],
          Text(
            'ファイル: $fileName ／ シート: $sheetName',
            style: const TextStyle(fontSize: 12),
          ),
          if (annual) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickPeriod(true),
                    child: Text(
                      '開始 ${_dateFmt.format(_periodFrom)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickPeriod(false),
                    child: Text(
                      '終了 ${_dateFmt.format(_periodTo)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
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
          ],
          const SizedBox(height: 4),
          Text(
            '左上（A1）：$_mainTitle（$_participants名）'
            '${annual ? '' : '\nA2：${_eventName ?? '-'}　会計報告書'}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final totalWidth =
        (_rowHeaderWidth + _colWidths.reduce((a, b) => a + b)) * _zoom;
    final rowCount = _maxRow() + 1;
    return Stack(
      children: [
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Scrollbar(
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
          ),
        ),
        Positioned(right: 8, bottom: 8, child: _zoomControls()),
      ],
    );
  }

  // ---- ピンチ拡大縮小 ----
  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _pinchStartDist = _pointerDistance();
      _pinchStartZoom = _zoom;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2 && _pinchStartDist != null) {
      final d = _pointerDistance();
      if (_pinchStartDist! > 0) {
        _setZoom(_pinchStartZoom * d / _pinchStartDist!);
      }
    }
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStartDist = null;
  }

  double _pointerDistance() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _setZoom(double z) {
    final clamped = z.clamp(_minZoom, _maxZoom).toDouble();
    if ((clamped - _zoom).abs() < 0.001) return;
    setState(() => _zoom = clamped);
  }

  Widget _zoomControls() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.9),
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '縮小',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.zoom_out),
            onPressed: _zoom <= _minZoom ? null : () => _setZoom(_zoom - 0.25),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(_zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '拡大',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.zoom_in),
            onPressed: _zoom >= _maxZoom ? null : () => _setZoom(_zoom + 0.25),
          ),
          IconButton(
            tooltip: '100%に戻す',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.restart_alt),
            onPressed: _zoom == 1.0 ? null : () => _setZoom(1.0),
          ),
        ],
      ),
    );
  }

  int _maxRow() {
    var max = 0;
    for (final r in _rows) {
      if (r.row > max) max = r.row;
    }
    return max;
  }

  Widget _gridHeader() {
    return Row(
      children: [
        _box(_rowHeaderWidth * _zoom, 28 * _zoom, '', header: true),
        for (var c = 0; c < _colWidths.length; c++)
          _box(
            _colWidths[c] * _zoom,
            28 * _zoom,
            excelColumnName(c),
            header: true,
          ),
      ],
    );
  }

  Widget _gridRow(int r) {
    final rowSelected = _selectedRow == r;
    return Row(
      children: [
        _box(
          _rowHeaderWidth * _zoom,
          _rowHeight * _zoom,
          '${r + 1}',
          header: true,
          highlight: rowSelected,
        ),
        for (var c = 0; c < _colWidths.length; c++) _cellWidget(r, c),
      ],
    );
  }

  Widget _cellWidget(int r, int c) {
    final scheme = Theme.of(context).colorScheme;
    final cell = _cellAt(r, c);
    final isCell = cell != null;
    final isHeader = cell?.header ?? false;
    final text = cell == null ? '' : _cellText(cell);
    final isFormula = cell?.isFormula ?? false;
    final selected = _selectedRow == r && _selectedCol == c;
    final rowSelected = _selectedRow == r;
    Color? bg;
    if (isHeader) {
      bg = const Color(0xFFE3F2FD);
    } else if (selected) {
      bg = scheme.primary.withValues(alpha: 0.35);
    } else if (rowSelected) {
      bg = scheme.primary.withValues(alpha: 0.10);
    }
    final isRight = cell?.amount != null;
    return InkWell(
      onTap: !isCell ? null : () => _select(r, c),
      child: Container(
        width: _colWidths[c] * _zoom,
        height: _rowHeight * _zoom,
        alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: 6 * _zoom),
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
            fontSize: 12 * _zoom,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
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
        style: TextStyle(fontSize: 12 * _zoom, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildExplain() {
    final scheme = Theme.of(context).colorScheme;
    final row = _selected;
    final String body;
    if (row == null) {
      body =
          '明細の行（月日・摘要・収入・支出の欄）をタップすると、'
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
          '選択セル ${cell.address}：${cell.role ?? _columnRole(cell.col)}'
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
