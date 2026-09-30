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

  // URL Foto Profil Google Drive via CDN Proxy (Anti-Blokir CORS di Web & Android)
  static const String profileImageUrl =
      'https://wsrv.nl/?url=https://lh3.googleusercontent.com/d/1JmEoK4F_UYpktkq4Vq9_ahhrAkSzBxXk&w=150&h=150&fit=cover';

  @override
  void initState() {
    super.initState();
    // Template pesan sambutan awal dari Pak Bagas
    _messages.add(ChatMessage(
      text:
          'Halo, saya Pak Bagas. Saya bisa membantumu untuk menyetel alarm otomatis sesuai permintaanmu. Katakan mau distel alarm untuk kapan? Berikan waktu yang spesifik yaa',
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
      return "Kunci API Gemini belum terbaca. Pastikan GEMINI_API_KEY sudah disimpan di GitHub Secrets.";
    }

    // Menggunakan model resmi aktif gemini-3.8-flash sesuai instruksi respons server Google
    final models = [
      'gemini-3.8-flash',
      'gemini-3.8-flash-lite',
      'gemini-3.5-flash',
    ];

    // Instruksi sistem: penanganan bahasa santai/gaul + aturan default jam 12.00 siang jika waktu tidak spesifik
    final systemInstruction =
        "Kamu adalah asisten pengatur alarm cerdas bernama Smart Alarm by Pak Bagas. "
        "Tugasmu adalah menganalisis pesan pengguna yang meminta setel alarm, pengingat, atau bangun tidur "
        "dalam bahasa apa pun dan ragam bahasa apa pun (baku/santai/gaul/singkatan). "
        "Konfirmasi kembali alarm tersebut dengan ramah, sebutkan jam berapa alarm disetel dan tujuannya.\n\n"
        "ATURAN KHUSUS WAKTU:\n"
        "Jika pengguna meminta disetelkan alarm tetapi TIDAK menyebutkan jam atau waktu yang spesifik (misalnya hanya bilang: 'bangunin gw ya', 'setel alarm dong', 'ingetin gw nanti'), "
        "kamu WAJIB menyetel alarm secara otomatis ke pukul 12.00 siang. "
        "Pada situasi ini, kamu WAJIB memberitahukan pengguna secara jelas di balasanmu bahwa karena dia tidak memberikan waktu yang spesifik, alarm otomatis kamu setelkan ke pukul 12.00 siang.";

    String lastError = '';

    for (final model in models) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiApiKey',
      );

      try {
        final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': geminiApiKey,
          },
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
          try {
            final errData = jsonDecode(response.body);
            final msg = errData['error']?['message'] ?? 'Kode: ${response.statusCode}';
            lastError = "$model ($msg)";
          } catch (_) {
            lastError = "$model (Kode: ${response.statusCode})";
          }
        }
      } catch (e) {
        lastError = "Koneksi jaringan terputus";
      }
    }

    setState(() => _isOnline = false);
    return "Gagal memproses ke server AI ($lastError). Coba periksa koneksi internet.";
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
        backgroundColor: const Color(0xFF075E54),
        title: Row(
          children: [
            const SizedBox(width: 8),
            // Avatar Profil Google Drive Anti-Blokir
            ClipOval(
              child: SizedBox(
                width: 42,
                height: 42,
                child: Image.network(
                  profileImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.white24,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: Colors.white10,
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Nama Profil dan Status Online Interaktif
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Smart Alarm by Pak Bagas',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      // Titik Hijau Menyala (Glowing Dot)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isOnline ? const Color(0xFF00FF66) : Colors.grey,
                          boxShadow: _isOnline
                              ? [
                                  const BoxShadow(
                                    color: Color(0xFF00FF66),
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
            ),
          ],
        ),
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
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                "Bot sedang membaca perintah...",
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
