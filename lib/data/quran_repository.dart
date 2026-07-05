import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../services/ayah_matcher.dart';

class QuranRepository {
  static Future<List<Ayah>> loadFullCorpus() async {
    final raw = await rootBundle.loadString('assets/quran/quran_full.json');
    final List<dynamic> data = jsonDecode(raw);
    return data.map((e) => Ayah(
      surah: e['surah'] as String,
      num: e['num'] as int,
      ar: e['ar'] as String,
      en: (e['en'] ?? '') as String,
    )).toList();
  }
}
