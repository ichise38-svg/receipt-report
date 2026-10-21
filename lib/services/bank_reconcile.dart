import '../models/bank_entry.dart';
import '../models/receipt.dart';

/// 照合の結果の種類
enum ReconcileStatus {
  /// 口座払いの明細と口座の出金が一致
  matched,

  /// 同じ日付の出金はあるが金額が違う
  amountMismatch,

  /// 口座払いの明細に対応する出金が見当たらない（出納の入力漏れの可能性）
  missingInBank,

  /// 口座の出金があるが、対応する口座払いの明細がない
  missingInLedger,
}

class ReconcileLine {
  final ReconcileStatus status;
  final DateTime date;
  final String label;
  final int ledgerAmount; // 明細側（支出の口座払い）。なければ 0
  final int bankAmount; // 出納側（出金）。なければ 0

  const ReconcileLine({
    required this.status,
    required this.date,
    required this.label,
    required this.ledgerAmount,
    required this.bankAmount,
  });

  int get difference => ledgerAmount - bankAmount;
}

class BankBalance {
  /// 口座残高（前年繰越の口座等 ＋ 入金 − 出金 − 現金引出）
  final int bank;

  /// 手持ち現金（前年繰越の現金 ＋ 現金引出 − 現金払いの支出 ＋ 現金払いの収入）
  final int cashOnHand;

  const BankBalance({required this.bank, required this.cashOnHand});
}

/// 口座の出納と、口座払いの明細の照合
///
/// - 対象は支出の「口座・デビット」明細（削除済みを除く）と、出納の「出金」行。
/// - 「現金引出」は口座から現金への移動のため、照合の対象外（残高計算にだけ使う）。
/// - 日付（年月日）と金額で一致を見る。同じ日・同じ金額が複数あれば件数の多い方で対応付ける。
class BankReconcile {
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<ReconcileLine> reconcile({
    required List<Receipt> receipts,
    required List<BankEntry> bankEntries,
    DateTime? from,
    DateTime? to,
  }) {
    bool inPeriod(DateTime d) {
      if (from != null &&
          d.isBefore(DateTime(from.year, from.month, from.day))) {
        return false;
      }
      if (to != null &&
          d.isAfter(DateTime(to.year, to.month, to.day, 23, 59, 59))) {
        return false;
      }
      return true;
    }

    final ledger =
        receipts
            .where(
              (r) =>
                  !r.deleted &&
                  !r.isIncome &&
                  r.payment == PaymentMethod.bank &&
                  inPeriod(r.date),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final bank =
        bankEntries
            .where((b) => b.kind == BankEntryKind.withdraw && inPeriod(b.date))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    final usedBank = List<bool>.filled(bank.length, false);
    final lines = <ReconcileLine>[];

    // 1) 日付と金額が一致する組を先に確定
    final usedLedger = List<bool>.filled(ledger.length, false);
    for (var i = 0; i < ledger.length; i++) {
      final r = ledger[i];
      for (var j = 0; j < bank.length; j++) {
        if (usedBank[j]) continue;
        final b = bank[j];
        if (_sameDay(r.date, b.date) && r.amount == b.amount) {
          usedLedger[i] = true;
          usedBank[j] = true;
          lines.add(
            ReconcileLine(
              status: ReconcileStatus.matched,
              date: r.date,
              label: r.storeName,
              ledgerAmount: r.amount,
              bankAmount: b.amount,
            ),
          );
          break;
        }
      }
    }

    // 2) 残りは同じ日付の出金と金額違いとして対応付け
    for (var i = 0; i < ledger.length; i++) {
      if (usedLedger[i]) continue;
      final r = ledger[i];
      var idx = -1;
      for (var j = 0; j < bank.length; j++) {
        if (!usedBank[j] && _sameDay(r.date, bank[j].date)) {
          idx = j;
          break;
        }
      }
      if (idx >= 0) {
        usedBank[idx] = true;
        lines.add(
          ReconcileLine(
            status: ReconcileStatus.amountMismatch,
            date: r.date,
            label: r.storeName,
            ledgerAmount: r.amount,
            bankAmount: bank[idx].amount,
          ),
        );
      } else {
        lines.add(
          ReconcileLine(
            status: ReconcileStatus.missingInBank,
            date: r.date,
            label: r.storeName,
            ledgerAmount: r.amount,
            bankAmount: 0,
          ),
        );
      }
    }

    // 3) 対応する明細がない出金
    for (var j = 0; j < bank.length; j++) {
      if (usedBank[j]) continue;
      lines.add(
        ReconcileLine(
          status: ReconcileStatus.missingInLedger,
          date: bank[j].date,
          label: bank[j].label,
          ledgerAmount: 0,
          bankAmount: bank[j].amount,
        ),
      );
    }

    lines.sort((a, b) => a.date.compareTo(b.date));
    return lines;
  }

  /// 口座と手持ち現金の残高
  ///
  /// - 口座: 繰越（口座等） ＋ 入金 − 出金 − 現金引出
  ///   ※ 口座払いの明細は、対応する口座の「出金」行で既に反映されている前提。
  /// - 手持ち現金: 繰越（現金） ＋ 現金引出 − 現金払いの支出 ＋ 現金払いの収入
  static BankBalance balances({
    required int carryCash,
    required int carryBank,
    required List<BankEntry> bankEntries,
    required List<Receipt> receipts,
  }) {
    var bankTotal = carryBank;
    var cashTotal = carryCash;
    for (final b in bankEntries) {
      bankTotal += b.balanceDelta;
      if (b.kind == BankEntryKind.cashOut) cashTotal += b.amount;
    }
    for (final r in receipts) {
      if (r.deleted || r.payment != PaymentMethod.cash) continue;
      cashTotal += r.isIncome ? r.amount : -r.amount;
    }
    return BankBalance(bank: bankTotal, cashOnHand: cashTotal);
  }
}
