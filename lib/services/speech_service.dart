// Live microphone ayah detection — the native counterpart of the HTML
// prototype's SpeechRecognition path: the platform's own speech recognizer
// (set to Arabic) produces a transcript plus alternatives, and every
// alternative is scored through the same AyahMatcher so the best-matching
// ayah wins, exactly like the browser version tried each alternative.
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ayah_matcher.dart';

class SpeechService {
  static final SpeechToText _stt = SpeechToText();
  static bool _initialized = false;

  static bool get isListening => _stt.isListening;

  /// Starts a single listen session. Resolves with the best ayah match among
  /// all recognizer alternatives, or null if nothing clears the confidence
  /// bar. Throws with an Arabic message when the device has no recognizer or
  /// mic permission was denied.
  static Future<AyahMatch?> listenForAyah(AyahMatcher matcher) async {
    if (!_initialized) {
      _initialized = await _stt.initialize();
      if (!_initialized) {
        throw Exception(
            'تعذّر تشغيل تعرّف الكلام — تأكد من السماح باستخدام الميكروفون وتوفر خدمة التعرف على الجهاز');
      }
    }
    SpeechRecognitionResult? finalResult;
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'ar_SA',
        partialResults: false,
      ),
      onResult: (r) {
        if (r.finalResult) finalResult = r;
      },
    );
    // wait until the session ends (finalResult delivered or timeout)
    while (_stt.isListening) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final result = finalResult;
    if (result == null) return null;
    AyahMatch? best;
    for (final alt in result.alternates) {
      final m = matcher.match(alt.recognizedWords);
      if (m != null && (best == null || m.confidence > best.confidence)) {
        best = m;
      }
    }
    return best;
  }

  static Future<void> stop() => _stt.stop();
}
