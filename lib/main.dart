import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Status Konfigurasi Wajib HP (Kunci Aplikasi)
  bool _isMandatorySetupDone = false;
  bool _checkedLockScreen = false;
  bool _checkedBatteryOptimization = false;
  bool _checkedPermissions = false;

  // Fitur Voice Input (Speech to Text)
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;

  // API Key disuntikkan secara aman via GitHub Secrets (--dart-define) saat kompilasi APK
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  // Foto Profil CDN Proxy Anti-Blokir
  static const String profileImageUrl =
      'https://wsrv.nl/?url=https://lh3.googleusercontent.com/d/1JmEoK4F_UYpktkq4Vq9_ahhrAkSzBxXk&w=150&h=150&fit=cover';

  final List<AlarmItem> _activeAlarms = [];
  Timer? _alarmClockTimer;
  Timer? _vibrationPulseTimer;
  Timer? _ringingDurationTimer;
  AlarmItem? _currentlyRingingAlarm;
  int _ringSecondsRemaining = 300; // 5 menit dering
  
  // Pengaturan Nada Dering & Getar
  bool _isVibrateEnabled = true;
  double _alarmVolume = 1.0;
  
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
      url: 'https://actions.google.com/sounds/v1/emergency/emergency_siren_close_long.ogg',
    ),
    RingtoneOption(
      name: 'Lonceng Mekanikal',
      url: 'https://actions.google.com/sounds/v1/alarms/mechanical_clock_ring.ogg',
    ),
  ];
  late RingtoneOption _selectedRingtone;

  @override
  void initState() {
    super.initState();
    _selectedRingtone = _availableRingtones[0];
    _speech = stt.SpeechToText();

    // Pesan sambutan awal Pak Bagas
    _messages.add(ChatMessage(
      text:
          'Halo, saya Pak Bagas. Saya bisa membantumu menyetel alarm otomatis melalui ketikan chat atau rekaman suara. Katakan mau distel alarm untuk kapan? Berikan waktu yang spesifik yaa',
      isUser: false,
      time: DateFormat('HH:mm').format(DateTime.now()),
    ));

    // Periksa status verifikasi izin HP pengguna & inisialisasi mesin
    _checkMandatorySetup();
    _initSpeechRecognizer();
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

  Future<void> _checkMandatorySetup() async {
    final prefs = await SharedPreferences.getInstance();
    final isDone = prefs.getBool('mandatory_setup_completed') ?? false;
    setState(() {
      _isMandatorySetupDone = isDone;
    });
  }

  Future<void> _completeMandatorySetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mandatory_setup_completed', true);
    setState(() {
      _isMandatorySetupDone = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Konfigurasi berhasil disimpan! Smart Alarm aktif.'),
        backgroundColor: Color(0xFF075E54),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _initSpeechRecognizer() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (val) {
          setState(() => _isListening = false);
        },
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );
      setState(() {});
    } catch (_) {
      _speechAvailable = false;
    }
  }

  void _startClockEngine() {
    _alarmClockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentlyRingingAlarm != null) return;

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
    // 1. Menyalakan dan mengunci layar agar tetap aktif
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    setState(() {
      alarm.isTriggered = true;
      _currentlyRingingAlarm = alarm;
      _ringSecondsRemaining = 300;
    });

    // 2. Putar audio di jalur stream ALARM perangkat keras sistem
    try {
      await _audioPlayer.setAudioContext(
        const AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.alarm,
            audioMode: AndroidAudioMode.normal,
          ),
        ),
      );
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.setVolume(_alarmVolume);
      await _audioPlayer.play(UrlSource(_selectedRingtone.url));
    } catch (_) {}

    // 3. Efek denyut getar perangkat keras daya sedang berulang
    if (_isVibrateEnabled) {
      _vibrationPulseTimer?.cancel();
      _vibrationPulseTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        HapticFeedback.vibrate();
        HapticFeedback.heavyImpact();
      });
    }

    // 4. Penghitung mundur durasi 5 menit
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

    try {
      await WakelockPlus.disable();
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
        content: Text('Alarm berhasil ditunda $minutes menit ke depan.'),
        backgroundColor: const Color(0xFF075E54),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _toggleVoiceRecording() async {
    if (!_isMandatorySetupDone) {
      _showMandatoryPopup();
      return;
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Izin mikrofon diperlukan untuk perintah suara.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      if (_controller.text.trim().isNotEmpty) {
        _handleSendMessage();
      }
    } else {
      if (!_speechAvailable) {
        await _initSpeechRecognizer();
      }

      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _controller.text = result.recognizedWords;
          });
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            setState(() => _isListening = false);
            _handleSendMessage();
          }
        },
        localeId: 'id_ID',
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _handleSendMessage() async {
    if (!_isMandatorySetupDone) {
      _showMandatoryPopup();
      return;
    }

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
      return "Kunci API Gemini belum terkonfigurasi.";
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

    String historyContext = "";
    final recentMessages = _messages.length > 6
        ? _messages.sublist(_messages.length - 6)
        : _messages;
    for (final m in recentMessages) {
      historyContext += "${m.isUser ? 'Pengguna' : 'Pak Bagas'}: ${m.text}\n";
    }

    final fullPrompt =
        "Kamu adalah Pak Bagas, asisten pengatur alarm cerdas via chat dan suara.\n"
        "WAKTU PERANGKAT SAAT INI: $currentDateStr (Tahun=${now.year}, Bulan=${now.month}, Tanggal=${now.day}, Jam=${now.hour}, Menit=${now.minute}).\n\n"
        "PEDOMAN & LOGIKA WAKTU (PENTING):\n"
        "1. Pengguna dapat menggunakan BAHASA GAUL/TIDAK BAKU (contoh: 'ntar jam 8 malem ya gas', 'bangunin 45 mnt lg', 'batalin alarm', 'besok subuh 04:30').\n"
        "2. NADA RESPON: Santai, ramah, bersahabat, ringkas (1-2 kalimat). KAMU WAJIB MENULISKAN JAM TARGET DAN TANGGAL DENGAN JELAS (Contoh: 'Siap! Alarm sudah distel untuk hari ini pukul 15:34 WIB ya.').\n"
        "3. WAKTU RELATIF: Jika user berkata '10 menit lagi', tambahkan tepat 10 menit dari waktu perangkat saat ini ($timeStr) dan sebutkan hasil jamnya.\n"
        "4. KETERANGAN AKTIVITAS: Masukkan ke properti 'note'. Jika tidak ada, biarkan string kosong \"\".\n"
        "5. JIKA BUKAN TENTANG ALARM: Balas sopan: 'Aku tidak mengerti maksudmu, bisa kau jelaskan lebih detail agar aku bisa setel alarm sesuai permintaanmu?' dengan action 'NONE'.\n\n"
        "FORMAT OUTPUT WAJIB:\n"
        "Akhiri jawabanmu dengan blok JSON tersembunyi berikut:\n"
        "|||JSON_DATA\n"
        "{\"action\":\"SET|CANCEL|NONE\",\"alarms\":[{\"year\":${now.year},\"month\":${now.month},\"day\":${now.day},\"hour\":15,\"minute\":34,\"note\":\"\"}]}\n"
        "JSON_DATA|||\n\n"
        "RIWAYAT PERCAKAPAN:\n"
        "$historyContext\n"
        "Perintah baru: $prompt";

    final models = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-pro'];

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
                  {"text": fullPrompt}
                ]
              }
            ],
            "generationConfig": {
              "maxOutputTokens": 800
            }
          }),
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]?['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              String replyText = '';
              for (final p in parts) {
                if (p is Map && p['text'] != null && p['thought'] != true) {
                  replyText += p['text'].toString();
                }
              }
              if (replyText.isEmpty && parts.last['text'] != null) {
                replyText = parts.last['text'].toString();
              }
              if (replyText.trim().isNotEmpty) {
                setState(() => _isOnline = true);
                return _parseAndRegisterAlarms(replyText.trim());
              }
            }
          }
        }
      } catch (_) {}
    }

    setState(() => _isOnline = false);
    return "Koneksi ke Pak Bagas terputus. Pastikan HP terhubung ke internet yaa.";
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
            final note = (a['note'] ?? '').toString();

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
            : "Siap, alarmnya sudah berhasil aku jadwalkan ya.";
      }
    } catch (_) {}

    return rawReply.replaceAll(RegExp(r'\|\|\|JSON_DATA[\s\S]*?JSON_DATA\|\|\|'), '').trim();
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

  void _showMandatoryPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allChecked = _checkedLockScreen && _checkedBatteryOptimization && _checkedPermissions;

            return PopScope(
              canPop: false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Konfigurasi Wajib HP',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Agar alarm dapat menyalakan layar saat HP terkunci dan tidak dimatikan paksa oleh Android, selesaikan 3 langkah wajib berikut:',
                        style: TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 14),

                      // Checklist 1: Layar Kunci
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF075E54),
                        title: const Text(
                          '1. Izin Tampilkan di Layar Kunci',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Aktifkan "Tampilkan di Layar Kunci" & "Tampil di atas aplikasi lain" di pengaturan HP.',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _checkedLockScreen,
                        onChanged: (val) {
                          setDialogState(() => _checkedLockScreen = val ?? false);
                        },
                      ),

                      // Checklist 2: Baterai Tidak Dibatasi
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF075E54),
                        title: const Text(
                          '2. Penghemat Baterai: Tidak Dibatasi',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Pilih "Tidak Dibatasi / No Restrictions" agar sistem HP tidak mematikan timer alarm saat HP tidur.',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _checkedBatteryOptimization,
                        onChanged: (val) {
                          setDialogState(() => _checkedBatteryOptimization = val ?? false);
                        },
                      ),

                      // Checklist 3: Izin Mikrofon & Notifikasi
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: const Color(0xFF075E54),
                        title: const Text(
                          '3. Izin Mikrofon & Alarm Presisi',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Diperlukan untuk perintah suara dan dering tepat detik ke-00.',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _checkedPermissions,
                        onChanged: (val) {
                          setDialogState(() => _checkedPermissions = val ?? false);
                        },
                      ),

                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade800,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 38),
                        ),
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text('Buka Pengaturan HP Sekarang', style: TextStyle(fontSize: 12)),
                        onPressed: () async {
                          await openAppSettings();
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: allChecked ? const Color(0xFF075E54) : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: allChecked
                        ? () {
                            Navigator.of(ctx).pop();
                            _completeMandatorySetup();
                          }
                        : null,
                    child: const Text(
                      'SAYA SUDAH MENGATUR & BUKA APLIKASI',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pengaturan Smart Alarm',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF075E54),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.help_outline, color: Color(0xFF075E54)),
                        tooltip: 'Panduan Pengaturan HP',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showMandatoryPopup();
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        // Rekap Alarm
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Rekap Alarm Aktif (${_activeAlarms.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (_activeAlarms.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setState(() => _activeAlarms.clear());
                                  setModalState(() {});
                                },
                                child: const Text('Hapus Semua', style: TextStyle(color: Colors.red, fontSize: 12)),
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
                            final dt = item.targetTime;
                            final timeStr =
                                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                            final noteStr = item.note.isEmpty ? 'Tanpa label' : item.note;
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
                                  const Icon(Icons.alarm, size: 20, color: Color(0xFF075E54)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '$timeStr - $noteStr',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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

                        // Opsi Getar
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Getar Daya Sedang (Vibrasi)'),
                          subtitle: const Text('Denyut getar berulang saat alarm berdering'),
                          activeColor: const Color(0xFF075E54),
                          value: _isVibrateEnabled,
                          onChanged: (val) {
                            setState(() => _isVibrateEnabled = val);
                            setModalState(() {});
                            if (val) {
                              HapticFeedback.vibrate();
                              HapticFeedback.heavyImpact();
                            }
                          },
                        ),

                        const Divider(height: 20),

                        // Nada Dering
                        const Text(
                          'Pilihan Nada Dering',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        ..._availableRingtones.map((tone) {
                          return RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            activeColor: const Color(0xFF075E54),
                            title: Text(tone.name),
                            value: tone.url,
                            groupValue: _selectedRingtone.url,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedRingtone = _availableRingtones.firstWhere((t) => t.url == val);
                                });
                                setModalState(() {});
                                _previewRingtone(val);
                              }
                            },
                          );
                        }),

                        const SizedBox(height: 12),

                        // Pengatur Volume
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

  Future<void> _previewRingtone(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(_alarmVolume);
      await _audioPlayer.play(UrlSource(url));
      Timer(const Duration(seconds: 3), () {
        _audioPlayer.stop();
      });
    } catch (_) {}
  }

  Widget _buildFullScreenRingingOverlay() {
    if (_currentlyRingingAlarm == null) return const SizedBox.shrink();

    final minutes = _ringSecondsRemaining ~/ 60;
    final seconds = _ringSecondsRemaining % 60;
    final timeFormatted =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    final dt = _currentlyRingingAlarm!.targetTime;
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final note = _currentlyRingingAlarm!.note.trim();

    return Container(
      color: const Color(0xFFB71C1C),
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            const Icon(Icons.alarm_on, color: Colors.white, size: 90),
            const SizedBox(height: 16),
            const Text(
              'ALARM BERDERING!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pukul $timeStr WIB',
              style: const TextStyle(color: Colors.white70, fontSize: 20),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  note,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Otomatis berdering: $timeFormatted',
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB71C1C),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  icon: const Icon(Icons.stop_circle, size: 24),
                  label: const Text('MATIKAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  onPressed: _stopAlarmRinging,
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  icon: const Icon(Icons.snooze, size: 20),
                  label: const Text('Tunda 5 Mnt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  onPressed: () => _snoozeAlarm(5),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
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
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Smart Alarm by Pak Bagas',
                    style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isOnline ? const Color(0xFF00FF66) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isOnline ? 'Online' : 'Offline',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'Pengaturan & Rekap Alarm',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Banner peringatan jika izin HP belum diselesaikan
              if (!_isMandatorySetupDone)
                InkWell(
                  onTap: _showMandatoryPopup,
                  child: Container(
                    color: Colors.amber.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: const [
                        Icon(Icons.warning, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Aplikasi Terkunci: Ketuk di sini untuk menyelesaikan Pengaturan Wajib HP.',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),

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

              // Indikator mendengarkan suara
              if (_isListening)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade50,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.mic, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Sedang mendengarkan suaramu... Bicara sekarang!',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
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

              // Input Bar: Teks & Mikrofon
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: Colors.white,
                child: Row(
                  children: [
                    // Tombol Mikrofon Voice Input
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.red : const Color(0xFF075E54),
                        size: 26,
                      ),
                      tooltip: 'Bicara ke Pak Bagas',
                      onPressed: _toggleVoiceRecording,
                    ),

                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: _isMandatorySetupDone,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSendMessage(),
                        decoration: InputDecoration(
                          hintText: _isMandatorySetupDone
                              ? 'Ketik atau ucapkan perintah alarm...'
                              : 'Selesaikan pengaturan wajib di atas...',
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
                    const SizedBox(width: 6),
                    CircleAvatar(
                      backgroundColor: _isMandatorySetupDone ? const Color(0xFF075E54) : Colors.grey,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                        onPressed: _isMandatorySetupDone ? _handleSendMessage : _showMandatoryPopup,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Layar Penuh Merah Berdering
          if (_currentlyRingingAlarm != null)
            Positioned.fill(
              child: _buildFullScreenRingingOverlay(),
            ),
        ],
      ),
    );
  }
}
