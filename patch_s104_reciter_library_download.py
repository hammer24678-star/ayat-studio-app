#!/usr/bin/env python3
"""
PATCH_S104_RECITER_LIBRARY_DOWNLOAD
====================================

The قرّاء (reciters) tab currently has 6 names and only supports one
audio source: the user manually attaching their own licensed file per
reciter. This patch adds:

  1. kReciters grows from 6 to 20 well-known Hafs-riwaya reciters
     (lib/data/studio_presets.dart).

  2. A new service, lib/services/reciter_audio_service.dart, that lets
     any of those 20 slots be filled by downloading the real recitation
     over the internet instead of attaching a file. It talks to
     mp3quran.net's public reciters API (https://www.mp3quran.net/api/v3/
     reciters) -- the same catalog powering mp3quran.net's own apps and
     dozens of other Quran apps -- and:
       - fetches + caches the full reciter/server list once per process,
       - matches an app reciter name against that catalog (normalized,
         diacritic-insensitive, prefers a Hafs-`an-`Asim moshaf when a
         reciter has more than one riwaya available),
       - downloads the chosen surah's mp3 to app storage and caches it
         on disk forever after that (never re-hits the network for the
         same reciter+surah again).
     Reciter *server hostnames are intentionally NOT hardcoded* -- they
     are resolved live against mp3quran.net's own response, so this
     keeps working even if mp3quran.net moves a reciter to a new server,
     and it also works for any of the 20 names as long as mp3quran.net's
     catalog has a matching entry (it currently lists 200+ reciters).

  3. lib/screens/home_screen.dart -- the قرّاء panel gets a second
     "تنزيل من الإنترنت" (cloud-download) button next to the existing
     play/pause button on every reciter row. Tapping it opens a سورة
     picker (built from the already-loaded Quran corpus, so no new
     surah-name list needs to be maintained), downloads that surah's
     audio, and plugs the resulting local file straight into the
     existing state.reciterAudioPaths[i] slot -- so playback / export /
     everything downstream is 100% unchanged, it just has a second way
     to get filled in. The panel's hint text is also updated since it's
     no longer true that the app can only use manually-attached files.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s104_reciter_library_download.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S104_RECITER_LIBRARY_DOWNLOAD"


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if new.strip() in text:
        print(f"  SKIP  ({label}): already applied")
        return False

    count = text.count(old)
    if count == 0:
        raise SystemExit(
            f"ERROR ({label}): expected old text not found in {path}. "
            f"File may have drifted since this patch was written -- "
            f"aborting instead of guessing."
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


# ---------------------------------------------------------------- kReciters

_RECITERS_OLD = """const List<String> kReciters = [
  'الشيخ الدوسري',
  'مشاري العفاسي',
  'عبدالباسط عبدالصمد',
  'ماهر المعيقلي',
  'ياسر الدوسري',
  'سعود الشريم',
];"""

_RECITERS_NEW = """const List<String> kReciters = [
  // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: grew from 6 to 20. Every name
  // below is matched at runtime against mp3quran.net's live reciter
  // catalog (see ReciterAudioService) for the "تنزيل من الإنترنت" button --
  // no per-reciter server URL is hardcoded here.
  'الشيخ الدوسري',
  'مشاري العفاسي',
  'عبدالباسط عبدالصمد',
  'ماهر المعيقلي',
  'ياسر الدوسري',
  'سعود الشريم',
  'عبدالرحمن السديس',
  'سعد الغامدي',
  'أحمد العجمي',
  'محمود خليل الحصري',
  'محمد صديق المنشاوي',
  'علي الحذيفي',
  'محمد أيوب',
  'ناصر القطامي',
  'هاني الرفاعي',
  'أبو بكر الشاطري',
  'خالد الجليل',
  'فارس عباد',
  'بندر بليلة',
  'صلاح البدير',
];"""

# ---------------------------------------------------------- new service file

_SERVICE_FILE = '''// PATCH_S104_RECITER_LIBRARY_DOWNLOAD: streams/downloads real recitation
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
    t = t.replaceAll(RegExp(r'[\\u064B-\\u0652]'), ''); // tashkeel
    t = t.replaceAll(RegExp(r'\\s+'), ' ');
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
        displayName.replaceAll(RegExp(r'[^\\u0600-\\u06FF0-9]'), '_');
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
'''


def write_new_file(path: pathlib.Path, content: str, label: str) -> bool:
    if path.exists():
        existing = path.read_text(encoding="utf-8")
        if MARKER in existing:
            print(f"  SKIP  ({label}): already applied")
            return False
        raise SystemExit(
            f"ERROR ({label}): {path} already exists and doesn't carry "
            f"{MARKER} -- refusing to overwrite, inspect it manually."
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"  OK    ({label}): created")
    return True


# ---------------------------------------------------------- home_screen.dart

_IMPORT_OLD = """import '../services/media_service.dart';
import '../services/settings_service.dart'; // PATCH_S37_PERSISTENT_SETTINGS"""

_IMPORT_NEW = """import '../services/media_service.dart';
import '../services/reciter_audio_service.dart'; // PATCH_S104_RECITER_LIBRARY_DOWNLOAD
import '../services/settings_service.dart'; // PATCH_S37_PERSISTENT_SETTINGS"""

_FIELDS_OLD = """  VideoPlayerController? _video;
  VideoPlayerController? _reciterPreview;
  int? _previewingReciter;"""

_FIELDS_NEW = """  VideoPlayerController? _video;
  VideoPlayerController? _reciterPreview;
  int? _previewingReciter;
  int? _downloadingReciter; // PATCH_S104_RECITER_LIBRARY_DOWNLOAD
  double? _downloadProgress; // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: 0..1, null = indeterminate"""

_METHODS_OLD = """    } catch (_) {
      _toast('تعذّر تشغيل هذا الملف الصوتي');
      setState(() {
        _reciterPreview = null;
        _previewingReciter = null;
      });
    }
  }

  Future<void> _applyCustomText() async {"""

_METHODS_NEW = """    } catch (_) {
      _toast('تعذّر تشغيل هذا الملف الصوتي');
      setState(() {
        _reciterPreview = null;
        _previewingReciter = null;
      });
    }
  }

  // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: second way to fill a reciter
  // slot -- download the real recitation instead of attaching a file.
  // Reuses state.reciterAudioPaths[i], so playback/export are unchanged.
  Future<void> _downloadReciterAudio(int i) async {
    final name = kReciters[i];
    final surahNum = await _pickSurahForDownload();
    if (surahNum == null || !mounted) return;
    setState(() {
      _downloadingReciter = i;
      _downloadProgress = null;
    });
    try {
      final path = await ReciterAudioService.downloadSurah(
        displayName: name,
        surahNum: surahNum,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;
      state.update(() => state.reciterAudioPaths[i] = path);
      _toast('تم تنزيل تلاوة $name ✓');
    } on ReciterAudioException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('تعذّر تنزيل الملف الصوتي');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingReciter = null;
          _downloadProgress = null;
        });
      }
    }
  }

  // Surah picker built from the already-loaded Quran corpus (state.matcher)
  // rather than a separately maintained list of 114 surah names.
  Future<int?> _pickSurahForDownload() async {
    final matcher = state.matcher;
    final surahs = <int, String>{};
    if (matcher != null) {
      for (final a in matcher.ayaat) {
        surahs[a.surahNum] = a.surah;
      }
    }
    final entries = surahs.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AyatColors.surface2,
        title: const Text('اختر السورة للتنزيل'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: entries.isEmpty
              ? const Center(
                  child: Text('انتظر تحميل بيانات القرآن ثم أعد المحاولة'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (c, idx) {
                    final e = entries[idx];
                    return ListTile(
                      title: Text('${e.key}. ${e.value}'),
                      onTap: () => Navigator.pop(ctx, e.key),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyCustomText() async {"""

_PANEL_HINT_OLD = """        _panelTitle('مقاطع صوتية للقرّاء',
            'أرفق تلاوة لكل قارئ ثم اختره لإضافة تلاوته إلى المقطع المُصدَّر. لا يضم التطبيق أي تلاوات مسجّلة مسبقًا — أرفق ملفات مرخّصة لديك.'),"""

_PANEL_HINT_NEW = """        _panelTitle('مقاطع صوتية للقرّاء',
            // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: no longer true that the app
            // can only use manually-attached files -- it can fetch real
            // recitations from mp3quran.net now.
            'اختر قارئًا ثم إمّا نزّل تلاوته لسورة معيّنة من الإنترنت، أو أرفق ملف تلاوة خاص بك.'),"""

_PANEL_BUTTONS_OLD = """                  IconButton(
                    onPressed: () => _toggleReciterPreview(i),
                    icon: Icon(
                      _previewingReciter == i
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: AyatColors.goldBright,
                    ),
                    tooltip: 'تشغيل/إيقاف',
                  ),
                ],
              ),
            ),
          ),"""

_PANEL_BUTTONS_NEW = """                  // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: download this
                  // reciter's audio for a chosen سورة straight from the
                  // internet instead of attaching a file.
                  _downloadingReciter == i
                      ? SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              value: _downloadProgress,
                              color: AyatColors.goldBright,
                            ),
                          ),
                        )
                      : IconButton(
                          onPressed: () => _downloadReciterAudio(i),
                          icon: const Icon(
                            Icons.cloud_download_outlined,
                            color: AyatColors.goldBright,
                          ),
                          tooltip: 'تنزيل من الإنترنت',
                        ),
                  IconButton(
                    onPressed: () => _toggleReciterPreview(i),
                    icon: Icon(
                      _previewingReciter == i
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: AyatColors.goldBright,
                    ),
                    tooltip: 'تشغيل/إيقاف',
                  ),
                ],
              ),
            ),
          ),"""


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 patch_s104_reciter_library_download.py <project_root>")
        sys.exit(1)

    project_dir = pathlib.Path(sys.argv[1]).resolve()
    if not project_dir.exists():
        raise SystemExit(f"ERROR: project root not found: {project_dir}")

    presets_path = project_dir / "lib" / "data" / "studio_presets.dart"
    service_path = project_dir / "lib" / "services" / "reciter_audio_service.dart"
    home_path = project_dir / "lib" / "screens" / "home_screen.dart"

    for p in (presets_path, home_path):
        if not p.exists():
            raise SystemExit(f"ERROR: expected file not found: {p}")

    print(f"Applying {MARKER} to {project_dir}\n")

    changed = False
    changed |= replace_once(presets_path, _RECITERS_OLD, _RECITERS_NEW,
                             "studio_presets.dart: kReciters -> 20 reciters")
    changed |= write_new_file(service_path, _SERVICE_FILE,
                               "reciter_audio_service.dart: new file")
    changed |= replace_once(home_path, _IMPORT_OLD, _IMPORT_NEW,
                             "home_screen.dart: import ReciterAudioService")
    changed |= replace_once(home_path, _FIELDS_OLD, _FIELDS_NEW,
                             "home_screen.dart: download progress state fields")
    changed |= replace_once(home_path, _METHODS_OLD, _METHODS_NEW,
                             "home_screen.dart: _downloadReciterAudio + surah picker")
    changed |= replace_once(home_path, _PANEL_HINT_OLD, _PANEL_HINT_NEW,
                             "home_screen.dart: reciters panel hint text")
    changed |= replace_once(home_path, _PANEL_BUTTONS_OLD, _PANEL_BUTTONS_NEW,
                             "home_screen.dart: reciters panel download button")

    print()
    if changed:
        print("Done. Reminder:")
        print("  git add lib/data/studio_presets.dart lib/services/reciter_audio_service.dart \\\\")
        print("          lib/screens/home_screen.dart")
        print("This adds an internet dependency for the download button only --")
        print("attaching your own file (existing flow) still works fully offline.")
    else:
        print("Nothing to do -- already applied.")


if __name__ == "__main__":
    main()
