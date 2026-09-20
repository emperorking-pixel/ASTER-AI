import 'package:flutter/material.dart';
import 'secure_key_store.dart';
import 'chat_screen.dart';
import 'background_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeBackgroundService(); // registers the service, does NOT start it
  runApp(const AsterApp());
}

class AsterApp extends StatelessWidget {
  const AsterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0A0E14)),
      home: const _RootGate(),
    );
  }
}

/// Decides whether to show the API key setup screen or the chat screen.
class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _loading = true;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final key = await SecureKeyStore.readKey();
    setState(() {
      _hasKey = key != null && key.isNotEmpty;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E14),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF7C5CFF))),
      );
    }
    if (!_hasKey) {
      return ApiKeySetupScreen(onSaved: () => setState(() => _hasKey = true));
    }
    return const ChatScreen();
  }
}
