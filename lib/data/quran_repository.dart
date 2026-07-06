import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../services/ayah_matcher.dart';

class QuranRepository {
  static Future<List<Ayah>> loadFullCorpus() async {
    final raw = await rootBundle.loadString('assets/quran/quran_full.json');
    final List<dynamic> data = jsonDecode(raw);
    // The asset lists ayat in canonical order but carries no surah number —
    // derive it from surah-name boundaries (names are unique per surah and
    // the list is contiguous per surah).
    final out = <Ayah>[];
    var surahNum = 0;
    String? lastSurah;
    for (final e in data) {
      final surah = e['surah'] as String;
      if (surah != lastSurah) {
        surahNum++;
        lastSurah = surah;
      }
      out.add(Ayah(
        surahNum: surahNum,
        surah: surah,
        num: e['num'] as int,
        ar: e['ar'] as String,
        en: (e['en'] ?? '') as String,
      ));
    }
    return out;
  }
}
