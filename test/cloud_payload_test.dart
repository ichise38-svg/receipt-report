import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:receipt_report/services/cloud_sync_service.dart';

/// 写真に近い（ノイズと階調を含む）画像を生成
img.Image _photoLike(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final n = (x * 31 + y * 17) % 97;
      im.setPixelRgb(
        x,
        y,
        (x * 255 ~/ w + n) % 256,
        (y * 255 ~/ h) % 256,
        (x + y + n) % 256,
      );
    }
  }
  return im;
}

void main() {
  test('大きい画像は長辺1200pxに縮小されJPEGになる', () {
    final big = _photoLike(3000, 2000);
    final src = Uint8List.fromList(img.encodePng(big));

    final b64 = CloudSyncService.compressBytesForTest(src);
    expect(b64, isNotNull);
    final out = img.decodeJpg(base64Decode(b64!));
    expect(out, isNotNull);
    expect(out!.width, 1200);
    expect(out.height, 800);
    expect(base64Decode(b64).length, lessThan(src.length));
  });

  test('縦長画像（長いレシート）は高さ2400pxまで残り、文字が読める', () {
    final tall = img.Image(width: 800, height: 3000);
    final src = Uint8List.fromList(img.encodePng(tall));
    final out = img.decodeJpg(
      base64Decode(CloudSyncService.compressBytesForTest(src)!),
    );
    expect(out!.height, 2400);
    expect(out.width, 640);
  });

  test('ほぼ正方形の画像は従来どおり長辺1200pxに縮小される', () {
    final sq = img.Image(width: 2000, height: 1800);
    final src = Uint8List.fromList(img.encodePng(sq));
    final out = img.decodeJpg(
      base64Decode(CloudSyncService.compressBytesForTest(src)!),
    );
    expect(out!.width, 1200);
  });

  test('小さい画像は拡大せずそのまま', () {
    final small = img.Image(width: 300, height: 200);
    final src = Uint8List.fromList(img.encodePng(small));
    final out = img.decodeJpg(
      base64Decode(CloudSyncService.compressBytesForTest(src)!),
    );
    expect(out!.width, 300);
    expect(out.height, 200);
  });

  test('画像として読めないデータはnull', () {
    expect(
      CloudSyncService.compressBytesForTest(Uint8List.fromList([1, 2, 3])),
      isNull,
    );
  });
}
