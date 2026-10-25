/**
 * 収支管理アプリ（Receipt Report）の会員同期サーバー（Google Apps Script・無料）
 * 外部の有料APIは使いません。
 *
 * 設定手順:
 * 1. Google スプレッドシートを新規作成（管理用・会員全員で同じURLを使う）
 * 2. 拡張機能 > Apps Script を開き、このコードを貼り付けて保存
 * 3. デプロイ > 新しいデプロイ > 種類「ウェブアプリ」
 *    - 実行ユーザー: 自分 / アクセスできるユーザー: 全員
 * 4. 発行されたURL（https://script.google.com/.../exec）をアプリに組み込む
 *
 * 保存先（年別にファイルを自動作成）:
 * - 管理用スプレッドシート（このファイル）:
 *     「参加者」 … 参加者名簿（年をまたいで共通）
 *     「年別ファイル」 … 年と、その年のスプレッドシートのID・URL の一覧
 *     「ID索引」 … 明細・口座出納のIDがどの年のファイルにあるかの一覧
 * - 「関桜会収支 2026」「関桜会収支 2027」… 年ごとのスプレッドシート（Googleドライブの「関桜会収支データ」フォルダ）
 *     「明細」 … レシート・収入（その年の日付のもの）
 *     「口座出納」 … 口座の出納（その年の日付のもの）
 * - 「収支レシート画像」フォルダ（Googleドライブ）: レシート画像
 *
 * 年の判定: 明細・口座出納の日付（yyyy-MM-dd）の年で振り分けます。
 * 日付を後から別の年に変えた場合は、古い年のファイルから移し、新しい年のファイルに保存します。
 *
 * 同期の考え方:
 * - 更新日時（updatedMs）が新しい方を採用（最後の更新優先）。削除も全員に反映。
 * - 同期時刻（syncMs）で差分を判定し、前回以降に変わった分だけ返す。
 * - 同時書き込みはロックで直列化する。
 *
 * 注意: 以前の版で作った「明細」シートがこの管理用ファイルに残っていても使いません。
 *       混乱を避けるため削除してください。
 */
const MEMBER_SHEET = '参加者';
const YEAR_SHEET = '年別ファイル';
const KEY_SHEET = 'ID索引';
const DETAIL_SHEET = '明細';
const BANK_SHEET = '口座出納';
const IMAGE_FOLDER = '収支レシート画像';
const DATA_FOLDER = '関桜会収支データ';
const BOOK_PREFIX = '関桜会収支 ';

const DETAIL_HEADERS = [
  'ID', '区分', '日付', '店舗・摘要', 'カテゴリ', '金額（円）', 'メモ',
  '画像URL', '更新ms', '削除', '同期ms', 'データ', 'イベント',
];
const MEMBER_HEADERS = ['ID', '氏名', 'メモ', '更新ms', '削除', '同期ms', 'データ'];
const BANK_HEADERS = ['ID', '日付', '区分', '摘要', '金額（円）', '更新ms', '削除', '同期ms', 'データ'];
const YEAR_HEADERS = ['年', 'ファイルID', 'ファイル名', 'URL'];
const KEY_HEADERS = ['種別', 'ID', '年'];

// 明細の列番号（1始まり）
const R_COL = { id: 1, kind: 2, date: 3, store: 4, category: 5, amount: 6, memo: 7,
  imageUrl: 8, updated: 9, deleted: 10, synced: 11, json: 12 };
// 参加者の列番号（1始まり）
const M_COL = { id: 1, name: 2, note: 3, updated: 4, deleted: 5, synced: 6, json: 7 };
// 口座出納の列番号（1始まり）
const B_COL = { id: 1, date: 2, kind: 3, label: 4, amount: 5, updated: 6, deleted: 7, synced: 8, json: 9 };

function doPost(e) {
  const lock = LockService.getScriptLock();
  let locked = false;
  try {
    const data = JSON.parse(e.postData.contents);
    if (data.ping) {
      return json_({ ok: true, message: 'pong' });
    }
    if (data.action === 'bug') {
      // 不具合報告は同期とは別の経路。同期データには触れない
      lock.waitLock(30000);
      locked = true;
      return json_(bugReports_(data));
    }
    if (data.action !== 'sync') {
      return json_({ ok: false, error: 'unknown action' });
    }
    lock.waitLock(60000);
    locked = true;
    return json_(sync_(data));
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  } finally {
    if (locked) lock.releaseLock();
  }
}

/** 同期本体：送られた変更を年別ファイルへ反映し、前回以降に変わった分を返す */
function sync_(data) {
  const now = Date.now();
  const ctx = openContext_();
  const mSheet = getSheet_(MEMBER_SHEET, MEMBER_HEADERS);
  const haveImages = data.haveImages || {};
  const acceptedIds = {}; // 反映（採用）された明細ID
  const sendBack = {};    // サーバー側が新しいため採用しなかったもの（端末へ返す）
  const imageUrls = {};   // 今回保存した画像のURL（ID→URL）

  // --- 明細: 送られてきた変更を反映 ---
  (data.receipts || []).forEach(function (r) {
    const incomingMs = Date.parse(r.updatedAt) || 0;
    const cur = readCurrent_(ctx, 'R', r.id);
    const curUpdated = cur ? Number(cur.values[R_COL.updated - 1]) || 0 : 0;
    if (cur && curUpdated >= incomingMs) {
      // サーバーの方が新しい/同じ: 採用せず、サーバーの内容を端末へ返す
      sendBack[r.id] = true;
      return;
    }
    const curImage = cur ? String(cur.values[R_COL.imageUrl - 1] || '') : '';

    let imageUrl = '';
    if (r.deleted) {
      if (curImage) trashImage_(curImage);
    } else if (r.imageBase64) {
      if (curImage) trashImage_(curImage);
      imageUrl = saveImage_(r.id, r.imageBase64, r.imageMimeType);
      imageUrls[r.id] = imageUrl;
    } else if (r.imageUrl) {
      imageUrl = curImage || r.imageUrl;
    } else {
      if (curImage) trashImage_(curImage);
    }

    const stored = JSON.parse(JSON.stringify(r));
    delete stored.imageBase64;
    delete stored.imageMimeType;
    stored.imageUrl = imageUrl;

    const year = yearOf_(r.date);
    const row = [
      r.id,
      r.kind === 'income' ? '収入' : '支出',
      r.date || '',
      r.storeName || '',
      r.category || '',
      Number(r.amount) || 0,
      r.memo || '',
      imageUrl,
      incomingMs,
      r.deleted ? '削除' : '',
      now,
      JSON.stringify(stored),
      r.event || '',
    ];
    if (cur && cur.year !== year) removeRow_(ctx, 'R', cur.year, r.id);
    putRow_(ctx, 'R', year, r.id, row);
    acceptedIds[r.id] = true;
  });

  // --- 明細: 前回以降に変わった分を返す（全年分） ---
  const since = Number(data.since) || 0;
  const receipts = [];
  eachYear_(ctx, function (book) {
    readAllRows_(book.detail, R_COL.json).forEach(function (row) {
      if (!row[R_COL.id - 1]) return;
      const id = String(row[R_COL.id - 1]);
      const synced = Number(row[R_COL.synced - 1]) || 0;
      if (synced <= since && !sendBack[id]) return;
      const obj = JSON.parse(String(row[R_COL.json - 1]));
      obj.imageUrl = String(row[R_COL.imageUrl - 1] || '');
      obj.deleted = row[R_COL.deleted - 1] === '削除';
      // 端末が持っていない画像だけ返す（通信量の節約）
      if (!acceptedIds[id] && obj.imageUrl && haveImages[id] !== obj.imageUrl) {
        obj.imageBase64 = readImageBase64_(obj.imageUrl);
        obj.imageMimeType = 'image/jpeg';
      }
      receipts.push(obj);
    });
  });

  // --- 参加者: 送られてきた変更を反映（年をまたいで共通） ---
  const mIndex = indexRows_(mSheet, M_COL.id);
  (data.members || []).forEach(function (m) {
    const incomingMs = Date.parse(m.updatedAt) || 0;
    const rowNo = mIndex[m.id];
    if (rowNo) {
      const current = Number(mSheet.getRange(rowNo, M_COL.updated).getValue()) || 0;
      if (current >= incomingMs) {
        sendBack[m.id] = true;
        return;
      }
    }
    const stored = JSON.parse(JSON.stringify(m));
    const row = [
      m.id,
      m.name || '',
      m.note || '',
      incomingMs,
      m.deleted ? '削除' : '',
      now,
      JSON.stringify(stored),
    ];
    if (rowNo) {
      mSheet.getRange(rowNo, 1, 1, row.length).setValues([row]);
    } else {
      mSheet.appendRow(row);
      mIndex[m.id] = mSheet.getLastRow();
    }
  });

  // --- 参加者: 前回以降に変わった分を返す ---
  const members = [];
  readAllRows_(mSheet, M_COL.json).forEach(function (row) {
    if (!row[M_COL.id - 1]) return;
    const synced = Number(row[M_COL.synced - 1]) || 0;
    if (synced <= since && !sendBack[String(row[M_COL.id - 1])]) return;
    members.push(JSON.parse(String(row[M_COL.json - 1])));
  });

  // --- 口座出納: 送られてきた変更を反映（後勝ち・削除は墓標）---
  (data.bankEntries || []).forEach(function (b) {
    const incomingMs = Date.parse(b.updatedAt) || 0;
    const cur = readCurrent_(ctx, 'B', b.id);
    const curUpdated = cur ? Number(cur.values[B_COL.updated - 1]) || 0 : 0;
    if (cur && curUpdated >= incomingMs) {
      sendBack[b.id] = true;
      return;
    }
    const stored = JSON.parse(JSON.stringify(b));
    const year = yearOf_(b.date);
    const row = [
      b.id,
      b.date || '',
      bankKindLabel_(b.kind),
      b.label || '',
      Number(b.amount) || 0,
      incomingMs,
      b.deleted ? '削除' : '',
      now,
      JSON.stringify(stored),
    ];
    if (cur && cur.year !== year) removeRow_(ctx, 'B', cur.year, b.id);
    putRow_(ctx, 'B', year, b.id, row);
  });

  // --- 口座出納: 前回以降に変わった分を返す（全年分） ---
  const bankEntries = [];
  eachYear_(ctx, function (book) {
    readAllRows_(book.bank, B_COL.json).forEach(function (row) {
      if (!row[B_COL.id - 1]) return;
      const synced = Number(row[B_COL.synced - 1]) || 0;
      if (synced <= since && !sendBack[String(row[B_COL.id - 1])]) return;
      bankEntries.push(JSON.parse(String(row[B_COL.json - 1])));
    });
  });

  return {
    ok: true,
    receipts: receipts,
    members: members,
    bankEntries: bankEntries,
    imageUrls: imageUrls,
    serverTime: now,
  };
}

/** 作業用の情報（年別ファイル一覧・ID索引）を読み込む */
function openContext_() {
  const yearSheet = getSheet_(YEAR_SHEET, YEAR_HEADERS);
  const keySheet = getSheet_(KEY_SHEET, KEY_HEADERS);
  const ctx = {
    books: {},      // 年 → { detail, bank, rIdx, bIdx }（開いた年のみ）
    years: {},      // 年 → スプレッドシートID
    yearSheet: yearSheet,
    keySheet: keySheet,
    keyYear: {},    // '種別|ID' → 年
    keyRow: {},     // '種別|ID' → 行番号
  };
  readAllRows_(yearSheet, YEAR_HEADERS.length).forEach(function (row) {
    if (!row[0]) return;
    ctx.years[String(row[0])] = String(row[1]);
  });
  readAllRows_(keySheet, KEY_HEADERS.length).forEach(function (row, i) {
    if (!row[1]) return;
    const key = String(row[0]) + '|' + String(row[1]);
    ctx.keyYear[key] = String(row[2]);
    ctx.keyRow[key] = i + 2;
  });
  return ctx;
}

/** 年のファイルを開く。create=true なら無ければ作る */
function yearBook_(ctx, year, create) {
  const y = String(year);
  if (ctx.books[y]) return ctx.books[y];
  let id = ctx.years[y];
  if (!id) {
    if (!create) return null;
    const ss = SpreadsheetApp.create(BOOK_PREFIX + y);
    DriveApp.getFileById(ss.getId()).moveTo(getDataFolder_());
    // 新規ファイルの既定シートを「明細」に使う
    ss.getSheets()[0].setName(DETAIL_SHEET);
    ss.getSheets()[0].appendRow(DETAIL_HEADERS);
    ss.getSheets()[0].setFrozenRows(1);
    ss.insertSheet(BANK_SHEET).appendRow(BANK_HEADERS);
    ss.getSheetByName(BANK_SHEET).setFrozenRows(1);
    id = ss.getId();
    ctx.years[y] = id;
    ctx.yearSheet.appendRow([Number(y), id, ss.getName(), ss.getUrl()]);
  }
  const ss = SpreadsheetApp.openById(id);
  const book = {
    detail: getSheetIn_(ss, DETAIL_SHEET, DETAIL_HEADERS),
    bank: getSheetIn_(ss, BANK_SHEET, BANK_HEADERS),
    rIdx: null,
    bIdx: null,
  };
  ctx.books[y] = book;
  return book;
}

/** 既存の年ファイルすべてに対して処理を行う */
function eachYear_(ctx, fn) {
  Object.keys(ctx.years).sort().forEach(function (year) {
    const book = yearBook_(ctx, year, false);
    if (book) fn(book);
  });
}

/** 種別（R=明細 / B=口座出納）の ID→行番号 マップ（必要になったとき一度だけ作る） */
function rowMap_(book, kind) {
  const key = kind === 'R' ? 'rIdx' : 'bIdx';
  if (!book[key]) {
    const sheet = kind === 'R' ? book.detail : book.bank;
    book[key] = indexRows_(sheet, kind === 'R' ? R_COL.id : B_COL.id);
  }
  return book[key];
}

/** ID の現在の保存先（年）と行の値を返す。無ければ null */
function readCurrent_(ctx, kind, id) {
  const year = ctx.keyYear[kind + '|' + String(id)];
  if (!year) return null;
  const book = yearBook_(ctx, year, false);
  if (!book) return null;
  const rowNo = rowMap_(book, kind)[String(id)];
  if (!rowNo) return null;
  const sheet = kind === 'R' ? book.detail : book.bank;
  const width = kind === 'R' ? R_COL.json : B_COL.json;
  return { year: year, values: sheet.getRange(rowNo, 1, 1, width).getValues()[0] };
}

/** 別の年のファイルから行を取り除く（年をまたいだ変更用） */
function removeRow_(ctx, kind, year, id) {
  const book = yearBook_(ctx, year, false);
  if (!book) return;
  const rowNo = rowMap_(book, kind)[String(id)];
  if (!rowNo) return;
  const sheet = kind === 'R' ? book.detail : book.bank;
  sheet.deleteRow(rowNo);
  // 行番号がずれるため、索引を作り直す
  if (kind === 'R') book.rIdx = null;
  else book.bIdx = null;
}

/** 年のファイルに行を書き込み（既存なら上書き、無ければ追加）し、ID索引を更新 */
function putRow_(ctx, kind, year, id, row) {
  const book = yearBook_(ctx, year, true);
  const sheet = kind === 'R' ? book.detail : book.bank;
  const map = rowMap_(book, kind);
  const rowNo = map[String(id)];
  if (rowNo) {
    sheet.getRange(rowNo, 1, 1, row.length).setValues([row]);
  } else {
    sheet.appendRow(row);
    map[String(id)] = sheet.getLastRow();
  }
  setKey_(ctx, kind, id, year);
}

/** ID索引（どの年にあるか）を更新 */
function setKey_(ctx, kind, id, year) {
  const key = kind + '|' + String(id);
  ctx.keyYear[key] = String(year);
  const rowNo = ctx.keyRow[key];
  if (rowNo) {
    ctx.keySheet.getRange(rowNo, 3).setValue(Number(year));
  } else {
    ctx.keySheet.appendRow([kind, String(id), Number(year)]);
    ctx.keyRow[key] = ctx.keySheet.getLastRow();
  }
}

/** 日付（yyyy-MM-dd）の年。日付が無い・不正なら今年（東京時間）にする */
function yearOf_(dateStr) {
  const m = /^(\d{4})/.exec(String(dateStr || ''));
  return m ? m[1] : Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy');
}

/** 口座出納の区分を表示用の語にする（端末の kind 名に合わせる） */
function bankKindLabel_(kind) {
  if (kind === 'withdraw') return '出金';
  if (kind === 'cashOut') return '現金引出';
  return '入金';
}

function getSheet_(name, headers) {
  return getSheetIn_(SpreadsheetApp.getActiveSpreadsheet(), name, headers);
}

function getSheetIn_(ss, name, headers) {
  let sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
    sheet.appendRow(headers);
    sheet.setFrozenRows(1);
  }
  return sheet;
}

/** ID→行番号のマップ（ヘッダー行を除く） */
function indexRows_(sheet, idCol) {
  const map = {};
  const last = sheet.getLastRow();
  if (last < 2) return map;
  const col = idCol || R_COL.id;
  const ids = sheet.getRange(2, col, last - 1, 1).getValues();
  ids.forEach(function (row, i) {
    if (row[0]) map[String(row[0])] = i + 2;
  });
  return map;
}

/** ヘッダー以外の全行を返す */
function readAllRows_(sheet, width) {
  const last = sheet.getLastRow();
  if (last < 2) return [];
  const w = width || R_COL.json;
  return sheet.getRange(2, 1, last - 1, w).getValues();
}

function saveImage_(id, b64, mime) {
  const blob = Utilities.newBlob(
    Utilities.base64Decode(b64),
    mime || 'image/jpeg',
    id + '.jpg'
  );
  const file = getImageFolder_().createFile(blob);
  return 'https://drive.google.com/file/d/' + file.getId() + '/view';
}

function fileIdOf_(url) {
  const m = /\/d\/([^/]+)/.exec(url || '');
  return m ? m[1] : '';
}

function trashImage_(url) {
  const fid = fileIdOf_(url);
  if (!fid) return;
  try {
    DriveApp.getFileById(fid).setTrashed(true);
  } catch (err) {
    // 既に削除済みなどは無視
  }
}

function readImageBase64_(url) {
  const fid = fileIdOf_(url);
  if (!fid) return '';
  try {
    return Utilities.base64Encode(DriveApp.getFileById(fid).getBlob().getBytes());
  } catch (err) {
    return '';
  }
}

function getImageFolder_() {
  return getNamedFolder_(IMAGE_FOLDER);
}

function getDataFolder_() {
  return getNamedFolder_(DATA_FOLDER);
}

function getNamedFolder_(name) {
  const it = DriveApp.getFoldersByName(name);
  return it.hasNext() ? it.next() : DriveApp.createFolder(name);
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * 不具合報告の受け口。管理用スプレッドシートの「bug_reports」に追記する。
 * 同じ内容（key）は既存行の件数・最終発生日時を更新し、重複行を作らない。
 * 90日より古い行は受信時に削除する。
 */
const BUG_HEADERS = ['key', 'version', 'build', 'platform', 'screen', 'kind', 'message', 'stack', 'count', 'first', 'last', 'updated'];
const BUG_RETENTION_DAYS = 90;

function bugReports_(data) {
  const reports = Array.isArray(data.reports) ? data.reports : [];
  if (reports.length > 50) {
    return { ok: false, error: 'too many reports' };
  }
  // 版と端末は送信側の app（リクエスト単位）から取る
  const app = data.app || {};
  const appVersion = String(app.version || '');
  const appBuild = String(app.build || '');
  const appPlatform = String(app.platform || '');
  const sheet = getSheet_('bug_reports', BUG_HEADERS);
  const rows = sheet.getLastRow() > 1
    ? sheet.getRange(2, 1, sheet.getLastRow() - 1, BUG_HEADERS.length).getValues()
    : [];
  const index = {};
  rows.forEach(function (row, i) { index[String(row[0])] = i + 2; });

  const now = new Date().toISOString();
  let added = 0;
  let updated = 0;
  reports.forEach(function (r) {
    // 送信側の sig（種類＋先頭スタック＋伏せ字メッセージ）を同一性のキーにする
    const key = String(r.sig || [r.kind, r.message].map(String).join('|')).slice(0, 300);
    const values = [
      key,
      appVersion,
      appBuild,
      appPlatform,
      String(r.screen || ''),
      String(r.kind || ''),
      String(r.message || '').slice(0, 200),
      String((r.stack || []).join ? (r.stack || []).join('\n') : r.stack || '').slice(0, 1000),
      Number(r.count) || 1,
      String(r.first || ''),
      String(r.last || ''),
      now,
    ];
    if (index[key]) {
      const rowNo = index[key];
      const prevCount = Number(sheet.getRange(rowNo, 9).getValue()) || 0;
      const prevLast = String(sheet.getRange(rowNo, 11).getValue());
      // 同じ端末からの再送で件数が増えないよう、大きい方の値を採用
      values[8] = Math.max(prevCount, Number(r.count) || 1);
      values[10] = prevLast > String(r.last || '') ? prevLast : String(r.last || '');
      sheet.getRange(rowNo, 1, 1, BUG_HEADERS.length).setValues([values]);
      updated++;
    } else {
      sheet.appendRow(values);
      index[key] = sheet.getLastRow();
      added++;
    }
  });

  // 保存期間を過ぎた行を削除（下から削除して行番号のずれを防ぐ）
  const limit = new Date(Date.now() - BUG_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    const upd = sheet.getRange(2, BUG_HEADERS.length, lastRow - 1, 1).getValues();
    for (let i = upd.length - 1; i >= 0; i--) {
      if (String(upd[i][0]) < limit) sheet.deleteRow(i + 2);
    }
  }
  return { ok: true, added: added, updated: updated };
}
