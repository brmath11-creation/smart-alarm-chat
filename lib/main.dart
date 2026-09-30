import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

class AlarmItem {
  final String id;
  final DateTime targetTime;
  final String note;
  bool isTriggered;

  AlarmItem({
    required this.id,
    required this.targetTime,
    required this.note,
    this.isTriggered = false,
  });
}

class RingtoneOption {
  final String name;
  final String url;

  const RingtoneOption({required this.name, required this.url});
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

  // GitHub Secrets API Key
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  // Foto Profil CDN Proxy Anti-Blokir
  static const String profileImageUrl =
      'https://wsrv.nl/?url=https://lh3.googleusercontent.com/d/1JmEoK4F_UYpktkq4Vq9_ahhrAkSzBxXk&w=150&h=150&fit=cover';

  final List<AlarmItem> _activeAlarms = [];
  Timer? _alarmClockTimer;
  Timer? _vibrationPulseTimer;
  Timer? _ringingDurationTimer;
  AlarmItem? _currentlyRingingAlarm;
  int _ringSecondsRemaining = 300; // 5 menit berdering (300 detik)
  
  // Pengaturan Nada Dering & Getar
  bool _isVibrateEnabled = true;
  double _alarmVolume = 0.8; // 80% volume default
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<RingtoneOption> _availableRingtones = const [
    RingtoneOption(
      name: 'Digital Beep Klasik',
      url: 'https://actions.google.com/sounds/v1/alarms/digital_watch_alarm_long.ogg',
    ),
    RingtoneOption(
      name: 'Melodi Lonceng Pagi',
      url: 'https://actions.google.com/sounds/v1/alarms/alarm_clock.ogg',
    ),
    RingtoneOption(
      name: 'Sirene Bangun Cepat',
      url: 'https://actions.google.com/sounds/v1/alarms/beep_short.ogg',
    ),
    RingtoneOption(
      name: 'Lonceng Mekanikal',
      url: 'https://actions.google.com/sounds/v1/alarms/mechanical_clock_ring.ogg',
    ),
  ];
  late RingtoneOption _selectedRingtone;
  String _customRingtoneName = '';

  @override
  void initState() {
    super.initState();
    _selectedRingtone = _availableRingtones[0];

    // Pesan sambutan awal Pak Bagas
    _messages.add(ChatMessage(
      text:
          'Halo, saya Pak Bagas. Saya bisa membantumu untuk menyetel alarm otomatis sesuai permintaanmu. Katakan mau distel alarm untuk kapan? Berikan waktu yang spesifik yaa',
      isUser: false,
      time: DateFormat('HH:mm').format(DateTime.now()),
    ));

    // Memulai mesin pendeteksi alarm setiap 1 detik
    _startClockEngine();
  }

  @override
  void dispose() {
    _alarmClockTimer?.cancel();
    _vibrationPulseTimer?.cancel();
    _ringingDurationTimer?.cancel();
    _audioPlayer.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startClockEngine() {
    _alarmClockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentlyRingingAlarm != null) return; // Jangan tumpuk jika sedang berdering

      final now = DateTime.now();
      for (final alarm in _activeAlarms) {
        if (!alarm.isTriggered &&
            now.year == alarm.targetTime.year &&
            now.month == alarm.targetTime.month &&
            now.day == alarm.targetTime.day &&
            now.hour == alarm.targetTime.hour &&
            now.minute == alarm.targetTime.minute) {
          _triggerAlarm(alarm);
          break;
        }
      }
    });
  }

  Future<void> _triggerAlarm(AlarmItem alarm) async {
    setState(() {
      alarm.isTriggered = true;
      _currentlyRingingAlarm = alarm;
      _ringSecondsRemaining = 300; // 5 menit
    });

    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(_alarmVolume);
      await _audioPlayer.play(UrlSource(_selectedRingtone.url));
    } catch (_) {
      // Audio fallback jika jaringan/perangkat membatasi
    }

    // Efek getar berulang jika opsi getar aktif
    if (_isVibrateEnabled) {
      _vibrationPulseTimer?.cancel();
      _vibrationPulseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        HapticFeedback.heavyImpact();
      });
    }

    // Timer penghitung mundur 5 menit tanpa interupsi
    _ringingDurationTimer?.cancel();
    _ringingDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_ringSecondsRemaining > 1) {
          _ringSecondsRemaining--;
        } else {
          _stopAlarmRinging();
        }
      });
    });
  }

  Future<void> _stopAlarmRinging() async {
    _ringingDurationTimer?.cancel();
    _vibrationPulseTimer?.cancel();
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    setState(() {
      if (_currentlyRingingAlarm != null) {
        _activeAlarms.removeWhere((a) => a.id == _currentlyRingingAlarm!.id);
      }
      _currentlyRingingAlarm = null;
    });
  }

  void _snoozeAlarm(int minutes) {
    if (_currentlyRingingAlarm == null) return;
    final newTime = DateTime.now().add(Duration(minutes: minutes));
    final snoozedNote = _currentlyRingingAlarm!.note;
    
    _stopAlarmRinging();

    setState(() {
      _activeAlarms.add(AlarmItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        targetTime: newTime,
        note: snoozedNote.isEmpty ? 'Tunda $minutes mnt' : '$snoozedNote (Tunda $minutes mnt)',
      ));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Alarm ditunda $minutes menit ke depan.'),
        backgroundColor: const Color(0xFF075E54),
        duration: const Duration(seconds: 2),
      ),
    );
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
      return "Kunci API Gemini belum terbaca di GitHub Secrets.";
    }

    final now = DateTime.now();
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    const months = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final dayName = days[now.weekday - 1];
    final monthName = months[now.month - 1];
    final timeStr = DateFormat('HH:mm').format(now);
    final currentDateStr = '$dayName, ${now.day} $monthName ${now.year} pukul $timeStr WIB';

    // Instruksi sistem multi-alarm dan format balasan terstruktur
    final systemInstruction =
        "Kamu adalah Pak Bagas, asisten pengatur alarm cerdas.\n"
        "WAKTU PERANGKAT SAAT INI: $currentDateStr (Format: YYYY=${now.year}, MM=${now.month}, DD=${now.day}, HH=${now.hour}, mm=${now.minute}).\n\n"
        "ATURAN & TUGAS:\n"
        "1. Pengguna bisa meminta 1 atau LEBIH DARI SATU alarm sekaligus dalam 1 chat.\n"
        "2. NADA BALASAN: Santai, akrab, jelas, singkat (maksimal 1-2 kalimat). Sebutkan semua waktu alarm yang disetel.\n"
        "3. JIKA WAKTU TIDAK SPESIFIK: Otomatis setel ke jam 12.00 siang hari yang dimaksud dan beritahu santai bahwa disetel jam 12 siang karena tidak menyebutkan jam yang jelas.\n"
        "4. JIKA PERINTAH SANGAT TIDAK JELAS / BUKAN ALARM: Balas TEPAT DENGAN: 'Aku tidak mengerti maksudmu, bisa kau jelaskan lebih detail agar aku bisa setel alarm sesuai permintaanmu?'\n"
        "5. JIKA MEMBATALKAN/REVISI: Sesuaikan dan jelaskan santai.\n\n"
        "FORMAT WAJIB KELUARAN:\n"
        "Kamu WAJIB mengakhiri jawabanmu dengan blok data JSON tersembunyi berformat seperti ini:\n"
        "|||JSON_DATA\n"
        "{\"action\":\"SET|CANCEL|NONE\",\"alarms\":[{\"year\":2026,\"month\":10,\"day\":1,\"hour\":8,\"minute\":0,\"note\":\"mencuci baju\"}]}\n"
        "JSON_DATA|||";

    // Menyusun memori riwayat chat
    final List<Map<String, dynamic>> contents = [];
    String lastRole = '';
    for (final m in _messages) {
      final currentRole = m.isUser ? 'user' : 'model';
      if (contents.isEmpty && currentRole != 'user') continue;
      if (currentRole == lastRole && contents.isNotEmpty) {
        final existingText = contents.last['parts'][0]['text'] as String;
        contents.last['parts'] = [{'text': '$existingText\n${m.text}'}];
      } else {
        contents.add({
          'role': currentRole,
          'parts': [{'text': m.text}],
        });
        lastRole = currentRole;
      }
    }

    // Menargetkan langsung model standar baru Gemini 3.8 Flash untuk kecepatan maksimal (<2 detik)
    final models = ['gemini-3.8-flash', 'gemini-3.8-flash-lite', 'gemini-3.5-flash'];

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
            "system_instruction": {
              "parts": [{"text": systemInstruction}]
            },
            "generationConfig": {
              "maxOutputTokens": 350,
              "temperature": 0.2
            },
            "contents": contents
          }),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final rawReply = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
          if (rawReply != null && rawReply.toString().trim().isNotEmpty) {
            setState(() => _isOnline = true);
            return _parseAndRegisterAlarms(rawReply.toString().trim());
          }
        }
      } catch (_) {
        // Coba model berikutnya jika ada rintangan koneksi
      }
    }

    setState(() => _isOnline = false);
    return "Aku tidak mengerti maksudmu, bisa kau jelaskan lebih detail agar aku bisa setel alarm sesuai permintaanmu?";
  }

  String _parseAndRegisterAlarms(String rawReply) {
    try {
      if (rawReply.contains('|||JSON_DATA') && rawReply.contains('JSON_DATA|||')) {
        final parts = rawReply.split('|||JSON_DATA');
        final visibleText = parts[0].trim();
        final jsonBlock = parts[1].split('JSON_DATA|||')[0].trim();

        final parsed = jsonDecode(jsonBlock);
        final action = parsed['action'];
        final alarmsList = parsed['alarms'] as List?;

        if (action == 'CANCEL') {
          setState(() {
            _activeAlarms.clear();
          });
        } else if (action == 'SET' && alarmsList != null) {
          for (final a in alarmsList) {
            final target = DateTime(
              a['year'] ?? DateTime.now().year,
              a['month'] ?? DateTime.now().month,
              a['day'] ?? DateTime.now().day,
              a['hour'] ?? 12,
              a['minute'] ?? 0,
            );
            final note = (a['note'] ?? '-').toString();

            setState(() {
              _activeAlarms.add(AlarmItem(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                targetTime: target,
                note: note,
              ));
            });
          }
        }
        return visibleText.isNotEmpty
            ? visibleText
            : "Oke siap, alarmnya sudah berhasil aku stel ya.";
      }
    } catch (_) {
      // Jika parsing JSON gagal, tetap kembalikan teks chat bersih
    }

    // Bersihkan penanda data jika tersisa
    return rawReply.replaceAll(RegExp(r'\|\|\|JSON_DATA[\s\S]*?JSON_DATA\|\|\|'), '').trim();
  }

  String _formatRekapItem(AlarmItem item) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final dt = item.targetTime;
    final dateStr = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}.${dt.minute.toString().padLeft(2, '0')}';
    final noteStr = item.note.trim().isEmpty ? '-' : item.note.trim();
    return '$dateStr ($timeStr) : $noteStr';
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

  void _openSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pengaturan Smart Alarm',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF075E54),
                    ),
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: ListView(
                      children: [
                        // BAGIAN 1: REKAP ALARM
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Rekap Alarm Aktif (${_activeAlarms.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            if (_activeAlarms.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setState(() => _activeAlarms.clear());
                                  setModalState(() {});
                                },
                                child: const Text(
                                  'Hapus Semua',
                                  style: TextStyle(color: Colors.red, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_activeAlarms.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Belum ada alarm yang disetel.',
                              style: TextStyle(fontSize: 13, color: Colors.black54),
                            ),
                          )
                        else
                          ..._activeAlarms.map((item) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F7F7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.alarm, size: 18, color: Color(0xFF075E54)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _formatRekapItem(item),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                    onPressed: () {
                                      setState(() {
                                        _activeAlarms.removeWhere((a) => a.id == item.id);
                                      });
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),

                        const Divider(height: 24),

                        // BAGIAN 2: EFEK GETAR
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Efek Getar (Vibrasi)'),
                          subtitle: const Text('Getar otomatis saat alarm berdering (5 menit)'),
                          activeColor: const Color(0xFF075E54),
                          value: _isVibrateEnabled,
                          onChanged: (val) {
                            setState(() => _isVibrateEnabled = val);
                            setModalState(() {});
                            if (val) HapticFeedback.heavyImpact();
                          },
                        ),

                        const Divider(height: 20),

                        // BAGIAN 3: NADA DERING & PILIH DARI PERANGKAT
                        const Text(
                          'Pilih Nada Dering',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        ..._availableRingtones.map((tone) {
                          return RadioListTile<RingtoneOption>(
                            contentPadding: EdgeInsets.zero,
                            activeColor: const Color(0xFF075E54),
                            title: Text(tone.name),
                            value: tone,
                            groupValue: _selectedRingtone,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedRingtone = val;
                                  _customRingtoneName = '';
                                });
                                setModalState(() {});
                                _previewRingtone(val.url);
                              }
                            },
                          );
                        }),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_open, color: Color(0xFF075E54)),
                          title: Text(
                            _customRingtoneName.isEmpty
                                ? 'Pilih berkas dari perangkat...'
                                : 'Nada Perangkat: $_customRingtoneName',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF075E54),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () {
                              _simulateDeviceRingtonePicker(setModalState);
                            },
                            child: const Text('Browse', style: TextStyle(fontSize: 12)),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // BAGIAN 4: SLIDER VOLUME
                        Row(
                          children: [
                            const Icon(Icons.volume_up, color: Color(0xFF075E54)),
                            const SizedBox(width: 8),
                            Text('Volume Alarm: ${(_alarmVolume * 100).toInt()}%'),
                          ],
                        ),
                        Slider(
                          value: _alarmVolume,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          activeColor: const Color(0xFF075E54),
                          onChanged: (val) {
                            setState(() => _alarmVolume = val);
                            setModalState(() {});
                            _audioPlayer.setVolume(val);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _simulateDeviceRingtonePicker(StateSetter setModalState) {
    showDialog(
      context: context,
      builder: (ctx) {
        final textCtrl = TextEditingController(text: 'Nada_Favorit_HP.mp3');
        return AlertDialog(
          title: const Text('Pilih Berkas Suara Perangkat', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Masukkan nama berkas audio yang ada di penyimpanan ponsel:'),
              const SizedBox(height: 8),
              TextField(
                controller: textCtrl,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'nama_audio.mp3',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF075E54),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final pickedName = textCtrl.text.trim();
                if (pickedName.isNotEmpty) {
                  setState(() {
                    _customRingtoneName = pickedName;
                  });
                  setModalState(() {});
                }
                Navigator.pop(ctx);
              },
              child: const Text('Gunakan'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _previewRingtone(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(_alarmVolume);
      await _audioPlayer.play(UrlSource(url));
      Timer(const Duration(seconds: 2), () {
        _audioPlayer.stop();
      });
    } catch (_) {}
  }

  Widget _buildRingingOverlay() {
    if (_currentlyRingingAlarm == null) return const SizedBox.shrink();

    final minutes = _ringSecondsRemaining ~/ 60;
    final seconds = _ringSecondsRemaining % 60;
    final timeFormatted =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      color: Colors.red.shade900.withOpacity(0.95),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.alarm_on, color: Colors.white, size: 64),
          const SizedBox(height: 8),
          const Text(
            'ALARM BERDERING!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatRekapItem(_currentlyRingingAlarm!),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Berdering otomatis selama: $timeFormatted',
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.stop_circle, size: 22),
                label: const Text(
                  'MATIKAN',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                onPressed: _stopAlarmRinging,
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                icon: const Icon(Icons.snooze, size: 20),
                label: const Text('Tunda 5 Mnt'),
                onPressed: () => _snoozeAlarm(5),
              ),
            ],
          ),
        ],
      ),
    );
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
                      // Titik Hijau Menyala (Neon Glow)
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
        actions: [
          // Titik tiga vertikal menu pengaturan
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'Pengaturan & Rekap Alarm',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner layar dering alarm aktif 5 menit
          _buildRingingOverlay(),

          // Daftar Gelembung Chat
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
                "Pak Bagas sedang membaca perintah...",
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
