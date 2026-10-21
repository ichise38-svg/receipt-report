/**
 * 収支管理アプリ（Receipt Report）の会員同期サーバー（Google Apps Script・無料）
 * 外部の有料APIは使いません。
 *
 * 設定手順:
 * 1. Google スプレッドシートを新規作成（会員全員で同じものを使う）
 * 2. 拡張機能 > Apps Script を開き、このコードを貼り付け
 * 3. SECRET_TOKEN を合言葉に変更（アプリの「合言葉」に同じ値を全員が入力）
 *    ※ Apps Script はリクエストヘッダを読めないため、合言葉は送信データ内の token で照合します
 * 4. デプロイ > 新しいデプロイ > 種類「ウェブアプリ」
 *    - 実行ユーザー: 自分 / アクセスできるユーザー: 全員
 * 5. 発行されたURL（https://script.google.com/.../exec）をアプリの「送信先URL」に入力
 *
 * 保存先:
 * - 「明細」シート: レシート・収入（読みやすい列 ＋ 同期用のデータ列）
 * - 「参加者」シート: 参加者名簿（同期用）
 * - 「収支レシート画像」フォルダ（Googleドライブ）: レシート画像
 *
 * 同期の考え方:
 * - 更新日時（updatedMs）が新しい方を採用（最後の更新優先）。削除も全員に反映。
 * - 同期時刻（syncMs）で差分を判定し、前回以降に変わった分だけ返す。
 * - 同時書き込みはロックで直列化する。
 *
 * 注意: 旧バージョンの「明細」シートを使っていた場合は、シートを削除してから
 *       この版を使ってください（列構成が異なるため）。
 */
const SECRET_TOKEN = 'CHANGE_ME_TO_YOUR_KEY';
const DETAIL_SHEET = '明細';
const MEMBER_SHEET = '参加者';
const IMAGE_FOLDER = '収支レシート画像';

const DETAIL_HEADERS = [
  'ID', '区分', '日付', '店舗・摘要', 'カテゴリ', '金額（円）', 'メモ',
  '画像URL', '更新ms', '削除', '同期ms', 'データ',
];
const MEMBER_HEADERS = ['ID', '氏名', 'メモ', '更新ms', '削除', '同期ms', 'データ'];

// 明細の列番号（1始まり）
const R_COL = { id: 1, kind: 2, date: 3, store: 4, category: 5, amount: 6, memo: 7,
  imageUrl: 8, updated: 9, deleted: 10, synced: 11, json: 12 };
// 参加者の列番号（1始まり）
const M_COL = { id: 1, name: 2, note: 3, updated: 4, deleted: 5, synced: 6, json: 7 };

function doPost(e) {
  const lock = LockService.getScriptLock();
  let locked = false;
  try {
    const data = JSON.parse(e.postData.contents);
    if (!checkToken_(data.token)) {
      return json_({ ok: false, error: 'unauthorized' });
    }
    if (data.ping) {
      return json_({ ok: true, message: 'pong' });
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

/** 同期本体：送られた変更を反映し、前回以降に変わった分を返す */
function sync_(data) {
  const now = Date.now();
  const rSheet = getSheet_(DETAIL_SHEET, DETAIL_HEADERS);
  const mSheet = getSheet_(MEMBER_SHEET, MEMBER_HEADERS);
  const haveImages = data.haveImages || {};
  const acceptedIds = {}; // 反映（採用）された明細ID
  const sendBack = {};    // サーバー側が新しいため採用しなかった明細・参加者（端末へ返す）
  const imageUrls = {};   // 今回保存した画像のURL（ID→URL）

  // --- 明細: 送られてきた変更を反映 ---
  const rIndex = indexRows_(rSheet);
  (data.receipts || []).forEach(function (r) {
    const incomingMs = Date.parse(r.updatedAt) || 0;
    const rowNo = rIndex[r.id];
    const current = rowNo ? readReceiptRow_(rSheet, rowNo) : null;
    if (current && current.updated >= incomingMs) {
      // サーバーの方が新しい/同じ: 採用せず、サーバーの内容を端末へ返す
      sendBack[r.id] = true;
      return;
    }

    let imageUrl = '';
    if (r.deleted) {
      if (current && current.imageUrl) trashImage_(current.imageUrl);
    } else if (r.imageBase64) {
      if (current && current.imageUrl) trashImage_(current.imageUrl);
      imageUrl = saveImage_(r.id, r.imageBase64, r.imageMimeType);
      imageUrls[r.id] = imageUrl;
    } else if (r.imageUrl) {
      imageUrl = current && current.imageUrl ? current.imageUrl : r.imageUrl;
    } else {
      if (current && current.imageUrl) trashImage_(current.imageUrl);
    }

    const stored = JSON.parse(JSON.stringify(r));
    delete stored.imageBase64;
    delete stored.imageMimeType;
    stored.imageUrl = imageUrl;

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
    ];
    if (rowNo) {
      rSheet.getRange(rowNo, 1, 1, row.length).setValues([row]);
    } else {
      rSheet.appendRow(row);
      rIndex[r.id] = rSheet.getLastRow();
    }
    acceptedIds[r.id] = true;
  });

  // --- 明細: 前回以降に変わった分を返す ---
  const since = Number(data.since) || 0;
  const receipts = [];
  readAllRows_(rSheet).forEach(function (row) {
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

  // --- 参加者: 送られてきた変更を反映 ---
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
  readAllRows_(mSheet, 7).forEach(function (row) {
    if (!row[M_COL.id - 1]) return;
    const synced = Number(row[M_COL.synced - 1]) || 0;
    if (synced <= since && !sendBack[String(row[M_COL.id - 1])]) return;
    members.push(JSON.parse(String(row[M_COL.json - 1])));
  });

  return {
    ok: true,
    receipts: receipts,
    members: members,
    imageUrls: imageUrls,
    serverTime: now,
  };
}

function checkToken_(token) {
  if (SECRET_TOKEN === 'CHANGE_ME_TO_YOUR_KEY') return false;
  return token === SECRET_TOKEN;
}

function getSheet_(name, headers) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
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

function readReceiptRow_(sheet, rowNo) {
  const row = sheet.getRange(rowNo, 1, 1, R_COL.json).getValues()[0];
  return {
    updated: Number(row[R_COL.updated - 1]) || 0,
    imageUrl: String(row[R_COL.imageUrl - 1] || ''),
  };
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
  const it = DriveApp.getFoldersByName(IMAGE_FOLDER);
  return it.hasNext() ? it.next() : DriveApp.createFolder(IMAGE_FOLDER);
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
