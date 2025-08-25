import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

// Screens
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/login_screen.dart' as ls;

// Services
import 'services/auth_service.dart';

Future<void> _ensureFirebase() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebase();
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
      ),
      home: const _AuthOrGuestGate(),
      routes: {
        ls.LoginScreen.route: (_) => const ls.LoginScreen(),
        '/library': (_) => const LibraryScreen(),
        ReaderScreen.route: (_) => const ReaderScreen(), // '/reader'
      },
    );
  }
}

class _AuthOrGuestGate extends StatefulWidget {
  const _AuthOrGuestGate({super.key});
  @override
  State<_AuthOrGuestGate> createState() => _AuthOrGuestGateState();
}

class _AuthOrGuestGateState extends State<_AuthOrGuestGate> {
  late final Stream<User?> _authStream = FirebaseAuth.instance.authStateChanges();
  Future<_GateState>? _gateFuture;

  @override
  void initState() {
    super.initState();
    _gateFuture = _computeInitialGate();
  }

  Future<_GateState> _computeInitialGate() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) return _GateState.allowLibrary;

      final isGuest = await AuthService.instance.isGuest;
      if (isGuest) {
        final usage = await AuthService.instance.guestUsage();
        if (usage.left > 0) return _GateState.allowLibrary;
      }
      return _GateState.requireLogin;
    } catch (_) {
      return _GateState.requireLogin;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_GateState>(
      future: _gateFuture,
      builder: (context, initialSnap) {
        if (initialSnap.connectionState != ConnectionState.done) {
          return const _Splash();
        }
        return StreamBuilder<User?>(
          stream: _authStream,
          builder: (context, authSnap) {
            final user = authSnap.data;
            if (user != null) return const LibraryScreen();
            return FutureBuilder<bool>(
              future: _hasGuestAllowance(),
              builder: (context, guestSnap) {
                if (guestSnap.connectionState != ConnectionState.done) {
                  return const _Splash();
                }
                return guestSnap.data == true
                    ? const LibraryScreen()
                    : const ls.LoginScreen();
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _hasGuestAllowance() async {
    try {
      final isGuest = await AuthService.instance.isGuest;
      if (!isGuest) return false;
      final usage = await AuthService.instance.guestUsage();
      return usage.left > 0;
    } catch (_) {
      return false;
    }
  }
}

enum _GateState { allowLibrary, requireLogin }

class _Splash extends StatelessWidget {
  const _Splash({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
