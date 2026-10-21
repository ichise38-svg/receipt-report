/**
 * 収支管理アプリ（Receipt Report）のクラウド受信側サンプル
 * Google Apps Script（無料）で動作します。外部の有料APIは使いません。
 *
 * 設定手順:
 * 1. Google スプレッドシートを新規作成
 * 2. 拡張機能 > Apps Script を開き、このコードを貼り付け
 * 3. SECRET_TOKEN を任意の文字列に変更（アプリの「アクセスキー」に同じ値を入力）
 *    ※ Apps Script はリクエストヘッダを読めないため、キーは送信データ内の token で照合します
 * 4. デプロイ > 新しいデプロイ > 種類「ウェブアプリ」
 *    - 実行ユーザー: 自分 / アクセスできるユーザー: 全員
 * 5. 発行されたURL（https://script.google.com/.../exec）をアプリの「送信先URL」に入力
 *
 * 保存先:
 * - 「明細」シート: 受信した収支を追記（同じIDは上書き）
 * - 「レシート画像」フォルダ（Googleドライブ）: レシート画像を保存
 */
const SECRET_TOKEN = 'CHANGE_ME_TO_YOUR_KEY';
const DETAIL_SHEET = '明細';
const IMAGE_FOLDER = '収支レシート画像';

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    if (!checkToken_(data.token)) {
      return json_({ ok: false, error: 'unauthorized' });
    }
    if (data.ping) {
      return json_({ ok: true, message: 'pong' });
    }
    const sheet = getDetailSheet_();
    const folder = getImageFolder_();
    const existing = indexRowsById_(sheet);
    let written = 0;

    (data.entries || []).forEach(function (r) {
      let imageUrl = '';
      if (r.imageBase64) {
        const blob = Utilities.newBlob(
          Utilities.base64Decode(r.imageBase64),
          r.imageMimeType || 'image/jpeg',
          r.id + '.jpg'
        );
        const file = folder.createFile(blob);
        imageUrl = file.getUrl();
      }
      const row = [
        r.id,
        r.kind === 'income' ? '収入' : '支出',
        new Date(r.date),
        r.storeName,
        r.category,
        Number(r.amount) || 0,
        r.memo || '',
        imageUrl,
        new Date(),
      ];
      if (existing[r.id]) {
        sheet.getRange(existing[r.id], 1, 1, row.length).setValues([row]);
      } else {
        sheet.appendRow(row);
      }
      written++;
    });

    return json_({ ok: true, written: written, title: data.title || '' });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  }
}

function checkToken_(token) {
  if (SECRET_TOKEN === 'CHANGE_ME_TO_YOUR_KEY') return false;
  return token === SECRET_TOKEN;
}

function getDetailSheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(DETAIL_SHEET);
  if (!sheet) {
    sheet = ss.insertSheet(DETAIL_SHEET);
    sheet.appendRow([
      'ID', '区分', '日付', '店舗・摘要', 'カテゴリ', '金額（円）', 'メモ', '画像URL', '受信日時',
    ]);
    sheet.setFrozenRows(1);
  }
  return sheet;
}

function getImageFolder_() {
  const it = DriveApp.getFoldersByName(IMAGE_FOLDER);
  return it.hasNext() ? it.next() : DriveApp.createFolder(IMAGE_FOLDER);
}

function indexRowsById_(sheet) {
  const map = {};
  const last = sheet.getLastRow();
  if (last < 2) return map;
  const ids = sheet.getRange(2, 1, last - 1, 1).getValues();
  ids.forEach(function (row, i) {
    if (row[0]) map[row[0]] = i + 2;
  });
  return map;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
