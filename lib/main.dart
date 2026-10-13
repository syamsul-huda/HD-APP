import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/dashboard_screen.dart';
import 'services/api_service.dart';
import 'services/app_settings.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await ApiService().init();
  await AppSettings.load();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (_, mode, __) => MaterialApp(
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
