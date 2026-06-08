// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

void triggerWebDownload(String url, String filename) {
  final a = html.AnchorElement(href: url)
    ..setAttribute('download', filename);
  html.document.body?.append(a);
  a.click();
  a.remove();
}

// Simpan bytes yang sudah diunduh ke file — tanpa buka tab baru.
void saveFileWeb(List<int> bytes, String filename) {
  final blob = html.Blob([Uint8List.fromList(bytes)]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..setAttribute('download', filename);
  html.document.body?.append(a);
  a.click();
  a.remove();
  // Revoke setelah browser sempat memulai unduhan
  Future.delayed(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(url));
}
