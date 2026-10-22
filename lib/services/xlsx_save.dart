import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Excel を保存先を選んで保存する（Android/iOS は保存先の選択画面。OneDrive なども選べる）。
/// Web は保存画面が使えないため共有シートを使う。
/// 戻り値: 保存先のパス（共有シートを使った場合は null）
Future<String?> saveXlsxBytes({
  required List<int> bytes,
  required String fileName,
  required String dialogTitle,
}) async {
  final data = Uint8List.fromList(bytes);
  if (!kIsWeb) {
    return FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: data,
    );
  }
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          data,
          name: fileName,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ],
      subject: fileName,
    ),
  );
  return null;
}
