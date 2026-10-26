import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// File yang dibuka dari aplikasi lain ("Buka dengan SuperAppHD").
class IncomingFile {
  final String path;
  final String name;
  const IncomingFile(this.path, this.name);

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// Menerima dokumen dari intent Android (ACTION_VIEW / ACTION_SEND) dan
/// "Open in" iOS. Sisi native menyalin file ke cache aplikasi lalu
/// mengirim path-nya lewat MethodChannel.
class OpenWithService {
  static const _channel = MethodChannel('superapp/open_with');
  static final _controller = StreamController<IncomingFile>.broadcast();
  static bool _initialized = false;

  /// File yang masuk saat aplikasi sudah berjalan.
  static Stream<IncomingFile> get files => _controller.stream;

  static void init() {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFile') {
        final f = _parse(call.arguments);
        if (f != null) _controller.add(f);
      }
    });
  }

  /// File yang membuat aplikasi diluncurkan (cold start), sekali ambil.
  static Future<IncomingFile?> initialFile() async {
    if (kIsWeb) return null;
    try {
      return _parse(await _channel.invokeMethod('getInitialFile'));
    } on MissingPluginException {
      return null; // platform tanpa implementasi native (desktop, test)
    } on PlatformException catch (e) {
      debugPrint('OpenWith: ${e.message}');
      return null;
    }
  }

  static IncomingFile? _parse(Object? args) {
    if (args is! Map) return null;
    final path = args['path'] as String?;
    if (path == null || path.isEmpty) return null;
    final name = (args['name'] as String?) ?? path.split('/').last;
    return IncomingFile(path, name);
  }
}
