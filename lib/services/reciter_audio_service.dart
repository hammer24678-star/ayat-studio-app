// PATCH_S104_RECITER_LIBRARY_DOWNLOAD: streams/downloads real recitation
// audio per surah from mp3quran.net's public reciters API -- the same
// catalog behind mp3quran.net's own apps and many other Quran apps -- so a
// قارئ slot no longer strictly needs a manually attached file. Pick a
// قارئ, pick a سورة, and the app fetches and caches the mp3 itself.
//
// Reciter servers are NOT hardcoded here: this calls mp3quran.net's own
// /api/v3/reciters endpoint and matches by (normalized) name against the
// live response, preferring a رواية حفص عن عاصم moshaf when a reciter has
// more than one. That keeps this correct even if mp3quran.net renames a
// server host later, and it works for any kReciters name that exists in
// their catalog without this file needing to track individual server
// hostnames by hand.
//
// Downloaded files are cached to disk forever, keyed by reciter+surah, so
// replaying the same choice never re-hits the network -- same pattern as
// AiArtService's on-disk cache (see ai_art_service.dart).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ReciterAudioException implements Exception {
  final String message;
  ReciterAudioException(this.message);
  @override
  String toString() => message;
}

class _MoshafEntry {
  final String server; // base url, already ends with '/'
  final Set<int> surahs;
  final String rewaya;
  _MoshafEntry(this.server, this.surahs, this.rewaya);
}

class ReciterAudioService {
  static const String _apiUrl =
      'https://www.mp3quran.net/api/v3/reciters?language=ar';

  // normalized-name -> best matching moshaf (Hafs preferred). Fetched once
  // and kept for the process lifetime -- mp3quran.net's catalog doesn't
  // change mid-session.
  static Map<String, _MoshafEntry>? _index;

  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/reciter_audio_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // Normalizes Arabic text (alef/yaa/taa-marbuta variants, tashkeel,
  // extra whitespace, a leading "الشيخ") so app names like 'الشيخ الدوسري'
  // can still be matched against catalog names like 'ياسر الدوسري' via
  // substring containment, and small spelling differences don't block a
  // match that would otherwise obviously be correct.
  static String _norm(String s) {
    var t = s.trim();
    t = t.replaceAll(RegExp('[أإآا]'), 'ا');
    t = t.replaceAll('ى', 'ي');
    t = t.replaceAll('ة', 'ه');
    t = t.replaceAll(RegExp(r'[\u064B-\u0652]'), ''); // tashkeel
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceFirst('الشيخ ', '');
    return t.trim();
  }

  static Future<void> _ensureIndex() async {
    if (_index != null) return;
    http.Response res;
    try {
      res = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw ReciterAudioException(
          'تعذّر الاتصال بالإنترنت لجلب قائمة القرّاء');
    }
    if (res.statusCode != 200) {
      throw ReciterAudioException(
          'تعذّر جلب قائمة القرّاء (${res.statusCode})');
    }
    final Map<String, dynamic> data =
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> reciters =
        (data['reciters'] as List<dynamic>?) ?? const [];
    final idx = <String, _MoshafEntry>{};
    for (final r in reciters) {
      final name = (r['name'] as String?) ?? '';
      final moshafList = (r['moshaf'] as List<dynamic>?) ?? const [];
      for (final m in moshafList) {
        final server = (m['server'] as String?) ?? '';
        final rewaya = (m['name'] as String?) ?? '';
        final surahListStr = (m['surah_list'] as String?) ?? '';
        if (server.isEmpty || surahListStr.isEmpty) continue;
        final surahs = surahListStr
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();
        final key = _norm(name);
        final existing = idx[key];
        final isHafs = rewaya.contains('حفص');
        if (existing == null ||
            (isHafs && !existing.rewaya.contains('حفص'))) {
          idx[key] = _MoshafEntry(server, surahs, rewaya);
        }
      }
    }
    _index = idx;
  }

  static Future<_MoshafEntry?> _resolve(String displayName) async {
    await _ensureIndex();
    final idx = _index!;
    final target = _norm(displayName);
    if (idx.containsKey(target)) return idx[target];
    for (final entry in idx.entries) {
      if (entry.key.contains(target) || target.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Downloads (or returns the already-cached copy of) surah [surahNum]
  /// (1..114) recited by [displayName]. Returns the local file path, or
  /// throws [ReciterAudioException] with a user-facing Arabic message.
  static Future<String> downloadSurah({
    required String displayName,
    required int surahNum,
    void Function(double? progress)? onProgress,
  }) async {
    final moshaf = await _resolve(displayName);
    if (moshaf == null) {
      throw ReciterAudioException(
          'لم يتم العثور على "$displayName" في قاعدة بيانات mp3quran.net — '
          'يمكنك إرفاق ملف تلاوة يدويًا بدلًا من ذلك');
    }
    if (!moshaf.surahs.contains(surahNum)) {
      throw ReciterAudioException(
          'هذا القارئ لم يسجّل هذه السورة في هذه الرواية');
    }
    final dir = await _cacheDir();
    final safeName =
        displayName.replaceAll(RegExp(r'[^\u0600-\u06FF0-9]'), '_');
    final file = File('${dir.path}/${safeName}_$surahNum.mp3');
    if (await file.exists() && await file.length() > 1024) {
      return file.path;
    }
    final surahStr = surahNum.toString().padLeft(3, '0');
    final url = Uri.parse('${moshaf.server}$surahStr.mp3');
    http.StreamedResponse streamed;
    try {
      final req = http.Request('GET', url);
      streamed =
          await http.Client().send(req).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw ReciterAudioException(
          'تعذّر تنزيل الملف الصوتي — تحقق من الاتصال بالإنترنت');
    }
    if (streamed.statusCode != 200) {
      throw ReciterAudioException('فشل التنزيل (${streamed.statusCode})');
    }
    final total = streamed.contentLength ?? 0;
    var received = 0;
    final tmp = File('${file.path}.part');
    final sink = tmp.openWrite();
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(total > 0 ? received / total : null);
    }
    await sink.close();
    if (await tmp.length() < 1024) {
      await tmp.delete().catchError((_) => tmp);
      throw ReciterAudioException('الملف المُنزَّل غير صالح — حاول مجددًا');
    }
    await tmp.rename(file.path);
    return file.path;
  }
}
