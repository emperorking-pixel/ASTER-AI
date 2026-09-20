// chat_screen.dart
//
// The main screen: chat with Aster, talk to it with the mic, and pull in
// buffered notifications only when you explicitly ask for them.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'anthropic_service.dart';
import 'secure_key_store.dart';
import 'notification_buffer_service.dart';
import 'background_service.dart';

class _Msg {
  final String role; // 'user' | 'assistant'
  final String text;
  _Msg(this.role, this.text);
  Map<String, dynamic> toJson() => {'role': role, 'text': text};
  factory _Msg.fromJson(Map<String, dynamic> j) => _Msg(j['role'], j['text']);
}

// Electric, near-black "futuristic electronics" palette.
const _bg = Color(0xFF0A0E14);
const _surface = Color(0xFF141A24);
const _border = Color(0xFF232B3A);
const _text = Color(0xFFE7ECF5);
const _muted = Color(0xFF7C8798);
const _accent = Color(0xFF7C5CFF); // electric violet
const _accent2 = Color(0xFF00E5FF); // electric cyan, used very sparingly

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final List<_Msg> _messages = [];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();

  bool _sending = false;
  bool _listening = false;
  bool _speakReplies = false;
  String _personality = 'Be direct, warm, and honest. Help with conversation, '
      'writing stories, and thinking through problems clearly.';
  DateTime? _lastNotificationCheck;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _speech.initialize();
  }

  Future<File> _historyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/aster_chat_history.json');
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _historyFile();
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
        setState(() {
          _messages.addAll(raw.map((j) => _Msg.fromJson(j as Map<String, dynamic>)));
        });
      }
    } catch (_) {
      // Start fresh if the history file is missing or unreadable.
    }
  }

  Future<void> _saveHistory() async {
    try {
      final file = await _historyFile();
      await file.writeAsString(jsonEncode(_messages.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _send(String text, {bool spoken = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    final apiKey = await SecureKeyStore.readKey();
    if (apiKey == null || apiKey.isEmpty) {
      _showError('No API key saved yet. Open Settings to add one.');
      return;
    }

    setState(() {
      _messages.add(_Msg('user', trimmed));
      _sending = true;
    });
    _inputController.clear();
    _scrollToEnd();
    await _saveHistory();

    try {
      final service = AnthropicService(apiKey);
      final conversation = _messages
          .map((m) => AnthropicMessage(m.role == 'user' ? 'user' : 'assistant', m.text))
          .toList();
      final reply = await service.send(conversation, systemPrompt: _personality);
      setState(() => _messages.add(_Msg('assistant', reply)));
      await _saveHistory();
      if (spoken || _speakReplies) {
        await _tts.speak(reply);
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  Future<void> _whatDidIMiss() async {
    final items = NotificationBufferService.unreadSince(_lastNotificationCheck);
    if (items.isEmpty) {
      _showError('Nothing buffered yet from apps you\'ve opted in.');
      return;
    }
    final lines = items.map((n) => '- [${n.packageName}] ${n.title}: ${n.content}').join('\n');
    _lastNotificationCheck = DateTime.now();
    await _send('Summarize what I missed from these notifications:\n$lines');
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize();
    if (!available) {
      _showError('Speech recognition isn\'t available (check mic permission).');
      return;
    }
    setState(() => _listening = true);
    _speech.listen(
      onResult: (result) {
        _inputController.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _listening = false);
          _send(result.recognizedWords, spoken: true);
        }
      },
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF3A1E1E)),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _SettingsSheet(
        speakReplies: _speakReplies,
        personality: _personality,
        onSpeakRepliesChanged: (v) => setState(() => _speakReplies = v),
        onPersonalityChanged: (v) => setState(() => _personality = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text('ASTER', style: TextStyle(color: _text, letterSpacing: 3, fontWeight: FontWeight.w600, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.notifications_none, color: _muted), onPressed: _whatDidIMiss, tooltip: 'What did I miss?'),
          IconButton(icon: const Icon(Icons.tune, color: _muted), onPressed: _openSettings, tooltip: 'Settings'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final m = _messages[i];
                final isUser = m.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: isUser ? _accent.withOpacity(0.18) : _surface,
                      border: Border.all(color: isUser ? _accent.withOpacity(0.5) : _border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(m.text, style: const TextStyle(color: _text, fontSize: 15, height: 1.4)),
                  ),
                );
              },
            ),
          ),
          if (_sending) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator(minHeight: 2, color: _accent2, backgroundColor: Colors.transparent)),
          Container(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? _accent2 : _muted),
                  onPressed: _toggleListening,
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    style: const TextStyle(color: _text),
                    decoration: InputDecoration(
                      hintText: 'Talk to Aster…',
                      hintStyle: const TextStyle(color: _muted),
                      filled: true,
                      fillColor: _surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, color: Colors.white),
                    onPressed: () => _send(_inputController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  final bool speakReplies;
  final String personality;
  final ValueChanged<bool> onSpeakRepliesChanged;
  final ValueChanged<String> onPersonalityChanged;

  const _SettingsSheet({
    required this.speakReplies,
    required this.personality,
    required this.onSpeakRepliesChanged,
    required this.onPersonalityChanged,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late TextEditingController _personalityController;
  bool _bgRunning = false;
  bool _notifPermission = false;

  @override
  void initState() {
    super.initState();
    _personalityController = TextEditingController(text: widget.personality);
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final running = await isAsterBackgroundServiceRunning();
    final notif = await NotificationBufferService.hasPermission();
    setState(() {
      _bgRunning = running;
      _notifPermission = notif;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Settings', style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            SwitchListTile(
              value: widget.speakReplies,
              onChanged: widget.onSpeakRepliesChanged,
              title: const Text('Speak replies aloud', style: TextStyle(color: _text)),
              activeColor: _accent,
            ),
            const SizedBox(height: 8),
            const Text('How Aster behaves', style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 6),
            TextField(
              controller: _personalityController,
              maxLines: 3,
              style: const TextStyle(color: _text),
              decoration: InputDecoration(
                filled: true, fillColor: _surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: widget.onPersonalityChanged,
            ),
            const SizedBox(height: 20),
            const Divider(color: _border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Background service', style: TextStyle(color: _text)),
              subtitle: Text(_bgRunning ? 'Running' : 'Stopped', style: const TextStyle(color: _muted)),
              trailing: Switch(
                activeColor: _accent,
                value: _bgRunning,
                onChanged: (v) async {
                  if (v) {
                    startAsterBackgroundService();
                  } else {
                    stopAsterBackgroundService();
                  }
                  await Future.delayed(const Duration(milliseconds: 300));
                  _refreshStatus();
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notification access', style: TextStyle(color: _text)),
              subtitle: Text(_notifPermission ? 'Granted' : 'Not granted', style: const TextStyle(color: _muted)),
              trailing: TextButton(
                onPressed: () async {
                  await NotificationBufferService.requestPermission();
                  await Future.delayed(const Duration(seconds: 1));
                  _refreshStatus();
                },
                child: const Text('Open settings'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Notifications are only read for apps you\'ve added to allowedPackages '
              'in notification_buffer_service.dart. Nothing is sent anywhere until '
              'you tap "What did I miss?" in the chat.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
