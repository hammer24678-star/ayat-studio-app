// Saves exported videos where the person can actually find them: the
// device's public Downloads folder (Download/AyatStudio), not the app's
// private documents directory buried under Android/data/com.ayatstudio.
//
// On Android 11+ apps may create files in the public Download collection
// through the normal File API without any permission. On Android 10 and
// below the WRITE_EXTERNAL_STORAGE permission is needed (declared with
// maxSdkVersion=29 in the manifest; requested lazily here). If anything
// about a given device/ROM refuses, we fall back to the app documents dir
// so the export is never lost — the caller shows whichever path was used.
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class SavedExport {
  final String path;
  final bool inDownloads;
  SavedExport(this.path, this.inDownloads);
}

class MediaSaver {
  static Future<SavedExport> saveVideo(String srcPath, String fileName) async {
    if (Platform.isAndroid) {
      try {
        // No-op on Android 11+ (auto-denied but also not needed); grants the
        // legacy write permission on Android 10 and below.
        await Permission.storage.request();
      } catch (_) {}
      try {
        final dir = Directory('/storage/emulated/0/Download/AyatStudio');
        await dir.create(recursive: true);
        final dest = '${dir.path}/$fileName';
        await File(srcPath).copy(dest);
        File(srcPath).delete().ignore();
        return SavedExport(dest, true);
      } catch (_) {
        // fall through to app storage
      }
    }
    final docs = await getApplicationDocumentsDirectory();
    final dest = '${docs.path}/$fileName';
    if (srcPath != dest) await File(srcPath).copy(dest);
    return SavedExport(dest, false);
  }
}
