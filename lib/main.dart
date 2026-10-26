import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/dashboard_screen.dart';
import 'screens/reader_screen.dart';
import 'services/api_service.dart';
import 'services/app_settings.dart';
import 'services/history_service.dart';
import 'services/open_with_service.dart';
import 'utils/app_theme.dart';
import 'utils/office/office_fonts.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await ApiService().init();
  await AppSettings.load();
  await HistoryService.load();
  OpenWithService.init();
  registerOfficeFontLicenses();
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  StreamSubscription<IncomingFile>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = OpenWithService.files.listen(_openIncoming);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInitialFile());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS menitipkan file yang dibuka saat aplikasi di background
    if (state == AppLifecycleState.resumed) _checkInitialFile();
  }

  Future<void> _checkInitialFile() async {
    final f = await OpenWithService.initialFile();
    if (f != null) _openIncoming(f);
  }

  /// Dokumen dari aplikasi lain: catat di Recent lalu buka viewer yang sesuai.
  Future<void> _openIncoming(IncomingFile file) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    await HistoryService.touchRecentFile(file.path, file.name, file.extension);
    if (!ctx.mounted) return;
    final ok = await openDocumentViewer(ctx, file.path, file.name, file.extension);
    if (!ok && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('.${file.extension.toUpperCase()} files cannot be opened'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (_, mode, __) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'SuperAppHD',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const DashboardScreen(),
      ),
    );
  }
}
