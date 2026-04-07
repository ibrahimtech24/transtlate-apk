import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/gemini_service.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ترانسلەیتی خێرا',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'NotoSansArabic',
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF060D0A),
        colorSchemeSeed: const Color(0xFF10B981),
      ),
      home: const TranslatorScreen(),
    );
  }
}

class TranslatorScreen extends StatefulWidget {
  const TranslatorScreen({super.key});

  @override
  State<TranslatorScreen> createState() => _TranslatorScreenState();
}

class _TranslatorScreenState extends State<TranslatorScreen>
    with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final GeminiService _geminiService = GeminiService();

  String _translatedText = '';
  bool _isLoading = false;
  String _fromLang = 'Auto';
  String _toLang = 'English';
  String _detectedLang = '';
  List<Map<String, dynamic>> _history = [];

  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _bgController;

  late AudioRecorder _record;
  final ImagePicker _picker = ImagePicker();
  bool _isListening = false;
  late FlutterTts _flutterTts;
  bool _isPlaying = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _record = AudioRecorder();
    _flutterTts = FlutterTts();
    _loadHistory();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _bgController.dispose();
    _debounce?.cancel();
    _flutterTts.stop();
    _record.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('translation_history') ?? [];
    if (mounted) {
      setState(() {
        _history = raw
            .map((e) => Map<String, dynamic>.from(
                  (jsonDecode(e) as Map).cast<String, dynamic>(),
                ))
            .toList();
      });
    }
  }

  Future<void> _saveToHistory(String input, String output) async {
    if (input.trim().isEmpty || output.trim().isEmpty) return;
    final entry = {
      'from': _fromLang,
      'to': _toLang,
      'input': input.trim(),
      'output': output.trim(),
      'detected': _detectedLang,
      'time': DateTime.now().toIso8601String(),
    };
    _history.insert(0, entry);
    if (_history.length > 50) _history = _history.sublist(0, 50);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'translation_history',
      _history.map((e) => jsonEncode(e)).toList(),
    );
  }

  void _showHistory() {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF172B1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: const Text('هێشتا هیچ مێژووێک نەكراوە',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.78,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1C14),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 14, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF10B981), Color(0xFFF59E0B)]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.history_rounded,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Text('مێژووی وەرگێڕان',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          setState(() => _history = []);
                          setModalState(() {});
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('translation_history');
                          if (mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete_sweep_rounded,
                            color: Color(0xFFF87171), size: 18),
                        label: const Text('سڕینەوە',
                            style: TextStyle(
                                color: Color(0xFFF87171), fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final h = _history[i];
                      final fromDisplay = h['from'] == 'Auto' && (h['detected'] as String).isNotEmpty
                          ? GeminiService.langNameFromCode(h['detected'] as String)
                          : h['from'] as String;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _inputController.text = h['input'] as String;
                            _translatedText = h['output'] as String;
                            _fromLang = h['from'] as String;
                            _toLang = h['to'] as String;
                          });
                          _fadeController.forward();
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.07)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '$fromDisplay → ${h['to']}',
                                    style: TextStyle(
                                        color: const Color(0xFF10B981),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _formatTime(h['time'] as String),
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.3),
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                h['input'] as String,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                h['output'] as String,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'ئێستا';
      if (diff.inMinutes < 60) return '${diff.inMinutes} خولەک';
      if (diff.inHours < 24) return '${diff.inHours} کاتژمێر';
      return '${diff.inDays} ڕۆژ';
    } catch (_) {
      return '';
    }
  }

  String _getTtsLangCode(String lang) {
    switch (lang) {
      case 'English': return 'en-US';
      case 'Arabic': return 'ar-SA';
      case 'Turkish': return 'tr-TR';
      case 'German': return 'de-DE';
      case 'French': return 'fr-FR';
      case 'Spanish': return 'es-ES';
      case 'Italian': return 'it-IT';
      case 'Russian': return 'ru-RU';
      case 'Japanese': return 'ja-JP';
      case 'Chinese': return 'zh-CN';
      case 'Korean': return 'ko-KR';
      case 'Hindi': return 'hi-IN';
      default: return 'en-US';
    }
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    
    if (_isPlaying) {
      await _flutterTts.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    if (_toLang.contains('Kurdish')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFC62828)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('ببورە، خوێندنەوەی دەنگی بۆ کوردی بەردەست نییە 😔',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
      return;
    }

    if (mounted) setState(() => _isPlaying = true);
    await _flutterTts.setLanguage(_getTtsLangCode(_getLangName(_toLang)));
    await _flutterTts.speak(text);
    
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  Future<void> _listen() async {
    if (!_isListening) {
      try {
        if (await _record.hasPermission()) {
          final tempDir = await getTemporaryDirectory();
          final path = '${tempDir.path}/gemini_audio.m4a';
          
          await _record.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
          
          setState(() {
            _isListening = true;
            _inputController.text = 'خەریکی گوێگرتنە... قسە بکە، پاشان جارێکی تر مایکەکە دابگرە.';
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE53935), Color(0xFFC62828)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('پێویستە ڕێگە بە مایکرۆفۆن بدەیت.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          );
        }
      } catch (e) {
        setState(() => _isListening = false);
      }
    } else {
      setState(() {
        _isListening = false;
        _isLoading = true;
        _inputController.text = 'خەریکی وەرگێڕانی دەنگەکەتی... چاوەڕێبە';
      });
      
      try {
        final path = await _record.stop();
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            final audioBytes = await file.readAsBytes();
            
            final result = await _geminiService.translateAudio(
              audioBytes: audioBytes,
              fromLang: _fromLang,
              toLang: _toLang,
            );
            
            setState(() {
              _inputController.text = result['transcription'] ?? '';
              _translatedText = result['translation'] ?? '';
              _isLoading = false;
            });
            _fadeController.forward();
            _saveToHistory(result['transcription'] ?? '', result['translation'] ?? '');
          }
        } else {
          setState(() {
            _inputController.clear();
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _inputController.text = 'هەڵەیەک ڕوویدا لە وەرگێڕانی فایلەکە: \${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openCamera() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1C14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF10B981)),
                ),
                title: const Text('کامێرا دابگیرسێنە', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF59E0B).withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFFF59E0B)),
                ),
                title: const Text('هەڵبژاردن لە گەلەری مۆبایل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _isLoading = true;
          _inputController.text = 'خەریکی دەرهێنان و وەرگێڕانی وێنەکەتی... چاوەڕێبە';
        });

        final bytes = await image.readAsBytes();
        final mimeType = lookupMimeType(image.path, headerBytes: bytes) ?? 'image/jpeg';
        
        final result = await _geminiService.translateImage(
          imageBytes: bytes,
          mimeType: mimeType,
          fromLang: _fromLang,
          toLang: _toLang,
        );

        setState(() {
          _inputController.text = result['extracted'] ?? '';
          _translatedText = result['translation'] ?? '';
          _isLoading = false;
        });
        _fadeController.forward();
        _saveToHistory(result['extracted'] ?? '', result['translation'] ?? '');
      }
    } catch (e) {
      setState(() {
        _inputController.text = 'هەڵەیەک ڕوویدا لە وەرگێڕانی وێنەکەدا: \${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _swapLanguages() {
    if (_fromLang == 'Auto') return; // نەتوانرێت Auto بگۆڕدرێتەوە
    setState(() {
      final temp = _fromLang;
      _fromLang = _toLang;
      _toLang = temp;
      _detectedLang = '';

      if (_translatedText.isNotEmpty) {
        _inputController.text = _translatedText;
        _translatedText = '';
        _fadeController.reverse();
      }
    });
  }

  Future<void> _translate() async {
    if (_inputController.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _translatedText = '';
      _detectedLang = '';
      _fadeController.reverse();
    });

    try {
      final result = await _geminiService.translate(
        text: _inputController.text.trim(),
        fromLang: _fromLang,
        toLang: _toLang,
      );

      final detected = _geminiService.lastDetectedLang ?? '';
      setState(() {
        _translatedText = result;
        _detectedLang = detected;
        _isLoading = false;
      });
      _fadeController.forward();
      _saveToHistory(_inputController.text, result);
    } catch (e) {
      setState(() {
        _translatedText = 'هەڵە: ${e.toString().replaceAll('Exception: ', '')}';
        _isLoading = false;
      });
      _fadeController.forward();
    }
  }

  void _copyToClipboard() {
    if (_translatedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _translatedText));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF065F46)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'دەقەکە کۆپی کرا ✅',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _shareTranslation() {
    if (_translatedText.isNotEmpty) {
      final text = '${_inputController.text.trim()}\n\n↓ ${_getLangName(_toLang)} ↓\n\n$_translatedText';
      Share.share(text);
    }
  }

  String _getLangName(String code) {
    if (code == 'Auto') return 'ناساندنی خۆکار';
    final lang = GeminiService.supportedLanguages
        .firstWhere((l) => l['code'] == code, orElse: () => {'name': code});
    return lang['name'] ?? code;
  }

  String _getLangFlag(String code) {
    if (code == 'Auto') return '🔍';
    final lang = GeminiService.supportedLanguages
        .firstWhere((l) => l['code'] == code, orElse: () => {'flag': ''});
    return lang['flag'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D0A),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          _buildAnimatedBackground(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
                    child: Column(
                      children: [
                        _buildLanguageSelector(),
                        const SizedBox(height: 16),
                        _buildInputArea(),
                        const SizedBox(height: 16),
                        if (_translatedText.isNotEmpty || _isLoading)
                          _buildOutputArea(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 30,
            child: _buildTranslateButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, child) {
        final t = _bgController.value * 2 * math.pi;
        final size = MediaQuery.of(context).size;
        return Stack(
          children: [
            // Base gradient background
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF060D0A),
                    Color(0xFF080F0C),
                    Color(0xFF060A06),
                  ],
                ),
              ),
            ),
            // Orb 1 — emerald top-left
            Positioned(
              top: -100 + 70 * math.sin(t * 0.5),
              left: -80 + 50 * math.cos(t * 0.4),
              child: _glow(380, const Color(0xFF10B981), 0.18),
            ),
            // Orb 2 — amber bottom-right
            Positioned(
              bottom: -120 + 60 * math.cos(t * 0.55),
              right: -100 + 45 * math.sin(t * 0.45),
              child: _glow(420, const Color(0xFFF59E0B), 0.14),
            ),
            // Orb 3 — teal center
            Positioned(
              top: size.height * 0.38 + 40 * math.sin(t * 0.35),
              left: size.width * 0.2 + 30 * math.cos(t * 0.28),
              child: _glow(220, const Color(0xFF34D399), 0.10),
            ),
            // Orb 4 — warm amber top-right
            Positioned(
              top: 80 + 35 * math.cos(t * 0.62),
              right: 20 + 25 * math.sin(t * 0.5),
              child: _glow(180, const Color(0xFFFBBF24), 0.09),
            ),
            // Soft blur over everything
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(color: Colors.transparent),
            ),
          ],
        );
      },
    );
  }

  Widget _glow(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withOpacity(opacity), Colors.transparent],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
 
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          // Logo
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.translate_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFFF59E0B)],
                ).createShader(bounds),
                child: const Text(
                  'ibrahim dev',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              Text(
                'وەرگێڕی زیرەکی کوردی',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.4),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          // History button
          GestureDetector(
            onTap: _showHistory,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF10B981).withOpacity(0.2),
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.history_rounded,
                      color: const Color(0xFF10B981).withOpacity(0.85), size: 22),
                  if (_history.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1C14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(child: _buildLangPill(_fromLang, true)),
          GestureDetector(
            onTap: _swapLanguages,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 22),
            ),
          ),
          Expanded(child: _buildLangPill(_toLang, false)),
        ],
      ),
    );
  }

  Widget _buildLangPill(String langCode, bool isFrom) {
    return GestureDetector(
      onTap: () => _showLanguagePicker(isFrom),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isFrom
              ? Colors.white.withOpacity(0.04)
              : const Color(0xFF10B981).withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFrom
                ? Colors.white.withOpacity(0.08)
                : const Color(0xFF10B981).withOpacity(0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_getLangFlag(langCode), style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _getLangName(langCode),
                style: TextStyle(
                  color: isFrom ? Colors.white60 : const Color(0xFF34D399),
                  fontSize: 13,
                  fontWeight: isFrom ? FontWeight.w500 : FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isFrom
                  ? Colors.white.withOpacity(0.35)
                  : const Color(0xFF10B981).withOpacity(0.7),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker(bool isFrom) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: BoxDecoration(
            color: const Color(0xFF0F1C14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 14, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFFF59E0B)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isFrom ? Icons.language_rounded : Icons.translate_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isFrom ? 'زمانی سەرچاوە' : 'زمانی مەبەست',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: GeminiService.supportedLanguages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final lang = GeminiService.supportedLanguages[index];
                    // Auto فەقەت بۆ زمانی سەرچاوە دیاریکراوە
                    if (!isFrom && lang['code'] == 'Auto') return const SizedBox.shrink();
                    final isSelected = isFrom ? _fromLang == lang['code'] : _toLang == lang['code'];

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isFrom) {
                            _fromLang = lang['code']!;
                          } else {
                            _toLang = lang['code']!;
                          }
                        });
                        Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [Color(0xFF10B981), Color(0xFFF59E0B)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                )
                              : null,
                          color: isSelected ? null : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Colors.transparent
                                : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(lang['flag'] ?? '', style: const TextStyle(fontSize: 26)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                lang['name'] ?? '',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlassCard({required Widget child, bool isInput = true}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isInput
            ? const Color(0xFF0F1C14)
            : const Color(0xFF0D1A10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isInput
              ? Colors.white.withOpacity(0.06)
              : const Color(0xFF10B981).withOpacity(0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isInput
                ? Colors.black.withOpacity(0.3)
                : const Color(0xFF10B981).withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildInputArea() {
    return _buildGlassCard(
      isInput: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF10B981),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withOpacity(0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _fromLang == 'Auto'
                      ? (_detectedLang.isNotEmpty
                          ? 'ناسرا: ${GeminiService.langNameFromCode(_detectedLang)}'
                          : 'ناساندنی خۆکار')
                      : _getLangName(_fromLang),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (_inputController.text.isNotEmpty) ...[
                  Text(
                    '${_inputController.text.length} پیت',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {
                      _inputController.clear();
                      _debounce?.cancel();
                      setState(() => _translatedText = '');
                      _fadeController.reverse();
                    },
                    child: Icon(Icons.close_rounded,
                        color: Colors.white.withOpacity(0.35), size: 18),
                  ),
                ],
              ],
            ),
          ),
          TextField(
            controller: _inputController,
            maxLines: 6,
            minLines: 3,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.55,
              fontWeight: FontWeight.w400,
            ),
            textDirection: _fromLang.contains('Kurdish') || _fromLang == 'Arabic' || _fromLang == 'Persian'
                ? TextDirection.rtl
                : TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'دەقەکەت بنووسە...',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.18),
                fontSize: 18,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            ),
            onChanged: (_) {
              setState(() {});
            },
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _buildIconBtn(
                  icon: _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _isListening ? const Color(0xFFF87171) : const Color(0xFF10B981),
                  onTap: _listen,
                  label: _isListening ? 'وەست' : 'دەنگ',
                ),
                const SizedBox(width: 6),
                _buildIconBtn(
                  icon: Icons.camera_alt_rounded,
                  color: const Color(0xFFF59E0B),
                  onTap: _openCamera,
                  label: 'وێنە',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildOutputArea() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: _buildGlassCard(
        isInput: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF59E0B),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF59E0B).withOpacity(0.6),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getLangName(_toLang),
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (_translatedText.isNotEmpty) ...[
                    _buildActionChip(
                      icon: _isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                      label: _isPlaying ? 'وەست' : 'گوێ',
                      color: _isPlaying ? const Color(0xFFF87171) : const Color(0xFF10B981),
                      onTap: () => _speak(_translatedText),
                    ),
                    const SizedBox(width: 6),
                    _buildActionChip(
                      icon: Icons.copy_rounded,
                      label: 'کۆپی',
                      color: const Color(0xFFF59E0B),
                      onTap: _copyToClipboard,
                    ),
                    const SizedBox(width: 6),
                    _buildActionChip(
                      icon: Icons.share_rounded,
                      label: 'ناردن',
                      color: const Color(0xFF34D399),
                      onTap: _shareTranslation,
                    ),
                  ],
                ],
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF10B981)),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: SelectableText(
                  _translatedText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                  textDirection: _toLang.contains('Kurdish') || _toLang == 'Arabic' || _toLang == 'Persian'
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslateButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _translate,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: _isLoading
                ? [
                    const Color(0xFF10B981).withOpacity(0.5),
                    const Color(0xFF059669).withOpacity(0.5),
                  ]
                : const [
                    Color(0xFF10B981),
                    Color(0xFF059669),
                  ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withOpacity(_isLoading ? 0.15 : 0.4),
              blurRadius: 24,
              spreadRadius: -2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: _isLoading
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'چاوەڕێبە...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'وەرگێڕان',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

