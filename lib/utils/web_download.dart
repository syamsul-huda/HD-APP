// Conditional export: pakai web_impl di browser, stub di mobile
export 'web_download_stub.dart' if (dart.library.html) 'web_download_impl.dart';
