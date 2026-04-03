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
      title: 'وەرگێڕی کوردی',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'NotoSansArabic',
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF030303),
        colorSchemeSeed: const Color(0xFF8A2BE2),
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
  String _fromLang = 'Kurdish (Sorani)';
  String _toLang = 'English';

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
            color: const Color(0xFF111116),
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
                  decoration: BoxDecoration(color: const Color(0xFF8A2BE2).withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF8A2BE2)),
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
                  decoration: BoxDecoration(color: const Color(0xFF00BFFF).withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF00BFFF)),
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
      }
    } catch (e) {
      setState(() {
        _inputController.text = 'هەڵەیەک ڕوویدا لە وەرگێڕانی وێنەکەدا: \${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _swapLanguages() {
    setState(() {
      final temp = _fromLang;
      _fromLang = _toLang;
      _toLang = temp;

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
      _fadeController.reverse();
    });

    try {
      final result = await _geminiService.translate(
        text: _inputController.text.trim(),
        fromLang: _fromLang,
        toLang: _toLang,
      );

      setState(() {
        _translatedText = result;
        _isLoading = false;
      });
      _fadeController.forward();
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
                colors: [Color(0xFF8A2BE2), Color(0xFF4B0082)],
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
    final lang = GeminiService.supportedLanguages
        .firstWhere((l) => l['code'] == code, orElse: () => {'name': code});
    return lang['name'] ?? code;
  }

  String _getLangFlag(String code) {
    final lang = GeminiService.supportedLanguages
        .firstWhere((l) => l['code'] == code, orElse: () => {'flag': ''});
    return lang['flag'] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
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
        return Stack(
          children: [
            Container(color: const Color(0xFF08080F)),
            Positioned(
              top: -80 + 60 * math.sin(t * 0.7),
              left: -60 + 40 * math.cos(t * 0.5),
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF6C63FF).withOpacity(0.25),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Positioned(
              bottom: -100 + 50 * math.cos(t * 0.6),
              right: -80 + 40 * math.sin(t * 0.4),
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFF00D4FF).withOpacity(0.15),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.45 + 30 * math.sin(t * 0.3),
              left: MediaQuery.of(context).size.width * 0.3,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    const Color(0xFFFF6584).withOpacity(0.12),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.transparent),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.translate_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ibrahim dev',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'تایبەت بەکارەکانی خۆم',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.45),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Expanded(child: _buildLangPill(_fromLang, true)),
          GestureDetector(
            onTap: _swapLanguages,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isFrom
              ? Colors.white.withOpacity(0.05)
              : const Color(0xFF6C63FF).withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFrom
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFF6C63FF).withOpacity(0.3),
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
                  color: isFrom ? Colors.white70 : Colors.white,
                  fontSize: 13,
                  fontWeight: isFrom ? FontWeight.w500 : FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withOpacity(0.4), size: 16),
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
            color: const Color(0xFF0F0F1A),
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
                          colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
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
                                  colors: [Color(0xFF6C63FF), Color(0xFF00D4FF)],
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isInput
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFF6C63FF).withOpacity(0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isInput
                  ? Colors.white.withOpacity(0.09)
                  : const Color(0xFF6C63FF).withOpacity(0.35),
              width: 1.2,
            ),
          ),
          child: child,
        ),
      ),
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
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getLangName(_fromLang),
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
                  color: _isListening ? const Color(0xFFFF6584) : const Color(0xFF6C63FF),
                  onTap: _listen,
                  label: _isListening ? 'وەست' : 'دەنگ',
                ),
                const SizedBox(width: 6),
                _buildIconBtn(
                  icon: Icons.camera_alt_rounded,
                  color: const Color(0xFF00D4FF),
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
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00D4FF),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getLangName(_toLang),
                    style: const TextStyle(
                      color: Color(0xFF00D4FF),
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
                      color: _isPlaying ? const Color(0xFFFF6584) : const Color(0xFF6C63FF),
                      onTap: () => _speak(_translatedText),
                    ),
                    const SizedBox(width: 6),
                    _buildActionChip(
                      icon: Icons.copy_rounded,
                      label: 'کۆپی',
                      color: const Color(0xFF00D4FF),
                      onTap: _copyToClipboard,
                    ),
                    const SizedBox(width: 6),
                    _buildActionChip(
                      icon: Icons.share_rounded,
                      label: 'ناردن',
                      color: const Color(0xFFFFD166),
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
                      valueColor: AlwaysStoppedAnimation(Color(0xFF6C63FF)),
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
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isLoading
                ? [const Color(0xFF6C63FF).withOpacity(0.6), const Color(0xFF00D4FF).withOpacity(0.6)]
                : [const Color(0xFF6C63FF), const Color(0xFF00D4FF)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(_isLoading ? 0.2 : 0.45),
              blurRadius: 20,
              offset: const Offset(0, 6),
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
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'وەرگێڕان',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

