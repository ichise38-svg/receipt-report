import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/member.dart';
import '../services/member_import.dart';
import '../services/member_store.dart';

/// 参加者名簿：手入力・CSV/TXT/Excel読込・名簿の写真保存
class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> {
  List<Member> _members = [];
  List<String> _photos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final members = await MemberStore.loadAll();
    final photos = await MemberStore.loadRosterPhotos();
    if (!mounted) return;
    setState(() {
      _members = members;
      _photos = photos;
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addByHand({Member? target}) async {
    final nameCtrl = TextEditingController(text: target?.name ?? '');
    final noteCtrl = TextEditingController(text: target?.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(target == null ? '参加者を追加' : '参加者を修正'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '氏名（必須）'),
            ),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: '所属・区分（任意）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    final note = noteCtrl.text.trim();
    nameCtrl.dispose();
    noteCtrl.dispose();
    if (saved != true) return;
    if (name.isEmpty) {
      _toast('氏名を入力してください。');
      return;
    }
    await MemberStore.upsert(
      Member(id: target?.id, name: name, note: note),
    );
    await _reload();
  }

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        _toast('ファイルを読み込めませんでした。');
        return;
      }
      final ext = (file.extension ?? '').toLowerCase();
      final List<String> names;
      if (ext == 'xlsx') {
        names = MemberImport.parseXlsx(bytes);
      } else {
        final text = _decodeUtf8(bytes);
        if (text == null) {
          _toast('文字コードを読み取れません。UTF-8のCSV、またはExcel(.xlsx)で保存してください。');
          return;
        }
        names = MemberImport.parseText(text);
      }
      if (names.isEmpty) {
        _toast('氏名を読み取れませんでした。1列目に氏名があるか確認してください。');
        return;
      }
      final added = await MemberStore.addNames(names);
      await _reload();
      _toast('$added名を追加しました（読込 ${names.length}件・重複は除外）。');
    } catch (_) {
      _toast('読み込みに失敗しました。');
    }
  }

  /// UTF-8 を優先し、失敗時は Shift_JIS 相当として扱う（Excel保存CSV対策）
  String? _decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (picked == null) return;
      await MemberStore.addRosterPhoto(picked.path);
      await _reload();
      _toast('名簿の写真を保存しました。');
    } catch (_) {
      _toast('写真の取得に失敗しました。カメラ・写真の許可を確認してください。');
    }
  }

  Future<void> _confirmDelete(Member m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${m.name}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MemberStore.delete(m.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('参加者名簿（${_members.length}名）'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '名簿を追加',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'file':
                  _importFile();
                  break;
                case 'camera':
                  _addPhoto(ImageSource.camera);
                  break;
                case 'gallery':
                  _addPhoto(ImageSource.gallery);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'file', child: Text('ファイルから読込（CSV/TXT/Excel）')),
              PopupMenuItem(value: 'camera', child: Text('名簿を撮影して保存')),
              PopupMenuItem(value: 'gallery', child: Text('名簿の写真を選択して保存')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.groups, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '参加人数：${_members.length}名\n'
                              '（報告書の人数・1人あたり支出に使用します）',
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _addByHand(),
                          icon: const Icon(Icons.person_add),
                          label: const Text('手入力で追加'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _importFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('ファイル読込'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _addPhoto(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('名簿を撮影'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '参加者が未登録です。\n手入力、またはCSV/Excelファイルから読み込んでください。',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._members.asMap().entries.map(
                      (e) => Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Text('${e.key + 1}')),
                          title: Text(e.value.name),
                          subtitle: e.value.note.isEmpty
                              ? null
                              : Text(e.value.note),
                          onTap: () => _addByHand(target: e.value),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(e.value),
                          ),
                        ),
                      ),
                    ),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '名簿の写真（控え）',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(_photos[i]),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton.filledTonal(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () async {
                                  await MemberStore.removeRosterPhoto(
                                    _photos[i],
                                  );
                                  await _reload();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
