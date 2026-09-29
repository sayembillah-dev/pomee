import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _rememberThemeMode();
  // Pomee rotates its own content based on sensors; the system must not.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const PomeeApp());
}

/// Restores the light/dark choice and saves it whenever it changes.
Future<void> _rememberThemeMode() async {
  const key = 'themeMode';
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(key);
    themeMode.value = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
    themeMode.addListener(() => prefs.setString(key, themeMode.value.name));
  } catch (_) {
    // Storage unavailable: just follow the system this time.
  }
}

class PomeeApp extends StatelessWidget {
  const PomeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Pomee',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: const HomeScreen(),
      ),
    );
  }
}
