import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  static const String _apiKey = 'AIzaSyBOdOWbBWb9nyMWVva4epwb9g-wAeXjfUE'; // ← کلیلەکەت لێرە دابنێ

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
    );
  }

  String? lastDetectedLang;

  static const _langMap = {
    'Auto': 'auto',
    'Kurdish (Sorani)': 'ckb',
    'Kurdish (Kurmanji)': 'ku',
    'Arabic': 'ar',
    'English': 'en',
    'Turkish': 'tr',
    'Persian': 'fa',
    'German': 'de',
    'French': 'fr',
    'Spanish': 'es',
    'Italian': 'it',
    'Japanese': 'ja',
    'Chinese': 'zh',
    'Korean': 'ko',
    'Russian': 'ru',
    'Hindi': 'hi',
  };

  /// وەرگێڕان لە زمانێکەوە بۆ زمانێکی تر
  Future<String> translate({
    required String text,
    required String fromLang,
    required String toLang,
  }) async {
    final from = _langMap[fromLang] ?? 'auto';
    final to = _langMap[toLang] ?? 'en';
    if (from != 'auto' && from == to) return text;

    // Google Translate ئەوەل، Gemini فالبەک
    try {
      return await _fetchGoogleFree(from, to, text);
    } catch (_) {
      return _fetchGemini(text: text, fromLang: fromLang == 'Auto' ? 'the input language' : fromLang, toLang: toLang);
    }
  }

  Future<String> _fetchGoogleFree(String from, String to, String text) async {
    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$from&tl=$to&dt=t&q=${Uri.encodeComponent(text)}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 6));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      // زمانی ناسراو دەگرینەوە کاتێک Auto بەکاردێت
      if (from == 'auto' && data.length > 2 && data[2] is String) {
        lastDetectedLang = data[2] as String;
      }
      final buffer = StringBuffer();
      for (final part in data[0]) {
        if (part[0] != null) buffer.write(part[0]);
      }
      final result = buffer.toString().trim();
      if (result.isNotEmpty) return result;
    }
    throw Exception('Google free failed');
  }

  Future<String> _fetchGemini({
    required String text,
    required String fromLang,
    required String toLang,
  }) async {
    final prompt =
        'Translate the following text from $fromLang to $toLang. Only return the translated text, nothing else.\n\n$text';
    final response = await _model.generateContent([Content.text(prompt)]);
    final result = response.text?.trim();
    if (result != null && result.isNotEmpty) return result;
    throw Exception('Gemini failed');
  }

  /// وەرگێڕان و نووسینەوەی دەنگ لە زمانێکەوە بۆ زمانێکی تر
  Future<Map<String, String>> translateAudio({
    required Uint8List audioBytes,
    required String fromLang,
    required String toLang,
  }) async {
    try {
      final prompt = '''
You are a professional translator and transcriber. I will provide an audio recording of speech in $fromLang.
1. Transcribe the audio exactly in $fromLang.
2. Translate the transcribed text into $toLang.

Provide your response EXACTLY in the following format:
TRANSCRIPTION:
<the transcribed text here>

TRANSLATION:
<the translated text here>
''';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('audio/mp4', audioBytes),
        ])
      ];

      final response = await _model.generateContent(content);
      final text = response.text?.trim() ?? '';
      
      String transcription = '';
      String translation = '';
      
      if (text.contains('TRANSCRIPTION:') && text.contains('TRANSLATION:')) {
        final parts = text.split('TRANSLATION:');
        transcription = parts[0].replaceAll('TRANSCRIPTION:', '').trim();
        translation = parts[1].trim();
      } else {
        // Fallback
        translation = text;
      }
      
      return {
        'transcription': transcription,
        'translation': translation,
      };
    } catch (e) {
      throw Exception('هەڵەیەک ڕوویدا لە تۆمارکردندا: $e');
    }
  }

  /// وەرگێڕان و دەرهێنانی نووسین لە وێنە
  Future<Map<String, String>> translateImage({
    required Uint8List imageBytes,
    required String mimeType,
    required String fromLang,
    required String toLang,
  }) async {
    try {
      final prompt = '''
You are an expert OCR system and professional translator. I will provide an image containing text in $fromLang.
1. Extract ALL text tightly as it appears in $fromLang.
2. Translate the extracted text accurately into $toLang.

Provide your response EXACTLY in the following format:
EXTRACTED_TEXT:
<the extracted text here>

TRANSLATION:
<the translated text here>
''';

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, imageBytes),
        ])
      ];

      final response = await _model.generateContent(content);
      final text = response.text?.trim() ?? '';
      
      String extracted = '';
      String translation = '';
      
      if (text.contains('EXTRACTED_TEXT:') && text.contains('TRANSLATION:')) {
        final parts = text.split('TRANSLATION:');
        extracted = parts[0].replaceAll('EXTRACTED_TEXT:', '').trim();
        translation = parts[1].trim();
      } else {
        translation = text;
      }
      
      return {
        'extracted': extracted,
        'translation': translation,
      };
    } catch (e) {
      throw Exception('هەڵەیەک ڕوویدا لە وەرگێڕانی وێنەکەدا: $e');
    }
  }

  /// ناوی زمان لە کۆدی زمانەوە
  static String langNameFromCode(String code) {
    const codeToName = {
      'ckb': 'Kurdish (Sorani)', 'ku': 'Kurdish (Kurmanji)', 'ar': 'Arabic',
      'en': 'English', 'tr': 'Turkish', 'fa': 'Persian', 'de': 'German',
      'fr': 'French', 'es': 'Spanish', 'it': 'Italian', 'ja': 'Japanese',
      'zh': 'Chinese', 'ko': 'Korean', 'ru': 'Russian', 'hi': 'Hindi',
    };
    return codeToName[code] ?? code.toUpperCase();
  }

  /// زمانەکان دیاری دەکات
  static List<Map<String, String>> get supportedLanguages => [
        {'code': 'Auto', 'name': 'ناساندنی خۆکار', 'flag': '🔍'},
        {'code': 'Kurdish (Sorani)', 'name': 'کوردی سۆرانی', 'flag': '🟢'},
        {'code': 'Kurdish (Kurmanji)', 'name': 'کوردی کورمانجی', 'flag': '🟡'},
        {'code': 'Arabic', 'name': 'عەرەبی', 'flag': '🇸🇦'},
        {'code': 'English', 'name': 'ئینگلیزی', 'flag': '🇬🇧'},
        {'code': 'Turkish', 'name': 'تورکی', 'flag': '🇹🇷'},
        {'code': 'Persian', 'name': 'فارسی', 'flag': '🇮🇷'},
        {'code': 'German', 'name': 'ئەڵمانی', 'flag': '🇩🇪'},
        {'code': 'French', 'name': 'فەرەنسی', 'flag': '🇫🇷'},
        {'code': 'Spanish', 'name': 'ئیسپانی', 'flag': '🇪🇸'},
        {'code': 'Italian', 'name': 'ئیتالی', 'flag': '🇮🇹'},
        {'code': 'Japanese', 'name': 'ژاپۆنی', 'flag': '🇯🇵'},
        {'code': 'Chinese', 'name': 'چینی', 'flag': '🇨🇳'},
        {'code': 'Korean', 'name': 'کۆری', 'flag': '🇰🇷'},
        {'code': 'Russian', 'name': 'ڕوسی', 'flag': '🇷🇺'},
        {'code': 'Hindi', 'name': 'هیندی', 'flag': '🇮🇳'},
      ];
}
