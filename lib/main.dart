import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' show Platform;


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await dotenv.load(fileName: ".env");

  runApp(const MyApp());
}

// The root widget of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "BasoChat App",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080C14),
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00C9A7),
          secondary: Color(0xFF64D2FF),
          surface: Color(0xFF0D1826),
          surfaceContainerHighest: Color(0xFF111E2E),
          onPrimary: Color(0xFF001A14),
          onSurface: Color(0xFFE8F4F4),
          onSurfaceVariant: Color(0xFFB0C8D4),
          secondaryContainer: Color(0xFF1A3A50),
          onSecondaryContainer: Color(0xFF9ECFEA),
          primaryContainer: Color(0xFF0F5244),
          onPrimaryContainer: Color(0xFFE8FAF6),
          tertiary: Color(0xFF9A8AFF),
          error: Color(0xFFFF6B6B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1826),
          foregroundColor: Color(0xFFE8F4F4),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF0B1220),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111E2E),
          hintStyle: const TextStyle(color: Color(0xFF4A6A7A)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24.0),
            borderSide: const BorderSide(color: Color(0xFF1E3A54)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24.0),
            borderSide: const BorderSide(color: Color(0xFF1E3A54), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24.0),
            borderSide: const BorderSide(color: Color(0xFF00C9A7), width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24.0),
            borderSide: const BorderSide(color: Color(0xFF1A2A36), width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C9A7),
            foregroundColor: const Color(0xFF001A14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            elevation: 0,
          ),
        ),
        iconButtonTheme: const IconButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(Color(0xFF8BA3B0)),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF1A3A50),
          thickness: 0.5,
        ),
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 600),
          textStyle: const TextStyle(fontSize: 12, color: Color(0xFFE8F4F4)),
          decoration: BoxDecoration(
            color: const Color(0xFF1A3A50),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2A5A78), width: 0.5),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1A3A50),
          contentTextStyle: const TextStyle(color: Color(0xFFE8F4F4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          behavior: SnackBarBehavior.floating,
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Color(0xFFD0E8F0),
          iconColor: Color(0xFF8BA3B0),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
