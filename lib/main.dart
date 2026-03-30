import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
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
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _bgController;

  late AudioRecorder _record;
  final ImagePicker _picker = ImagePicker();
  bool _isListening = false;
  late FlutterTts _flutterTts;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Column(
                      children: [
                        _buildLanguageSelector(),
                        const SizedBox(height: 24),
                        _buildInputArea(),
                        if (_translatedText.isNotEmpty || _isLoading) ...[
                          const SizedBox(height: 24),
                          _buildOutputArea(),
                        ],
                        const SizedBox(height: 120), // Padding for button
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
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
        return Stack(
          children: [
            Container(color: const Color(0xFF07070F)),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.1 * math.sin(_bgController.value * 2 * math.pi),
              left: MediaQuery.of(context).size.width * 0.2 * math.cos(_bgController.value * 2 * math.pi),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8A2BE2).withOpacity(0.15),
                ),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).size.height * 0.2 * math.cos(_bgController.value * 2 * math.pi),
              right: MediaQuery.of(context).size.width * 0.1 * math.sin(_bgController.value * 2 * math.pi),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4B0082).withOpacity(0.15),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.4,
              right: -100,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00BFFF).withOpacity(0.1),
                ),
              ),
            ),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: Colors.transparent),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'وەرگێڕی زیرەک',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'بەهێزکراوە بە پێشکەوتووترین ژیری دەستکرد',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: const Icon(Icons.g_translate_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildLangPill(_fromLang, true)),
          GestureDetector(
            onTap: _swapLanguages,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: Colors.white,
                size: 24,
              ),
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
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              _getLangFlag(langCode),
              style: const TextStyle(fontSize: 26),
            ),
            const SizedBox(height: 6),
            Text(
              _getLangName(langCode),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
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
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: const Color(0xFF111116),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 16, bottom: 20),
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  isFrom ? 'زمانی سەرچاوە' : 'زمانی مەبەست',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: GeminiService.supportedLanguages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF8A2BE2).withOpacity(0.2) : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF8A2BE2) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(lang['flag'] ?? '', style: const TextStyle(fontSize: 28)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                lang['name'] ?? '',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF8A2BE2)),
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
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isInput ? 0.05 : 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(isInput ? 0.08 : 0.15),
              width: 1,
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
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _getLangName(_fromLang),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                if (_inputController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _inputController.clear();
                      setState(() {
                        _translatedText = '';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                    ),
                  ),
              ],
            ),
          ),
          TextField(
            controller: _inputController,
            maxLines: 7,
            minLines: 4,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
            textDirection: _fromLang.contains('Kurdish') || _fromLang == 'Arabic' || _fromLang == 'Persian'
                ? TextDirection.rtl
                : TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'دەقەکەت بنووسە یان پەستی بکە...',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.2),
                fontSize: 20,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(20),
            ),
            onChanged: (_) => setState(() {}),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _listen,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isListening ? Colors.redAccent.withOpacity(0.2) : const Color(0xFF8A2BE2).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isListening ? Colors.redAccent : const Color(0xFF8A2BE2),
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _openCamera,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8A2BE2).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Color(0xFF8A2BE2),
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  ' پیت',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
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
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getLangName(_toLang),
                    style: const TextStyle(
                      color: Color(0xFF8A2BE2),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (_translatedText.isNotEmpty)
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _speak(_translatedText),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _isPlaying ? const Color(0xFFE53935).withOpacity(0.15) : const Color(0xFF8A2BE2).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_isPlaying ? Icons.stop_rounded : Icons.volume_up_rounded, color: _isPlaying ? const Color(0xFFE53935) : const Color(0xFF8A2BE2), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  _isPlaying ? 'وەستان' : 'خوێندنەوە',
                                  style: TextStyle(
                                    color: _isPlaying ? const Color(0xFFE53935) : const Color(0xFF8A2BE2),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _copyToClipboard,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A2BE2).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, color: Color(0xFF8A2BE2), size: 16),
                                SizedBox(width: 6),
                                Text(
                                  'کۆپی',
                                  style: TextStyle(
                                    color: Color(0xFF8A2BE2),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                _translatedText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
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

  Widget _buildTranslateButton() {
    return ScaleTransition(
      scale: _isLoading ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF9D4EDD), // Lighter purple
              Color(0xFF5A189A), // Darker deep purple
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9D4EDD).withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _translate,
            borderRadius: BorderRadius.circular(24),
            splashColor: Colors.white.withOpacity(0.2),
            highlightColor: Colors.white.withOpacity(0.1),
            child: Center(
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                        SizedBox(width: 16),
                        Text(
                          'چاوەڕێبە...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
                        SizedBox(width: 12),
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
        ),
      ),
    );
  }
}

