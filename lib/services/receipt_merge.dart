import '../models/receipt.dart';

/// 新規保存の結果
enum SaveOutcome {
  /// 新しい明細を作成した
  created,

  /// 既存明細（同じID）を修正した
  updated,

  /// 内容が同じ既存明細に、撮影した写真だけを付けた
  photoAttached,

  /// 内容が同じ既存明細が写真付きだったため、新しい写真は保存しなかった
  duplicateSkipped,

  /// 内容が同じ既存明細に、イベント名だけを補った
  eventAttached,
}

/// 既存明細と新しい入力の突き合わせ結果
class MergePlan {
  final SaveOutcome outcome;

  /// 保存後の明細。created のときは新規の draft がそのまま入る
  final Receipt? updated;

  /// 既存明細を更新せず、draft の写真ファイルを削除すべきか
  final bool discardDraftImage;

  const MergePlan({
    required this.outcome,
    this.updated,
    this.discardDraftImage = false,
  });
}

/// 同じ内容のレシート・領収書を二重登録しないための判定
///
/// 同一とみなす条件: 区分・支払方法・年月日・店舗名（前後の空白を除く）・金額がすべて一致。
/// 削除済み（tombstone）は対象外。
class ReceiptMerge {
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static Receipt? findDuplicate(List<Receipt> all, Receipt draft) {
    final name = draft.storeName.trim();
    for (final r in all) {
      if (r.deleted) continue;
      if (r.id == draft.id) continue;
      if (r.kind != draft.kind) continue;
      if (r.payment != draft.payment) continue;
      if (!_sameDay(r.date, draft.date)) continue;
      if (r.storeName.trim() != name) continue;
      if (r.amount != draft.amount) continue;
      return r;
    }
    return null;
  }

  /// 新規入力 [draft] を既存の [existing] とどう統合するかを決める
  static MergePlan plan(Receipt? existing, Receipt draft, {DateTime? now}) {
    if (existing == null) {
      return const MergePlan(outcome: SaveOutcome.created);
    }
    final stamp = now ?? DateTime.now();
    final hasDraftPhoto = draft.imagePath.isNotEmpty;
    final existingHasPhoto = existing.imagePath.isNotEmpty;

    var updated = existing;
    var photoAdded = false;
    var eventAdded = false;
    var discard = false;

    if (hasDraftPhoto && !existingHasPhoto) {
      updated = updated.copyWith(
        imagePath: draft.imagePath,
        imageUrl: '',
        updatedAt: stamp,
      );
      photoAdded = true;
    } else if (hasDraftPhoto) {
      // 既に写真がある明細には、同じ内容の写真を重ねて保存しない
      discard = true;
    }

    final draftEvent = draft.event.trim();
    if (draftEvent.isNotEmpty && existing.event.trim().isEmpty) {
      updated = updated.copyWith(event: draftEvent, updatedAt: stamp);
      eventAdded = true;
    }

    final SaveOutcome outcome;
    if (photoAdded) {
      outcome = SaveOutcome.photoAttached;
    } else if (eventAdded) {
      outcome = SaveOutcome.eventAttached;
    } else {
      outcome = SaveOutcome.duplicateSkipped;
    }

    return MergePlan(
      outcome: outcome,
      updated: photoAdded || eventAdded ? updated : null,
      discardDraftImage: discard,
    );
  }
}

/// 保存結果を利用者向けの文言にする
String saveMessage(SaveOutcome outcome) {
  switch (outcome) {
    case SaveOutcome.created:
      return '保存しました';
    case SaveOutcome.updated:
      return '修正しました';
    case SaveOutcome.photoAttached:
      return '同じ内容の明細に写真を追加しました（二重登録はしていません）';
    case SaveOutcome.eventAttached:
      return '同じ内容の明細にイベント名を追加しました（二重登録はしていません）';
    case SaveOutcome.duplicateSkipped:
      return '同じ内容の明細が既にあるため、二重登録しませんでした';
  }
}
