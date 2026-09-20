// secure_key_store.dart
//
// Stores the user's Anthropic API key using flutter_secure_storage, which on
// Android is backed by the Android Keystore (encrypted, not plain text).
//
// IMPORTANT: never hardcode a real API key into this file or any file you
// commit to GitHub. The key is meant to be typed in once at runtime by
// whoever installs the app, and live only in secure storage on that phone.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyStore {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'anthropic_api_key';

  static Future<String?> readKey() => _storage.read(key: _keyName);

  static Future<void> saveKey(String key) => _storage.write(key: _keyName, value: key.trim());

  static Future<void> clearKey() => _storage.delete(key: _keyName);
}

/// Simple onboarding/settings screen for entering the API key.
/// Shown at first launch, and reachable later from Settings to change it.
class ApiKeySetupScreen extends StatefulWidget {
  final VoidCallback onSaved;
  const ApiKeySetupScreen({super.key, required this.onSaved});

  @override
  State<ApiKeySetupScreen> createState() => _ApiKeySetupScreenState();
}

class _ApiKeySetupScreenState extends State<ApiKeySetupScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (!key.startsWith('sk-ant-')) {
      setState(() => _error = 'That doesn\'t look like an Anthropic API key (should start with "sk-ant-").');
      return;
    }
    setState(() { _saving = true; _error = null; });
    await SecureKeyStore.saveKey(key);
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Connect Aster',
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'Paste your own Anthropic API key. It\'s stored encrypted on this '
                'phone only, and every message you send is billed to your own '
                'Anthropic account.',
                style: TextStyle(color: Color(0xFF8B93A3), fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                obscureText: _obscure,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'sk-ant-...',
                  hintStyle: const TextStyle(color: Color(0xFF555F70)),
                  filled: true,
                  fillColor: const Color(0xFF161B24),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF8B93A3)),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Color(0xFFE0685A))),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C5CFF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save and continue', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
