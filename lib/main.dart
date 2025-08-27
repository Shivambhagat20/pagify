// lib/main.dart
import 'package:flutter/material.dart';

// ✅ If you use Syncfusion on desktop, register your license (remove comment)
// import 'package:syncfusion_flutter_core/core.dart';

// Screens
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔑 Syncfusion license (uncomment and paste your key if you have one)
  // SyncfusionLicense.registerLicense('YOUR_SYNCFUSION_LICENSE_KEY');

  runApp(const PagifyApp());
}

class PagifyApp extends StatelessWidget {
  const PagifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pagify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        // Slightly crisper desktop UX
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Keep Library as the default screen
      initialRoute: '/',
      routes: {
        '/': (_) => const LibraryScreen(),
        // ReaderScreen takes arguments via Navigator.pushNamed
        // (name, docId, bytes/filePath, startPage)
        ReaderScreen.route: (_) => const ReaderScreen(),
      },
    );
  }
}
