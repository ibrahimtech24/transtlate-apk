import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSyBHbzaJiMOAsYJQc6Lw5fiMU4iJ0Dm4oBY'; // ← کلیلەکەت لێرە دابنێ

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
    );
  }

  /// وەرگێڕان لە زمانێکەوە بۆ زمانێکی تر
  Future<String> translate({
    required String text,
    required String fromLang,
    required String toLang,
  }) async {
    try {
      final prompt = '''
You are a professional translator. Translate the following text from $fromLang to $toLang.
Only return the translated text, nothing else. No explanations, no quotes, no extra text.

Text to translate:
$text
''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text?.trim() ?? 'وەرگێڕان نەکرا';
    } catch (e) {
      throw Exception('هەڵەیەک ڕوویدا لە وەرگێڕاندا: $e');
    }
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

  /// زمانەکان دیاری دەکات
  static List<Map<String, String>> get supportedLanguages => [
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
