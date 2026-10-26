import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

// PNG 1×1 transparan
final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

Uint8List zip(Map<String, Object> files) {
  final a = Archive();
  files.forEach((name, content) {
    final bytes = content is String ? utf8.encode(content) : content as List<int>;
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}
