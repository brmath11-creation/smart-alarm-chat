import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

void main() {
  runApp(const SmartAlarmApp());
}

class SmartAlarmApp extends StatelessWidget {
  const SmartAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Alarm by Pak Bagas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF075E54),
          primary: const Color(0xFF075E54),
        ),
        useMaterial3: true,
      ),
      home: const ChatAlarmScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String time;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
  });
}

class ChatAlarmScreen extends StatefulWidget {
  const ChatAlarmScreen({super.key});

  @override
  State<ChatAlarmScreen> createState() => _ChatAlarmScreenState();
}

class _ChatAlarmScreenState extends State<ChatAlarmScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isOnline = true;

  // Membaca API Key yang disuntikkan secara aman oleh GitHub Secrets
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(
      text: 'Halo! Saya asisten alarm pintarmu. Mau pasang alarm untuk jam berapa? (Bisa pakai bahasa apa saja atau bahasa gaul).',
      isUser: false,
      time: DateFormat('HH:mm').format(DateTime.now()),
    ));
  }

  Future<void> _handleSendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final nowStr = DateFormat('HH:mm').format(DateTime.now());
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, time: nowStr));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    final botReply = await _processWithAI(text);

    setState(() {
      _messages.add(ChatMessage(
        text: botReply,
        isUser: false,
        time: DateFormat('HH:mm').format(DateTime.now()),
      ));
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<String> _processWithAI(String prompt) async {
    if (geminiApiKey.isEmpty) {
      setState(() => _isOnline = false);
      return "Kunci API Gemini belum terkonfigurasi. Pastikan GEMINI_API_KEY sudah diatur di GitHub Secrets.";
    }

    // Menggunakan model aktif terbaru dengan sistem toleransi fallback
    final models = ['gemini-2.5-flash', 'gemini-2.0-flash'];
    String lastError = '';

    for (final model in models) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiApiKey',
      );

      final systemInstruction =
          "Kamu adalah asisten pengatur alarm cerdas bernama Smart Alarm by Pak Bagas. "
          "Tugasmu adalah menganalisis pesan pengguna yang meminta setel alarm, pengingat, atau bangun tidur "
          "dalam bahasa apa pun dan ragam bahasa apa pun (baku/santai/gaul). "
          "Konfirmasi kembali alarm tersebut dengan ramah, sebutkan jam berapa alarm disetel dan tujuannya. "
          "Jika waktu yang diminta tidak jelas, tanyakan kembali dengan sopan.";

      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "contents": [
              {
                "parts": [
                  {"text": "$systemInstruction\n\nPesan pengguna: $prompt"}
                ]
              }
            ]
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'];
          if (candidates != null && candidates.isNotEmpty) {
            final reply = candidates[0]['content']?['parts']?[0]?['text'];
            if (reply != null && reply.toString().trim().isNotEmpty) {
              setState(() => _isOnline = true);
              return reply.toString().trim();
            }
          }
        } else {
          lastError = "Kode: ${response.statusCode}";
        }
      } catch (e) {
        lastError = "Koneksi terganggu";
      }
    }

    // Jika seluruh upaya gagal, perbarui status menjadi offline
    setState(() => _isOnline = false);
    return "Gagal menghubungi AI ($lastError). Coba periksa koneksi internet.";
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            // Avatar Profil Google Drive Anti-Blokir
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white24,
              child: ClipOval(
                child: Image.network(
                  'https://lh3.googleusercontent.com/d/1JmEoK4F_UYpktkq4Vq9_ahhrAkSzBxXk',
                  headers: const {'Referrer-Policy': 'no-referrer'},
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.alarm, color: Colors.white);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Alarm by Pak Bagas',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Lingkaran Hijau Menyala (Glowing Dot)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isOnline ? const Color(0xFF25D366) : Colors.grey,
                        boxShadow: _isOnline
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF25D366).withOpacity(0.8),
                                  blurRadius: 6,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [],
                      ),
                    ),
                    if (_isOnline) ...[
                      const SizedBox(width: 6),
                      const Text(
                        'Online',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF075E54),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return Align(
                  alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: message.isUser ? const Color(0xFFE7FFDB) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: message.isUser ? const Radius.circular(12) : const Radius.circular(0),
                        bottomRight: message.isUser ? const Radius.circular(0) : const Radius.circular(12),
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(message.text, style: const TextStyle(fontSize: 15, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(message.time, style: const TextStyle(fontSize: 10, color: Colors.black45)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "Sedang membaca perintah...",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Ketik perintah alarm...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFF075E54),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _handleSendMessage,
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
